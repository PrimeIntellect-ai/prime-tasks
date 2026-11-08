#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import shutil
import sqlite3
import secrets
import subprocess
import pandas as pd
import pytest

SOURCE = "/home/user/fast_graph.c"
BINARY = "/home/user/fast_graph"
VERIFIER_BINARY = "/tmp/verifier_fast_graph"
DB = "/home/user/taxonomy.db"
RESULTS = "/home/user/results.csv"
LEGACY = "/app/legacy_calc"


def run_cmd(cmd):
    start = time.time()
    subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return time.time() - start


def compile_source():
    proc = subprocess.run(
        ["gcc", "-O3", "-o", VERIFIER_BINARY, SOURCE, "-lsqlite3"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert proc.returncode == 0, f"fast_graph.c did not compile successfully:\n{proc.stderr}"
    assert os.path.isfile(VERIFIER_BINARY) and os.access(VERIFIER_BINARY, os.X_OK)


def read_csv(path):
    assert os.path.isfile(path), f"Expected output file {path} was not created."
    try:
        df = pd.read_csv(path, header=None)
    except pd.errors.EmptyDataError:
        pytest.fail(f"Output file {path} is empty.")
    assert df.shape[1] == 4, "Output must contain exactly four CSV columns."
    return df.sort_values([0, 3, 1]).reset_index(drop=True)


def create_random_taxonomy(path, n, group_count):
    rng = secrets.SystemRandom()
    nonce = secrets.token_hex(5)
    groups = [f"Audit_{nonce}_{i}" for i in range(group_count)]

    while True:
        node_groups = [groups[i % group_count] for i in range(n)]
        rng.shuffle(node_groups)
        edges = []
        children = [[] for _ in range(n + 1)]
        for child in range(2, n + 1):
            parent = rng.randrange(1, child)
            cents = rng.randrange(10, 1001)
            edges.append((parent, child, cents / 100.0))
            children[parent].append((child, cents))

        totals = [0] * (n + 1)
        for node in range(n, 0, -1):
            totals[node] = sum(cents + totals[child] for child, cents in children[node])

        # Avoid depending on the legacy qsort's unspecified ordering for ties.
        valid = True
        for group in groups:
            vals = sorted(
                (totals[i] for i in range(1, n + 1) if node_groups[i - 1] == group),
                reverse=True,
            )
            if len(vals) < 3 or len(set(vals[:3])) != 3 or (len(vals) > 3 and vals[2] == vals[3]):
                valid = False
                break
        if valid:
            break

    for suffix in ("", "-wal", "-shm", "-journal"):
        try:
            os.remove(path + suffix)
        except FileNotFoundError:
            pass

    conn = sqlite3.connect(path)
    conn.execute("CREATE TABLE nodes(id INTEGER PRIMARY KEY, category_group TEXT)")
    conn.execute("CREATE TABLE edges(parent_id INTEGER, child_id INTEGER, weight REAL)")
    conn.executemany(
        "INSERT INTO nodes VALUES (?, ?)",
        [(i, node_groups[i - 1]) for i in range(1, n + 1)],
    )
    conn.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)
    conn.commit()
    conn.close()

    expected = []
    for group in sorted(groups):
        ranked = sorted(
            ((i, totals[i]) for i in range(1, n + 1) if node_groups[i - 1] == group),
            key=lambda item: item[1],
            reverse=True,
        )[:3]
        for rank, (node_id, cents) in enumerate(ranked, 1):
            expected.append([group, node_id, cents / 100.0, rank])
    return pd.DataFrame(expected).sort_values([0, 3, 1]).reset_index(drop=True)


def run_and_check(binary, expected):
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    proc = subprocess.run(
        [binary], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20
    )
    assert proc.returncode == 0, f"{binary} exited with status {proc.returncode}."
    actual = read_csv(RESULTS)
    try:
        pd.testing.assert_frame_equal(
            expected,
            actual,
            check_dtype=False,
            check_exact=False,
            rtol=1e-4,
        )
    except AssertionError as e:
        pytest.fail(f"{binary} produced incorrect results for a fresh taxonomy database:\n{e}")


def test_source_exists_and_compiles():
    assert os.path.isfile(SOURCE), f"C source {SOURCE} not found."
    assert os.path.getsize(SOURCE) > 0, f"C source {SOURCE} is empty."
    compile_source()


def test_fast_graph_exists_and_executable():
    binary_path = BINARY
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} not found. Did you compile your C program?"
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast_graph must be a compiled executable."
    with open(binary_path, "rb") as submitted, open(LEGACY, "rb") as legacy:
        assert submitted.read() != legacy.read(), "fast_graph must not be a byte-identical copy of legacy_calc."


def test_speedup_and_correctness():
    legacy_output = "/home/user/legacy_output.csv"
    agent_output = RESULTS

    if os.path.exists(legacy_output):
        os.remove(legacy_output)
    if os.path.exists(agent_output):
        os.remove(agent_output)

    time_legacy = run_cmd(f"/app/legacy_calc > {legacy_output}")
    assert os.path.isfile(legacy_output), "Legacy output was not created."

    time_agent = run_cmd(BINARY)
    time_agent = max(time_agent, 1e-6)

    assert os.path.isfile(agent_output), f"Agent output {agent_output} was not created."

    try:
        df_legacy = pd.read_csv(legacy_output, header=None)
    except pd.errors.EmptyDataError:
        pytest.fail("Legacy output is empty.")

    try:
        df_agent = pd.read_csv(agent_output, header=None)
    except pd.errors.EmptyDataError:
        pytest.fail("Agent output is empty.")

    df_legacy_sorted = df_legacy.sort_values([0, 3, 1]).reset_index(drop=True)
    df_agent_sorted = df_agent.sort_values([0, 3, 1]).reset_index(drop=True)

    try:
        pd.testing.assert_frame_equal(
            df_legacy_sorted,
            df_agent_sorted,
            check_dtype=False,
            check_exact=False,
            rtol=1e-4,
        )
    except AssertionError as e:
        pytest.fail(f"Agent output does not match legacy output exactly:\n{e}")

    speedup = time_legacy / time_agent
    assert speedup >= 25.0, f"Speedup too low: {speedup:.2f}x (Legacy: {time_legacy:.4f}s, Agent: {time_agent:.4f}s). Target is >= 25.0x."


def test_fresh_random_taxonomies():
    compile_source()
    backup = "/tmp/original_taxonomy.db"
    if os.path.exists(backup):
        os.remove(backup)
    src = sqlite3.connect(DB)
    dst = sqlite3.connect(backup)
    src.backup(dst)
    dst.close()
    src.close()

    try:
        for n, groups in ((731, 7), (1103, 9)):
            expected = create_random_taxonomy(DB, n, groups)
            # Test both the required submitted executable and a fresh build of the
            # submitted C source, so cached output and unrelated source cannot pass.
            run_and_check(BINARY, expected)
            run_and_check(VERIFIER_BINARY, expected)
    finally:
        for suffix in ("", "-wal", "-shm", "-journal"):
            try:
                os.remove(DB + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(backup, DB)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
