# OMEN v3.2 - fix alpaca baseline

status: ready
version: v3.2-fix-alpaca-baseline
repo: aharger3/tradingbot
doc: Projects/TradingBot.md
previous: omen-v3.1.md - T2-T6 completed for one_candle_rule

target: Fix the Alpaca paper account 403 Forbidden issue so that the frozen baseline can accumulate trades.

---

## Model routing

opus -> glm 5.2 -> deepseek -> omniroute

| phase / task | model | why |
|---|---|---|
| T1 fix alpaca account | opus | decision and action |

## Environment

- set PYTHONIOENCODING=utf-8 before every Python run
- cd to project: above
- No pytest. Tests = assert scripts: python test_x.py
- ALPACA_PAPER_KEY/SECRET live (fixed 7/31)
- OMEN_FROZEN_HASH=804abeb70aa8 (frozen cohort stays armed)

## Tasks

### T1 -- fix alpaca paper account and verify frozen baseline accumulates

- model: opus (direct to api.anthropic.com via CLAUDE_CONSOLE_API_KEY)

- Check the Alpaca dashboard for the paper account. If it shows 403 Forbidden, regenerate the paper API key and secret.
- Update the .env file with the new secret (if needed) using the keys.py script.
- Verify that the PaperBook can now instantiate without throwing 403 Forbidden.
- Optionally, run the frozen scanner for a short time to verify that trades are being logged to journal/paper-frozen.jsonl.

- **done-when:** Alpaca paper account returns 200 for API calls, .env updated if needed, and a test run of the frozen scanner logs at least one trade to journal/paper-frozen.jsonl.