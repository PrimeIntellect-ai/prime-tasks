#!/bin/bash
set -e
mkdir -p /logs/verifier

backup_dir=$(mktemp -d)
cp /home/user/network_events.jsonl "$backup_dir/network_events.jsonl"
had_result=0
if [ -f /home/user/optimized_results.json ]; then
    cp /home/user/optimized_results.json "$backup_dir/optimized_results.json"
    had_result=1
fi
cleanup() {
    cp "$backup_dir/network_events.jsonl" /home/user/network_events.jsonl
    if [ "$had_result" -eq 1 ]; then
        cp "$backup_dir/optimized_results.json" /home/user/optimized_results.json
    else
        rm -f /home/user/optimized_results.json
    fi
    rm -rf "$backup_dir"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import builtins
import io
import json
import os
import secrets
import subprocess
import sys
import tempfile

import pytest

SCRIPT = "/home/user/compute_metrics.py"
DATASET = "/home/user/network_events.jsonl"
RESULT = "/home/user/optimized_results.json"

RUNNER = r'''
import builtins
import io
import os
import runpy
import sys

script, dataset, count_path = sys.argv[1:4]
real_builtin_open = builtins.open
real_io_open = io.open
count = 0

def is_dataset(file):
    try:
        return os.path.realpath(os.fspath(file)) == os.path.realpath(dataset)
    except TypeError:
        return False

def builtin_open(file, *args, **kwargs):
    global count
    if is_dataset(file):
        count += 1
    return real_builtin_open(file, *args, **kwargs)

def io_open(file, *args, **kwargs):
    global count
    if is_dataset(file):
        count += 1
    return real_io_open(file, *args, **kwargs)

builtins.open = builtin_open
io.open = io_open
try:
    runpy.run_path(script, run_name="__main__")
finally:
    with real_builtin_open(count_path, "w") as f:
        f.write(str(count))
'''


def run_submission():
    assert os.path.isfile(SCRIPT), f"The required script {SCRIPT} is missing."
    assert not os.path.islink(SCRIPT), f"{SCRIPT} must be a Python source file, not a symlink."

    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT} is not valid Python: {exc}")

    forbidden = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            forbidden.update(alias.name.split('.')[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            forbidden.add(node.module.split('.')[0])
    assert not ({"networkx", "pandas"} & forbidden), "Only standard-library Python may be used."

    fd, count_path = tempfile.mkstemp(prefix="dataset_open_count_")
    os.close(fd)
    os.unlink(count_path)
    try:
        proc = subprocess.run(
            [sys.executable, "-c", RUNNER, SCRIPT, DATASET, count_path],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=15,
        )
        assert proc.returncode == 0, (
            f"compute_metrics.py failed with exit code {proc.returncode}.\n"
            f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
        )
        assert os.path.isfile(count_path), "Could not verify dataset access by compute_metrics.py."
        with open(count_path, "r") as f:
            open_count = int(f.read())
        assert 1 <= open_count <= 3, (
            f"compute_metrics.py opened the dataset {open_count} times; "
            "the dataset must be processed with a constant number of scans rather than once per user."
        )
    except subprocess.TimeoutExpired:
        pytest.fail("compute_metrics.py did not finish within 15 seconds.")
    finally:
        if os.path.exists(count_path):
            os.unlink(count_path)


def load_result():
    try:
        with open(RESULT, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {RESULT} is not valid JSON.")
    except Exception as e:
        pytest.fail(f"Could not read {RESULT}: {e}")


def expected_metrics(events):
    users = sorted({e["source"] for e in events} | {e["target"] for e in events})
    incoming = {u: 0 for u in users}
    outgoing = {u: [] for u in users}
    for event in events:
        incoming[event["target"]] += 1
        outgoing[event["source"]].append(event["target"])

    ranks = {u: 1.0 for u in users}
    for _ in range(2):
        new_ranks = {u: 0.0 for u in users}
        for user in users:
            targets = outgoing[user]
            if targets:
                share = ranks[user] / len(targets)
                for target in targets:
                    new_ranks[target] += share
        ranks = new_ranks

    return {
        "top_in_degree": sorted(users, key=lambda u: (-incoming[u], u))[:5],
        "top_pagerank": sorted(users, key=lambda u: (-ranks[u], u))[:5],
    }, incoming, ranks


@pytest.fixture(scope="module", autouse=True)
def execute_on_original_dataset():
    if os.path.exists(RESULT):
        os.unlink(RESULT)
    run_submission()


def test_optimized_results_exists():
    file_path = "/home/user/optimized_results.json"
    assert os.path.isfile(file_path), f"The output file {file_path} is missing."


def test_optimized_results_content():
    file_path = "/home/user/optimized_results.json"

    try:
        with open(file_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {file_path} is not valid JSON.")
    except Exception as e:
        pytest.fail(f"Could not read {file_path}: {e}")

    expected_in_degree = ["user_1", "user_5", "user_9", "user_2", "user_3"]
    expected_pagerank = ["user_1", "user_5", "user_4", "user_9", "user_2"]

    assert "top_in_degree" in data, "The key 'top_in_degree' is missing from the JSON output."
    assert "top_pagerank" in data, "The key 'top_pagerank' is missing from the JSON output."

    assert data["top_in_degree"] == expected_in_degree, (
        f"Incorrect 'top_in_degree'. Expected {expected_in_degree}, got {data['top_in_degree']}"
    )

    assert data["top_pagerank"] == expected_pagerank, (
        f"Incorrect 'top_pagerank'. Expected {expected_pagerank}, got {data['top_pagerank']}"
    )


def test_script_computes_metrics_for_unseen_dataset():
    rng = secrets.SystemRandom()

    for _ in range(100):
        token = secrets.token_hex(5)
        users = [f"verify_{token}_{i:02d}" for i in range(12)]
        events = []

        # Ensure every generated user occurs as both a source and a target.
        for i, user in enumerate(users):
            events.append({
                "source": user,
                "target": users[(i + 1) % len(users)],
                "timestamp": 1700000000 + i,
                "type": "message",
            })

        for i in range(500):
            source = rng.choice(users)
            target = rng.choice(users)
            while target == source:
                target = rng.choice(users)
            events.append({
                "source": source,
                "target": target,
                "timestamp": 1700001000 + i,
                "type": "message",
            })

        expected, incoming, ranks = expected_metrics(events)
        degree_values = sorted(incoming.values(), reverse=True)
        rank_values = sorted(ranks.values(), reverse=True)
        if degree_values[4] != degree_values[5] and all(
            abs(rank_values[i] - rank_values[i + 1]) > 1e-8 for i in range(5)
        ):
            break
    else:
        pytest.fail("Could not construct a suitable verification dataset.")

    with open(DATASET, "w") as f:
        for event in events:
            f.write(json.dumps(event) + "\n")

    if os.path.exists(RESULT):
        os.unlink(RESULT)
    run_submission()

    assert os.path.isfile(RESULT), "compute_metrics.py did not create optimized_results.json."
    actual = load_result()
    assert set(actual.keys()) == {"top_in_degree", "top_pagerank"}, (
        "optimized_results.json must contain exactly top_in_degree and top_pagerank."
    )
    assert actual == expected, (
        "compute_metrics.py produced incorrect metrics for an unseen dataset. "
        f"Expected {expected}, got {actual}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
