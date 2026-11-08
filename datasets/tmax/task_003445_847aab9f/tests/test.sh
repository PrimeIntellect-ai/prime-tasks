#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

SOURCE = '/home/user/spectro_profile.c'
INPUT = '/home/user/input.pdb'
OUTPUT = '/home/user/kl_divergence.txt'
BINARY = '/tmp/spectro_profile_verified'


def compute_expected_kl(pdb_path):
    ca_coords = []
    with open(pdb_path, 'r') as f:
        for line in f:
            if line.startswith('ATOM  ') or line.startswith('HETATM'):
                atom_name = line[12:16].strip()
                if atom_name == 'CA':
                    x = float(line[30:38])
                    y = float(line[38:46])
                    z = float(line[46:54])
                    ca_coords.append((x, y, z))

    histogram = [0] * 100
    total_pairs = 0
    for i in range(len(ca_coords)):
        for j in range(i + 1, len(ca_coords)):
            a, b = ca_coords[i], ca_coords[j]
            distance = math.sqrt(
                (a[0] - b[0]) ** 2 +
                (a[1] - b[1]) ** 2 +
                (a[2] - b[2]) ** 2
            )
            if distance < 100.0:
                bin_idx = int(math.floor(distance))
                if 0 <= bin_idx < 100:
                    histogram[bin_idx] += 1
                    total_pairs += 1

    if total_pairs == 0:
        return 0.0

    kl_div = 0.0
    for count in histogram:
        if count > 0:
            p = count / total_pairs
            kl_div += p * math.log(p / 0.01)
    return kl_div


def pdb_line(serial, atom_name, resid, x, y, z, record='ATOM  '):
    atom_field = f'{atom_name:>4}'
    return (
        f'{record}{serial:5d} {atom_field} ALA A{resid:4d}    '
        f'{x:8.3f}{y:8.3f}{z:8.3f}  1.00 20.00           C  \n'
    )


def write_case(coords, include_hetatm=False):
    lines = []
    serial = 1
    for resid, (x, y, z) in enumerate(coords, 1):
        lines.append(pdb_line(serial, 'N', resid, x + 0.125, y, z))
        serial += 1
        record = 'HETATM' if include_hetatm and resid % 4 == 0 else 'ATOM  '
        lines.append(pdb_line(serial, 'CA', resid, x, y, z, record))
        serial += 1
        lines.append(pdb_line(serial, 'CB', resid, x, y + 0.125, z))
        serial += 1
    lines.append('TER\n')
    with open(INPUT, 'w') as f:
        f.writelines(lines)


def run_and_check():
    expected = f'{compute_expected_kl(INPUT):.6f}'
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run([BINARY], cwd='/home/user', capture_output=True,
                            text=True, timeout=10)
    assert result.returncode == 0, (
        f'Compiled program exited with {result.returncode}: {result.stderr}'
    )
    assert os.path.isfile(OUTPUT), f'{OUTPUT} was not created by the program.'
    with open(OUTPUT, 'r') as f:
        raw = f.read()
    assert re.fullmatch(r'-?[0-9]+\.[0-9]{6}\n?', raw), (
        'Output must contain only one value formatted to exactly 6 decimal places.'
    )
    assert raw.strip() == expected, f'Expected {expected}, but got {raw.strip()}.'


def test_c_source_exists():
    assert os.path.isfile(SOURCE), f'{SOURCE} does not exist.'


def test_kl_divergence_output():
    assert os.path.isfile(OUTPUT), f'{OUTPUT} does not exist. Did the program run successfully?'
    assert os.path.isfile(INPUT), f'{INPUT} is missing.'
    expected_str = f'{compute_expected_kl(INPUT):.6f}'
    with open(OUTPUT, 'r') as f:
        content = f.read().strip()
    assert content == expected_str, (
        f'Expected KL divergence {expected_str}, but got {content} in {OUTPUT}.'
    )


def test_compile_and_execute_on_generated_inputs():
    compile_result = subprocess.run(
        ['gcc', '-O3', SOURCE, '-o', BINARY, '-lm'],
        capture_output=True, text=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        f'C source failed to compile: {compile_result.stderr}'
    )

    with open(INPUT, 'rb') as f:
        original_input = f.read()
    original_output = None
    if os.path.exists(OUTPUT):
        with open(OUTPUT, 'rb') as f:
            original_output = f.read()

    rng = random.SystemRandom()
    cases = [
        [(0.0, 0.0, 0.0), (0.999, 0.0, 0.0), (1.0, 0.0, 0.0),
         (17.25, 0.0, 0.0), (99.999, 0.0, 0.0), (100.0, 0.0, 0.0),
         (145.0, 0.0, 0.0)],
        [(round(rng.uniform(-25, 25), 3),
          round(rng.uniform(-25, 25), 3),
          round(rng.uniform(-25, 25), 3)) for _ in range(19)],
        [(round(rng.uniform(-130, 130), 3),
          round(rng.uniform(-130, 130), 3),
          round(rng.uniform(-130, 130), 3)) for _ in range(23)],
    ]

    try:
        for index, coords in enumerate(cases):
            write_case(coords, include_hetatm=(index == 1))
            run_and_check()
    finally:
        with open(INPUT, 'wb') as f:
            f.write(original_input)
        if original_output is not None:
            with open(OUTPUT, 'wb') as f:
                f.write(original_output)
        elif os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        if os.path.exists(BINARY):
            os.remove(BINARY)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
