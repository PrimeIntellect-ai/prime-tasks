#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import pathlib
import re
import secrets
import subprocess
import tempfile

HOME = pathlib.Path('/home/user')
OUTPUT = HOME / 'convergence_order.txt'
NS = (10, 20, 40, 80)
INPUTS = [HOME / f'sim_{n}.txt' for n in NS]


def parse_output(path):
    assert path.is_file(), f'Missing output file: {path}'
    content = path.read_text().strip()
    assert re.fullmatch(r'[+-]?\d+\.\d{3}', content), \
        f'{path} must contain exactly one number formatted to three decimal places, got {content!r}'
    return float(content)


def expected_slope(file_bytes):
    xs = []
    ys = []
    for n, data in zip(NS, file_bytes):
        values = [float(line) for line in data.decode().splitlines() if line.strip()]
        assert len(values) == 10000
        mean = sum(values) / 10000.0
        variance = sum((v - mean) ** 2 for v in values) / 10000.0
        std = math.sqrt(variance)
        distance = (mean - 2.0) ** 2 + (std - 2.0) ** 2
        assert distance > 0.0
        xs.append(math.log(1.0 / n))
        ys.append(math.log(distance))
    xbar = sum(xs) / len(xs)
    ybar = sum(ys) / len(ys)
    return sum((x - xbar) * (y - ybar) for x, y in zip(xs, ys)) / sum((x - xbar) ** 2 for x in xs)


def make_case(rng):
    order = rng.uniform(0.65, 3.35)
    scale = rng.uniform(0.8, 2.2)
    result = []
    for n in NS:
        dt = 1.0 / n
        # Non-collinear perturbations ensure the program must regress all four results.
        distance = scale * (dt ** order) * math.exp(rng.uniform(-0.18, 0.18))
        angle = rng.uniform(0.18, 1.35)
        mean = 2.0 + math.sqrt(distance) * math.cos(angle)
        std = 2.0 + math.sqrt(distance) * math.sin(angle)
        low = mean - std
        high = mean + std
        text = (f'{low:.9f}\n' * 5000) + (f'{high:.9f}\n' * 5000)
        result.append(text.encode())
    return result


def compile_candidates(sources, directory):
    groups = []
    if len(sources) > 1:
        groups.append(sources)
    groups.extend([[source] for source in sources])
    executables = []
    for index, group in enumerate(groups):
        executable = pathlib.Path(directory) / f'candidate_{index}'
        command = ['gcc', '-std=c11', '-O2', *map(str, group), '-o', str(executable), '-lm']
        completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if completed.returncode == 0:
            executables.append(executable)
    return executables


def test_convergence_order_and_c_program():
    # Preserve the original verifier's assertion on the supplied simulation data.
    original_value = parse_output(OUTPUT)
    expected_original = 2.052
    assert math.isclose(original_value, expected_original, abs_tol=0.005), \
        f'Expected value close to {expected_original}, but got {original_value}'

    sources = sorted(HOME.rglob('*.c'))
    assert sources, 'No C source file was found under /home/user'

    original_inputs = [path.read_bytes() for path in INPUTS]
    original_output = OUTPUT.read_bytes()
    rng = secrets.SystemRandom()
    cases = [make_case(rng), make_case(rng)]

    try:
        with tempfile.TemporaryDirectory(prefix='convergence_verify_') as build_dir:
            executables = compile_candidates(sources, build_dir)
            assert executables, 'The submitted C source could not be compiled with gcc'

            failures = []
            for executable in executables:
                passed = True
                reason = ''
                for case in cases:
                    for path, data in zip(INPUTS, case):
                        path.write_bytes(data)
                    if OUTPUT.exists():
                        OUTPUT.unlink()
                    try:
                        run = subprocess.run(
                            [str(executable)], cwd=str(HOME),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=15
                        )
                    except subprocess.TimeoutExpired:
                        passed = False
                        reason = 'timed out'
                        break
                    if run.returncode != 0:
                        passed = False
                        reason = f'exited with status {run.returncode}'
                        break
                    try:
                        actual = parse_output(OUTPUT)
                    except AssertionError as exc:
                        passed = False
                        reason = str(exc)
                        break
                    expected = expected_slope(case)
                    if not math.isclose(actual, expected, abs_tol=0.00051):
                        passed = False
                        reason = f'produced {actual:.3f}; expected {expected:.3f} on verifier-generated data'
                        break
                if passed:
                    return
                failures.append(f'{executable.name}: {reason}')

            assert False, 'No compiled C program correctly processed the verifier-generated inputs: ' + '; '.join(failures)
    finally:
        for path, data in zip(INPUTS, original_inputs):
            path.write_bytes(data)
        OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
