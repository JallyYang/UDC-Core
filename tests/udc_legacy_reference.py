"""Compare the standalone 64B path against its pre-slice implementation."""
from pathlib import Path
import re
import subprocess
import sys
repo = Path(__file__).resolve().parents[1]
build = Path(sys.argv[1]).resolve()
build.mkdir(parents=True, exist_ok=True)
modules = ['udc_dic_enc', 'udc_enc_decorrelate', 'udc_enc_delta',
           'udc_enc_index_sel', 'udc_enc_candidate_sel', 'udc_enc_package']
files = []
for module in modules:
    source = subprocess.check_output(
        ['git', 'show', f'eb71130:rtl/{module}.sv'], cwd=repo, text=True)
    source = re.sub(r'\budc_(\w+)', r'ref_udc_\1', source)
    path = build / f'ref_{module}.sv'
    path.write_text(source)
    files.append(str(path))
source = (repo / 'rtl/udc_dic_enc.sv').read_text()
ports = source[source.index('        input logic clk'):source.index('    );')]
lines = []
connections = {}
for prefix in ['n', 'r']:
    connections[prefix] = []
    for line in ports.splitlines():
        match = re.search(r'(\w+),?$', line.strip())
        if not match:
            continue
        name = match[1]
        renamed = name if name in ['clk', 'rst_n'] else prefix + '_' + name
        if prefix == 'n' or name not in ['clk', 'rst_n']:
            lines.append(re.sub(r'\b' + name + r'\b', renamed, line.strip().rstrip(',')))
        connections[prefix].append(f'.{name}({renamed})')
wrapper = 'module legacy_compare #(parameter UNIT_ID_W=4) (\n' + ',\n'.join(lines) + '\n);\n'
for prefix, module in [('n', 'udc_dic_enc'), ('r', 'ref_udc_dic_enc')]:
    wrapper += module + ' ' + prefix + ' (' + ', '.join(connections[prefix]) + ');\n'
wrapper += 'endmodule\n'
(build / 'legacy_compare.sv').write_text(wrapper)
(build / 'reference.f').write_text('\n'.join(files) + '\n')
