# UDDC decode regression

Run `bash tests/run_uddc.sh` from a checkout with Python 3, Verilator and a
C++20 compiler. The Python `verilator` package is supported as an alternative
to an executable on PATH. Build products stay outside the checkout. Set
`UDDC_TEST_BUILD_DIR` to reuse a build directory and `UDDC_TEST_JOBS` to limit
parallel compilation (default 4).
The regression defaults to four slots; set `UDDC_TEST_SLOTS=8` to check the RTL's
unchanged default configuration.

`uddc_dispatch.cpp` verifies the dispatcher's first-beat context bypass,
consecutive snapshot replacement, same-cycle accepted-input forwarding,
package switching and request stability under backpressure. Its parser
completion input is modeled independently using the required byte count.

With the first input handshake numbered cycle 0, a continuously supplied
three-sector unit whose pkg0 requires 40B produces requests at:

| Cycle | Request |
| --- | --- |
| 1 | pkg0, first 32B |
| 2 | pkg0, first 64B |
| 3 | pkg1, all 96B |

The previous dispatcher produced requests on cycles 2, 4 and 6 in the same
scenario. A pkg0 that completes in the first sector switches earlier; pkg1
still waits until the occupied region is available because its header is at
the high end. Input gaps and backpressure can extend this schedule.

`uddc_generate.py` constructs 908 deterministic units using a software model
of field allocation, signed deltas, predictor reconstruction, color recovery
and pixel ordering from `DicAlgo.html`. Cases cover all 14 formats, all CBMD
modes, invalid reserved header bits, and explicit >64B packages in both roles.
`uddc_decode.cpp` compares all output words, framing and errors in input order,
with random source gaps and output backpressure, including stalled-output
stability. This is an RTL regression, not an independent normative codec.

The decoder does not impose a 64B package limit: section 2.1.5.3 allows packages
up to 68B. An incomplete pkg0 prefix is retried with the third sector. The
parser's internal `s_done` indicates successful parsing or final malformed
input; the dispatcher uses it only on a valid/ready handshake. Unlike the old
global `result_sent` state, this handshake needs no final-sector cleanup
request after an early successful parse.

These checks establish cycle scheduling and functional behavior. They do not
measure Fmax or area. The completion feedback includes parser combinational
logic; synthesis and static timing analysis are needed to assess that path.

## Decode latency regression

The decode path now performs distance-1 accumulation in the first delta
register, followed by distances 2, 4 and 8. It has four delta registers rather
than an input-copy register plus four accumulation registers. Color recovery
uses the combinational option of `uddc_correlation`; pixel reconstruction
captures the recovered, reordered pixels in one register. The default
standalone correlation module still registers its output.

`uddc_package_out` includes an accepted head-unit package in its combinational
view of completion, formats, sizes, errors and data. If that package completes
the unit, the first output beat need not wait for cache writeback. All checks
still precede output. The same package is written to storage whether the
output accepts or stalls, preserving the first beat and its error status.

With no queueing, continuously supplied input and `m_ready=1`, cycle 0 is the
first input handshake:

| Case | Previous first output | Current first output | Current last output |
| --- | --- | --- | --- |
| One-sector DIC | 11 | 8 | 11 |
| Three-sector DIC, pkg0=64B/pkg1=20B | 12 | 9 | 12 |
| Three-sector DIC, pkg0>64B | 13 | 10 | 13 |
| Three-sector DIC, invalid pkg0 header | 13 | 10 | 13 |

`uddc_latency_vectors.py` generates explicit 64B boundary packages in both
roles, >64B compatibility, short packages, malformed headers and mixed modes.
The continuous-source tests require the first output at the cycle above and
zero subsequent gaps in the primed workloads. Randomized functional tests
continue to exercise source gaps, output stalls and data ordering.

`uddc_output_forward.cpp` directly checks both package arrival orders,
immediate output, forwarding-to-storage stability while stalled, package
errors, mismatched formats, invalid sizes and final retirement.

Starting with Clear still exposes a startup gap before a following DIC unit:
the directed case now has three gap cycles rather than six. There is no new
output prefill policy. These latency reductions are in clock cycles; the
merged color/pixel path and output-forwarding path require static timing
analysis before claiming a frequency or elapsed-time improvement.
