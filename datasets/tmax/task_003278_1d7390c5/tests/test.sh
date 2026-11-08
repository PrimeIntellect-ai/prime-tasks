#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

DUMP_PATH = Path('/home/user/crash.dump')
HAVERSINE_PATH = Path('/home/user/haversine.c')
MRE_PATH = Path('/home/user/mre.c')
RECOVERY_PATH = Path('/home/user/recovery_distance.txt')


def extract_coordinates():
    assert DUMP_PATH.is_file(), f'File not found: {DUMP_PATH}'
    data = DUMP_PATH.read_bytes()
    pattern = rb'LAST_REQ:\s*lat1=([-+]?\d+(?:\.\d+)?),lon1=([-+]?\d+(?:\.\d+)?),lat2=([-+]?\d+(?:\.\d+)?),lon2=([-+]?\d+(?:\.\d+)?)'
    matches = re.findall(pattern, data)
    assert len(matches) == 1, f'Expected exactly one valid LAST_REQ record, found {len(matches)}'
    return tuple(float(value) for value in matches[0])


def reference_distance(lat1, lon1, lat2, lon2):
    radius = 6371.0
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2.0) ** 2 +
         math.cos(lat1_rad) * math.cos(lat2_rad) *
         math.sin(dlon / 2.0) ** 2)
    a = min(1.0, max(0.0, a))
    return radius * 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))


def test_recovery_distance_file():
    """Keep the original output assertion and validate its formatting."""
    assert RECOVERY_PATH.exists(), f'File not found: {RECOVERY_PATH}'
    content = RECOVERY_PATH.read_text().strip()
    expected_distance = '5570.22'
    assert content == expected_distance, (
        f"Expected distance '{expected_distance}', but got '{content}' in {RECOVERY_PATH}"
    )
    assert re.fullmatch(r'\d+\.\d{2}', content), 'Output must be one number with exactly two decimals'

    coords = extract_coordinates()
    derived = f'{reference_distance(*coords):.2f}'
    assert content == derived, f'Distance does not match the coordinates extracted from the dump: {derived}'


def test_mre_c_exists():
    """Keep the original existence assertion and require a real C source file."""
    assert MRE_PATH.exists(), f'MRE source file not found: {MRE_PATH}'
    assert MRE_PATH.is_file() and not MRE_PATH.is_symlink(), 'MRE must be a regular source file'
    source = MRE_PATH.read_text()
    assert source.strip(), 'MRE source is empty'
    assert re.search(r'\bcalculate_distance\s*\(', source), 'MRE does not call calculate_distance'

    # The MRE must contain the four coordinate values recovered from LAST_REQ.
    numbers = [float(x) for x in re.findall(r'(?<![A-Za-z_])[-+]?(?:\d+\.\d+|\d+)(?![A-Za-z_])', source)]
    for coordinate in extract_coordinates():
        assert any(abs(value - coordinate) < 1e-10 for value in numbers), (
            f'MRE does not contain extracted coordinate {coordinate}'
        )


def test_haversine_c_fixed():
    """Keep the original textual assertion, then exercise the implementation."""
    assert HAVERSINE_PATH.exists(), f'File not found: {HAVERSINE_PATH}'
    assert HAVERSINE_PATH.is_file() and not HAVERSINE_PATH.is_symlink(), 'haversine.c must be a regular file'
    content = HAVERSINE_PATH.read_text()
    assert 'cos(lat1) * cos(lat2)' not in content, (
        f'The bug in {HAVERSINE_PATH} does not appear to be fixed. '
        "It still contains the buggy 'cos(lat1) * cos(lat2)' calculation."
    )

    # Generate fresh test points at verification time so a fixed answer or fixed
    # subset cannot substitute for a correct implementation.
    rng = secrets.SystemRandom()
    cases = [(rng.uniform(-85.0, 85.0), rng.uniform(-179.0, 179.0),
              rng.uniform(-85.0, 85.0), rng.uniform(-179.0, 179.0))
             for _ in range(12)]

    with tempfile.TemporaryDirectory() as td:
        harness = Path(td) / 'harness.c'
        binary = Path(td) / 'harness'
        rows = ',\n'.join(
            '    {%.17g, %.17g, %.17g, %.17g}' % case for case in cases
        )
        harness.write_text(f'''#include <stdio.h>
double calculate_distance(double, double, double, double);
int main(void) {{
    const double cases[][4] = {{
{rows}
    }};
    const int count = (int)(sizeof(cases) / sizeof(cases[0]));
    for (int i = 0; i < count; ++i) {{
        printf("%.12f\\n", calculate_distance(cases[i][0], cases[i][1], cases[i][2], cases[i][3]));
    }}
    return 0;
}}
''')
        subprocess.run(
            ['gcc', '-std=c11', str(harness), str(HAVERSINE_PATH), '-lm', '-o', str(binary)],
            check=True, capture_output=True, text=True, timeout=20
        )
        result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=10)
        lines = result.stdout.splitlines()
        assert len(lines) == len(cases), 'Distance function produced an unexpected number of results'
        for case, line in zip(cases, lines):
            actual = float(line)
            expected = reference_distance(*case)
            assert math.isfinite(actual)
            assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-7), (
                f'Incorrect distance for {case}: expected {expected}, got {actual}'
            )


def test_compile_and_run_mre():
    """Compile and execute the demanded MRE and verify the value it actually produces."""
    coords = extract_coordinates()
    expected = f'{reference_distance(*coords):.2f}'

    with tempfile.TemporaryDirectory() as td:
        binary = Path(td) / 'mre'
        standalone = ['gcc', '-std=c11', str(MRE_PATH), '-lm', '-o', str(binary)]
        built = subprocess.run(standalone, capture_output=True, text=True, timeout=20)
        if built.returncode != 0:
            linked = ['gcc', '-std=c11', str(MRE_PATH), str(HAVERSINE_PATH), '-lm', '-o', str(binary)]
            built = subprocess.run(linked, capture_output=True, text=True, timeout=20)
        assert built.returncode == 0, f'MRE failed to compile:\n{built.stderr}'
        assert binary.is_file(), 'Compilation did not produce an executable'

        backup = Path(td) / 'original_recovery_distance.txt'
        os.replace(RECOVERY_PATH, backup)
        try:
            run = subprocess.run(
                [str(binary)], cwd='/home/user', capture_output=True, text=True, timeout=10
            )
            assert run.returncode == 0, f'MRE exited with status {run.returncode}: {run.stderr}'
            stdout_value = run.stdout.strip()
            file_value = RECOVERY_PATH.read_text().strip() if RECOVERY_PATH.exists() else None
            assert stdout_value == expected or file_value == expected, (
                f'Running the MRE did not produce the derived distance {expected}; '
                f'stdout={stdout_value!r}, file={file_value!r}'
            )
        finally:
            if RECOVERY_PATH.exists():
                RECOVERY_PATH.unlink()
            os.replace(backup, RECOVERY_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
