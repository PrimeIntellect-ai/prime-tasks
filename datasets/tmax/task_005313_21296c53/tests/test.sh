#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import secrets
import subprocess
import tempfile
import uuid

DETECTOR = '/home/user/detector.py'


def test_detector_exists():
    assert os.path.isfile(DETECTOR), "/home/user/detector.py does not exist."


def run_detector(path):
    return subprocess.run(
        ['python3', DETECTOR, path],
        capture_output=True,
        text=True,
        timeout=15
    )


def test_adversarial_corpus():
    clean_dir = '/home/user/corpora/clean'
    evil_dir = '/home/user/corpora/evil'

    clean_files = glob.glob(os.path.join(clean_dir, '*.csv'))
    evil_files = glob.glob(os.path.join(evil_dir, '*.csv'))

    assert len(clean_files) > 0, f"No clean CSV files found in {clean_dir}."
    assert len(evil_files) > 0, f"No evil CSV files found in {evil_dir}."

    clean_failures = []
    for cf in clean_files:
        try:
            result = run_detector(cf)
            output = result.stdout.strip()
            if output != "CLEAN":
                clean_failures.append(os.path.basename(cf))
        except subprocess.TimeoutExpired:
            clean_failures.append(f"{os.path.basename(cf)} (TIMEOUT)")
        except Exception as e:
            clean_failures.append(f"{os.path.basename(cf)} (ERROR: {str(e)})")

    evil_failures = []
    for ef in evil_files:
        try:
            result = run_detector(ef)
            output = result.stdout.strip()
            if output != "EVIL":
                evil_failures.append(os.path.basename(ef))
        except subprocess.TimeoutExpired:
            evil_failures.append(f"{os.path.basename(ef)} (TIMEOUT)")
        except Exception as e:
            evil_failures.append(f"{os.path.basename(ef)} (ERROR: {str(e)})")

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: " + ", ".join(evil_failures))
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified: " + ", ".join(clean_failures))

    if error_msgs:
        assert False, " | ".join(error_msgs)


def oracle(path):
    graph = {}
    nodes = set()
    with open(path, newline='') as f:
        for row in csv.DictReader(f):
            source = row['source_account']
            target = row['target_account']
            nodes.update((source, target))
            if float(row['amount']) >= 50000:
                graph.setdefault(source, set()).add(target)

    # Search for a simple directed cycle containing at least three distinct nodes.
    for start in nodes:
        def visit(current, path, seen):
            for nxt in graph.get(current, ()):
                if nxt == start:
                    if len(path) >= 3:
                        return True
                elif nxt not in seen:
                    if visit(nxt, path + [nxt], seen | {nxt}):
                        return True
            return False

        if visit(start, [start], {start}):
            return 'EVIL'
    return 'CLEAN'


def account_name(rng):
    return 'acct_' + ''.join(rng.choice('abcdefghijklmnopqrstuvwxyz0123456789') for _ in range(18))


def make_case(rng, should_be_evil):
    count = rng.randint(5, 9)
    nodes = [account_name(rng) for _ in range(count)]
    edges = {}
    high = [50000, 50000.01, 61735, 99999]
    low = [1000, 27500, 49999, 49999.99]

    if should_be_evil:
        cycle_len = rng.randint(3, min(6, count))
        cycle = rng.sample(nodes, cycle_len)
        for i, source in enumerate(cycle):
            edges[(source, cycle[(i + 1) % cycle_len])] = rng.choice(high)
    else:
        # All threshold-qualified edges follow this random order, so they are acyclic.
        order = nodes[:]
        rng.shuffle(order)
        for i in range(len(order)):
            for j in range(i + 1, len(order)):
                if rng.random() < 0.28:
                    edges[(order[i], order[j])] = rng.choice(high)

    # Add arbitrary low-value noise in either direction. It cannot create a
    # qualifying cycle but prevents classification by simple row patterns.
    target_rows = rng.randint(max(5, count), count * 3)
    attempts = 0
    while len(edges) < target_rows and attempts < 500:
        attempts += 1
        source, target = rng.sample(nodes, 2)
        if (source, target) not in edges:
            edges[(source, target)] = rng.choice(low)

    rows = []
    for index, ((source, target), amount) in enumerate(edges.items()):
        rows.append({
            'source_account': source,
            'target_account': target,
            'timestamp': f"2024-{rng.randint(1,12):02d}-{rng.randint(1,28):02d}T{index % 24:02d}:00:00Z",
            'amount': str(amount),
        })
    rng.shuffle(rows)
    return rows


def test_generated_transaction_graphs():
    rng = random.Random(secrets.randbits(128))
    cases = [False] * 6 + [True] * 6
    rng.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix='transactions_' + uuid.uuid4().hex + '_') as directory:
        paths = []
        for evil in cases:
            path = os.path.join(directory, uuid.uuid4().hex + '.csv')
            rows = make_case(rng, evil)
            with open(path, 'w', newline='') as f:
                writer = csv.DictWriter(
                    f,
                    fieldnames=['source_account', 'target_account', 'timestamp', 'amount']
                )
                writer.writeheader()
                writer.writerows(rows)
            expected = oracle(path)
            assert expected == ('EVIL' if evil else 'CLEAN')
            paths.append((path, expected))

        rng.shuffle(paths)
        failures = []
        for path, expected in paths:
            try:
                result = run_detector(path)
                actual = result.stdout.strip()
                if result.returncode != 0 or actual != expected:
                    failures.append(
                        f"{os.path.basename(path)} expected {expected}, got {actual!r}, exit={result.returncode}"
                    )
            except subprocess.TimeoutExpired:
                failures.append(f"{os.path.basename(path)} timed out")
            except Exception as exc:
                failures.append(f"{os.path.basename(path)} error: {exc}")

        assert not failures, "Generated graph failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
