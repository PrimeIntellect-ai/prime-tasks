#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import math
import os
import random
import re
import stat
import subprocess
from pathlib import Path

import pytest

NETWORK = Path('/home/user/network.csv')
PATCH = Path('/app/patch.png')
RESULT = Path('/home/user/metric_result.txt')
EXECUTABLE = Path('/tmp/agent_network_program')

ORIGINAL_NETWORK = [
    (0, 1, 10),
    (0, 2, 5),
    (1, 3, 1),
    (2, 1, 3),
    (2, 3, 9),
    (2, 4, 2),
    (3, 4, 4),
    (4, 0, 7),
    (4, 3, 6),
]
ORIGINAL_PATCH = [(2, 1, 2), (3, 4, 1), (4, 5, 3)]


def find_and_compile_program():
    sources = []
    for root in ('/home/user', '/app'):
        for directory, _, files in os.walk(root):
            for name in files:
                if not name.endswith('.c'):
                    continue
                path = os.path.join(directory, name)
                mode = os.lstat(path).st_mode
                if stat.S_ISREG(mode):
                    sources.append(path)

    assert sources, 'No regular C source file was found under /home/user or /app.'

    proc = subprocess.run(
        ['/usr/bin/gcc', '-std=c11', '-O2', *sorted(sources), '-o', str(EXECUTABLE), '-lm'],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, (
        'The submitted C program did not compile successfully.\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    assert EXECUTABLE.is_file(), 'Compilation did not produce an executable program.'


def replace_path(path):
    if path.exists() or path.is_symlink():
        if path.is_dir() and not path.is_symlink():
            pytest.fail(f'Expected {path} to be a file, but it is a directory.')
        path.unlink()


def install_inputs(network_edges, patch_edges):
    replace_path(NETWORK)
    NETWORK.write_text(''.join(f'{u},{v},{w}\n' for u, v, w in network_edges))

    replace_path(PATCH)
    command = [
        '/usr/bin/convert', '-size', '200x100', 'xc:white',
        '-font', 'DejaVu-Sans', '-pointsize', '16', '-fill', 'black',
    ]
    for index, (u, v, w) in enumerate(patch_edges, start=1):
        command.extend(['-annotate', f'+10+{20 * index}', f'{u},{v},{w}'])
    command.append(str(PATCH))
    proc = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert proc.returncode == 0, f'Could not create verifier patch image: {proc.stderr}'


def expected_average(network_edges, patch_edges):
    merged = {(u, v): w for u, v, w in network_edges}
    merged.update({(u, v): w for u, v, w in patch_edges})

    graph = {}
    for (u, v), weight in merged.items():
        graph.setdefault(u, []).append((v, weight))

    distances = {0: 0}
    queue = [(0, 0)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances[node]:
            continue
        for target, weight in graph.get(node, []):
            candidate = distance + weight
            if candidate < distances.get(target, math.inf):
                distances[target] = candidate
                heapq.heappush(queue, (candidate, target))

    reachable = [distance for node, distance in distances.items() if node != 0]
    assert reachable
    return sum(reachable) / len(reachable)


def run_program_and_read_result():
    if RESULT.exists() or RESULT.is_symlink():
        if RESULT.is_dir() and not RESULT.is_symlink():
            pytest.fail(f'{RESULT} is a directory rather than a result file.')
        RESULT.unlink()

    proc = subprocess.run(
        [str(EXECUTABLE)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert proc.returncode == 0, (
        f'The compiled C program exited with status {proc.returncode}.\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    assert RESULT.exists(), f'Expected result file {RESULT} does not exist.'
    assert RESULT.is_file(), f'{RESULT} is not a file.'

    content = RESULT.read_text().strip()
    assert re.fullmatch(r'[+-]?\d+\.\d{4,}(?:[eE][+-]?\d+)?', content), (
        'The result must contain one floating-point number formatted to at least '
        f'4 decimal places. Content: {content!r}'
    )
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f'Could not parse the content of {RESULT} as a float. Content: {content!r}')
    assert math.isfinite(value), 'The result must be a finite floating-point number.'
    return value


def random_case(rng):
    network = [
        (0, 1, rng.randint(1, 9)),
        (0, 2, rng.randint(1, 9)),
        (1, 3, rng.randint(1, 9)),
        (2, 1, rng.randint(1, 9)),
        (2, 3, rng.randint(1, 9)),
        (2, 4, rng.randint(1, 9)),
        (3, 4, rng.randint(1, 9)),
        (4, 0, rng.randint(1, 9)),
        (4, 3, rng.randint(1, 9)),
    ]
    patch = [
        (2, 1, rng.randint(1, 9)),
        (3, 4, rng.randint(1, 9)),
        (4, 5, rng.randint(1, 9)),
    ]
    return network, patch


def test_compiled_program_computes_metric_from_both_inputs():
    find_and_compile_program()

    # Preserve the verifier's original assertion on the supplied task inputs.
    install_inputs(ORIGINAL_NETWORK, ORIGINAL_PATCH)
    agent_val = run_program_and_read_result()
    reference = 7.4
    threshold = 0.05
    diff = abs(agent_val - reference)
    assert diff <= threshold, (
        f'The calculated average shortest path ({agent_val}) differs from the expected '
        f'value ({reference}) by {diff}, which is greater than {threshold}.'
    )

    # Exercise the freshly compiled artifact on unpredictable replacements for
    # both the CSV and screenshot, deriving each answer independently.
    rng = random.SystemRandom()
    cases = []
    while len(cases) < 2:
        candidate = random_case(rng)
        expected = expected_average(*candidate)
        if abs(expected - reference) > 0.2 and all(
            abs(expected - previous[2]) > 0.2 for previous in cases
        ):
            cases.append((candidate[0], candidate[1], expected))

    for index, (network, patch, expected) in enumerate(cases, start=1):
        install_inputs(network, patch)
        actual = run_program_and_read_result()
        assert abs(actual - expected) <= 0.0005, (
            f'Behavioral case {index}: program produced {actual}, but merging the CSV '
            f'with the screenshot edges and computing shortest paths gives {expected}.'
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
