#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
from pathlib import Path
import random
import subprocess
import tempfile

import pytest

SOURCE = Path('/home/user/extractor.cpp')
METRIC = Path('/home/user/distance_metric.txt')
DATASET = Path('/app/dataset_record.wav')
OFFSET = 44100


def read_metric():
    assert METRIC.exists(), f'The output file {METRIC} is missing.'
    try:
        content = METRIC.read_text().strip()
        value = float(content)
    except ValueError:
        pytest.fail(f"The content of {METRIC} ('{content}') could not be parsed as a float.")
    except Exception as exc:
        pytest.fail(f'Failed to read {METRIC}: {exc}')
    assert math.isfinite(value), f'The calculated distance must be finite, got {value}.'
    return value


def test_extractor_cpp_exists():
    """Test that the C++ extractor program was created."""
    assert os.path.exists(SOURCE), f'The C++ source file {SOURCE} is missing.'
    assert os.path.isfile(SOURCE), f'The path {SOURCE} is not a file.'


def test_distance_metric_value():
    """Keep the original assertion for the supplied dataset."""
    value = read_metric()
    target_value = 40.00
    threshold = 0.1
    diff = abs(value - target_value)
    assert diff <= threshold, (
        f'Calculated distance {value} is not within {threshold} '
        f'of the target {target_value}.'
    )


def make_embedded_elf(workdir, gcode, index):
    src = workdir / f'dummy_{index}.cpp'
    base_elf = workdir / f'dummy_{index}.elf'
    gcode_file = workdir / f'dataset_{index}.gcode'
    embedded = workdir / f'embedded_{index}.elf'
    src.write_text('int main(){return 0;}\n')
    gcode_file.write_text(gcode)
    subprocess.run(
        ['g++', str(src), '-o', str(base_elf)],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    subprocess.run(
        ['objcopy', '--add-section', f'.gcode={gcode_file}',
         str(base_elf), str(embedded)],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    return embedded.read_bytes()


def run_submission(executable, expected):
    METRIC.unlink(missing_ok=True)
    subprocess.run(
        [str(executable)], cwd='/home/user', check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    value = read_metric()
    assert abs(value - expected) <= 0.02, (
        f'Program produced {value}, but the GCode in the embedded ELF has '
        f'a total 2D distance of {expected:.2f}.'
    )


def test_extractor_executes_and_computes_from_embedded_gcode():
    """Compile the submitted artifact and exercise it on derived, varying inputs."""
    original = DATASET.read_bytes()
    assert len(original) > OFFSET, 'The supplied dataset does not contain an appended ELF.'
    assert original[OFFSET:OFFSET + 4] == b'\x7fELF', (
        'The supplied dataset has no ELF at the spoken byte offset.'
    )

    with tempfile.TemporaryDirectory(prefix='extractor_verify_') as temp:
        workdir = Path(temp)
        executable = workdir / 'submitted_extractor'
        subprocess.run(
            ['g++', '-std=c++17', '-O2', str(SOURCE), '-o', str(executable)],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )

        try:
            # The program itself must reproduce the original result; a prewritten
            # distance_metric.txt is not accepted.
            DATASET.write_bytes(original)
            run_submission(executable, 40.00)

            rng = random.SystemRandom()
            for case in range(3):
                points = []
                while len(points) < 6:
                    point = (rng.randint(-90, 90), rng.randint(-90, 90))
                    if not points or point != points[-1]:
                        points.append(point)

                lines = ['G0 X700 Y700', 'G1 X999', 'G1 Y-999']
                for i, (x, y) in enumerate(points):
                    lines.append(f'G1 X{x} Y{y}')
                    if i == 2:
                        lines.extend(['G0 X-500 Y-500', 'G1 X12345'])
                lines.extend(['G2 X1 Y1', 'M30'])
                gcode = '\n'.join(lines) + '\n'

                previous = (0.0, 0.0)
                total = 0.0
                for point in points:
                    total += math.hypot(point[0] - previous[0],
                                        point[1] - previous[1])
                    previous = point
                expected = round(total, 2)

                embedded = make_embedded_elf(workdir, gcode, case)
                prefix = bytearray(original[:OFFSET])
                # A false ELF signature before the dictated offset rejects
                # implementations that merely scan for the first magic bytes.
                prefix[OFFSET - 32:OFFSET - 28] = b'\x7fELF'
                DATASET.write_bytes(bytes(prefix) + embedded)
                run_submission(executable, expected)
        finally:
            DATASET.write_bytes(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
