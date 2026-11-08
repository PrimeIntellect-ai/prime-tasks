#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import secrets
import subprocess
import tempfile
import time
from pathlib import Path

BINARY = "/home/user/app/deadlock_detector/target/debug/deadlock_detector"
PROJECT = "/home/user/app/deadlock_detector"
COMPOSE = "/home/user/services/docker-compose.yml"


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, **kwargs)


def compose_exec(service, *args):
    return run(["docker-compose", "-f", COMPOSE, "exec", "-T", service, *args])


def wait_for_services():
    deadline = time.time() + 20
    last_error = ""
    while time.time() < deadline:
        pg = compose_exec("postgres_db", "psql", "-U", "admin", "-d", "monitoring", "-At", "-c", "SELECT 1")
        rd = compose_exec("redis_cache", "redis-cli", "PING")
        if pg.returncode == 0 and pg.stdout.strip() == "1" and rd.returncode == 0 and "PONG" in rd.stdout:
            return
        last_error = f"postgres: {pg.stderr or pg.stdout}; redis: {rd.stderr or rd.stdout}"
        time.sleep(1)
    raise AssertionError(f"PostgreSQL and Redis services are not running and ready: {last_error}")


def pg(sql):
    result = compose_exec("postgres_db", "psql", "-U", "admin", "-d", "monitoring", "-At", "-F", "|", "-c", sql)
    assert result.returncode == 0, result.stderr
    return [line for line in result.stdout.splitlines() if line.strip()]


def redis_hset(mapping):
    for key, value in mapping.items():
        result = compose_exec("redis_cache", "redis-cli", "HSET", "queries", key, value)
        assert result.returncode == 0, result.stderr


def write_csv(path, rows):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["tx_id", "waiting_for_tx_id", "query_hash"])
        writer.writerows(rows)


def assert_report_filename(stored, expected):
    assert stored == expected or os.path.basename(stored) == os.path.basename(expected), (
        f"Report filename {stored!r} does not identify {expected!r}"
    )


def test_deadlock_detector_binary_exists():
    """Check that an executable Rust binary project exists and can be built."""
    assert os.path.isfile(BINARY), f"Missing compiled Rust binary at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Binary at {BINARY} is not executable"
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Missing Cargo.toml"
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "Missing Rust src/main.rs"

    # Recreate the submitted executable through Cargo so a stand-alone script cannot pass.
    os.remove(BINARY)
    env = os.environ.copy()
    env["PATH"] = "/root/.cargo/bin:" + env.get("PATH", "")
    env["CARGO_NET_OFFLINE"] = "true"
    built = run(["cargo", "build", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")], env=env, timeout=180)
    assert built.returncode == 0, f"Cargo build failed:\n{built.stdout}\n{built.stderr}"
    assert os.path.isfile(BINARY), f"Cargo did not produce {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Cargo output at {BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Cargo output is not an ELF executable"


def test_services_random_graphs_and_integrations():
    """Exercise derived graphs plus Redis lookup and PostgreSQL report contents."""
    wait_for_services()
    rng = random.Random(secrets.randbits(128))

    with tempfile.TemporaryDirectory(prefix="graph_verifier_") as td:
        metadata = {}

        # Generate fresh DAGs whose names and transaction IDs are not part of the fixed corpus.
        for case in range(6):
            nodes = rng.sample(range(1000, 900000), rng.randint(8, 16))
            rows = []
            for i in range(1, len(nodes)):
                parent = nodes[rng.randrange(i)]
                child = nodes[i]
                h = secrets.token_hex(16)
                metadata[h] = f"SELECT {child}"
                rows.append((child, parent, h))
                if i > 2 and rng.random() < 0.35:
                    other_parent = nodes[rng.randrange(i)]
                    h2 = secrets.token_hex(16)
                    metadata[h2] = f"SELECT {child}"
                    rows.append((child, other_parent, h2))
            rng.shuffle(rows)
            path = os.path.join(td, f"derived_{secrets.token_hex(8)}.csv")
            write_csv(path, rows)
            result = run([BINARY, path], timeout=20)
            assert result.returncode == 0, f"Fresh DAG was rejected: {path}\n{result.stderr}"

        # Generate fresh cycles with arbitrary IDs and shuffled row order.
        for case in range(6):
            nodes = rng.sample(range(1000, 900000), rng.randint(3, 11))
            rows = []
            for i, tx in enumerate(nodes):
                waiter = nodes[i - 1]
                h = secrets.token_hex(16)
                metadata[h] = f"SELECT {tx}"
                rows.append((tx, waiter, h))
            rng.shuffle(rows)
            path = os.path.join(td, f"derived_{secrets.token_hex(8)}.csv")
            write_csv(path, rows)
            redis_hset({row[2]: metadata[row[2]] for row in rows})
            result = run([BINARY, path], timeout=20)
            assert result.returncode == 1, f"Fresh cyclic graph was not detected: {path}\n{result.stderr}"

        # A clean graph must produce a non-deadlocked PostgreSQL report.
        pg("TRUNCATE deadlock_reports")
        clean_path = os.path.join(td, f"report_{secrets.token_hex(8)}.csv")
        clean_rows = [
            (701, 700, secrets.token_hex(16)),
            (702, 701, secrets.token_hex(16)),
            (703, 700, secrets.token_hex(16)),
        ]
        redis_hset({row[2]: f"SELECT {row[0]}" for row in clean_rows})
        write_csv(clean_path, clean_rows)
        result = run([BINARY, clean_path], timeout=20)
        assert result.returncode == 0, result.stderr
        reports = pg("SELECT file_name,is_deadlocked,COALESCE(root_cause_tx::text,''),COALESCE(root_query,'') FROM deadlock_reports")
        assert len(reports) == 1, f"Expected one clean report, got {reports}"
        fields = reports[0].split("|", 3)
        assert_report_filename(fields[0], clean_path)
        assert fields[1] == "f", f"Clean graph was not stored as non-deadlocked: {reports[0]}"

        # In the cycle, tx 811 has the greatest in-degree (three incoming edges).
        # The verifier controls Redis and checks the selected transaction and fetched SQL.
        pg("TRUNCATE deadlock_reports")
        hashes = {tx: secrets.token_hex(16) for tx in (810, 811, 812)}
        root_query = f"SELECT * FROM accounts WHERE id = {secrets.randbelow(1000000)}"
        redis_hset({hashes[810]: "SELECT 'tx810'", hashes[811]: root_query, hashes[812]: "SELECT 'tx812'"})
        root_path = os.path.join(td, f"centrality_{secrets.token_hex(8)}.csv")
        root_rows = [
            (811, 810, hashes[811]),
            (812, 811, hashes[812]),
            (810, 812, hashes[810]),
            (811, 930, hashes[811]),
            (811, 931, hashes[811]),
        ]
        rng.shuffle(root_rows)
        write_csv(root_path, root_rows)
        result = run([BINARY, root_path], timeout=20)
        assert result.returncode == 1, f"Centrality test cycle was not detected: {result.stderr}"
        reports = pg("SELECT file_name,is_deadlocked,COALESCE(root_cause_tx::text,''),COALESCE(root_query,'') FROM deadlock_reports")
        assert len(reports) == 1, f"Expected one deadlock report, got {reports}"
        fields = reports[0].split("|", 3)
        assert_report_filename(fields[0], root_path)
        assert fields[1] == "t", f"Cycle was not stored as deadlocked: {reports[0]}"
        assert fields[2] == "811", f"Wrong root-cause transaction: {reports[0]}"
        assert fields[3] == root_query, f"Root query was not fetched from Redis: {reports[0]}"

        # Equal-centrality cycle: the lowest transaction ID must win the tie.
        pg("TRUNCATE deadlock_reports")
        tie_nodes = rng.sample(range(1000000, 2000000), 3)
        expected = min(tie_nodes)
        tie_hashes = {tx: secrets.token_hex(16) for tx in tie_nodes}
        expected_query = f"SELECT 'tie-{secrets.token_hex(8)}'"
        redis_hset({tie_hashes[tx]: expected_query if tx == expected else f"SELECT {tx}" for tx in tie_nodes})
        tie_rows = [
            (tie_nodes[0], tie_nodes[2], tie_hashes[tie_nodes[0]]),
            (tie_nodes[1], tie_nodes[0], tie_hashes[tie_nodes[1]]),
            (tie_nodes[2], tie_nodes[1], tie_hashes[tie_nodes[2]]),
        ]
        tie_path = os.path.join(td, f"tie_{secrets.token_hex(8)}.csv")
        write_csv(tie_path, tie_rows)
        result = run([BINARY, tie_path], timeout=20)
        assert result.returncode == 1, result.stderr
        reports = pg("SELECT file_name,is_deadlocked,COALESCE(root_cause_tx::text,''),COALESCE(root_query,'') FROM deadlock_reports")
        assert len(reports) == 1, f"Expected one tie report, got {reports}"
        fields = reports[0].split("|", 3)
        assert fields[2] == str(expected), f"Centrality tie was not broken by lowest tx_id: {reports[0]}"
        assert fields[3] == expected_query, f"Wrong Redis query for tie winner: {reports[0]}"


def test_adversarial_corpus():
    """Check if the binary correctly identifies clean and evil corpora."""
    clean_files = sorted(glob.glob("/home/user/corpora/clean/*.csv"))
    evil_files = sorted(glob.glob("/home/user/corpora/evil/*.csv"))

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for f in clean_files:
        result = subprocess.run([BINARY, f], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(f))

    evil_failed = []
    for f in evil_files:
        result = subprocess.run([BINARY, f], capture_output=True)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(f))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean files rejected (expected exit code 0): {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil files bypassed (expected exit code 1): {', '.join(evil_failed)}")
    assert not errors, "\n".join(errors)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
