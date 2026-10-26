# UDDC decode regression

Run `bash tests/run_uddc.sh` from a checkout with Python 3, Verilator and a
C++20 compiler. The Python `verilator` package is supported as an alternative
to an executable on PATH. Build products stay outside the checkout. Set
`UDDC_TEST_BUILD_DIR` to reuse a build directory and `UDDC_TEST_JOBS` to limit
parallel compilation (default 4).

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
