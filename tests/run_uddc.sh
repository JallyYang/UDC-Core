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
# -include also accommodates Python-distributed Verilator builds whose make
# configuration leaves the GCC precompiled-header inclusion flag empty.
common=(--cc --exe --build --assert -Wno-fatal -j "$jobs" -CFLAGS -O0
        -MAKEFLAGS 'CFG_CXXFLAGS_PCH_I=-include OPT_FAST=-O0')
python3 tests/uddc_generate.py "$build_dir/vectors.txt"
"${simulator[@]}" "${common[@]}" --top-module uddc_dec_split \
    rtl/uddc_dec_split.sv "$repo_dir/tests/uddc_dispatch.cpp" \
    --Mdir "$build_dir/dispatch" > "$build_dir/dispatch-build.log" 2>&1
"$build_dir/dispatch/Vuddc_dec_split"
"${simulator[@]}" "${common[@]}" --top-module uddc_dec_core \
    -f filelist.f "$repo_dir/tests/uddc_decode.cpp" \
    --Mdir "$build_dir/opt" > "$build_dir/opt-build.log" 2>&1
"$build_dir/opt/Vuddc_dec_core" "$build_dir/vectors.txt"
echo "Build logs and vectors: $build_dir"
