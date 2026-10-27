"""Check RTL declaration/process rules using the SystemVerilog syntax tree.

Dependency: pyslang 12.1.0 (python3 -m pip install pyslang==12.1.0).
"""
from collections import defaultdict
from pathlib import Path
import re
import sys

from pyslang.ast import Compilation
from pyslang.syntax import SyntaxTree


def kind(node):
    return str(getattr(node, 'kind', ''))


def assigned_variables(node):
    result = set()

    def visit(expression):
        if kind(expression) in ('SyntaxKind.AssignmentExpression',
                                 'SyntaxKind.NonblockingAssignmentExpression'):
            # Array elements and slices belong to one signal. Struct members
            # are checked independently, including payload pipeline registers.
            name = re.sub(r'\[[^\]]*\]', '', str(expression.left).strip())
            result.add(name)

    node.visit(visit)
    return result


root = Path(__file__).resolve().parents[1]
compilation = Compilation()
failures = []
process_count = 0
file_count = 0
fsm_count = 0
for path in sorted((root/'rtl').glob('*.sv')):
    source = path.read_text()
    tree = SyntaxTree.fromText(source, name=str(path))
    compilation.addSyntaxTree(tree)
    file_count += 1
    declaration_lines = defaultdict(list)
    processes = []

    def failure(node, message):
        line = source.count('\n', 0, node.sourceRange.start.offset) + 1
        failures.append(f'{path.relative_to(root)}:{line}: {message}')

    def visit(node):
        global process_count
        node_kind = kind(node)
        if node_kind == 'SyntaxKind.Declarator':
            line = source.count('\n', 0, node.name.location.offset) + 1
            declaration_lines[line].append(node.name.rawText)
        if node_kind in ('SyntaxKind.DataDeclaration', 'SyntaxKind.ParameterDeclaration'):
            declarations = [item for item in node.declarators
                            if kind(item) == 'SyntaxKind.Declarator']
            if len(declarations) > 1:
                failure(node, 'declare one variable per statement')
        if node_kind in ('SyntaxKind.AlwaysCombBlock', 'SyntaxKind.AlwaysFFBlock',
                         'SyntaxKind.AlwaysBlock', 'SyntaxKind.AlwaysLatchBlock'):
            process_count += 1
            targets = assigned_variables(node.statement)
            processes.append((node, targets))
            if len(targets) > 1:
                failure(node, 'always block assigns multiple variables: ' + ', '.join(sorted(targets)))

    tree.root.visit(visit)
    for line, names in declaration_lines.items():
        if len(names) > 1:
            failures.append(f'{path.relative_to(root)}:{line}: multiple declarations on one line: {names}')
    for diagnostic in tree.diagnostics:
        failures.append(f'{path.name}: syntax diagnostic {diagnostic.code}')

    if re.search(r'\blogic\s*\[1:0\]\s+dispatch_state\s*;', source):
        fsm_count += 1
        state_registers = [node for node, targets in processes
                           if kind(node) == 'SyntaxKind.AlwaysFFBlock' and targets == {'dispatch_state'}]
        next_logic = [node for node, targets in processes
                      if kind(node) == 'SyntaxKind.AlwaysCombBlock' and targets == {'next_dispatch_state'}]
        output_logic = [node for node, targets in processes
                        if kind(node) == 'SyntaxKind.AlwaysCombBlock' and targets == {'ctx_valid'}
                        and 'dispatch_state' in str(node)]
        if len(state_registers) != 1 or 'next_dispatch_state' not in str(state_registers[0]):
            failures.append(f'{path.name}: missing dedicated current-state register')
        if len(next_logic) != 1 or 'case (dispatch_state)' not in str(next_logic[0]):
            failures.append(f'{path.name}: missing separate next-state case logic')
        if not output_logic:
            failures.append(f'{path.name}: missing separate state-output process')

for diagnostic in compilation.getAllDiagnostics():
    if diagnostic.isError():
        failures.append(f'SystemVerilog elaboration error: {diagnostic.code} {diagnostic.args}')
if failures:
    print('\n'.join(failures), file=sys.stderr)
    raise SystemExit(1)
print(f'PASS RTL style: {file_count} files, {process_count} always blocks, {fsm_count} three-part FSMs; no syntax/elaboration errors')
