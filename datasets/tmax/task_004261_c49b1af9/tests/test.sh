#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile

import pytest

DATA_PATH = '/app/data.fasta'
RESULT_PATH = '/app/result.txt'


def get_truth(path=DATA_PATH):
    lengths = []
    gc_counts = []
    with open(path, 'r') as f:
        seq = ""
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if seq:
                    lengths.append(len(seq))
                    gc_counts.append(seq.count('G') + seq.count('C'))
                seq = ""
            else:
                seq += line
        if seq:
            lengths.append(len(seq))
            gc_counts.append(seq.count('G') + seq.count('C'))

    n = len(lengths)
    adj = {i: [] for i in range(n)}
    for i in range(n):
        for j in range(i + 1, n):
            if abs(lengths[i] - lengths[j]) <= 2:
                adj[i].append(j)
                adj[j].append(i)

    visited = set()
    components = []
    for i in range(n):
        if i not in visited:
            comp = []
            q = [i]
            visited.add(i)
            while q:
                curr = q.pop(0)
                comp.append(curr)
                for neighbor in adj[curr]:
                    if neighbor not in visited:
                        visited.add(neighbor)
                        q.append(neighbor)
            components.append(comp)

    lcc = max(components, key=len)
    x = [lengths[i] for i in lcc]
    y = [gc_counts[i] for i in lcc]

    mean_x = sum(x) / len(x)
    mean_y = sum(y) / len(y)
    num = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    den_x = sum((xi - mean_x) ** 2 for xi in x)
    den_y = sum((yi - mean_y) ** 2 for yi in y)
    r = num / math.sqrt(den_x * den_y)

    N = len(lcc)
    t = r * math.sqrt(N - 2) / math.sqrt(1 - r ** 2)
    return abs(t)


def read_result():
    assert os.path.isfile(RESULT_PATH), f"Expected output file {RESULT_PATH} does not exist."
    with open(RESULT_PATH, 'r') as f:
        content = f.read().strip()
    try:
        value = float(content)
    except ValueError:
        pytest.fail(f"Content of {RESULT_PATH} is not a valid float: '{content}'")
    assert math.isfinite(value), f"Content of {RESULT_PATH} is not a finite float: '{content}'"
    return value


def write_case(rng, case_number):
    while True:
        main_count = 8 + case_number
        start = rng.randint(24, 42)
        lengths = [start]
        for _ in range(main_count - 1):
            lengths.append(lengths[-1] + rng.choice([1, 2]))
        gc_counts = [rng.randint(2, length - 2) for length in lengths]

        secondary_count = 3 + case_number
        secondary_start = lengths[-1] + rng.randint(25, 40)
        secondary_lengths = [secondary_start + 2 * i for i in range(secondary_count)]
        secondary_gc = [rng.randint(2, length - 2) for length in secondary_lengths]

        records = list(zip(lengths, gc_counts)) + list(zip(secondary_lengths, secondary_gc))
        rng.shuffle(records)

        with open(DATA_PATH, 'w') as f:
            for i, (length, gc_count) in enumerate(records):
                seq = 'G' * gc_count + 'A' * (length - gc_count)
                f.write(f">hidden_{case_number}_{i}\n")
                split = max(1, length // 3)
                for pos in range(0, length, split):
                    f.write(seq[pos:pos + split] + '\n')

        try:
            expected = get_truth()
        except (ValueError, ZeroDivisionError):
            continue
        if math.isfinite(expected):
            return expected


def compile_candidates(sources, tempdir):
    attempts = []
    attempts.append(tuple(sources))
    for source in sources:
        attempts.append((source,))

    main_sources = []
    support_sources = []
    main_pattern = re.compile(r'\bmain\s*\(')
    for source in sources:
        try:
            with open(source, 'r', errors='ignore') as f:
                text = f.read()
        except OSError:
            continue
        if main_pattern.search(text):
            main_sources.append(source)
        else:
            support_sources.append(source)
    for main_source in main_sources:
        attempts.append(tuple([main_source] + support_sources))

    seen = set()
    binaries = []
    for index, attempt in enumerate(attempts):
        attempt = tuple(dict.fromkeys(attempt))
        if not attempt or attempt in seen:
            continue
        seen.add(attempt)
        binary = os.path.join(tempdir, f'candidate_{index}')
        command = ['gcc', '-std=c11', '-O2', *attempt, '-lm', '-o', binary]
        try:
            completed = subprocess.run(
                command, cwd='/app', stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=20
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        if completed.returncode == 0 and os.path.isfile(binary):
            mode = os.stat(binary).st_mode
            if mode & stat.S_IXUSR:
                binaries.append(binary)
    return binaries


def test_original_result_and_c_implementation():
    # Preserve the original verifier's assertion on the submitted result.
    agent_val = read_result()
    target_val = get_truth()
    error = abs(agent_val - target_val)
    assert error <= 0.01, (
        f"Computed statistic is incorrect. Agent value: {agent_val}, "
        f"Target value: {target_val}, Absolute error: {error} "
        f"(Threshold: <= 0.01)"
    )

    sources = sorted(
        path for path in glob.glob('/app/**/*.c', recursive=True)
        if os.path.isfile(path)
    )
    assert sources, "No C source program was found under /app."

    original_data = open(DATA_PATH, 'rb').read()
    original_result = open(RESULT_PATH, 'rb').read()
    tempdir = tempfile.mkdtemp(prefix='verify_c_')

    try:
        binaries = compile_candidates(sources, tempdir)
        assert binaries, "The submitted C source could not be compiled with gcc and -lm."

        rng = random.SystemRandom()
        passed_binary = None
        failure_details = []
        for binary in binaries:
            binary_ok = True
            for case_number in range(3):
                expected = write_case(rng, case_number)
                try:
                    os.remove(RESULT_PATH)
                except FileNotFoundError:
                    pass
                try:
                    run = subprocess.run(
                        [binary], cwd='/app', stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, timeout=8
                    )
                except (OSError, subprocess.TimeoutExpired) as exc:
                    failure_details.append(f"{os.path.basename(binary)} failed to run: {exc}")
                    binary_ok = False
                    break
                if run.returncode != 0:
                    failure_details.append(
                        f"{os.path.basename(binary)} exited with status {run.returncode}"
                    )
                    binary_ok = False
                    break
                try:
                    actual = read_result()
                except AssertionError as exc:
                    failure_details.append(f"{os.path.basename(binary)}: {exc}")
                    binary_ok = False
                    break
                if abs(actual - expected) > 0.01:
                    failure_details.append(
                        f"{os.path.basename(binary)} produced {actual}, expected {expected}"
                    )
                    binary_ok = False
                    break
            if binary_ok:
                passed_binary = binary
                break

        assert passed_binary is not None, (
            "No submitted C program correctly implemented the protocol on verification inputs. "
            + "; ".join(failure_details[-5:])
        )
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)
        with open(RESULT_PATH, 'wb') as f:
            f.write(original_result)
        shutil.rmtree(tempdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
