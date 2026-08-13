#!/usr/bin/env bash
# test-notify.sh - self-check for ci/notify.sh. Run: bash ci/test-notify.sh
#
# Sends NOTHING. A fake `curl` is put first on PATH; it writes the arguments it was handed to a
# file and exits 0, so every assertion below is about what notify.sh WOULD have sent.
#
# Two things are worth locking down here. The three-type rule is enforced by nothing but the
# case statement, and CLAUDE.md lists a fourth type as a settled negative - so "an unknown type
# exits 2" is a real invariant, not a formality. And the body goes out as --data-binary @file
# precisely so a newline or a quote cannot truncate it: a truncated `blocked` message is a
# missing resume step, which is the one failure that reaches Austin's phone wrong.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0

expect() { # expect <name> <condition-exit> <detail>
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1 : $3"; fails=$((fails+1)); fi
}

# --- the fake curl ---------------------------------------------------------------------------
mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CURL_ARGS_OUT"
exit 0
SHIM
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"

run_notify() { # run_notify <type> <title> <body-file>; captures args + exit code
  export CURL_ARGS_OUT="$tmp/args.txt"
  : > "$CURL_ARGS_OUT"
  NTFY_TOPIC=test-topic RUN_URL='https://example.com/run' \
    bash "$root/ci/notify.sh" "$1" "$2" "$3" >"$tmp/out.txt" 2>"$tmp/err.txt"
  echo $?
}

printf 'a body\n' > "$tmp/body.txt"

# --- the three legal types --------------------------------------------------------------------
for t in start blocked done; do
  rc=$(run_notify "$t" "T" "$tmp/body.txt")
  expect "type '$t' is accepted" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" "exited $rc"
done

# --- the fourth type, which must be impossible -------------------------------------------------
# `recommend` was deleted 2026-08-09 and is a settled negative. If this ever passes, a fourth
# notification has quietly become sendable again.
for t in recommend info warning ''; do
  rc=$(run_notify "$t" "T" "$tmp/body.txt")
  expect "type '${t:-<empty>}' is refused" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exited $rc, should be non-zero"
done
rc=$(run_notify recommend "T" "$tmp/body.txt")
expect "an unknown type exits exactly 2" "$([ "$rc" -eq 2 ] && echo 0 || echo 1)" "exited $rc"
expect "an unknown type sends nothing" "$([ ! -s "$tmp/args.txt" ] && echo 0 || echo 1)" "curl was still called"

# --- priority: blocked is the only one allowed to wake anyone ------------------------------------
run_notify blocked "T" "$tmp/body.txt" >/dev/null
expect "blocked is high priority" "$(grep -qx 'Priority: high' "$tmp/args.txt" && echo 0 || echo 1)" "blocked was not high"
for t in start done; do
  run_notify "$t" "T" "$tmp/body.txt" >/dev/null
  expect "$t is NOT high priority" "$(grep -qx 'Priority: high' "$tmp/args.txt" && echo 1 || echo 0)" "$t would wake him"
done

# --- the body is sent by reference, never inlined -------------------------------------------------
printf 'line one\n"quoted" and \x27single\x27\nline three\n' > "$tmp/tricky.txt"
run_notify done "T" "$tmp/tricky.txt" >/dev/null
expect "body is passed as --data-binary @file" "$(grep -qx -- "--data-binary" "$tmp/args.txt" && grep -qx -- "@$tmp/tricky.txt" "$tmp/args.txt" && echo 0 || echo 1)" "body was not sent by file reference"
expect "no body text is inlined into argv" "$(grep -q 'line three' "$tmp/args.txt" && echo 1 || echo 0)" "body content leaked into the command line"

# --- title and topic ------------------------------------------------------------------------------
run_notify done "Loop done - 5/6" "$tmp/body.txt" >/dev/null
expect "title is passed through whole" "$(grep -qx 'Title: Loop done - 5/6' "$tmp/args.txt" && echo 0 || echo 1)" "title mangled"
expect "NTFY_TOPIC is honoured" "$(grep -qx 'https://ntfy.sh/test-topic' "$tmp/args.txt" && echo 0 || echo 1)" "wrong topic - a run could publish to the wrong channel"

# --- missing arguments fail loudly rather than sending a blank ---------------------------------------
rc=$(CURL_ARGS_OUT="$tmp/args.txt" bash -c 'NTFY_TOPIC=t bash "$1/ci/notify.sh" done' _ "$root" >/dev/null 2>&1; echo $?)
expect "a missing title is refused" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exited $rc"

# --- buttons: Open run stays LAST ---------------------------------------------------------------------
# ntfy allows at most 3 actions and Austin pressed the first one. Summary must outrank Open run.
export CURL_ARGS_OUT="$tmp/args.txt"; : > "$CURL_ARGS_OUT"
NTFY_TOPIC=t RUN_URL='https://example.com/run' SUMMARY_URL='https://example.com/note' \
  bash "$root/ci/notify.sh" done "T" "$tmp/body.txt" >/dev/null 2>&1
actions=$(grep -m1 '^Actions: ' "$tmp/args.txt")
expect "Summary button comes before Open run" "$([ "${actions%%Open run*}" != "$actions" ] && [[ "$actions" == *"Summary"*"Open run"* ]] && echo 0 || echo 1)" "got [$actions]"

if [ "$fails" -gt 0 ]; then echo; echo "$fails FAILED"; exit 1; fi
echo; echo "all notify checks pass"
