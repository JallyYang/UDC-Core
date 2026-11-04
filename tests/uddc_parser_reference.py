"""Build all optional-register variants and the pinned independent parser."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
build = Path(sys.argv[1]).resolve()
build.mkdir(parents=True, exist_ok=True)
reference = subprocess.check_output(
    ['git', 'show', '66e10f3:rtl/uddc_channel_split.sv'], cwd=root, text=True)
(build/'reference_parser.sv').write_text(reference.replace('uddc_channel_split', 'reference_parser'))
ports = '''input logic clk,
input logic rst_n,
input logic [7:0] s_valid,
output logic [7:0] s_ready,
input logic [3:0] s_unit_id,
input logic s_pkg_id,
input logic [3:0] s_cbmd,
input logic [767:0] s_region,
input logic [6:0] s_available_bytes,
input logic s_final,
output logic [7:0] response_valid,
output logic [7:0] done,
output logic [7:0] m_valid,
input logic [7:0] m_ready,
output logic [7:0][3:0] m_unit_id,
output logic [7:0] m_pkg_id,
output logic [7:0][3:0] m_fmt,
output logic [7:0] m_decor,
output logic [7:0][127:0] m_anchors,
output logic [7:0][511:0] m_deltas,
output logic [7:0][6:0] m_size,
output logic [7:0] m_error,
input logic reference_valid,
output logic reference_done,
output logic [3:0] reference_fmt,
output logic reference_decor,
output logic [127:0] reference_anchors,
output logic [511:0] reference_deltas,
output logic [6:0] reference_size,
output logic reference_error'''
shared = '.clk(clk),.rst_n(rst_n),.s_unit_id(s_unit_id),.s_pkg_id(s_pkg_id),.s_cbmd(s_cbmd),.s_region(s_region),.s_available_bytes(s_available_bytes),.s_final(s_final)'
wrapper = 'module parser_compare (\n'+ports+'\n);\n'
for mode in range(8):
    wrapper += f'''uddc_channel_split #(.OFFSET_REGISTERED({mode&1}),.INDEX_REGISTERED({(mode>>1)&1}),.LAYOUT_REGISTERED({(mode>>2)&1}),.MERGE_PREFIXES(1'b1)) parser_{mode} (
{shared},.s_valid(s_valid[{mode}]),.s_ready(s_ready[{mode}]),.s_response_valid(response_valid[{mode}]),.s_streaming(),.s_done(done[{mode}]),
.m_valid(m_valid[{mode}]),.m_ready(m_ready[{mode}]),.m_unit_id(m_unit_id[{mode}]),.m_pkg_id(m_pkg_id[{mode}]),.m_fmt(m_fmt[{mode}]),.m_decor(m_decor[{mode}]),.m_anchors(m_anchors[{mode}]),.m_deltas(m_deltas[{mode}]),.m_size_bytes(m_size[{mode}]),.m_error(m_error[{mode}])
);\n'''
wrapper += f'''reference_parser reference_instance ({shared},
.s_valid(reference_valid),.s_ready(),.s_done(reference_done),.m_valid(),.m_ready(1'b1),
.m_unit_id(),.m_pkg_id(),.m_fmt(reference_fmt),.m_decor(reference_decor),.m_anchors(reference_anchors),.m_deltas(reference_deltas),.m_size_bytes(reference_size),.m_error(reference_error));
endmodule
'''
(build/'parser_compare.sv').write_text(wrapper)
