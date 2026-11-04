# Codex repository rules

These rules apply to all RTL in this repository, including new modules and
future edits. Read [rtl/STYLE.md](rtl/STYLE.md) before changing RTL.

- Do not use SystemVerilog structures: no packed or unpacked `struct`, anonymous
  structures, or `typedef struct`. Use explicitly named scalar/vector signals
  and arrays. Persistent pipeline/FIFO fields must remain separately named.
  Plain concatenations may carry fields across interfaces or function returns;
  document their field order and keep their widths explicit. The ban also
  covers inactive preprocessing branches and unused macro definitions.
- Declare one variable per declaration and per line.
- Each always block may assign only one variable. Array elements/slices count
  as the same variable. Express competing writes with explicit priority.
- Use three-part FSMs: state register, next-state logic, and output logic.
- All modules share reset, and no transfer occurs during reset. Keep reset in
  sequential logic, not in combinational ready/valid or datapath logic.
- Do not add file-header comments, default_nettype directives, or
  translate_off/translate_on blocks to RTL.
- Independently switchable pipeline boundaries must support registered and
  combinational modes with matching data, valid, ready, tags and error state.
- Update architecture, macro/port descriptions, cycle tables, tests and comments
  with RTL changes. Label default, bypass and historical configurations clearly.
- Maintain `docs/UDDC_CHANNEL_SPLIT.md` alongside `uddc_channel_split.sv`,
  `uddc_parse_stage.sv`, and splitter/parser handshake changes in the same
  commit. Keep variable meanings before behavior, function descriptions, bit
  layout examples, macro defaults, response/dedup rules, backpressure and cycle
  tables accurate. Also update the linked pipeline/architecture/test documents;
  do not preserve obsolete behavior as a description of the current design.
- Run `python3 tests/check_rtl_style.py` and the regressions relevant to changed
  datapaths. The style checker rejects structures throughout `rtl/`.
