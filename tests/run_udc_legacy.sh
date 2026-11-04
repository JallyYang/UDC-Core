#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
build_dir=${UDC_LEGACY_BUILD_DIR:-$(mktemp -d /tmp/udc-legacy.XXXXXX)}
mkdir -p "$build_dir"
build_dir=$(cd "$build_dir" && pwd)
cd "$repo_dir"
if command -v verilator >/dev/null 2>&1; then simulator=(verilator); else simulator=(python3 -m verilator); fi
# Avoid very large unity translation units on newer Verilator versions.
split_args=()
if [[ $("${simulator[@]}" --help 2>&1) == *"--output-groups"* ]]; then
    split_args=(--output-groups 0)
fi
python3 tests/udc_legacy_reference.py "$build_dir"
"${simulator[@]}" "${split_args[@]}" --cc --exe --build -Wno-fatal -j "${UDC_TEST_JOBS:-2}" \
    -CFLAGS -O0 -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include OPT_FAST=-O0' \
    --top-module legacy_compare -f filelist.f -f "$build_dir/reference.f" \
    "$build_dir/legacy_compare.sv" "$repo_dir/tests/udc_legacy_compare.cpp" \
    --Mdir "$build_dir/build" > "$build_dir/build.log" 2>&1
"$build_dir/build/Vlegacy_compare"
