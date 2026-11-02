#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
build_dir=${UDC_TEST_BUILD_DIR:-$(mktemp -d /tmp/udc-stream-test.XXXXXX)}
mkdir -p "$build_dir"
build_dir=$(cd "$build_dir" && pwd)
cd "$repo_dir"
if command -v verilator >/dev/null 2>&1; then
    simulator=(verilator)
else
    simulator=(python3 -m verilator)
fi
python3 tests/udc_stream_reference.py "$build_dir"
"${simulator[@]}" --cc --exe --build --assert -Wno-fatal -j "${UDC_TEST_JOBS:-4}" \
    -CFLAGS -O0 -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include OPT_FAST=-O0' \
    --top-module compare -f filelist.f -f "$build_dir/old.f" \
    "$build_dir/compare.sv" "$repo_dir/tests/udc_stream_compare.cpp" \
    "$repo_dir/tests/udc_stream_performance.cpp" \
    --Mdir "$build_dir/build" > "$build_dir/build.log" 2>&1
"$build_dir/build/Vcompare"
"$build_dir/build/Vcompare" --performance
