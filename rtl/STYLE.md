# RTL style

- Declare one variable per declaration and per line, including function
  arguments, local variables, parameters and unpacked arrays.
- Each `always`, `always_comb` or `always_ff` process assigns only one target
  variable. Array elements and slices count as one signal; payload struct
  fields have separate processes. Loop-control variables are not state outputs.
- Write state machines in three parts: a dedicated current-state register,
  combinational next-state `case`, and separate output logic. Split the output
  part into one process per variable. Preserve the existing combinational or
  registered output timing; adding a register solely for style changes latency.
- Preserve reset behavior, clock enables and the priority of multiple writes
  to one variable when splitting a process.
- Express competing updates to the same register bit with explicit `if / else if`
  branches rather than relying on the order of nonblocking assignments. For
  indexed flags, update each slot independently so different slots can still
  change in the same cycle.
- All connected modules share reset; no transfer is valid while `rst_n=0`.
  Do not gate combinational datapaths, next-state logic or ready/valid outputs
  directly with reset. Keep sequential reset/write guards;
  ready/valid levels during reset do not represent accepted transactions.
- Prefer descriptive event names such as `input_accepted` and
  `package_dispatch_finished` over abbreviations such as `fire`.

- Keep file headers free of explanatory comments and omit `default_nettype`
  directives. Do not add `translate_off/on` simulation blocks to RTL.
- Update architecture, interfaces, cycle tables, test commands and code comments
  together with functional or pipeline changes; label nondefault configurations.

Run `python3 tests/check_rtl_style.py` with `pyslang==12.1.0` installed to check
declarations, assignment targets, both dispatch FSMs and RTL elaboration.
Run `bash tests/run_uddc.sh` to check decoder functionality and cycle latency.
