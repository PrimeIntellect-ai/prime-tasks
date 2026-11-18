#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

DB_PATH = "/home/user/backup_metadata.db"
LOG_PATH = "/home/user/chain_15.log"
RS_PATH_1 = "/home/user/get_chain.rs"
RS_PATH_2 = "/home/user/backup_tool/src/main.rs"


def get_expected_chain(db_path, target_id):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    query = """
    WITH RECURSIVE backup_chain AS (
        SELECT id, parent_id, size_bytes, created_at
        FROM backups
        WHERE id = ?

        UNION ALL

        SELECT b.id, b.parent_id, b.size_bytes, b.created_at
        FROM backups b
        INNER JOIN backup_chain c ON c.parent_id = b.id
    )
    SELECT id, size_bytes FROM backup_chain
    ORDER BY created_at ASC;
    """
    cursor.execute(query, (target_id,))
    results = cursor.fetchall()
    conn.close()
    return [f"{row[0]},{row[1]}" for row in results]


def find_rust_source():
    if os.path.isfile(RS_PATH_1):
        return RS_PATH_1
    if os.path.isfile(RS_PATH_2):
        return RS_PATH_2

    for root, _, files in os.walk("/home/user"):
        for filename in files:
            if filename.endswith(".rs"):
                return os.path.join(root, filename)
    return None


@pytest.fixture(scope="session")
def rust_source():
    source = find_rust_source()
    assert source is not None, (
        "Could not find the Rust source file (e.g., /home/user/get_chain.rs)."
    )
    return source


def compile_source(source):
    work = tempfile.mkdtemp(prefix="verify_backup_tool_")
    copied_manifest = os.path.join(work, "backup_tool", "Cargo.toml")
    original_project = "/home/user/backup_tool"

    package_name = None
    bin_name = None
    manifest = None

    if os.path.isfile(os.path.join(original_project, "Cargo.toml")):
        shutil.copytree(original_project, os.path.join(work, "backup_tool"))
        manifest = copied_manifest
        metadata_proc = subprocess.run(
            ["cargo", "metadata", "--format-version", "1", "--no-deps", "--manifest-path", manifest],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        if metadata_proc.returncode == 0:
            metadata = json.loads(metadata_proc.stdout)
            candidates = []
            for package in metadata.get("packages", []):
                for target in package.get("targets", []):
                    if "bin" in target.get("kind", []):
                        candidates.append((package, target))
            if candidates:
                package, target = candidates[0]
                package_name = package["name"]
                bin_name = target["name"]
                target_source = target["src_path"]
                if os.path.realpath(source) != os.path.realpath(RS_PATH_2):
                    os.makedirs(os.path.dirname(target_source), exist_ok=True)
                    shutil.copyfile(source, target_source)

    if package_name is None:
        project = os.path.join(work, "standalone")
        os.makedirs(os.path.join(project, "src"), exist_ok=True)
        shutil.copyfile(source, os.path.join(project, "src", "main.rs"))
        manifest = os.path.join(project, "Cargo.toml")
        with open(manifest, "w") as f:
            f.write(
                "[package]\n"
                "name = \"get_chain_verification\"\n"
                "version = \"0.1.0\"\n"
                "edition = \"2021\"\n\n"
                "[dependencies]\n"
                "rusqlite = \"0.29.0\"\n"
            )
        package_name = "get_chain_verification"
        bin_name = "get_chain_verification"

    command = [
        "cargo", "build", "--manifest-path", manifest,
        "--package", package_name, "--bin", bin_name,
        "--message-format=json",
    ]
    proc = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=240,
    )
    assert proc.returncode == 0, (
        "The submitted Rust program did not compile successfully.\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )

    executable = None
    for line in proc.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get("reason") == "compiler-artifact":
            target = message.get("target", {})
            if target.get("name") == bin_name and "bin" in target.get("kind", []):
                if message.get("executable"):
                    executable = message["executable"]

    assert executable and os.path.isfile(executable), (
        "Cargo succeeded but no compiled program executable was produced."
    )
    return executable


@pytest.fixture(scope="session")
def executable(rust_source):
    return compile_source(rust_source)


def run_program(executable, target_id):
    proc = subprocess.run(
        [executable, str(target_id)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, (
        f"Program failed for backup ID {target_id}.\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    return proc.stdout.splitlines()


def test_log_output_correct():
    assert os.path.isfile(LOG_PATH), f"Output log {LOG_PATH} does not exist."

    expected_lines = get_expected_chain(DB_PATH, 15)
    with open(LOG_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {LOG_PATH} do not match the expected backup chain.\n"
        f"Expected: {expected_lines}\nActual: {actual_lines}"
    )


def test_rust_code_parameterized(rust_source):
    with open(rust_source, "r") as f:
        content = f.read()

    # Preserve the original parameter-marker assertion.
    has_params = "?" in content or "$1" in content or ":1" in content or "?1" in content
    assert has_params, (
        f"The Rust source code in {rust_source} does not appear to use a "
        "parameterized query (missing '?', '$1', etc.)."
    )

    assert re.search(r"\brusqlite\b", content), "The program must use the rusqlite crate."
    assert re.search(r"WITH\s+RECURSIVE", content, re.IGNORECASE), (
        "The SQL executed by the program must contain a recursive CTE."
    )
    assert re.search(r"WHERE\s+(?:\w+\.)?id\s*=\s*(?:\?|\?1|\$1|:1)", content, re.IGNORECASE), (
        "The target backup lookup in the recursive query must use a parameter placeholder."
    )
    assert re.search(r"JOIN\s+backup_chain|JOIN\s+\w+\s+ON\s+\w+\.parent_id", content, re.IGNORECASE), (
        "The recursive CTE must traverse the parent_id chain."
    )
    assert "/home/user/backup_metadata.db" in content, (
        "The program must connect to /home/user/backup_metadata.db."
    )


def test_compiled_program_on_existing_chains(executable):
    for target_id in (1, 5, 6, 15):
        expected = get_expected_chain(DB_PATH, target_id)
        actual = run_program(executable, target_id)
        assert actual == expected, (
            f"Incorrect output for backup ID {target_id}.\n"
            f"Expected: {expected}\nActual: {actual}"
        )


def test_compiled_program_on_unseen_chain(executable):
    backup_copy = tempfile.mktemp(prefix="backup_metadata_", suffix=".db")
    shutil.copy2(DB_PATH, backup_copy)

    try:
        conn = sqlite3.connect(DB_PATH)
        current_max = conn.execute("SELECT COALESCE(MAX(id), 0) FROM backups").fetchone()[0]
        base = current_max + random.SystemRandom().randint(1000, 100000)
        ids = [base, base + 1, base + 2, base + 3]
        sizes = [random.SystemRandom().randint(100000, 9000000000) for _ in ids]
        rows = [
            (ids[0], "verification-random", "FULL", None, sizes[0], "2041-01-01 00:00:00"),
            (ids[1], "verification-random", "INC", ids[0], sizes[1], "2041-01-02 00:00:00"),
            (ids[2], "verification-random", "INC", ids[1], sizes[2], "2041-01-03 00:00:00"),
            (ids[3], "verification-random", "INC", ids[2], sizes[3], "2041-01-04 00:00:00"),
        ]
        conn.executemany("INSERT INTO backups VALUES (?, ?, ?, ?, ?, ?)", rows)
        conn.commit()
        conn.close()

        expected = get_expected_chain(DB_PATH, ids[-1])
        actual = run_program(executable, ids[-1])
        assert actual == expected, (
            "The compiled program did not resolve a newly created, previously unseen chain.\n"
            f"Expected: {expected}\nActual: {actual}"
        )
    finally:
        os.replace(backup_copy, DB_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
