#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess
import uuid
from pathlib import Path

import pytest

BASE = Path("/home/user/capacity_planner")
DATA = BASE / "data"
PREDICTOR = BASE / "predictor"


def run_ok(command, *, cwd=None, timeout=120):
    result = subprocess.run(
        command,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command {command!r} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_init_env_exists_and_executable():
    """Test that init_env.sh exists, is executable, successful, and idempotent."""
    script_path = Path("/home/user/init_env.sh")
    assert script_path.is_file(), f"Missing setup script at {script_path}"
    assert os.access(script_path, os.X_OK), f"Setup script at {script_path} is not executable"

    result = subprocess.run([str(script_path)], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"{script_path} failed with exit code {result.returncode}. Stderr: {result.stderr}"
    )

    assert DATA.is_dir(), "/home/user/capacity_planner/data directory was not created"
    cargo_toml = PREDICTOR / "Cargo.toml"
    main_rs = PREDICTOR / "src/main.rs"
    assert cargo_toml.is_file(), "Cargo project was not initialized at /home/user/capacity_planner/predictor"
    assert main_rs.is_file(), "Cargo binary project is missing src/main.rs"

    cargo_before = cargo_toml.read_bytes()
    main_before = main_rs.read_bytes()
    run_ok([str(script_path)])
    assert cargo_toml.read_bytes() == cargo_before, "init_env.sh overwrote Cargo.toml on a repeated run"
    assert main_rs.read_bytes() == main_before, "init_env.sh overwrote src/main.rs on a repeated run"


def test_scripts_and_predictor_work_on_derived_inputs():
    fetch = BASE / "fetch.exp"
    cleaner = BASE / "clean.sh"
    main_rs = PREDICTOR / "src/main.rs"
    manifest = PREDICTOR / "Cargo.toml"
    monitor = Path("/home/user/legacy_monitor.py")

    assert fetch.is_file(), f"Missing Expect script at {fetch}"
    assert cleaner.is_file(), f"Missing cleaning script at {cleaner}"
    assert main_rs.is_file(), f"Missing Rust source at {main_rs}"
    assert manifest.is_file(), f"Missing Cargo manifest at {manifest}"
    assert monitor.is_file(), f"Missing legacy monitor at {monitor}"

    DATA.mkdir(parents=True, exist_ok=True)
    original_monitor = monitor.read_bytes()
    original_mode = monitor.stat().st_mode

    token = uuid.uuid4().hex
    fetch_node = "fetch-" + uuid.uuid4().hex[:10]
    fetch_cpu = random.SystemRandom().randint(11, 89)
    fetch_mem = random.SystemRandom().randint(501, 9501)
    challenge_monitor = f'''import sys
sys.stdout.write("Enter cluster name: ")
sys.stdout.flush()
cluster = sys.stdin.readline().strip()
sys.stdout.write("Enter days of history: ")
sys.stdout.flush()
days = sys.stdin.readline().strip()
if cluster != "ALPHA_CLUSTER" or days != "7":
    print("BAD INPUT")
    raise SystemExit(9)
print("TOKEN:{token}")
print("[INFO] | {fetch_node} | CPU: {fetch_cpu}.5 | MEM: {fetch_mem}.0")
'''

    try:
        monitor.write_text(challenge_monitor)
        os.chmod(monitor, 0o755)
        raw = DATA / "raw.txt"
        if raw.exists():
            raw.unlink()
        run_ok(["expect", str(fetch)])
        assert raw.is_file(), "fetch.exp did not create data/raw.txt"
        fetched = raw.read_text().replace("\r\n", "\n").replace("\r", "\n")
        expected_fetch = (
            "Enter cluster name: Enter days of history: "
            f"TOKEN:{token}\n"
            f"[INFO] | {fetch_node} | CPU: {fetch_cpu}.5 | MEM: {fetch_mem}.0\n"
        )
        assert fetched == expected_fetch, (
            "fetch.exp did not perform the required interaction or raw.txt contained "
            f"something other than the monitor's stdout. Got: {fetched!r}"
        )

        node_a = "clean-" + uuid.uuid4().hex[:10]
        node_b = "clean-" + uuid.uuid4().hex[:10]
        cpu_a = f"{random.SystemRandom().randint(10, 70)}.25"
        cpu_b = f"{random.SystemRandom().randint(71, 99)}.5"
        mem_a = f"{random.SystemRandom().randint(1000, 5000)}.75"
        mem_b = str(random.SystemRandom().randint(5001, 9000))
        raw.write_text(
            "HEADER JUNK\n"
            f"[WARN] | {node_a} | CPU: 999 | MEM: 999\n"
            f"[INFO] | {node_a} | CPU: {cpu_a} | MEM: {mem_a}\n"
            f"[INFO] |{node_b}| CPU: {cpu_b} | MEM: {mem_b}\n"
            f"prefix [INFO] | fake-node | CPU: 1 | MEM: 2\n"
            "=== END ===\n"
        )
        clean_csv = DATA / "clean.csv"
        if clean_csv.exists():
            clean_csv.unlink()
        run_ok(["bash", str(cleaner)])
        assert clean_csv.is_file(), "clean.sh did not create data/clean.csv"
        cleaned_lines = clean_csv.read_text().splitlines()
        assert cleaned_lines == [
            f"{node_a},{cpu_a},{mem_a}",
            f"{node_b},{cpu_b},{mem_b}",
        ], f"clean.sh produced incorrect CSV for derived input: {cleaned_lines!r}"

        rng = random.SystemRandom()
        rust_a = "rust-" + uuid.uuid4().hex[:10]
        rust_b = "rust-" + uuid.uuid4().hex[:10]
        a_cpu_1, a_cpu_2 = rng.randint(10, 40), rng.randint(60, 90)
        a_mem_1, a_mem_2 = rng.randint(1000, 3000), rng.randint(4000, 7000)
        b_cpu, b_mem = rng.randint(20, 95), rng.randint(800, 8000)
        clean_csv.write_text(
            f"{rust_a},{a_cpu_1},{a_mem_1}\n"
            f"{rust_b},{b_cpu},{b_mem}\n"
            f"{rust_a},{a_cpu_2},{a_mem_2}\n"
        )
        report = BASE / "report.json"
        if report.exists():
            report.unlink()
        run_ok(["cargo", "run", "--quiet"], cwd=PREDICTOR, timeout=180)
        assert report.is_file(), "Running the Rust predictor did not create report.json"
        try:
            generated = json.loads(report.read_text())
        except json.JSONDecodeError as exc:
            pytest.fail(f"Rust predictor produced invalid JSON: {exc}")

        assert set(generated) == {rust_a, rust_b}, "Rust predictor did not report exactly the input nodes"
        expected = {
            rust_a: {
                "avg_cpu": (a_cpu_1 + a_cpu_2) / 2.0,
                "avg_mem": (a_mem_1 + a_mem_2) / 2.0,
            },
            rust_b: {"avg_cpu": float(b_cpu), "avg_mem": float(b_mem)},
        }
        for node, averages in expected.items():
            record = generated[node]
            assert set(record) == {"avg_cpu", "avg_mem", "projected_cpu", "projected_mem"}
            assert math.isclose(float(record["avg_cpu"]), averages["avg_cpu"], rel_tol=1e-9, abs_tol=1e-9)
            assert math.isclose(float(record["avg_mem"]), averages["avg_mem"], rel_tol=1e-9, abs_tol=1e-9)
            assert math.isclose(float(record["projected_cpu"]), averages["avg_cpu"] * 1.2, rel_tol=1e-9, abs_tol=1e-9)
            assert math.isclose(float(record["projected_mem"]), averages["avg_mem"] * 1.2, rel_tol=1e-9, abs_tol=1e-9)
    finally:
        monitor.write_bytes(original_monitor)
        os.chmod(monitor, original_mode)

    # Regenerate the required final state from the real monitor so the original
    # fixed-output assertions below remain meaningful.
    run_ok(["expect", str(fetch)])
    run_ok(["bash", str(cleaner)])
    run_ok(["cargo", "run", "--quiet"], cwd=PREDICTOR, timeout=180)


def test_clean_csv_exists_and_correct():
    """Test that clean.csv exists and contains the correctly formatted data."""
    csv_path = "/home/user/capacity_planner/data/clean.csv"
    assert os.path.isfile(csv_path), f"Missing cleaned CSV data at {csv_path}"

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    expected_lines = [
        "node-alpha,50.0,2000.0",
        "node-beta,80.0,4000.0",
        "node-alpha,60.0,2400.0",
        "node-beta,90.0,4200.0"
    ]

    assert lines == expected_lines, f"Content of {csv_path} does not match expected output. Got: {lines}"


def test_report_json_exists_and_correct():
    """Test that report.json exists and contains the correct calculated averages and projections."""
    json_path = "/home/user/capacity_planner/report.json"
    assert os.path.isfile(json_path), f"Missing JSON report at {json_path}"

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} does not contain valid JSON")

    assert "node-alpha" in data, "Missing 'node-alpha' in JSON report"
    assert "node-beta" in data, "Missing 'node-beta' in JSON report"

    alpha = data["node-alpha"]
    assert math.isclose(alpha.get("avg_cpu", 0), 55.0, rel_tol=1e-5), "node-alpha avg_cpu is incorrect"
    assert math.isclose(alpha.get("avg_mem", 0), 2200.0, rel_tol=1e-5), "node-alpha avg_mem is incorrect"
    assert math.isclose(alpha.get("projected_cpu", 0), 66.0, rel_tol=1e-5), "node-alpha projected_cpu is incorrect"
    assert math.isclose(alpha.get("projected_mem", 0), 2640.0, rel_tol=1e-5), "node-alpha projected_mem is incorrect"

    beta = data["node-beta"]
    assert math.isclose(beta.get("avg_cpu", 0), 85.0, rel_tol=1e-5), "node-beta avg_cpu is incorrect"
    assert math.isclose(beta.get("avg_mem", 0), 4100.0, rel_tol=1e-5), "node-beta avg_mem is incorrect"
    assert math.isclose(beta.get("projected_cpu", 0), 102.0, rel_tol=1e-5), "node-beta projected_cpu is incorrect"
    assert math.isclose(beta.get("projected_mem", 0), 4920.0, rel_tol=1e-5), "node-beta projected_mem is incorrect"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
