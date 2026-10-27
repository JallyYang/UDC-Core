"""Directed latency cases sharing the regression's package reference model."""
import random
import sys
from pathlib import Path
import uddc_generate as model

destination = Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=True)
original_random = model.r


class FixedWidths:
    def __init__(self, widths):
        self.widths = iter(widths)

    def randrange(self, count):
        return 0  # One width index for the whole channel.

    def getrandbits(self, width):
        return original_random.getrandbits(width)

    def choice(self, choices):
        width = next(self.widths)
        return next(choice for choice in choices if choice[1] == width)


def fixed_package(format_id, reverse, widths):
    model.r = FixedWidths(widths)
    try:
        return model.package(format_id, reverse, 32, 0)
    finally:
        model.r = original_random


def unit(first, second):
    total = first[0] + second[0]
    assert max(first[0], second[0]) <= 68 and total <= 96
    if total <= 32:
        mode, occupied = 1, 32
    elif total <= 64:
        mode = 2 if max(first[0], second[0]) <= 32 else 3 if first[0] < 32 else 4
        occupied = 64
    else:
        mode, occupied = 5, 96
    return (mode, first[1] | second[1] << ((occupied - second[0]) * 8),
            first[2] | second[2] << 512, 0)


first = fixed_package(5, False, [32, 32, 32, 20])
second = fixed_package(5, True, [0, 0, 0, 0])
assert (first[0], second[0]) == (64, 20)
boundary = unit(first, second)
reverse_boundary = unit(fixed_package(5, False, [0]*4),
                        fixed_package(5, True, [32, 32, 32, 20]))
wide = unit(fixed_package(3, False, [32]), fixed_package(3, True, [0]))
short = unit(fixed_package(1, False, [0]), fixed_package(1, True, [0]))
clear_pattern = sum((0x10203040 + i) << (32*i) for i in range(4))
clear = (6, 0, sum(clear_pattern << (128*i) for i in range(8)), 0)
bad_header = (boundary[0], boundary[1] | 3, 0, 1)

random_source = random.Random(84731)
mixed = [boundary]
for _ in range(1024):
    value = random_source.getrandbits(1024)
    mixed.append(random_source.choice([boundary, reverse_boundary, short,
                                      clear, (0, value, value, 0)]))
cases = {
    'boundary': [boundary]*128,
    'reverse_boundary': [reverse_boundary]*128,
    'wide': [wide]*128,
    'short': [short]*128,
    'bad_header': [bad_header],
    'mixed': mixed,
    'clear_then_boundary': [clear] + [boundary]*127,
}
for name, records in cases.items():
    (destination / (name + '.txt')).write_text(''.join(
        f'{mode} {data:0256x} {raw:0256x} {error}\n'
        for mode, data, raw, error in records))
print('Generated directed latency, continuity and error cases.')
