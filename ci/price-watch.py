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
PIN_DRIFT = 0.15                      # a pin 15%+ above the floor is worth re-pinning
SNAP = os.path.join(os.path.dirname(__file__), "price-snapshot.json")

# What each tier runs today. Keep in sync with the TIERS table in run-spec.ps1.
# GLM is the CODING tier, not a grunt tier - it exists to write code, and calling it "bulk"
# is what made the first report read as if it were interchangeable with flash.
STACK = {
    "grunt":  "deepseek/deepseek-v4-flash",
    "coding": "z-ai/glm-5.2",
}

# Provider pinned per model via CLAUDE_CODE_EXTRA_BODY in .github/workflows/loop.yml.
# /v1/models reports ONE price per model, so the tier checks above are blind to the spread
# BETWEEN providers serving it - on 2026-08-08 that spread was 0.36 vs 1.40 per M input for
# the same glm-5.2, i.e. 3.9x. A pin is a bet that one provider stays cheapest, and nothing
# was watching whether it still is.
PINS = {
    "z-ai/glm-5.2": "StreamLake",
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

def endpoints(mid):
    """Per-provider prices for one model. Returns [] on any failure - a pin check that
    can't run must not take the tier checks down with it."""
    req = urllib.request.Request(
        f"https://openrouter.ai/api/v1/models/{mid}/endpoints",
        headers={"User-Agent": "loop-ci-price-watch"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            eps = json.load(r)["data"]["endpoints"]
    except Exception:
        return []
    out = []
    for e in eps:
        try:
            out.append({"name": e["provider_name"],
                        "in": float(e["pricing"]["prompt"]) * 1e6,
                        "out": float(e["pricing"]["completion"]) * 1e6,
                        "ctx": e.get("context_length") or 0})
        except (KeyError, TypeError, ValueError):
            continue
    return [e for e in out if e["in"] > 0]


def pin_drift(mid, pinned_name):
    """One line if the pinned provider is gone, or is meaningfully off the floor.

    Point-in-time, so nothing is snapshotted: "is my pin still the cheapest" has a fresh
    answer every run, unlike "did this price move" which needs last month to compare to.
    A cheaper provider that truncates context is not cheaper, it is a different model.
    """
    eps = endpoints(mid)
    if not eps:
        return None
    # A provider can list the same model twice at different prices (fp8 vs bf16 variants);
    # on 2026-08-08 five did. Take the provider's CHEAPEST entry so a pricier sibling variant
    # can't fake a "repin" alarm against a pin that is actually fine.
    mine = [e for e in eps if e["name"] == pinned_name]
    pinned = min(mine, key=blended) if mine else None
    if not pinned:
        floor = min(eps, key=blended)
        return (f"PIN DEAD: {pinned_name} no longer serves {mid}. Cheapest now is "
                f"{floor['name']} at ${floor['in']:.2f}/${floor['out']:.2f}/M. "
                f"Repin in CLAUDE_CODE_EXTRA_BODY (loop.yml) or requests land anywhere.")
    rivals = [e for e in eps if e["ctx"] >= pinned["ctx"] * 0.9]
    floor = min(rivals, key=blended)
    if floor["name"] == pinned_name:
        return None
    gain = 1 - blended(floor) / blended(pinned)
    if gain < PIN_DRIFT:
        return None
    return (f"REPIN {mid}: {floor['name']} is ~{gain*100:.0f}% under your {pinned_name} pin "
            f"(${floor['in']:.2f}/${floor['out']:.2f} vs ${pinned['in']:.2f}/"
            f"${pinned['out']:.2f}/M, {floor['ctx']//1000}k ctx). "
            f"Swap the provider.order in CLAUDE_CODE_EXTRA_BODY.")


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

    # Pin drift is the OTHER half of "am I overpaying": the tier loop above compares models,
    # this compares providers serving the model already chosen.
    for mid, pinned_name in PINS.items():
        line = pin_drift(mid, pinned_name)
        if line:
            lines.append(line)

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
