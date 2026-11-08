#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

import numpy as np

SCRIPT = '/home/user/analyze.py'
STRUCTURE = '/home/user/structure.pdb'
OUTPUT = '/home/user/top_sv.txt'
PROFILE = '/home/user/profile.txt'


def expected_value(coords):
    points = np.asarray(coords, dtype=float)
    distances = np.linalg.norm(points[:, None, :] - points[None, :, :], axis=2)
    adjacency = (distances <= 7.0).astype(float)
    return f"{np.linalg.svd(adjacency, compute_uv=False)[0]:.2f}"


def parse_ca_coords(path):
    coords = []
    with open(path, 'r') as handle:
        for line in handle:
            if line.startswith(('ATOM  ', 'HETATM')) and line[12:16].strip() == 'CA':
                coords.append((float(line[30:38]), float(line[38:46]), float(line[46:54])))
    return coords


def run_script():
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', 'timeout', '20', 'python3', SCRIPT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=25,
    )
    assert result.returncode == 0, f"analyze.py failed with stderr: {result.stderr}"
    assert result.stderr == '', f"analyze.py wrote unexpected stderr: {result.stderr!r}"
    assert re.fullmatch(r'-?\d+\.\d{2}\n?', result.stdout), (
        f"Script must output only one value rounded to two decimals, got {result.stdout!r}"
    )
    return result.stdout.strip()


def pdb_line(serial, atom_name, residue, x, y, z):
    return (
        f"ATOM  {serial:5d} {atom_name:^4s} ALA A{residue:4d}    "
        f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00 20.00           C\n"
    )


def write_case(coords):
    with open(STRUCTURE, 'w') as handle:
        serial = 1
        for residue, (x, y, z) in enumerate(coords, 1):
            # Include non-CA records whose coordinates must not enter the graph.
            handle.write(pdb_line(serial, 'N', residue, x + 0.123, y, z))
            serial += 1
            handle.write(pdb_line(serial, 'CA', residue, x, y, z))
            serial += 1


def test_analyze_script_exists():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."


def test_top_sv_output_and_original_execution():
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} is missing."
    with open(OUTPUT, 'r') as handle:
        content = handle.read().strip()
    assert content == '3.22', f"Expected top_sv.txt to contain '3.22', but found '{content}'."

    coords = parse_ca_coords(STRUCTURE)
    assert coords, 'The supplied structure contains no CA atoms.'
    derived = expected_value(coords)
    assert derived == '3.22'
    assert run_script() == derived, 'analyze.py does not compute the correct result for structure.pdb.'


def test_script_on_unpredictable_contact_graphs():
    with open(STRUCTURE, 'rb') as handle:
        original = handle.read()
    original_mode = os.stat(STRUCTURE).st_mode

    try:
        # Explicitly exercise the diagonal, the inclusive 7.0 cutoff, and a non-edge.
        cases = [
            [(0.0, 0.0, 0.0)],
            [(0.0, 0.0, 0.0), (7.0, 0.0, 0.0), (14.001, 0.0, 0.0)],
        ]

        rng = secrets.SystemRandom()
        for _ in range(3):
            count = rng.randint(8, 15)
            coords = []
            for _ in range(count):
                coords.append(tuple(round(rng.uniform(-12.0, 12.0), 3) for _ in range(3)))
            cases.append(coords)

        for coords in cases:
            write_case(coords)
            assert run_script() == expected_value(coords)
    finally:
        with open(STRUCTURE, 'wb') as handle:
            handle.write(original)
        os.chmod(STRUCTURE, original_mode)


def test_profile_output():
    assert os.path.exists(PROFILE), f"Profile output file {PROFILE} is missing."
    with open(PROFILE, 'r') as handle:
        content = handle.read()

    assert 'Maximum resident set size' in content, (
        "profile.txt does not contain 'Maximum resident set size', indicating /usr/bin/time -v was not used correctly."
    )
    assert 'User time' in content, (
        "profile.txt does not contain 'User time', indicating /usr/bin/time -v was not used correctly."
    )

    lines = content.splitlines()
    assert lines and lines[0].strip() == '3.22', 'profile.txt must contain the script output from the profiled run.'
    assert re.search(r'Command being timed:\s*"python3 /home/user/analyze.py"', content)
    assert re.search(r'Exit status:\s*0\s*$', content, re.MULTILINE)

    numeric_fields = [
        'User time \(seconds\)',
        'System time \(seconds\)',
        'Percent of CPU this job got',
        'Maximum resident set size \(kbytes\)',
        'Minor \(reclaiming a frame\) page faults',
        'Major \(requiring I/O\) page faults',
        'Voluntary context switches',
        'Involuntary context switches',
        'File system inputs',
        'File system outputs',
    ]
    for field in numeric_fields:
        assert re.search(rf'{field}:\s*[0-9.]+%?\s*$', content, re.MULTILINE), (
            f'profile.txt is missing a valid GNU time field: {field}'
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
