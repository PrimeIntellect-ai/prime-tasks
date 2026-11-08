#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import random
import string
import stat
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/query_oracle"
AGENT_PATH = "/home/user/solution"
SOURCE_PATH = "/home/user/solution.c"
NUM_TESTS = 30


def generate_random_string(rng, length):
    return ''.join(rng.choices(string.ascii_letters + string.digits, k=length))


def create_fuzz_db(db_path, seed):
    rng = random.Random(seed)
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("CREATE TABLE sensors (id INTEGER PRIMARY KEY, name TEXT, category TEXT);")
    cursor.execute("CREATE TABLE events (id INTEGER PRIMARY KEY, sensor_id INTEGER, ts INTEGER, metric REAL);")

    num_sensors = rng.randint(5, 15)
    for i in range(1, num_sensors + 1):
        name = generate_random_string(rng, rng.randint(5, 10))
        category = generate_random_string(rng, rng.randint(3, 8))
        cursor.execute("INSERT INTO sensors (id, name, category) VALUES (?, ?, ?)", (i, name, category))

    num_events = rng.randint(50, 200)
    for i in range(1, num_events + 1):
        sensor_id = rng.randint(1, num_sensors)
        ts = rng.randint(1000, 5000)
        metric = round(rng.uniform(10.0, 100.0), 2)
        cursor.execute("INSERT INTO events (id, sensor_id, ts, metric) VALUES (?, ?, ?, ?)",
                       (i, sensor_id, ts, metric))

    conn.commit()
    conn.close()


def assert_regular_executable(path, label):
    assert os.path.isfile(path), f"{label} not found at {path}"
    assert stat.S_ISREG(os.lstat(path).st_mode), f"{label} must be a regular file, not a symlink"
    assert os.access(path, os.X_OK), f"{label} at {path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{label} is not a compiled ELF binary"


def copy_runtime_dependencies(binary, root):
    result = subprocess.run(["ldd", binary], capture_output=True, text=True, check=False)
    assert result.returncode == 0, f"ldd failed for {binary}: {result.stderr}"
    assert "not found" not in result.stdout, f"Missing runtime dependency for {binary}:\n{result.stdout}"

    paths = set()
    for line in result.stdout.splitlines():
        match = re.search(r"=>\s+(/\S+)", line)
        if match:
            paths.add(match.group(1))
            continue
        match = re.match(r"\s*(/\S+)", line)
        if match:
            paths.add(match.group(1))

    for source in paths:
        destination = os.path.join(root, source.lstrip("/"))
        os.makedirs(os.path.dirname(destination), mode=0o755, exist_ok=True)
        shutil.copy2(source, destination, follow_symlinks=True)
        os.chmod(destination, 0o755)


def run_isolated(root, program_name):
    return subprocess.run(
        ["chroot", "--userspec=65534:65534", root, "/" + program_name, "/data/current.db"],
        capture_output=True,
        text=True,
        check=False,
        timeout=15,
    )


def test_fuzz_equivalence():
    # Preserve the original artifact and oracle assertions.
    assert_regular_executable(AGENT_PATH, "Agent solution binary")
    assert_regular_executable(ORACLE_PATH, "Oracle binary")
    assert os.path.isfile(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"
    assert stat.S_ISREG(os.lstat(SOURCE_PATH).st_mode), "solution.c must be a regular file"

    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(AGENT_PATH, "rb") as f:
        assert f.read() != oracle_bytes, "Agent solution must not be a copy of the oracle binary"

    with tempfile.TemporaryDirectory() as tmpdir:
        os.chmod(tmpdir, 0o755)
        cases = []

        # Derive all expected answers from the oracle before running either submitted artifact.
        for i in range(NUM_TESTS):
            db_path = os.path.join(tmpdir, f"fuzz_{i}.db")
            create_fuzz_db(db_path, seed=42 + i)
            oracle_res = subprocess.run(
                [ORACLE_PATH, db_path], capture_output=True, text=True, check=False, timeout=15
            )
            assert oracle_res.returncode == 0, \
                f"Oracle failed on test {i} with error: {oracle_res.stderr}"
            cases.append((db_path, oracle_res.stdout))

        # Independently compile the required C source. This prevents a copied binary,
        # symlink, shell wrapper, or executable that merely calls /app/query_oracle
        # from satisfying the task.
        rebuilt = os.path.join(tmpdir, "rebuilt")
        compile_res = subprocess.run(
            ["gcc", "-O2", SOURCE_PATH, "-lsqlite3", "-o", rebuilt],
            capture_output=True,
            text=True,
            check=False,
            timeout=30,
        )
        assert compile_res.returncode == 0, \
            f"solution.c did not compile successfully:\n{compile_res.stderr}"
        assert_regular_executable(rebuilt, "Verifier-rebuilt solution")
        with open(rebuilt, "rb") as f:
            assert f.read() != oracle_bytes, "Rebuilt solution must not be the oracle binary"

        # Run both the submitted executable and the independently rebuilt executable
        # in a clean chroot containing only their runtime libraries and the test DB.
        # In particular, /app/query_oracle and agent-created helper files are absent.
        root = os.path.join(tmpdir, "root")
        os.makedirs(os.path.join(root, "data"), mode=0o755)
        os.chmod(root, 0o755)

        installed_dst = os.path.join(root, "installed")
        rebuilt_dst = os.path.join(root, "rebuilt")
        shutil.copy2(AGENT_PATH, installed_dst)
        shutil.copy2(rebuilt, rebuilt_dst)
        os.chmod(installed_dst, 0o755)
        os.chmod(rebuilt_dst, 0o755)
        copy_runtime_dependencies(installed_dst, root)
        copy_runtime_dependencies(rebuilt_dst, root)

        for i, (db_path, expected) in enumerate(cases):
            isolated_db = os.path.join(root, "data", "current.db")
            shutil.copy2(db_path, isolated_db)
            os.chmod(isolated_db, 0o644)

            for program_name, label in (("installed", "Agent solution"),
                                        ("rebuilt", "Rebuilt solution")):
                result = run_isolated(root, program_name)
                assert result.returncode == 0, \
                    f"{label} failed on test {i} with error: {result.stderr}"
                if result.stdout != expected:
                    pytest.fail(
                        f"Mismatch for {label} on fuzz test {i}!\n"
                        f"Oracle output (first 500 chars):\n{expected[:500]}\n...\n"
                        f"Agent output (first 500 chars):\n{result.stdout[:500]}\n..."
                    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
