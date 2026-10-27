"""Reproduce isolated adder-tree synthesis and register-to-register STA.

Requires an unencrypted NLDM Liberty library, Yosys/ABC and OpenSTA. Results
are pre-layout estimates, not timing signoff for the full decoder.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


def quote_yosys(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'


def quote_tcl(value):
    text = str(value)
    for char in ('\\', '"', '$', '[', ']'):
        text = text.replace(char, '\\' + char)
    return '"' + text + '"'


def executable(value):
    found = shutil.which(value)
    if not found:
        raise RuntimeError('Missing executable: ' + value)
    return str(Path(found).resolve())


def run(command, log):
    with log.open('w') as stream:
        subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=True)
    # Older OpenSTA versions can return success after a Tcl error.
    text = log.read_text()
    if re.search(r'^\s*(Error:|ERROR:|FATAL:)', text, re.MULTILINE):
        raise RuntimeError('Tool error; inspect ' + str(log))
    return text


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--liberty', type=Path, required=True)
parser.add_argument('--build-dir', type=Path, required=True)
parser.add_argument('--driving-cell', required=True)
parser.add_argument('--wire-load-model', default='')
parser.add_argument('--load-ff', type=float, default=1.0)
parser.add_argument('--clock-ns', type=float, default=2/3)
parser.add_argument('--yosys', default='yosys')
parser.add_argument('--abc', default='yosys-abc')
parser.add_argument('--sta', default='sta')
args = parser.parse_args()
liberty = args.liberty.resolve(strict=True)
root = args.build_dir.resolve()
root.mkdir(parents=True, exist_ok=True)
source = Path(__file__).resolve().parent
if args.clock_ns <= 0 or args.load_ff < 0:
    raise ValueError('Clock must be positive and load must be nonnegative')
for name in (args.driving_cell, args.wire_load_model):
    if name and not re.fullmatch(r'[A-Za-z0-9_.+-]+', name):
        raise ValueError('Unsupported cell/model name: ' + name)
yosys, abc, sta = (executable(tool) for tool in (args.yosys, args.abc, args.sta))
subprocess.run([sys.executable, '-B', str(source/'generate.py'), str(root/'rtl')], check=True)
constraint = root/'abc.constr'
constraint.write_text(f'set_driving_cell {args.driving_cell}\nset_load {args.load_ff}\n')
summary = []
for width in (8, 16, 32):
    for stages in (1, 2):
        case = f'tree_w{width}_p{stages}'
        destination = root/case
        destination.mkdir(exist_ok=True)
        script = destination/'synth.ys'
        script.write_text(f'''read_liberty -lib {quote_yosys(liberty)}
read_verilog {quote_yosys(root/'rtl'/(case+'.v'))}
hierarchy -check -top {case}
synth -top {case} -flatten -noabc
dfflibmap -liberty {quote_yosys(liberty)}
abc -exe {quote_yosys(abc)} -liberty {quote_yosys(liberty)} -constr {quote_yosys(constraint)} -D {args.clock_ns*1000:.6f}
clean
check
stat -liberty {quote_yosys(liberty)}
write_verilog -noattr -noexpr {quote_yosys(destination/'mapped.v')}
write_json {quote_yosys(destination/'mapped.json')}
''')
        synth_log = run([yosys, '-s', str(script)], destination/'synth.log')
        wire_load = ''
        if args.wire_load_model:
            wire_load = ('set_wire_load_mode top\nset_wire_load_model -name '
                         + quote_tcl(args.wire_load_model) + ' [current_design]\n')
        timing = destination/'timing.tcl'
        timing.write_text(f'''read_liberty {quote_tcl(liberty)}
read_verilog {quote_tcl(destination/'mapped.v')}
link_design {case}
set_units -time ns -capacitance fF
create_clock -name clk -period {args.clock_ns:.9f} [get_ports clk]
set_clock_uncertainty 0 [get_clocks clk]
set_input_delay 0 -clock clk [get_ports {{delta_in* anchor_in*}}]
set_output_delay 0 -clock clk [get_ports samples_out*]
set_driving_cell -lib_cell {quote_tcl(args.driving_cell)} [get_ports {{delta_in* anchor_in*}}]
set_load {args.load_ff} [get_ports samples_out*]
{wire_load}check_setup -verbose
report_checks -from [all_registers -clock_pins] -to [all_registers -data_pins] -path_delay max -group_count 5 -endpoint_count 1 -format full_clock_expanded -fields {{slew capacitance fanout}} -digits 6
exit
''')
        timing_log = run([sta, '-exit', str(timing)], destination/'timing.log')
        slacks = re.findall(r'([-+\d.]+)\s+slack \(', timing_log)
        if not slacks:
            raise RuntimeError('No constrained register-to-register path in ' + case)
        slack = float(slacks[0])
        netlist = json.loads((destination/'mapped.json').read_text())
        cells = netlist['modules'][case]['cells']
        # Use dfflibmap's selected library cell names, including custom PDK names.
        flop_types = set(re.findall(r'mapped \d+ \$_DFF\S* cells to \\(\S+) cells', synth_log))
        area = re.findall(r'Chip area for module.*?:\s*([\d.]+)', synth_log)
        if not flop_types or not area:
            raise RuntimeError('Missing sequential-cell or area statistics in ' + case)
        minimum_period = args.clock_ns-slack
        entry = dict(case=case, width=width, stages=stages, slack_ns=slack,
                     minimum_period_estimate_ns=minimum_period,
                     frequency_estimate_ghz=1/minimum_period,
                     cell_area=float(area[-1]), cells=len(cells),
                     flipflops=sum(cell['type'] in flop_types for cell in cells.values()))
        mapped_verilog = (destination/'mapped.v').read_text()
        for role in ('Startpoint', 'Endpoint'):
            cell_name = re.search(role+r': (\S+)', timing_log)[1]
            instance = re.search(r'\b'+re.escape(cell_name)+r'\s*\((.*?)\);', mapped_verilog, re.S)
            output_pin = re.search(r'\.(Q|QN)\((.*?)\)', instance[1]) if instance else None
            entry[role.lower()] = output_pin[2] if output_pin else cell_name
        summary.append(entry)
        print(json.dumps(entry), flush=True)
(root/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
provenance = dict(liberty_sha256=hashlib.sha256(liberty.read_bytes()).hexdigest(),
                  clock_period_ns=args.clock_ns, clock_uncertainty_ns=0,
                  driving_cell=args.driving_cell, load_ff=args.load_ff,
                  wire_load_model=args.wire_load_model or 'library default',
                  yosys=subprocess.check_output([yosys, '-V'], text=True).strip(),
                  abc=subprocess.check_output([abc, '-c', 'version'], text=True).strip(),
                  opensta=subprocess.check_output([sta, '-version'], text=True).strip(),
                  benchmark='isolated constant-format reconstruction; ideal clock; pre-layout')
(root/'provenance.json').write_text(json.dumps(provenance, indent=2)+'\n')
