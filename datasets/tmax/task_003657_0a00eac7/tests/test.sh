#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import re
import secrets
import subprocess
import tempfile
from collections import defaultdict
from decimal import Decimal

import pytest

SCRIPT_PATH = "/home/user/etl_filter.sh"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"
HEADER = ["account_id", "parent_account_id", "balance", "account_type"]


def run_script(path, **kwargs):
    return subprocess.run(
        [SCRIPT_PATH, path], capture_output=True, timeout=15, **kwargs
    )


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_contains_required_sql_strategy():
    with open(SCRIPT_PATH, "r", errors="replace") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert first_line.startswith("#!") and "bash" in first_line, "Submission must be a Bash script."

    noncomment = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    assert re.search(r"(?i)\bsqlite3\b", noncomment), "The script does not invoke SQLite3."
    assert re.search(r"(?is)\bCREATE\s+(?:UNIQUE\s+)?INDEX\b", noncomment), \
        "The script does not create an index."
    assert re.search(r"(?is)\bWITH\s+RECURSIVE\b", noncomment), \
        "The script does not contain a recursive CTE."


def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS, "*.csv"))
    assert len(clean_files) > 0, f"No clean CSV files found in {CLEAN_CORPUS}."

    failed_files = []
    for csv_file in clean_files:
        result = run_script(csv_file)
        if result.returncode != 0:
            failed_files.append(os.path.basename(csv_file))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files rejected (should be accepted). Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS, "*.csv"))
    assert len(evil_files) > 0, f"No evil CSV files found in {EVIL_CORPUS}."

    bypassed_files = []
    for csv_file in evil_files:
        result = run_script(csv_file)
        if result.returncode == 0:
            bypassed_files.append(os.path.basename(csv_file))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed (should be rejected). Offending files: {', '.join(bypassed_files)}")


def reference_validate(rows):
    nodes = {}
    children = defaultdict(list)
    for row in rows:
        aid = row["account_id"]
        pid = row["parent_account_id"]
        if not aid or aid in nodes:
            return False
        try:
            balance = Decimal(row["balance"])
        except Exception:
            return False
        nodes[aid] = {"pid": pid, "balance": balance, "type": row["account_type"]}
        if pid:
            children[pid].append(aid)

    if not nodes:
        return True
    if any(data["pid"] and data["pid"] not in nodes for data in nodes.values()):
        return False

    for pid, child_ids in children.items():
        if nodes[pid]["type"] == "Leaf" and child_ids:
            return False

    for aid, data in nodes.items():
        if data["type"] == "Summary":
            if data["balance"] != sum((nodes[c]["balance"] for c in children[aid]), Decimal(0)):
                return False

    state = {}
    def visit(aid):
        if state.get(aid) == 1:
            return False
        if state.get(aid) == 2:
            return True
        state[aid] = 1
        for child in children[aid]:
            if not visit(child):
                return False
        state[aid] = 2
        return True

    if any(not visit(aid) for aid in nodes):
        return False

    roots = [aid for aid, data in nodes.items() if not data["pid"]]
    reached = set()
    stack = [(root, 1) for root in roots]
    while stack:
        aid, depth = stack.pop()
        if depth > 7:
            return False
        reached.add(aid)
        stack.extend((child, depth + 1) for child in children[aid])
    return len(reached) == len(nodes)


def make_tree(rng, size, max_depth=7):
    ids = [str(x) for x in rng.sample(range(100000, 999999), size)]
    parents = {ids[0]: ""}
    depths = {ids[0]: 1}
    children = defaultdict(list)
    for aid in ids[1:]:
        candidates = [prior for prior in parents if depths[prior] < max_depth]
        parent = rng.choice(candidates)
        parents[aid] = parent
        depths[aid] = depths[parent] + 1
        children[parent].append(aid)

    balances = {}
    types = {}
    for aid in reversed(ids):
        if children[aid]:
            types[aid] = "Summary"
            balances[aid] = sum(balances[c] for c in children[aid])
        else:
            types[aid] = "Leaf"
            balances[aid] = rng.randint(1, 5000)

    rows = [
        {
            "account_id": aid,
            "parent_account_id": parents[aid],
            "balance": str(balances[aid]),
            "account_type": types[aid],
        }
        for aid in ids
    ]
    rng.shuffle(rows)
    return rows


def make_depth_eight(rng):
    ids = [str(x) for x in rng.sample(range(1000000, 9999999), 8)]
    amount = rng.randint(1, 1000)
    rows = []
    for i, aid in enumerate(ids):
        rows.append({
            "account_id": aid,
            "parent_account_id": "" if i == 0 else ids[i - 1],
            "balance": str(amount),
            "account_type": "Leaf" if i == 7 else "Summary",
        })
    rng.shuffle(rows)
    return rows


def write_csv(path, rows):
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=HEADER)
        writer.writeheader()
        writer.writerows(rows)


def test_runtime_generated_cases_and_actual_sqlite_execution():
    rng = random.Random(secrets.randbits(128))
    cases = []

    for _ in range(7):
        valid = make_tree(rng, rng.randint(10, 45), rng.randint(3, 7))
        cases.append(valid)

        mismatch = [dict(r) for r in valid]
        summary = next(r for r in mismatch if r["account_type"] == "Summary")
        summary["balance"] = str(int(summary["balance"]) + rng.randint(1, 31))
        cases.append(mismatch)

        leaf_parent = [dict(r) for r in valid]
        parent_ids = {r["parent_account_id"] for r in leaf_parent if r["parent_account_id"]}
        victim = next(r for r in leaf_parent if r["account_id"] in parent_ids)
        victim["account_type"] = "Leaf"
        cases.append(leaf_parent)

        cycle = [dict(r) for r in valid]
        root = next(r for r in cycle if not r["parent_account_id"])
        descendant = rng.choice([r for r in cycle if r is not root])
        root["parent_account_id"] = descendant["account_id"]
        cases.append(cycle)

    cases.extend(make_depth_eight(rng) for _ in range(4))
    rng.shuffle(cases)

    expected_results = [reference_validate(rows) for rows in cases]
    assert any(expected_results) and not all(expected_results)

    with tempfile.TemporaryDirectory(prefix="etl-runtime-") as directory:
        failures = []
        valid_path = None
        for rows, expected in zip(cases, expected_results):
            name = secrets.token_hex(14) + ".csv"
            path = os.path.join(directory, name)
            write_csv(path, rows)
            if expected and valid_path is None:
                valid_path = path
            result = run_script(path)
            accepted = result.returncode == 0
            if accepted != expected:
                failures.append((name, expected, result.returncode, result.stderr[-300:]))

        assert not failures, f"Runtime-generated validation failures: {failures[:5]}"

        wrapper_dir = os.path.join(directory, "bin")
        os.mkdir(wrapper_dir)
        sqlite_log = os.path.join(directory, "sqlite-called")
        wrapper = os.path.join(wrapper_dir, "sqlite3")
        with open(wrapper, "w") as f:
            f.write("#!/bin/bash\necho called >> " + repr(sqlite_log) + "\nexec /usr/bin/sqlite3 \"$@\"\n")
        os.chmod(wrapper, 0o755)
        env = os.environ.copy()
        env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
        traced = subprocess.run(
            ["bash", "-x", SCRIPT_PATH, valid_path],
            capture_output=True, text=True, timeout=15, env=env
        )
        assert traced.returncode == 0, "Script rejected a generated valid file under execution tracing."
        trace_called_sqlite = re.search(
            r"(?m)^\++\s+(?:\S*/)?sqlite3(?:\s|$)", traced.stderr
        ) is not None
        assert os.path.exists(sqlite_log) or trace_called_sqlite, \
            "The executed validation path did not run SQLite3."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
