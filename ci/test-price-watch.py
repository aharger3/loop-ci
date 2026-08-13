#!/usr/bin/env python3
"""Self-check for ci/price-watch.py. Run: python3 ci/test-price-watch.py

Hits no network: fetch() and endpoints() are replaced with canned data, and the snapshot is
redirected to a temp file so the committed ci/price-snapshot.json is never touched.

The invariant worth defending here is SILENCE. This script exists to stay quiet, and every
historical complaint about it was a false positive - a line that fired forever, a pricier
sibling variant faking a repin alarm, a "challenger" that was only cheap because it dropped
context. A test that only checked "does it warn" would be testing the wrong half.
"""
import importlib.util, json, os, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("pw", os.path.join(HERE, "price-watch.py"))
pw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pw)

fails = 0
def expect(name, cond, detail=""):
    global fails
    if cond:
        print(f"ok   {name}")
    else:
        print(f"FAIL {name} : {detail}")
        fails += 1

def model(pin, pout, ctx=128000):
    return {"in": pin, "out": pout, "ctx": ctx}

GRUNT, CODING = pw.STACK["grunt"], pw.STACK["coding"]
BASE = {GRUNT: model(0.10, 0.40), CODING: model(0.36, 1.40)}

def run(now, snapshot=None, endpoints=None):
    """Run main() against canned data. Returns (printed lines, snapshot written)."""
    tmp = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump(snapshot or {}, tmp)
    tmp.close()
    old_snap, old_fetch, old_eps = pw.SNAP, pw.fetch, pw.endpoints
    pw.SNAP = tmp.name
    pw.fetch = lambda: json.loads(json.dumps(now))          # deep copy: main() mutates it
    pw.endpoints = (lambda mid: (endpoints or {}).get(mid, []))
    import io, contextlib
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            pw.main()
        written = json.load(open(tmp.name))
    finally:
        pw.SNAP, pw.fetch, pw.endpoints = old_snap, old_fetch, old_eps
        os.unlink(tmp.name)
    return buf.getvalue().strip(), written

# ------------------------------------------------------------------------------- blended -----
# Input-weighted 10:1. A model with a cheap headline output price but dear input must NOT rank
# above one that is cheaper on the input side - that mistake is how a "cheaper" swap costs more.
expect("blended weights input 10:1", pw.blended(model(1.0, 0.0)) == 10.0, pw.blended(model(1.0, 0.0)))
expect("blended ranks input-dominated work",
       pw.blended(model(0.10, 5.0)) < pw.blended(model(1.00, 0.10)),
       "a dear-input model ranked cheaper")

# --------------------------------------------------------------------------------- silence ---
out, _ = run(BASE, snapshot=BASE)
expect("silent when nothing moved", out == "no actionable change", f"said: {out}")

out, _ = run(BASE)
expect("silent on a first run with no snapshot", out == "no actionable change", f"said: {out}")

# --------------------------------------------------------------------- price move threshold ---
# 25% is the bar. Just under it is noise and must stay silent; over it is worth a line.
under = {GRUNT: model(0.12, 0.40), CODING: BASE[CODING]}          # +20%
out, _ = run(under, snapshot=BASE)
expect("a 20% move stays silent", out == "no actionable change", f"said: {out}")

over = {GRUNT: model(0.14, 0.40), CODING: BASE[CODING]}           # +40%
out, _ = run(over, snapshot=BASE)
expect("a 40% rise is reported", "grunt" in out and "+40%" in out, f"said: {out}")
expect("a rise suggests action", "Consider swapping" in out, f"said: {out}")

cheaper = {GRUNT: model(0.05, 0.40), CODING: BASE[CODING]}        # -50%
out, _ = run(cheaper, snapshot=BASE)
expect("a fall says explicitly no action", "no action" in out, f"said: {out}")

# ------------------------------------------------------------------------- a missing model ----
out, _ = run({CODING: BASE[CODING]}, snapshot=BASE)
expect("a vanished tier model is reported", "GONE" in out, f"said: {out}")

# ------------------------------------------------------------------------------ challengers ---
# Cheaper AND not losing context. A rival that truncates context is a different model, not a
# cheaper one, and swapping to it costs a rewrite.
short = dict(BASE); short["rival/short-ctx"] = model(0.01, 0.02, ctx=8000)
out, _ = run(short, snapshot=BASE)
expect("a cheap rival with less context is ignored", out == "no actionable change", f"said: {out}")

good = dict(BASE); good["rival/full-ctx"] = model(0.01, 0.02, ctx=128000)
out, _ = run(good, snapshot=BASE)
expect("a cheap rival at full context is reported", "rival/full-ctx" in out, f"said: {out}")

# 30% cheaper is not enough - the bar is blended < 70% of current, because a swap is not free.
# 0.30/1.20 is ~16% under the coding tier and dearer than the grunt tier, so neither may bite.
marginal = dict(BASE); marginal["rival/meh"] = model(0.30, 1.20, ctx=128000)
out, _ = run(marginal, snapshot=BASE)
expect("a marginally cheaper rival is ignored", "rival/meh" not in out, f"said: {out}")

# The tiers must never challenge EACH OTHER. deepseek really is ~55% cheaper than glm at the
# same context, so before 2026-08-13 this script told Austin to replace his coding tier with his
# own grunt model. A tier chosen on capability is not a rival to a tier chosen on price.
out, _ = run(BASE, snapshot=BASE)
expect("the grunt tier is not offered as a coding challenger", GRUNT not in out, f"said: {out}")
expect("the coding tier is not offered as a grunt challenger", CODING not in out, f"said: {out}")

# ------------------------------------------------------------------- the newsletter guard -----
# A challenger stays cheaper every month. Saying so once is a recommendation; saying so every
# month is the newsletter this script exists not to be.
out1, snap1 = run(good, snapshot=BASE)
expect("a new finding is said once", "rival/full-ctx" in out1, f"said: {out1}")
out2, _ = run(good, snapshot=snap1)
expect("the same finding is NOT repeated", out2 == "no actionable change", f"repeated: {out2}")
expect("the finding is remembered in _said", any("rival/full-ctx" in s for s in snap1["_said"]),
       f"_said: {snap1.get('_said')}")

# A DIFFERENT finding still gets through after a quiet month.
newer = dict(good); newer["rival/cheaper-still"] = model(0.005, 0.01, ctx=128000)
out3, _ = run(newer, snapshot=snap1)
expect("a genuinely new finding still fires", "cheaper-still" in out3, f"said: {out3}")

# ---------------------------------------------------------------------------- pin drift -------
PINNED = pw.PINS and list(pw.PINS.items())[0]
expect("there is a pin to check", bool(PINNED), "PINS is empty")
mid, pin_name = PINNED

def ep(name, pin, pout, ctx=128000):
    return {"name": name, "in": pin, "out": pout, "ctx": ctx}

pw_eps = lambda eps: (lambda m: eps)
old = pw.endpoints
try:
    pw.endpoints = pw_eps([ep(pin_name, 0.36, 1.40), ep("Rival", 0.35, 1.38)])
    expect("a pin within 15% of the floor is silent", pw.pin_drift(mid, pin_name) is None,
           pw.pin_drift(mid, pin_name))

    pw.endpoints = pw_eps([ep(pin_name, 1.40, 2.00), ep("Rival", 0.36, 1.00)])
    d = pw.pin_drift(mid, pin_name)
    expect("a badly drifted pin is reported", d and "REPIN" in d, d)

    pw.endpoints = pw_eps([ep("Rival", 0.36, 1.00)])
    d = pw.pin_drift(mid, pin_name)
    expect("a dead pin is reported", d and "PIN DEAD" in d, d)

    # The fp8-vs-bf16 case: the pinned provider lists the model twice. Its CHEAPEST entry is the
    # one that counts, or a pricier sibling variant fakes a repin alarm against a healthy pin.
    pw.endpoints = pw_eps([ep(pin_name, 5.00, 9.00), ep(pin_name, 0.36, 1.40), ep("Rival", 0.35, 1.38)])
    expect("a pricier sibling variant does not fake an alarm", pw.pin_drift(mid, pin_name) is None,
           pw.pin_drift(mid, pin_name))

    # A cheaper rival that truncates context is not cheaper here either.
    pw.endpoints = pw_eps([ep(pin_name, 1.40, 2.00), ep("Rival", 0.10, 0.20, ctx=8000)])
    expect("a short-context rival cannot win the pin", pw.pin_drift(mid, pin_name) is None,
           pw.pin_drift(mid, pin_name))

    # endpoints() returns [] on any failure, and a pin check that cannot run must stay quiet
    # rather than guess.
    pw.endpoints = pw_eps([])
    expect("an unavailable endpoint list is silent", pw.pin_drift(mid, pin_name) is None,
           pw.pin_drift(mid, pin_name))
finally:
    pw.endpoints = old

# ------------------------------------------------------- it never sends a notification --------
# Settled negative: ntfy is aborted everywhere except the loop lifecycle topic. This script
# writes to the step summary and nowhere else.
src = open(os.path.join(HERE, "price-watch.py")).read()
expect("price-watch never touches ntfy", "ntfy" not in src.lower().replace("# ntfy", ""),
       "an ntfy call appeared in a script that must stay silent")

if fails:
    print(f"\n{fails} FAILED")
    sys.exit(1)
print("\nall price-watch checks pass")
