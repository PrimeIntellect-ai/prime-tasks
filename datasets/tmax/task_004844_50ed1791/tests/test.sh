#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import uuid

ANALYZER = "/home/user/analyze.go"
DATABASE = "/home/user/backups.db"
OUTPUT = "/home/user/compromised_backups.txt"


def run_analyzer():
    if os.path.lexists(OUTPUT):
        os.unlink(OUTPUT)

    result = subprocess.run(
        ["go", "run", ANALYZER],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"analyze.go failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"File {OUTPUT} does not exist."


def derive_expected(db_path):
    connection = sqlite3.connect(db_path)
    try:
        assets = {
            row[0]: (row[1], row[2], row[3])
            for row in connection.execute(
                "SELECT id, name, type, is_corrupted FROM assets"
            )
        }
        adjacency = {}
        for src, dst in connection.execute(
            "SELECT src, dst FROM links WHERE status = 'active'"
        ):
            adjacency.setdefault(src, []).append(dst)
    finally:
        connection.close()

    pending = [asset_id for asset_id, value in assets.items() if value[2] == 1]
    visited = set(pending)
    while pending:
        current = pending.pop()
        for destination in adjacency.get(current, []):
            if destination not in visited:
                visited.add(destination)
                pending.append(destination)

    return sorted(
        assets[asset_id][0]
        for asset_id in visited
        if asset_id in assets and assets[asset_id][1] == "storage"
    )


def test_analyzer_and_compromised_backups_file():
    assert os.path.exists(ANALYZER), f"File {ANALYZER} does not exist."
    assert not os.path.islink(ANALYZER), f"File {ANALYZER} must not be a symbolic link."
    mode = os.stat(ANALYZER).st_mode
    assert stat.S_ISREG(mode), f"File {ANALYZER} is not a regular Go source file."
    assert os.path.getsize(ANALYZER) > 0, f"File {ANALYZER} is empty."

    # Execute the submitted Go program against the supplied database and retain
    # the original verifier's exact output assertion.
    run_analyzer()
    expected_content = "s3-archive\ns3-metrics\nsan-primary\ntape-vault"
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content == expected_content, (
        f"Content of {OUTPUT} is incorrect.\n"
        f"Expected:\n{expected_content}\nGot:\n{content}"
    )

    original_output = open(OUTPUT, "rb").read()
    backup_fd, backup_path = tempfile.mkstemp(prefix="backups-", suffix=".db")
    os.close(backup_fd)
    shutil.copy2(DATABASE, backup_path)

    try:
        # Replace the original corruption roots and add a randomized graph with
        # an active multi-hop path, a cycle, and a stale edge.
        connection = sqlite3.connect(DATABASE)
        try:
            connection.execute("UPDATE assets SET is_corrupted = 0")
            base = connection.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM assets").fetchone()[0]
            token = uuid.uuid4().hex
            rows = [
                (base, f"dynamic-db-{token}", "database", 1),
                (base + 1, f"dynamic-job-{token}", "job", 0),
                (base + 2, f"dynamic-storage-a-{token}", "storage", 0),
                (base + 3, f"dynamic-storage-b-{token}", "storage", 0),
                (base + 4, f"stale-storage-{token}", "storage", 0),
                (base + 5, f"isolated-storage-{token}", "storage", 0),
            ]
            connection.executemany("INSERT INTO assets VALUES (?, ?, ?, ?)", rows)
            connection.executemany(
                "INSERT INTO links VALUES (?, ?, ?)",
                [
                    (base, base + 1, "active"),
                    (base + 1, base + 2, "active"),
                    (base + 2, base + 3, "active"),
                    (base + 3, base + 1, "active"),
                    (base, base + 4, "stale"),
                ],
            )
            connection.commit()
        finally:
            connection.close()

        expected_names = derive_expected(DATABASE)
        run_analyzer()
        with open(OUTPUT, "r") as f:
            actual_content = f.read().strip()
        expected_dynamic_content = "\n".join(expected_names)
        assert actual_content == expected_dynamic_content, (
            "analyze.go did not derive the sorted reachable storage assets from "
            "the modified SQLite graph using only active links.\n"
            f"Expected:\n{expected_dynamic_content}\nGot:\n{actual_content}"
        )
    finally:
        for suffix in ("-wal", "-shm"):
            try:
                os.unlink(DATABASE + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(backup_path, DATABASE)
        os.unlink(backup_path)
        with open(OUTPUT, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
