#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess

SRC = "/home/user/get_restore_chain.c"
EXE = "/home/user/get_restore_chain"
DB = "/home/user/backup_metadata.db"
CSV = "/home/user/restore_plan.csv"


def test_c_source_code_exists():
    """Verify that the C source code file exists."""
    assert os.path.exists(SRC), f"C source file {SRC} does not exist."
    assert os.path.isfile(SRC), f"Path {SRC} is not a file."


def test_executable_exists():
    """Verify that the compiled executable exists and is executable."""
    assert os.path.exists(EXE), f"Compiled executable {EXE} does not exist."
    assert os.path.isfile(EXE), f"Path {EXE} is not a file."
    st = os.stat(EXE)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), \
        f"File {EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXE} is not a compiled ELF executable."


def test_restore_plan_csv_content():
    """Verify the requested initial execution produced the correct shortest path."""
    csv_path = CSV
    assert os.path.exists(csv_path), f"Output file {csv_path} does not exist."
    assert os.path.isfile(csv_path), f"Path {csv_path} is not a file."
    with open(csv_path, "r") as f:
        content = f.read().strip()
    expected_content = "full_base_001,shortcut_diff,incr_log_999"
    assert content == expected_content, (
        f"Incorrect path found in {csv_path}.\n"
        f"Expected: '{expected_content}'\n"
        f"Actual:   '{content}'"
    )


def shortest_path(names, edges, target):
    children = collections.defaultdict(list)
    for parent, child in edges:
        children[parent].append(child)
    queue = collections.deque([("full_base_001", ["full_base_001"])])
    seen = {"full_base_001"}
    while queue:
        node, path = queue.popleft()
        if node == target:
            return path
        for child in children[node]:
            if child not in seen:
                seen.add(child)
                queue.append((child, path + [child]))
    return None


def run_and_check(executable, target, expected):
    if os.path.exists(CSV):
        os.unlink(CSV)
    result = subprocess.run(
        [executable, target], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{executable} failed for target {target!r}: {result.stderr}"
    )
    assert os.path.isfile(CSV), f"{executable} did not create {CSV}."
    with open(CSV, "r") as f:
        raw = f.read()
    expected_line = ",".join(expected)
    assert raw.splitlines() == [expected_line], (
        f"Wrong path for {target!r}: expected {expected_line!r}, got {raw!r}"
    )


def test_compiled_program_traverses_database_and_handles_arguments():
    source = open(SRC, "r").read()
    assert re.search(r"\bsqlite3_prepare(?:_v2|_v3)?\s*\(", source), \
        "Source does not use a prepared SQLite statement."
    assert re.search(r"\bsqlite3_bind_text\s*\(", source), \
        "Source does not bind the target backup as text."

    rebuilt = "/tmp/get_restore_chain_rebuilt"
    build = subprocess.run(
        ["gcc", "-Wall", "-Wextra", SRC, "-o", rebuilt, "-lsqlite3"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert build.returncode == 0, f"Source failed to compile: {build.stderr}"

    token = secrets.token_hex(8)
    long_a = f"long_a_{token}"
    long_b = f"long_b_{token}"
    shortcut = f"shortcut_{token}"
    target = f"target_{token}"
    quoted_target = f"quoted_'_target_{token}"
    noise = f"noise_{token}"
    names = [
        "full_base_001", long_a, long_b, shortcut, target,
        quoted_target, noise
    ]
    edges = [
        ("full_base_001", long_a),
        (long_a, long_b),
        (long_b, target),
        ("full_base_001", shortcut),
        (shortcut, target),
        ("full_base_001", quoted_target),
        (noise, long_b),
    ]

    backup = "/tmp/backup_metadata_original.db"
    shutil.copy2(DB, backup)
    try:
        os.unlink(DB)
        con = sqlite3.connect(DB)
        con.executescript("""
            CREATE TABLE backups (
                id INTEGER PRIMARY KEY,
                backup_name TEXT UNIQUE NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE restore_links (
                parent_id INTEGER,
                child_id INTEGER,
                FOREIGN KEY(parent_id) REFERENCES backups(id),
                FOREIGN KEY(child_id) REFERENCES backups(id)
            );
        """)
        ids = {}
        for i, name in enumerate(names, 1):
            con.execute("INSERT INTO backups(id, backup_name) VALUES (?, ?)", (i, name))
            ids[name] = i
        for parent, child in edges:
            con.execute(
                "INSERT INTO restore_links(parent_id, child_id) VALUES (?, ?)",
                (ids[parent], ids[child])
            )
        con.commit()
        con.close()

        cases = [target, quoted_target, "full_base_001"]
        for executable in (EXE, rebuilt):
            for case in cases:
                expected = shortest_path(names, edges, case)
                assert expected is not None
                run_and_check(executable, case, expected)

            no_arg = subprocess.run(
                [executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=10
            )
            assert no_arg.returncode != 0, \
                f"{executable} accepted zero command-line arguments."
            two_args = subprocess.run(
                [executable, target, noise], stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, timeout=10
            )
            assert two_args.returncode != 0, \
                f"{executable} accepted more than one command-line argument."
    finally:
        if os.path.exists(DB):
            os.unlink(DB)
        shutil.copy2(backup, DB)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
