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

### T2 -- judgment row that must wait for T1

- model: opus
- depends-on: T1

Decide something.

- **done-when:** decided.

### T3 -- glm row, also waits for T1

- model: z-ai/glm-5.2
- depends-on: T1

Mechanical but big.

- **done-when:** done.

### [x] T4 -- already finished, must be skipped not re-run

- model: auto/best-coding

Old row.

- **done-when:** already done.

### T5 -- runs last

- model: glm
- depends-on: everything

Write the report.

- **done-when:** report exists.
