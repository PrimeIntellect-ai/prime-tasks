#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH=/usr/local/cargo/bin:$PATH

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import random
import re
import shutil
import sqlite3
import stat
import subprocess
import tempfile


def test_restore_plan_correct():
    target_file = "/home/user/restore_plan.txt"

    assert os.path.exists(target_file), f"The file {target_file} does not exist."
    assert os.path.isfile(target_file), f"{target_file} is not a file."

    with open(target_file, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_content = "Total Time: 35 mins\nPath: DB_MAIN_FULL -> INC_1 -> INC_3 -> RESTORE_COMPLETE"

    # Normalize line endings and whitespace for robustness
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = expected_content.splitlines()

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in output, found {len(actual_lines)}."

    assert actual_lines[0] == expected_lines[0], f"First line mismatch. Expected '{expected_lines[0]}', got '{actual_lines[0]}'."
    assert actual_lines[1] == expected_lines[1], f"Second line mismatch. Expected '{expected_lines[1]}', got '{actual_lines[1]}'."


def expected_from_sources(db_path, status_path):
    with open(status_path, "r", encoding="utf-8") as f:
        documents = json.load(f)
    valid = {item["id"] for item in documents if item.get("state") == "valid"}

    graph = {}
    with sqlite3.connect(db_path) as connection:
        rows = connection.execute(
            "SELECT src, dst, time_mins FROM recovery_edges"
        ).fetchall()
    for src, dst, weight in rows:
        if src in valid and dst in valid:
            graph.setdefault(src, []).append((dst, int(weight)))

    start = "DB_MAIN_FULL"
    goal = "RESTORE_COMPLETE"
    queue = [(0, start, [start])]
    best = {start: 0}
    while queue:
        total, node, path = heapq.heappop(queue)
        if total != best.get(node):
            continue
        if node == goal:
            return total, path
        for nxt, weight in graph.get(node, []):
            candidate = total + weight
            if candidate < best.get(nxt, float("inf")):
                best[nxt] = candidate
                heapq.heappush(queue, (candidate, nxt, path + [nxt]))
    raise AssertionError("Verifier fixture unexpectedly has no restoration path")


def write_database(path, edges):
    if os.path.exists(path):
        os.remove(path)
    with sqlite3.connect(path) as connection:
        connection.execute(
            "CREATE TABLE recovery_edges (src TEXT, dst TEXT, time_mins INTEGER)"
        )
        connection.executemany(
            "INSERT INTO recovery_edges (src, dst, time_mins) VALUES (?, ?, ?)",
            edges,
        )
        connection.commit()


def run_and_check(project, db_path, status_path, plan_path):
    if os.path.lexists(plan_path):
        os.remove(plan_path)

    try:
        result = subprocess.run(
            ["/usr/local/cargo/bin/cargo", "run", "--quiet", "--manifest-path", os.path.join(project, "Cargo.toml")],
            cwd=project,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
            env={**os.environ, "PATH": "/usr/local/cargo/bin:" + os.environ.get("PATH", "")},
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError("The Rust program did not finish within 180 seconds") from exc

    assert result.returncode == 0, (
        "cargo run failed.\nstdout:\n"
        + result.stdout
        + "\nstderr:\n"
        + result.stderr
    )
    assert os.path.isfile(plan_path), "The executed Rust program did not create restore_plan.txt"

    expected_time, expected_path = expected_from_sources(db_path, status_path)
    with open(plan_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]
    expected_lines = [
        f"Total Time: {expected_time} mins",
        "Path: " + " -> ".join(expected_path),
    ]
    assert lines == expected_lines, f"Expected {expected_lines!r}, got {lines!r}"


def test_rust_project_reads_and_routes_dynamic_sources():
    project = "/home/user/backup_router"
    manifest = os.path.join(project, "Cargo.toml")
    main_rs = os.path.join(project, "src", "main.rs")
    db_path = "/home/user/backups.db"
    status_path = "/home/user/node_status.json"
    plan_path = "/home/user/restore_plan.txt"

    assert os.path.isdir(project), f"Cargo project directory {project} does not exist"
    assert os.path.isfile(manifest), "backup_router/Cargo.toml does not exist"
    assert stat.S_ISREG(os.stat(manifest, follow_symlinks=False).st_mode), "Cargo.toml must be a regular file"
    assert os.path.isfile(main_rs), "backup_router/src/main.rs does not exist"
    assert stat.S_ISREG(os.stat(main_rs, follow_symlinks=False).st_mode), "src/main.rs must be a regular Rust source file"

    with open(manifest, "r", encoding="utf-8") as f:
        manifest_text = f.read()
    assert re.search(r'(?m)^\s*name\s*=\s*["\']backup_router["\']\s*$', manifest_text), (
        "Cargo package must be named backup_router"
    )
    with open(main_rs, "r", encoding="utf-8") as f:
        assert f.read().strip(), "src/main.rs is empty"

    backup_dir = tempfile.mkdtemp(prefix="backup-router-verifier-")
    originals = {}
    try:
        for path in (db_path, status_path, plan_path):
            saved = os.path.join(backup_dir, os.path.basename(path))
            shutil.copy2(path, saved)
            originals[path] = saved

        nonce = os.urandom(8).hex().upper()
        route_a = "VERIFIER_A_" + nonce
        route_b = "VERIFIER_B_" + nonce
        ghost = "VERIFIER_GHOST_" + nonce
        rng = random.SystemRandom()
        a1, a2 = rng.randint(11, 35), rng.randint(11, 35)
        b1, b2 = rng.randint(41, 65), rng.randint(41, 65)
        edges = [
            ("DB_MAIN_FULL", route_a, a1),
            (route_a, "RESTORE_COMPLETE", a2),
            ("DB_MAIN_FULL", route_b, b1),
            (route_b, "RESTORE_COMPLETE", b2),
            ("DB_MAIN_FULL", ghost, 1),
            (ghost, "RESTORE_COMPLETE", 1),
            ("DB_MAIN_FULL", "RESTORE_COMPLETE", 250),
        ]
        write_database(db_path, edges)

        first_status = [
            {"id": "DB_MAIN_FULL", "state": "valid"},
            {"id": route_a, "state": "valid"},
            {"id": route_b, "state": "corrupted"},
            {"id": "RESTORE_COMPLETE", "state": "valid"},
        ]
        with open(status_path, "w", encoding="utf-8") as f:
            json.dump(first_status, f)
        run_and_check(project, db_path, status_path, plan_path)

        second_status = [
            {"id": "DB_MAIN_FULL", "state": "valid"},
            {"id": route_a, "state": "corrupted"},
            {"id": route_b, "state": "valid"},
            {"id": ghost, "state": "corrupted"},
            {"id": "RESTORE_COMPLETE", "state": "valid"},
        ]
        with open(status_path, "w", encoding="utf-8") as f:
            json.dump(second_status, f)
        run_and_check(project, db_path, status_path, plan_path)
    finally:
        for path, saved in originals.items():
            shutil.copy2(saved, path)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
