#!/usr/bin/env bash
# notify.sh <type> <title> <body-file> - the ONLY thing in this repo allowed to touch ntfy.
#
# Austin 2026-08-02: "ntfy notifs are a mess, it needs to be simple and accurate. Just start
# and eta, another recommendation, blocked/human task needed with exact steps to get it
# running again, and done." Those four. The old rig sent a rollup per row per phase, which is
# why nothing got read. Anything not in this list is a log line, not a notification.
#
# Enforcement is the case statement: an unknown type exits 2 and fails the step, so a new
# notification cannot be added by accident somewhere else in the workflow.
set -euo pipefail

TYPE="${1:?type: start|blocked|recommend|done}"
TITLE="${2:?title}"
BODY="${3:?path to body file}"
TOPIC="${NTFY_TOPIC:-aharg-loop}"

case "$TYPE" in
  start)     PRIO=default; TAGS="rocket"        ;;
  blocked)   PRIO=high;    TAGS="warning"       ;;  # the only one that should wake anyone
  recommend) PRIO=low;     TAGS="bulb"          ;;
  done)      PRIO=default; TAGS="white_check_mark" ;;
  *) echo "notify.sh: refusing unknown type '$TYPE' (start|blocked|recommend|done)" >&2; exit 2 ;;
esac

# --data-binary @file, never -d "$string": a body with a newline or a quote in it silently
# truncates otherwise, and a truncated BLOCKED message is a missing resume step.
curl -sS --fail-with-body \
  -H "Title: ${TITLE}" \
  -H "Priority: ${PRIO}" \
  -H "Tags: ${TAGS}" \
  -H "Actions: view, Open run, ${RUN_URL:-https://github.com}" \
  --data-binary "@${BODY}" \
  "https://ntfy.sh/${TOPIC}" > /dev/null
