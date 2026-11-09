#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import itertools
import json
import os
import random
import subprocess
import sys
import tempfile

import pytest

APP_ENV = dict(os.environ, PYTHONPATH="/app" + (":" + os.environ["PYTHONPATH"] if os.environ.get("PYTHONPATH") else ""))
AGENT_SCRIPT = "/home/user/audit.py"
TRANSACTION_SOURCE = "/app/graph_auditor/core/transaction.py"


def run_agent(records, timeout=5):
    result = subprocess.run(
        [sys.executable, AGENT_SCRIPT, json.dumps(records, separators=(",", ":"))],
        capture_output=True,
        text=True,
        timeout=timeout,
        env=APP_ENV,
    )
    assert result.returncode == 0, f"audit.py failed:\nstdout={result.stdout}\nstderr={result.stderr}"
    try:
        output = json.loads(result.stdout.strip())
    except Exception as exc:
        pytest.fail(f"audit.py did not print a JSON result: {result.stdout!r} ({exc})")
    assert isinstance(output, list), "The audit result must be a JSON list"
    return result.stdout.strip(), output


def expected_cycle_sets(records):
    totals = collections.Counter()
    edges = set()
    for record in records:
        src = record["from_acct"]
        dst = record["to_acct"]
        amount = record["amount"]
        totals[src] += amount
        totals[dst] += amount
        edges.add((src, dst))

    eligible = sorted(account for account, total in totals.items() if total > 10000)
    cycles = set()
    for length in (2, 3):
        for nodes in itertools.permutations(eligible, length):
            if all((nodes[i], nodes[(i + 1) % length]) in edges for i in range(length)):
                cycles.add(frozenset(nodes))
    return cycles


def normalize_cycles(output, records):
    edges = {(r["from_acct"], r["to_acct"]) for r in records}
    normalized = set()
    for path in output:
        assert isinstance(path, list), f"Cycle path is not a list: {path!r}"
        assert all(isinstance(node, str) for node in path), f"Cycle contains a non-string account: {path!r}"
        nodes = list(path)
        if len(nodes) >= 2 and nodes[0] == nodes[-1]:
            nodes.pop()
        assert len(nodes) in (2, 3), f"Cycle must have length 2 or 3: {path!r}"
        assert len(set(nodes)) == len(nodes), f"Cycle repeats an account internally: {path!r}"
        assert all((nodes[i], nodes[(i + 1) % len(nodes)]) in edges for i in range(len(nodes))), (
            f"Reported path is not a directed cycle in the input: {path!r}"
        )
        normalized.add(frozenset(nodes))
    return normalized


def assert_correct(records):
    _, output = run_agent(records)
    assert normalize_cycles(output, records) == expected_cycle_sets(records)


def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), "The agent script /home/user/audit.py does not exist."


def test_vendored_insert_edge_no_longer_deadlocks():
    assert os.path.isfile(TRANSACTION_SOURCE)
    probe = r'''
import os
import threading
from graph_auditor.core import transaction

# The transaction operation must still use the package's lock facility rather
# than merely being replaced by an empty no-op.
if "get_lock" not in transaction.insert_edge.__code__.co_names:
    raise SystemExit(4)

for iteration in range(12):
    barrier = threading.Barrier(2)
    errors = []
    a = "A" + str(iteration)
    b = "B" + str(iteration)

    def worker(src, dst):
        try:
            barrier.wait()
            transaction.insert_edge(src, dst, {"iteration": iteration})
        except BaseException as exc:
            errors.append(repr(exc))

    threads = [threading.Thread(target=worker, args=(a, b), daemon=True),
               threading.Thread(target=worker, args=(b, a), daemon=True)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(1.0)
    if any(thread.is_alive() for thread in threads):
        os._exit(3)
    if errors:
        raise RuntimeError(errors)
'''
    try:
        result = subprocess.run(
            [sys.executable, "-c", probe], capture_output=True, text=True,
            timeout=4, env=APP_ENV
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Concurrent reverse edge insertions deadlocked in the vendored package")
    assert result.returncode == 0, (
        f"Vendored transaction concurrency test failed with {result.returncode}:\n{result.stderr}"
    )


def test_known_cycle_and_threshold_cases():
    records = [
        {"tx_id": "T1", "from_acct": "A", "to_acct": "B", "amount": 11001},
        {"tx_id": "T2", "from_acct": "B", "to_acct": "C", "amount": 11002},
        {"tx_id": "T3", "from_acct": "C", "to_acct": "A", "amount": 11003},
        {"tx_id": "T4", "from_acct": "D", "to_acct": "E", "amount": 20000},
    ]
    first_stdout, first_output = run_agent(records)
    second_stdout, second_output = run_agent(records)
    assert first_stdout == second_stdout, "audit.py output is not deterministic"
    assert first_output == second_output
    assert normalize_cycles(first_output, records) == {frozenset(("A", "B", "C"))}

    assert_correct([
        {"tx_id": "T1", "from_acct": "A", "to_acct": "B", "amount": 5000},
        {"tx_id": "T2", "from_acct": "B", "to_acct": "A", "amount": 5000},
    ])
    assert_correct([
        {"tx_id": "T1", "from_acct": "A", "to_acct": "B", "amount": 10001},
        {"tx_id": "T2", "from_acct": "B", "to_acct": "A", "amount": 10001},
    ])


def test_derived_random_cases():
    rng = random.Random(8675309)
    accounts = list("ABCDEF")
    for case in range(8):
        records = []
        for index in range(rng.randint(8, 18)):
            src, dst = rng.sample(accounts, 2)
            records.append({
                "tx_id": f"R{case}_{index}",
                "from_acct": src,
                "to_acct": dst,
                "amount": rng.randint(500, 14000),
            })
        assert_correct(records)


def test_audit_uses_package_to_load_every_edge():
    original = open(TRANSACTION_SOURCE, "r", encoding="utf-8").read()
    trace_fd, trace_path = tempfile.mkstemp(prefix="graph_auditor_trace_")
    os.close(trace_fd)
    os.unlink(trace_path)
    wrapper = r'''

# Verification instrumentation
import json as _verify_json
import os as _verify_os
_verify_real_insert_edge = insert_edge
def insert_edge(src, dst, data):
    _trace = _verify_os.environ.get("GRAPH_AUDITOR_TRACE")
    if _trace:
        with open(_trace, "a", encoding="utf-8") as _trace_file:
            _trace_file.write(_verify_json.dumps([src, dst], separators=(",", ":")) + "\\n")
    return _verify_real_insert_edge(src, dst, data)
'''
    records = [
        {"tx_id": "L1", "from_acct": "U", "to_acct": "V", "amount": 12001},
        {"tx_id": "L2", "from_acct": "V", "to_acct": "W", "amount": 13002},
        {"tx_id": "L3", "from_acct": "W", "to_acct": "X", "amount": 14003},
    ]
    try:
        with open(TRANSACTION_SOURCE, "w", encoding="utf-8") as source_file:
            source_file.write(original + wrapper)
        env = dict(APP_ENV, GRAPH_AUDITOR_TRACE=trace_path)
        result = subprocess.run(
            [sys.executable, AGENT_SCRIPT, json.dumps(records)],
            capture_output=True, text=True, timeout=5, env=env
        )
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(trace_path), "audit.py never called graph_auditor.core.transaction.insert_edge"
        with open(trace_path, "r", encoding="utf-8") as trace_file:
            calls = [tuple(json.loads(line)) for line in trace_file if line.strip()]
        for record in records:
            assert (record["from_acct"], record["to_acct"]) in calls, (
                f"Transaction {record['tx_id']} was not loaded through graph_auditor"
            )
    finally:
        with open(TRANSACTION_SOURCE, "w", encoding="utf-8") as source_file:
            source_file.write(original)
        if os.path.exists(trace_path):
            os.unlink(trace_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
