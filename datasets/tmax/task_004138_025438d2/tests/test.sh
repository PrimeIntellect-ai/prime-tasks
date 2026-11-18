#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import struct
import subprocess
import tempfile

EMBEDDINGS = '/home/user/embeddings.bin'
RESULTS = '/home/user/results.txt'


def read_vectors(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()
    assert len(data) == 100 * 64 * 4, 'Embeddings file has an unexpected size.'
    floats = struct.unpack('<6400f', data)
    return [list(floats[i * 64:(i + 1) * 64]) for i in range(100)]


def dot(v1, v2):
    return sum(x * y for x, y in zip(v1, v2))


def norm(v):
    return math.sqrt(sum(x * x for x in v))


def cos_sim(v1, v2):
    n1 = norm(v1)
    n2 = norm(v2)
    if n1 == 0 or n2 == 0:
        return 0.0
    return dot(v1, v2) / (n1 * n2)


def compute_ground_truth(filepath):
    vectors = read_vectors(filepath)
    exact_sims = [cos_sim(vectors[0], vectors[i]) for i in range(1, 100)]
    indexed_sims = list(enumerate(exact_sims, start=1))
    indexed_sims.sort(key=lambda x: x[1], reverse=True)
    top3 = [x[0] for x in indexed_sims[:3]]

    q_vectors = [
        [round(x * 127.0) / 127.0 for x in vector]
        for vector in vectors
    ]
    q_sims = [cos_sim(q_vectors[0], q_vectors[i]) for i in range(1, 100)]
    errors = [exact - quantized for exact, quantized in zip(exact_sims, q_sims)]
    mean_err = sum(errors) / len(errors)
    variance = sum((e - mean_err) ** 2 for e in errors) / (len(errors) - 1)
    ci_margin = 1.96 * math.sqrt(variance) / math.sqrt(99)
    return top3, mean_err, ci_margin


def validate_results(expected):
    assert os.path.isfile(RESULTS), f'File {RESULTS} is missing.'
    with open(RESULTS, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 3, 'Results file must contain at least 3 lines.'
    top3, mean_err, ci_margin = expected
    expected_top3 = f'Top3_Indices: {top3[0]}, {top3[1]}, {top3[2]}'
    assert lines[0] == expected_top3, f"Expected '{expected_top3}', got '{lines[0]}'"

    try:
        agent_mean = float(lines[1].split(': ')[1])
    except Exception as exc:
        raise AssertionError(f'Could not parse Mean_Error from line: {lines[1]}') from exc
    assert abs(agent_mean - mean_err) < 1e-5, \
        f'Mean error mismatch. Expected around {mean_err:.6f}, got {agent_mean}'

    try:
        agent_ci = float(lines[2].split(': ')[1])
    except Exception as exc:
        raise AssertionError(f'Could not parse CI_Margin from line: {lines[2]}') from exc
    assert abs(agent_ci - ci_margin) < 1e-5, \
        f'CI margin mismatch. Expected around {ci_margin:.6f}, got {agent_ci}'


def find_c_sources():
    excluded = {'/proc', '/sys', '/dev', '/usr', '/var', '/etc', '/run', '/lib',
                '/lib64', '/bin', '/sbin', '/boot', '/logs', '/tests'}
    found = []
    for root, dirs, files in os.walk('/', topdown=True, followlinks=False):
        if root == '/':
            dirs[:] = [d for d in dirs if os.path.join('/', d) not in excluded]
        if any(root == p or root.startswith(p + os.sep) for p in excluded):
            dirs[:] = []
            continue
        for name in files:
            if not name.lower().endswith('.c'):
                continue
            path = os.path.join(root, name)
            try:
                if os.path.isfile(path) and os.path.getsize(path) <= 2 * 1024 * 1024:
                    found.append(path)
            except OSError:
                pass
    return sorted(set(found))


def compilation_units(sources):
    units = [(source,) for source in sources]
    by_directory = {}
    for source in sources:
        by_directory.setdefault(os.path.dirname(source), []).append(source)
    for group in by_directory.values():
        if 1 < len(group) <= 10:
            units.append(tuple(sorted(group)))
    seen = set()
    answer = []
    for unit in units:
        if unit not in seen:
            seen.add(unit)
            answer.append(unit)
    return answer


def make_hidden_embeddings():
    rng = random.Random(20260911)
    values = [rng.uniform(-3.0, 3.0) for _ in range(100 * 64)]
    return struct.pack('<6400f', *values)


def run_program(executable):
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    subprocess.run([executable], cwd='/home/user', check=True, timeout=15,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_results_and_c_implementation():
    with open(EMBEDDINGS, 'rb') as f:
        original_data = f.read()
    original_expected = compute_ground_truth(EMBEDDINGS)

    # Preserve the original verifier's assertion that the submitted output is correct.
    validate_results(original_expected)

    sources = find_c_sources()
    assert sources, 'No C source file was found.'
    hidden_data = make_hidden_embeddings()
    successful = False
    failures = []

    try:
        for index, unit in enumerate(compilation_units(sources)):
            executable = os.path.join(tempfile.gettempdir(), f'verified_c_program_{index}')
            compile_result = subprocess.run(
                ['gcc', '-std=c11', '-O2', *unit, '-lm', '-o', executable],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )
            if compile_result.returncode != 0:
                continue

            try:
                with open(EMBEDDINGS, 'wb') as f:
                    f.write(original_data)
                run_program(executable)
                validate_results(original_expected)

                with open(EMBEDDINGS, 'wb') as f:
                    f.write(hidden_data)
                hidden_expected = compute_ground_truth(EMBEDDINGS)
                run_program(executable)
                validate_results(hidden_expected)

                # Leave the requested result for the original supplied dataset.
                with open(EMBEDDINGS, 'wb') as f:
                    f.write(original_data)
                run_program(executable)
                validate_results(original_expected)
                successful = True
                break
            except Exception as exc:
                failures.append(f'{unit}: {exc}')

        assert successful, 'No submitted C source compiled and produced correct results when executed. ' + '; '.join(failures[-3:])
    finally:
        with open(EMBEDDINGS, 'wb') as f:
            f.write(original_data)


if __name__ == '__main__':
    test_results_and_c_implementation()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
