"""Constant-format 512-bit reconstruction trees, with anchors in the tree."""
import sys
from pathlib import Path

output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)


def generate(width, stages):
    samples = 512 // width
    row = 8 if width in (8, 16) else 4
    name = f'tree_w{width}_p{stages}'
    lines = [f'module {name}(input clk, input [511:0] delta_in,',
             '  input [31:0] anchor_in, output reg [511:0] samples_out);',
             '  reg [511:0] delta_ready;',
             f'  reg [{width-1}:0] anchor_ready;',
             '  always @(posedge clk) begin',
             '    delta_ready <= delta_in;',
             f'    anchor_ready <= anchor_in[{width-1}:0];',
             '  end']
    register_updates = []
    serial = 0

    def tree(terms, prefix):
        nonlocal serial
        while len(terms) > 1:
            following = []
            for index in range(0, len(terms), 2):
                if index + 1 == len(terms):
                    following.append(terms[index])
                else:
                    wire = f'{prefix}_{serial}'
                    serial += 1
                    lines.append(f'  wire [{width-1}:0] {wire} = {terms[index]} + {terms[index+1]};')
                    following.append(wire)
            terms = following
        return terms[0]

    for sample in range(samples):
        ancestors = []
        current = sample
        while current:
            ancestors.append(current)
            current = current - 1 if current % row else current - row
        terms = [f'delta_ready[{k*width} +: {width}]' for k in ancestors]
        terms.append('anchor_ready')
        if stages == 2:
            partials = []
            for group in range(0, len(terms), 4):
                value = tree(terms[group:group+4], f'lower_{sample}')
                partial = f'partial_{sample}_{group//4}'
                lines.append(f'  reg [{width-1}:0] {partial};')
                register_updates.append(f'    {partial} <= {value};')
                partials.append(partial)
            value = tree(partials, f'upper_{sample}')
        else:
            value = tree(terms, f'sum_{sample}')
        register_updates.append(f'    samples_out[{sample*width} +: {width}] <= {value};')
    lines += ['  always @(posedge clk) begin', *register_updates, '  end', 'endmodule']
    (output / (name + '.v')).write_text('\n'.join(lines) + '\n')
    return name


for width in (8, 16, 32):
    for stages in (1, 2):
        print(generate(width, stages))
