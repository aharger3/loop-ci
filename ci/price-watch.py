#!/usr/bin/env python3
"""Tell Austin when to CHANGE his model stack. Never when not to.

He browses pricing pages because nothing tells him when something matters, so he checks
constantly and optimizes instead of shipping. This runs monthly and stays silent unless
there is an action to take. A notification with no action is the thing being replaced.

Silent means silent: no "all quiet" ping, no monthly digest, no newsletter.

Fires only when:
  1. a tier he actually uses moved more than THRESHOLD in price, or
  2. a model got cheap enough to replace one of his tiers at similar-or-better context.

ponytail: stdlib only, and the snapshot is a committed JSON file rather than a database.
"""
import json, os, sys, urllib.request

THRESHOLD = 0.25                      # 25% move is worth a push notification; 5% is noise
SNAP = os.path.join(os.path.dirname(__file__), "price-snapshot.json")

# What each tier runs today. Keep in sync with the TIERS table in run-spec.ps1.
# GLM is the CODING tier, not a grunt tier - it exists to write code, and calling it "bulk"
# is what made the first report read as if it were interchangeable with flash.
STACK = {
    "grunt":  "deepseek/deepseek-v4-flash",
    "coding": "z-ai/glm-5.2",
}

def fetch():
    req = urllib.request.Request("https://openrouter.ai/api/v1/models",
                                 headers={"User-Agent": "loop-ci-price-watch"})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.load(r)["data"]
    out = {}
    for m in data:
        p = m.get("pricing") or {}
        try:
            pin, pout = float(p["prompt"]) * 1e6, float(p["completion"]) * 1e6
        except (KeyError, TypeError, ValueError):
            continue
        if pin <= 0:                  # free/unpriced entries make "cheaper than" meaningless
            continue
        out[m["id"]] = {"in": pin, "out": pout, "ctx": m.get("context_length") or 0}
    return out

def blended(m):
    """One number to rank on. Weighted 10:1 toward input because agent work is
    input-dominated - it reads files and tool results and writes small diffs. Ranking on
    output price alone is how a model looks cheap and then isn't."""
    return m["in"] * 10 + m["out"]

def main():
    now = fetch()
    old = json.load(open(SNAP)) if os.path.exists(SNAP) else {}
    lines = []

    for tier, mid in STACK.items():
        cur, prev = now.get(mid), old.get(mid)
        if not cur:
            lines.append(f"{tier}: {mid} is GONE from OpenRouter. Pick a replacement.")
            continue
        if prev:
            for k in ("in", "out"):
                if prev[k] > 0:
                    d = (cur[k] - prev[k]) / prev[k]
                    if abs(d) >= THRESHOLD:
                        lines.append(
                            f"{tier} ({mid}) {k} {'+' if d>0 else ''}{d*100:.0f}% "
                            f"(${prev[k]:.3f} -> ${cur[k]:.3f}/M)."
                            + (" Your specs just got cheaper, no action." if d < 0
                               else " Consider swapping this tier.")
                        )
        # A challenger must be cheaper AND not lose context, or the swap costs a rewrite.
        rivals = [(blended(v), k, v) for k, v in now.items()
                  if k != mid and v["ctx"] >= cur["ctx"] * 0.9 and blended(v) < blended(cur) * 0.7]
        if rivals:
            _, name, v = min(rivals)
            lines.append(
                f"{tier}: {name} is ~{(1-blended(v)/blended(cur))*100:.0f}% cheaper at "
                f"${v['in']:.3f}/${v['out']:.3f} with {v['ctx']//1000}k ctx. "
                f"Swap = one env block in ci/run-spec.ps1."
            )

    # A challenger stays cheaper every month, so without this the same "qwen is 74% cheaper"
    # line fires forever and becomes the newsletter this script exists to avoid. Only say it
    # when it is NEW. Austin ignoring it once is an answer.
    said = old.get("_said", [])
    fresh = [l for l in lines if l not in said]
    now["_said"] = lines
    json.dump(now, open(SNAP, "w"), indent=0, sort_keys=True)

    lines = fresh
    if not lines:
        print("no actionable change")   # deliberately NOT a notification
        return 0

    body = "\n".join(f"- {l}" for l in lines)
    print(body)
    # NOT a notification. Austin 2026-08-07: the only pushes he expects are the loop's own
    # four (start/blocked/recommend/done) from a run he triggered. A monthly cron posting
    # `recommend` to the same topic is the fifth sender, and an unattributed "recommendation"
    # with no run behind it is exactly the noise that killed the old channel. It lands on the
    # workflow run summary instead, where it is read when he looks, not when it fires.
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write("## Model stack: something worth changing\n\n" + body + "\n")
    return 0

if __name__ == "__main__":
    sys.exit(main())
