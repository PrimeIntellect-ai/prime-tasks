#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import stat
import subprocess
import uuid
from collections import defaultdict, deque

import pytest

SCRIPT = "/home/user/backup_manager.py"
CSV_PATH = "/home/user/relational_deps.csv"
JSON_PATH = "/home/user/doc_deps.json"
LOG_PATH = "/home/user/restore_plan.log"

ORIGINAL_CSV = """db,depends_on
user_db,auth_db
profile_db,user_db
billing_db,user_db
analytics_db,billing_db
"""

ORIGINAL_JSON = [
    {"db": "notification_db", "requires": ["profile_db"]},
    {"db": "recommendation_db", "requires": ["user_db", "analytics_db"]},
    {"db": "auth_db", "requires": ["root_ca_db"]},
    {"db": "unrelated_db", "requires": ["some_other_db"]},
]

EXPECTED_ORIGINAL = [
    "3: analytics_db",
    "3: notification_db",
    "2: billing_db",
    "2: profile_db",
    "2: recommendation_db",
    "1: user_db",
]


def read_optional(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        return f.read()


def restore_optional(path, data):
    if data is None:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    else:
        with open(path, "wb") as f:
            f.write(data)


@pytest.fixture(scope="session", autouse=True)
def preserve_agent_files():
    saved = {path: read_optional(path) for path in (CSV_PATH, JSON_PATH, LOG_PATH)}
    yield
    for path, data in saved.items():
        restore_optional(path, data)


def install_inputs(csv_rows, documents):
    with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["db", "depends_on"])
        writer.writerows(csv_rows)
    with open(JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(documents, f)


def install_original_inputs():
    with open(CSV_PATH, "w", encoding="utf-8") as f:
        f.write(ORIGINAL_CSV)
    with open(JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(ORIGINAL_JSON, f)


def run_script():
    try:
        os.remove(LOG_PATH)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(LOG_PATH), f"The file {LOG_PATH} was not created."
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def derive_expected(csv_rows, documents):
    reverse = defaultdict(set)
    for db, dependency in csv_rows:
        reverse[dependency].add(db)
    for document in documents:
        for dependency in document["requires"]:
            reverse[dependency].add(document["db"])

    distances = {"auth_db": 0}
    queue = deque(["auth_db"])
    while queue:
        current = queue.popleft()
        for dependent in reverse[current]:
            if dependent not in distances:
                distances[dependent] = distances[current] + 1
                queue.append(dependent)

    affected = [(distance, db) for db, distance in distances.items() if db != "auth_db"]
    affected.sort(key=lambda item: (-item[0], item[1]))
    return [f"{distance}: {db}" for distance, db in affected]


def test_backup_manager_exists_and_is_python_without_networkx():
    assert os.path.exists(SCRIPT), f"The required script {SCRIPT} does not exist."
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} must be a regular file."
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            assert all(alias.name.split(".")[0] != "networkx" for alias in node.names), \
                "External graph library networkx must not be used."
        elif isinstance(node, ast.ImportFrom):
            assert not node.module or node.module.split(".")[0] != "networkx", \
                "External graph library networkx must not be used."


def test_restore_plan_log_exists():
    install_original_inputs()
    run_script()
    path = "/home/user/restore_plan.log"
    assert os.path.isfile(path), f"The file {path} was not created."


def test_restore_plan_log_content():
    install_original_inputs()
    run_script()
    path = "/home/user/restore_plan.log"
    assert os.path.isfile(path), f"The file {path} was not created."

    expected_lines = EXPECTED_ORIGINAL
    with open(path, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"The contents of {path} do not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_script_reads_both_files_and_computes_dynamic_shortest_paths():
    token = uuid.uuid4().hex
    names = [f"db_{token}_{suffix}" for suffix in ("alpha", "beta", "gamma", "delta", "epsilon", "zeta", "unrelated")]
    alpha, beta, gamma, delta, epsilon, zeta, unrelated = names

    # The paths deliberately cross file formats. zeta has paths of lengths 3
    # and 4, so the implementation must select the shortest one.
    csv_rows = [
        (alpha, "auth_db"),
        (gamma, beta),
        (epsilon, delta),
        (unrelated, f"missing_{token}"),
    ]
    documents = [
        {"db": beta, "requires": [alpha]},
        {"db": delta, "requires": ["auth_db"]},
        {"db": zeta, "requires": [gamma, epsilon]},
        {"db": f"isolated_{token}", "requires": [unrelated]},
    ]

    install_inputs(csv_rows, documents)
    expected = derive_expected(csv_rows, documents)
    actual = run_script()
    assert actual == expected, (
        "The script did not correctly read and unify both dependency files, "
        "compute shortest paths, or apply the required ordering.\n"
        f"Expected:\n{chr(10).join(expected)}\n\n"
        f"Actual:\n{chr(10).join(actual)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
