#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
build_dir=${RS_TEST_BUILD_DIR:-$(mktemp -d /tmp/de-rs-reg.XXXXXX)}
mkdir -p "$build_dir"
build_dir=$(cd "$build_dir" && pwd)
cd "$repo_dir"
if command -v verilator >/dev/null 2>&1; then simulator=(verilator); else simulator=(python3 -m verilator); fi
"${simulator[@]}" --cc --exe --build -Wno-fatal -j "${RS_TEST_JOBS:-2}" \
    -CFLAGS -O0 -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include OPT_FAST=-O0' \
    --top-module de_rs_reg_test rtl/de_rs_reg.v tests/de_rs_reg_test.sv \
    "$repo_dir/tests/de_rs_reg_test.cpp" --Mdir "$build_dir/build" > "$build_dir/build.log" 2>&1
"$build_dir/build/Vde_rs_reg_test"
