# One-cycle versus two-cycle reconstruction trees

Target requested: TSMC7, 1.5GHz (0.666667ns). No TSMC7 Liberty library, process
corner, RC corner, or commercial synthesis installation was available in this
workspace. **The following numbers are Nangate45 reference results, not TSMC7
timing results.** They do not establish whether either design meets 1.5GHz in
TSMC7. Absolute frequency must not be scaled between the two technologies.

## What is compared

`generate.py` builds constant-format versions of actual decoder prediction
relations: format 1 (64 samples of 8 bits, row width 8), format 2 (32 samples
of 16 bits, row width 8), and format 3 (16 samples of 32 bits, row width 4).
Each design restores every sample in a 512-bit block, with the channel anchor
included in each balanced summation tree. Samples use the decoder's modulo
channel-width arithmetic. The maximum nonzero-delta chain lengths are 14,
10, and 6 respectively; including the anchor gives at most 15, 11, and 7
operands. Sample zero equals the anchor and does not consume delta zero.

Both alternatives include identical input-capture registers and registered
outputs. Those input registers provide a comparable real cell driving the
tree for register-to-register STA. Tree latency is counted **after** the
input-capture register: one or two cycles. The two-cycle variant registers
groups of up to four operands, splitting four logical levels as 2+2, or three
levels as 2+1. No automatic retiming crosses these register boundaries.

This benchmark isolates arithmetic on ready operands. It does **not** include
runtime format selection, parser bit extraction, valid/ready control, color
recovery, pixel reconstruction, or output forwarding. It is not the timing
of the complete current `uddc_delta_cal` or decoder. The synthesis tool may
optimize associative sums and share logic differently across alternatives.

## Reference conditions and results

- Yosys 0.52, its packaged ABC, OpenSTA 2.0.17; versions and hashes are in
  `reports/nangate45_typical/provenance.json`.
- Nangate45 typical library, 1.10V, 25C. Library source is pinned to OpenROAD
  flow scripts commit `64939f3717ad7c694199ba04cb98924b98022868`.
- Ideal 1.5GHz clock, zero clock uncertainty, no clock-tree insertion/skew.
- Identical library `5K_hvratio_1_1` top wire-load model; no placement or routed
  parasitics. BUF_X1 ABC driving model and 1fF output load.
- Worst register-to-register setup path, including launch clock-to-Q and
  capture setup time. No unconstrained timing endpoint or tool error was
  reported by the checks used here.

The equivalent minimum period below is `0.666667ns - worst setup slack` for
the **fixed mapped netlist**, not a new synthesis run at that period or a
post-layout Fmax measurement.

| Sample width | One-cycle period estimate | Two-cycle period estimate | Period reduction | Cell area increase |
| --- | ---: | ---: | ---: | ---: |
| 8 | 1.188854ns | 0.806911ns | 32.1% | 17.2% |
| 16 | 1.257997ns | 0.900875ns | 28.4% | 21.4% |
| 32 | 1.778421ns | 1.683127ns | 5.4% | 24.5% |

| Width | One-cycle setup slack at 0.666667ns | Two-cycle setup slack | One-cycle cell area | Two-cycle cell area |
| --- | ---: | ---: | ---: | ---: |
| 8 | -0.522187ns | -0.140244ns | 12686.604 | 14863.282 |
| 16 | -0.591330ns | -0.234208ns | 12558.392 | 15244.726 |
| 32 | -1.111754ns | -1.016460ns | 11308.990 | 14074.858 |

Areas are Nangate library cell areas (um^2); they exclude routing and CTS.
Each one-cycle variant has 1024 FF bits; each two-cycle variant has 1536.
Counts include 512 common input-capture FF bits. Thus splitting adds 512 FF
bits, rather than changing the input sampling or throughput. Both designs
can accept one ready 512-bit block every cycle.

All six reference variants violate the requested 0.666667ns period **in this
Nangate45 experiment**. No conclusion about TSMC7 pass/fail follows from that.

The 32-bit two-cycle critical path runs from `delta_ready[384]` to
`partial_15_0[31]`: the first half is still the limiting stage. This 32-bit
format has only three logical sum levels, split as 2+1. Mapping, carry
propagation, sharing, fanout, and wire-load estimates make the improvement
much smaller than an assumed factor of two. Pipeline balance and arithmetic
implementation need attention before merely adding more registers.

For latency-sensitive use at a fixed 1.5GHz, prefer the fewest stages that
meet the real TSMC7 setup budget with margin: one tree cycle costs 0.667ns;
two cost 1.333ns. The reference numbers alone do not choose that stage count.

## Reproduce or substitute a library

Install Yosys/ABC, OpenSTA and optionally Icarus Verilog. Use an unencrypted
NLDM Liberty library that the tools support. The Liberty file is not included
in this repository; source URL and SHA256 are recorded in provenance.

```bash
python3 synthesis/adder_tree_compare/run.py \
  --liberty /path/to/NangateOpenCellLibrary_typical.lib \
  --build-dir /tmp/uddc-tree-compare \
  --driving-cell BUF_X1 \
  --wire-load-model 5K_hvratio_1_1
```

The runner accepts `--yosys`, `--abc`, `--sta`, `--clock-ns` and `--load-ff`.
For TSMC7, supply the actual licensed corner library and a valid driving cell
name. Supply the appropriate wire-load model if present; omission uses the
library default, which can mean no wire parasitics. That is still pre-layout
analysis and must be labeled accordingly. A `.db`-only or encrypted library
requires an appropriate commercial tool flow rather than this runner.

`run.py` records mapped netlists, scripts, tool logs, area/register counts,
the five worst setup paths and machine-readable summary/provenance in the
build directory. It rejects tool errors even when older OpenSTA returns a
zero exit code. The checked-in reports contain the reference setup paths
and summaries, not the PDK or generated netlists.

## Functional checks

`testbench.sv` uses an independent serial predictor recurrence, not another
copy of the generated balanced tree. It checks both pipeline latencies on
512 inputs per width, including zeros, all ones, signed edge patterns and
random data. All three widths passed (1536 input blocks, both alternatives).

```bash
python3 synthesis/adder_tree_compare/generate.py /tmp/uddc-tree-compare/rtl
for width in 8 16 32; do
  iverilog -g2012 -s testbench -Ptestbench.WIDTH="$width" \
    -o "/tmp/uddc-tree-compare/check$width" \
    synthesis/adder_tree_compare/testbench.sv /tmp/uddc-tree-compare/rtl/*.v
  vvp "/tmp/uddc-tree-compare/check$width"
done
```
