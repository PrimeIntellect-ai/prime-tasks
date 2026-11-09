#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import sqlite3
import subprocess
import uuid

SCRIPT_PATH = "/home/user/analyze_locks.sh"
DB_PATH = "/home/user/db_state.sqlite"
RESULT_PATH = "/home/user/deadlock_result.txt"


def create_database(transactions, locks):
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    connection = sqlite3.connect(DB_PATH)
    try:
        connection.execute("CREATE TABLE transactions (tx_id TEXT PRIMARY KEY, type TEXT)")
        connection.execute("CREATE TABLE locks (tx_id TEXT, resource_id TEXT, granted INTEGER)")
        connection.executemany(
            "INSERT INTO transactions (tx_id, type) VALUES (?, ?)", transactions
        )
        connection.executemany(
            "INSERT INTO locks (tx_id, resource_id, granted) VALUES (?, ?, ?)", locks
        )
        connection.commit()
    finally:
        connection.close()


def create_initial_database():
    transactions = [
        ("TX_A", "app"), ("TX_B", "app"), ("TX_C", "app"),
        ("TX_D", "backup"), ("TX_E", "app"), ("TX_F", "app"),
    ]
    locks = [
        ("TX_A", "RES_1", 1), ("TX_A", "RES_2", 0),
        ("TX_B", "RES_2", 1), ("TX_B", "RES_3", 0),
        ("TX_C", "RES_3", 1), ("TX_C", "RES_4", 0),
        ("TX_D", "RES_4", 1), ("TX_D", "RES_1", 0),
        ("TX_E", "RES_5", 1), ("TX_E", "RES_6", 0),
        ("TX_F", "RES_6", 1),
    ]
    create_database(transactions, locks)


def run_script():
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    completed = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"Script exited with status {completed.returncode}. "
        f"stdout: {completed.stdout!r}; stderr: {completed.stderr!r}"
    )


def make_id():
    return "T_" + uuid.uuid4().hex


def add_cycle(ids, locks):
    resources = ["R_" + uuid.uuid4().hex for _ in ids]
    for index, tx_id in enumerate(ids):
        locks.append((tx_id, resources[index], 1))
        locks.append((tx_id, resources[(index + 1) % len(ids)], 0))


def create_dynamic_database(short_length, long_length):
    shortest_cycle = [make_id() for _ in range(short_length)]
    longer_cycle = [make_id() for _ in range(long_length)]
    chain = [make_id() for _ in range(3)]
    isolated = [make_id() for _ in range(2)]
    all_ids = shortest_cycle + longer_cycle + chain + isolated

    transactions = [
        (tx_id, "backup" if index % 4 == 0 else "app")
        for index, tx_id in enumerate(all_ids)
    ]
    random.SystemRandom().shuffle(transactions)

    locks = []
    add_cycle(shortest_cycle, locks)
    add_cycle(longer_cycle, locks)

    chain_resources = ["R_" + uuid.uuid4().hex for _ in chain]
    for index, tx_id in enumerate(chain):
        locks.append((tx_id, chain_resources[index], 1))
        if index + 1 < len(chain):
            locks.append((tx_id, chain_resources[index + 1], 0))

    for tx_id in isolated:
        locks.append((tx_id, "R_" + uuid.uuid4().hex, 1))

    random.SystemRandom().shuffle(locks)
    create_database(transactions, locks)
    return ",".join(sorted(shortest_cycle))


def test_script_exists_and_executable():
    """Verify that the analyze_locks.sh script exists and is executable."""
    script_path = "/home/user/analyze_locks.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_script_runs_on_initial_database():
    create_initial_database()
    run_script()


def test_result_file_exists():
    """Verify that the deadlock_result.txt file exists."""
    result_path = "/home/user/deadlock_result.txt"
    assert os.path.isfile(result_path), f"Result file {result_path} does not exist."


def test_result_content():
    """Verify that the deadlock result contains the correct transactions."""
    result_path = "/home/user/deadlock_result.txt"
    assert os.path.isfile(result_path), f"Result file {result_path} does not exist."

    with open(result_path, "r") as f:
        content = f.read().strip()

    expected = "TX_A,TX_B,TX_C,TX_D"
    assert content == expected, f"Expected content '{expected}', but got '{content}'."


def test_recomputes_shortest_cycle_for_changed_databases():
    for short_length, long_length in ((2, 4), (3, 5)):
        expected = create_dynamic_database(short_length, long_length)
        run_script()
        assert os.path.isfile(RESULT_PATH), f"Result file {RESULT_PATH} does not exist."
        with open(RESULT_PATH, "r") as result_file:
            content = result_file.read().strip()
        assert content == expected, f"Expected content '{expected}', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
