#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest


def parse_graph():
    """
    Returns the expected state from the immutable task fixture definition rather
    than trusting the agent-writable graph file.
    """
    path = "/home/user/db_graph.nt"
    assert os.path.exists(path), f"Graph file missing at {path}"

    statuses = {
        "UserDB": "SUCCESS",
        "AuthDB": "FAILED",
        "OrderDB": "SUCCESS",
        "PaymentDB": "MISSING",
        "ReportDB": "SUCCESS",
        "AuditDB": "FAILED",
    }
    sizes = {
        "UserDB": 50,
        "AuthDB": 10,
        "OrderDB": 100,
        "PaymentDB": 20,
        "ReportDB": 200,
        "AuditDB": 5,
    }
    deps = [
        ("AuthDB", "UserDB"),
        ("OrderDB", "UserDB"),
        ("PaymentDB", "OrderDB"),
        ("PaymentDB", "UserDB"),
        ("ReportDB", "OrderDB"),
        ("ReportDB", "PaymentDB"),
        ("AuditDB", "AuthDB"),
        ("AuditDB", "PaymentDB"),
    ]
    return statuses, sizes, deps


def test_total_backup_size():
    """Validates that the total size file contains the correct computed sum."""
    statuses, sizes, _ = parse_graph()

    target_dbs = {db for db, status in statuses.items() if status != "SUCCESS"}
    expected_size = sum(sizes[db] for db in target_dbs)

    size_file = "/home/user/total_backup_size.txt"
    assert os.path.exists(size_file), f"Output file {size_file} does not exist."

    with open(size_file, "r") as f:
        content = f.read().strip()

    assert content.isdigit(), f"File {size_file} should contain only an integer, got: '{content}'"
    actual_size = int(content)
    assert actual_size == expected_size, f"Expected total size {expected_size}, but got {actual_size}."


def test_execute_backups_script_exists_and_executable():
    """Validates the execution script exists, is executable, and has a valid shebang."""
    script_file = "/home/user/execute_backups.sh"
    assert os.path.exists(script_file), f"Script {script_file} does not exist."
    assert os.access(script_file, os.X_OK), f"Script {script_file} is not executable."

    with open(script_file, "r") as f:
        first_line = f.readline().strip()

    assert first_line == "#!/bin/bash", f"Script must start with '#!/bin/bash', got '{first_line}'."


def test_execute_backups_script_content_and_order():
    """Validates the script targets the correct databases in a valid topological order."""
    statuses, _, deps = parse_graph()
    target_dbs = {db for db, status in statuses.items() if status != "SUCCESS"}

    script_file = "/home/user/execute_backups.sh"
    assert os.path.exists(script_file), f"Script {script_file} missing."

    executed_dbs = []
    with open(script_file, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("/usr/local/bin/backup_tool --database"):
                parts = line.split()
                if len(parts) >= 3:
                    executed_dbs.append(parts[2])

    assert set(executed_dbs) == target_dbs, (
        f"Executed databases {set(executed_dbs)} do not match the identified target "
        f"databases {target_dbs}."
    )
    assert len(executed_dbs) == len(target_dbs), "There are duplicate backup executions in the script."

    for sub, obj in deps:
        if sub in target_dbs and obj in target_dbs:
            sub_idx = executed_dbs.index(sub)
            obj_idx = executed_dbs.index(obj)
            assert obj_idx < sub_idx, (
                f"Topological sort violation: '{sub}' depends on '{obj}', "
                f"so '{obj}' must be backed up before '{sub}'."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
