#!/bin/bash
set -e
mkdir -p /logs/verifier

SCRIPT=/home/user/plan_backups.sh
if [ ! -f "$SCRIPT" ] || [ ! -x "$SCRIPT" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

# Require the submitted script itself to generate the outputs for the supplied data.
rm -f /home/user/backup_set.txt /home/user/core_table.txt
if ! (cd /home/user && timeout 15 "$SCRIPT"); then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import string
import subprocess
from collections import Counter, defaultdict
from pathlib import Path


def test_plan_backups_script_exists_and_executable():
    script_path = "/home/user/plan_backups.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_backup_set_correct():
    output_path = "/home/user/backup_set.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    expected_set = [
        "categories",
        "inventory",
        "orders",
        "permissions",
        "products",
        "roles",
        "users",
        "warehouses"
    ]

    with open(output_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_set, (
        f"Contents of {output_path} are incorrect.\n"
        f"Expected: {expected_set}\n"
        f"Got: {actual_lines}"
    )


def test_core_table_correct():
    output_path = "/home/user/core_table.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    with open(output_path, "r") as f:
        actual = f.read().strip()

    expected = "users"
    assert actual == expected, (
        f"Contents of {output_path} are incorrect. "
        f"Expected '{expected}', got '{actual}'."
    )


def _expected_backup(edges, critical):
    dependencies = defaultdict(set)
    for table, dependency in edges:
        dependencies[table].add(dependency)

    seen = set(critical)
    pending = list(critical)
    while pending:
        table = pending.pop()
        for dependency in dependencies[table]:
            if dependency not in seen:
                seen.add(dependency)
                pending.append(dependency)
    return sorted(seen)


def _expected_core(edges):
    indegree = Counter()
    for table, dependency in edges:
        if table != dependency:
            indegree[dependency] += 1
    maximum = max(indegree.values())
    winners = [table for table, count in indegree.items() if count == maximum]
    assert len(winners) == 1
    return winners[0]


def _random_names():
    prefix = "".join(secrets.choice(string.ascii_lowercase) for _ in range(12))
    labels = ["start", "alpha", "beta", "gamma", "delta", "hub", "branch",
              "leaf", "other", "tail", "critical"]
    return {label: prefix + label for label in labels}


def test_script_computes_results_from_changed_inputs():
    home = Path("/home/user")
    schema_path = home / "schema_fks.txt"
    critical_path = home / "critical_tables.txt"
    backup_path = home / "backup_set.txt"
    core_path = home / "core_table.txt"
    paths = [schema_path, critical_path, backup_path, core_path]
    originals = {path: path.read_bytes() if path.exists() else None for path in paths}

    try:
        for _ in range(2):
            n = _random_names()
            edges = [
                (n["start"], n["alpha"]),
                (n["start"], n["branch"]),
                (n["alpha"], n["hub"]),
                (n["beta"], n["hub"]),
                (n["gamma"], n["hub"]),
                (n["delta"], n["hub"]),
                (n["alpha"], n["leaf"]),
                (n["branch"], n["leaf"]),
                (n["other"], n["branch"]),
                (n["tail"], n["other"]),
            ]
            # Vary input order so correctness cannot depend on the fixture ordering.
            secrets.SystemRandom().shuffle(edges)
            critical = [n["start"], n["delta"], n["critical"]]
            secrets.SystemRandom().shuffle(critical)

            expected_backup = _expected_backup(edges, critical)
            expected_core = _expected_core(edges)

            schema_path.write_text("".join(f"{a} {b}\n" for a, b in edges))
            critical_path.write_text("".join(f"{table}\n" for table in critical))
            backup_path.unlink(missing_ok=True)
            core_path.unlink(missing_ok=True)

            subprocess.run(
                [str(home / "plan_backups.sh")],
                cwd=str(home),
                check=True,
                timeout=15,
            )

            assert backup_path.is_file(), "Script did not create backup_set.txt"
            assert core_path.is_file(), "Script did not create core_table.txt"

            actual_backup = backup_path.read_text().splitlines()
            actual_core_lines = core_path.read_text().splitlines()
            assert actual_backup == expected_backup, (
                f"Changed-input backup set is incorrect. Expected {expected_backup}, "
                f"got {actual_backup}"
            )
            assert actual_core_lines == [expected_core], (
                f"Changed-input core table is incorrect. Expected {expected_core}, "
                f"got {actual_core_lines}"
            )
    finally:
        for path, content in originals.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
