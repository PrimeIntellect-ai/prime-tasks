#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import math
import os
import random
import re
import stat
import subprocess
import sys
import time
from collections import deque

PROFILE = '/home/user/profile_results.txt'
FAST_SIM = '/home/user/fast_sim.py'
NETWORK = '/home/user/network_data.csv'
RESULT = '/home/user/result.txt'


def canonical_network_bytes():
    rng = random.Random(123)
    edges = []
    for i in range(99):
        edges.append((i, i + 1, rng.randint(1, 10)))
    for _ in range(200):
        u = rng.randint(0, 99)
        v = rng.randint(0, 99)
        if u != v:
            edges.append((u, v, rng.randint(0, 5)))

    output = io.StringIO(newline='')
    writer = csv.writer(output)
    writer.writerow(['source', 'target', 'observations'])
    writer.writerows(edges)
    return output.getvalue().encode()


def reference_result(data):
    graph = {}
    reader = csv.DictReader(io.StringIO(data.decode()))
    for row in reader:
        u = int(row['source'])
        v = int(row['target'])
        p = 1.0 / (1.0 + int(row['observations']))
        graph.setdefault(u, []).append((v, p))
        graph.setdefault(v, []).append((u, p))

    rng = random.Random(42)
    successes = 0
    for _ in range(10000):
        simulated = {}
        for u, neighbors in graph.items():
            surviving = []
            for v, p in neighbors:
                if rng.random() > p:
                    surviving.append(v)
            simulated[u] = surviving

        seen = {0}
        queue = deque([0])
        found = False
        while queue:
            node = queue.popleft()
            if node == 99:
                found = True
                break
            for neighbor in simulated.get(node, []):
                if neighbor not in seen:
                    seen.add(neighbor)
                    queue.append(neighbor)
        successes += int(found)

    return successes / 10000.0


def execute_fast():
    if os.path.lexists(RESULT):
        os.remove(RESULT)

    start = time.monotonic()
    try:
        completed = subprocess.run(
            [sys.executable, FAST_SIM],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=3.0,
            env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'},
        )
    except subprocess.TimeoutExpired:
        raise AssertionError('fast_sim.py did not finish within 3 seconds')
    elapsed = time.monotonic() - start

    assert completed.returncode == 0, (
        f'fast_sim.py exited with status {completed.returncode}. '
        f'stdout={completed.stdout!r}, stderr={completed.stderr!r}'
    )
    assert elapsed < 3.0, f'fast_sim.py took {elapsed:.3f} seconds; limit is 3 seconds'
    assert os.path.isfile(RESULT), 'fast_sim.py did not create /home/user/result.txt'

    content = open(RESULT, 'r').read().strip()
    try:
        probability = float(content)
    except ValueError:
        raise AssertionError(f'{RESULT} does not contain a valid float. Found: {content}')
    assert math.isfinite(probability), f'{RESULT} must contain a finite probability'
    assert 0.0 <= probability <= 1.0, f'Invalid probability: {probability}'
    return probability, content


def test_profile_results_exists_and_format():
    """Test that profile_results.txt is a complete time-sorted cProfile report."""
    assert os.path.isfile(PROFILE), f'Missing file: {PROFILE}'
    content = open(PROFILE, 'r').read()

    # Preserve the original standard-header assertions.
    assert 'ncalls' in content and 'tottime' in content and 'cumtime' in content, \
        f'File {PROFILE} does not appear to contain valid cProfile output.'

    assert re.search(r'\d+ function calls(?: \(\d+ primitive calls\))? in [0-9.]+ seconds', content), \
        'Missing the cProfile call-count and elapsed-time summary'
    assert 'Ordered by: internal time' in content, 'Profile was not sorted by internal time'
    assert re.search(r'slow_sim\.py:\d+\(run_simulation\)', content), 'run_simulation is absent from profile'
    assert re.search(r'slow_sim\.py:\d+\(load_graph\)', content), 'load_graph is absent from profile'
    assert re.search(r'^\s*10000\s+.*slow_sim\.py:\d+\(has_path\)', content, re.MULTILINE), \
        'Profile does not show 10,000 calls to has_path'

    times = [float(match.group(1)) for match in re.finditer(
        r'^\s*\d+(?:/\d+)?\s+([0-9]+\.[0-9]+)\s+[0-9]+\.[0-9]+\s+[0-9]+\.[0-9]+\s+',
        content,
        re.MULTILINE,
    )]
    assert len(times) >= 10, 'Profiling report is incomplete'
    assert all(a >= b for a, b in zip(times, times[1:])), \
        'Profiling rows are not sorted by internal time'


def test_fast_sim_exists():
    """Test that the fast_sim.py script exists and is a regular Python file."""
    assert os.path.isfile(FAST_SIM), f'Missing file: {FAST_SIM}'
    assert stat.S_ISREG(os.stat(FAST_SIM, follow_symlinks=False).st_mode), \
        f'{FAST_SIM} must be a regular file'
    with open(FAST_SIM, 'rb') as handle:
        source = handle.read()
    compile(source, FAST_SIM, 'exec')


def test_result_txt_exists_and_correct():
    """Execute the optimized simulation and verify its behavior and runtime."""
    canonical = canonical_network_bytes()
    original_network = open(NETWORK, 'rb').read() if os.path.exists(NETWORK) else None
    canonical_result_text = None

    try:
        # Test the shipped network independently of any stale result or modified input.
        with open(NETWORK, 'wb') as handle:
            handle.write(canonical)
        probability, canonical_result_text = execute_fast()
        expected = reference_result(canonical)
        assert abs(probability - expected) <= 0.01, \
            f'Probability {probability} differs from independently computed result {expected}'

        # Preserve the original range assertion.
        assert 0.16 <= probability <= 0.20, \
            f'Probability in {RESULT} is {probability}, outside [0.16, 0.20]'

        # Exercise the implementation on additional networks so a fabricated constant
        # result cannot pass. Each expected value is independently simulated here.
        probes = [
            b'source,target,observations\n0,99,1\n',
            b'source,target,observations\n0,99,9\n',
        ]
        for probe in probes:
            with open(NETWORK, 'wb') as handle:
                handle.write(probe)
            observed, _ = execute_fast()
            probe_expected = reference_result(probe)
            assert abs(observed - probe_expected) <= 0.01, (
                f'fast_sim.py produced {observed} for a probe network; '
                f'expected approximately {probe_expected}'
            )
    finally:
        if original_network is None:
            if os.path.exists(NETWORK):
                os.remove(NETWORK)
        else:
            with open(NETWORK, 'wb') as handle:
                handle.write(original_network)
        if canonical_result_text is not None:
            with open(RESULT, 'w') as handle:
                handle.write(canonical_result_text)

    assert os.path.isfile(RESULT), f'Missing file: {RESULT}'

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
