#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
build_dir=${UDDC_TEST_BUILD_DIR:-$(mktemp -d /tmp/uddc-test.XXXXXX)}
mkdir -p "$build_dir"
build_dir=$(cd "$build_dir" && pwd)
cd "$repo_dir"
if command -v verilator >/dev/null 2>&1; then
    simulator=(verilator)
else
    simulator=(python3 -m verilator)
fi
jobs=${UDDC_TEST_JOBS:-4}
slots=${UDDC_TEST_SLOTS:-4}
header_reg=${UDDC_PARSE_HEADER_REG:-1}
index_reg=${UDDC_PARSE_INDEX_REG:-1}
layout_reg=${UDDC_PARSE_LAYOUT_REG:-1}
for value in "$header_reg" "$index_reg" "$layout_reg"; do
    [[ "$value" == 0 || "$value" == 1 ]] || { echo 'Parser register switches must be 0 or 1' >&2; exit 2; }
done
extra_stages=$((header_reg + index_reg + layout_reg))
# -include also accommodates Python-distributed Verilator builds whose make
# configuration leaves the GCC precompiled-header inclusion flag empty.
common=(--cc --exe --build --assert -Wno-fatal -j "$jobs" -CFLAGS -O0
        +define+UDDC_PARSE_HEADER_REG="$header_reg"
        +define+UDDC_PARSE_INDEX_REG="$index_reg"
        +define+UDDC_PARSE_LAYOUT_REG="$layout_reg"
        -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include OPT_FAST=-O0')
python3 tests/uddc_generate.py "$build_dir/vectors.txt"
"${simulator[@]}" "${common[@]}" --top-module uddc_dec_split \
    -GUNIT_SLOTS="$slots" \
    rtl/uddc_dec_split.sv "$repo_dir/tests/uddc_dispatch.cpp" \
    --Mdir "$build_dir/dispatch" > "$build_dir/dispatch-build.log" 2>&1
"$build_dir/dispatch/Vuddc_dec_split"
"${simulator[@]}" "${common[@]}" --top-module uddc_package_out \
    -GUNIT_SLOTS="$slots" \
    rtl/uddc_package_out.sv "$repo_dir/tests/uddc_output_forward.cpp" \
    --Mdir "$build_dir/output" > "$build_dir/output-build.log" 2>&1
"$build_dir/output/Vuddc_package_out"
"${simulator[@]}" "${common[@]}" --top-module uddc_dec_core \
    -GUNIT_SLOTS="$slots" \
    -f filelist.f "$repo_dir/tests/uddc_decode.cpp" \
    --Mdir "$build_dir/obj$slots" > "$build_dir/core-build.log" 2>&1
decoder="$build_dir/obj$slots/Vuddc_dec_core"
"$decoder" "$build_dir/vectors.txt"
python3 -B tests/uddc_latency_vectors.py "$build_dir/latency"
# Registered mode sends longer prefixes while older ones are still in flight.
if ((extra_stages == 3)); then
    for name in boundary reverse_boundary mixed wide bad_header; do
        "$decoder" "$build_dir/latency/$name.txt" --continuous --expect-first=13 --max-gaps=0
    done
    "$decoder" "$build_dir/latency/short.txt" --continuous --expect-first=11 --max-gaps=0
    "$decoder" "$build_dir/latency/clear_then_boundary.txt" --continuous --expect-first=4 --max-gaps=6
    echo "Build logs and vectors: $build_dir"
    exit 0
fi
if ((extra_stages > 0)); then
    for name in boundary reverse_boundary mixed short wide bad_header clear_then_boundary; do
        "$decoder" "$build_dir/latency/$name.txt" --continuous
    done
    echo "Build logs and vectors: $build_dir"
    exit 0
fi
# All three register boundaries bypassed: retain the earlier cycle targets.
for name in boundary reverse_boundary mixed; do
    "$decoder" "$build_dir/latency/$name.txt" --continuous --expect-first=9 --max-gaps=0
done
"$decoder" "$build_dir/latency/short.txt" --continuous --expect-first=8 --max-gaps=0
"$decoder" "$build_dir/latency/wide.txt" --continuous --expect-first=10 --max-gaps=0
"$decoder" "$build_dir/latency/bad_header.txt" --continuous --expect-first=10 --max-gaps=0
"$decoder" "$build_dir/latency/clear_then_boundary.txt" --continuous --expect-first=4 --max-gaps=3
echo "Build logs and vectors: $build_dir"
