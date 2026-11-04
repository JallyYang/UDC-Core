#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
build_dir=${UDDC_PARSER_BUILD_DIR:-$(mktemp -d /tmp/uddc-parser.XXXXXX)}
mkdir -p "$build_dir"
build_dir=$(cd "$build_dir" && pwd)
cd "$repo_dir"
if command -v verilator >/dev/null 2>&1; then simulator=(verilator); else simulator=(python3 -m verilator); fi
python3 tests/uddc_generate.py "$build_dir/vectors.txt"
python3 tests/uddc_parser_reference.py "$build_dir"
"${simulator[@]}" --cc --exe --build -Wno-fatal -j "${UDDC_TEST_JOBS:-4}" \
    -CFLAGS -O0 -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include OPT_FAST=-O0' \
    --top-module parser_compare rtl/uddc_parse_stage.sv rtl/uddc_channel_split.sv \
    "$build_dir/reference_parser.sv" "$build_dir/parser_compare.sv" \
    "$repo_dir/tests/uddc_parser_compare.cpp" --Mdir "$build_dir/build" > "$build_dir/build.log" 2>&1
"$build_dir/build/Vparser_compare" "$build_dir/vectors.txt"
