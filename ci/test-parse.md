# selftest spec

status: ready
version: selftest
repo: aharger3/example

target: prove the parser and the router agree with the spec, for zero tokens.

## Tasks

### T1 -- grunt row, no deps

- model: deepseek

Do a mechanical thing.

- **done-when:** it is done.
- **verify:** `test -f README.md`

### T2 -- judgment row that must wait for T1

- model: opus
- depends-on: T1

Decide something.

- **done-when:** decided.
- **verify:** `grep -q "loop-ci" README.md`

### T3 -- glm row, also waits for T1

- model: z-ai/glm-5.2
- depends-on: T1

Mechanical but big. This row's verify is a FENCED BLOCK, the two-command dialect - if it ever
stops parsing, a multi-step check silently becomes an empty one.

- **done-when:** done.
- **verify:**
  ```bash
  test -d ci
  test -f ci/notify.sh
  ```

### [x] T4 -- already finished, must be skipped not re-run

- model: auto/best-coding

Old row. A row already marked [x] is never executed, so it is the one row allowed to have no
verify: at all - the parser must not demand one here.

- **done-when:** already done.

### T5 -- runs last

- model: glm
- depends-on: everything

Write the report. Backticks are markup, not part of the command, and a glob inside them must
survive - Clean() would have eaten both.

- **done-when:** report exists.
- **verify:** `ls specs/*.md > /dev/null`
