#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import stat
import subprocess
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path


def test_profile_sh_exists_and_executable():
    script_path = "/home/user/profile.sh"
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_results_csv_content():
    results_path = "/home/user/results.csv"
    assert os.path.exists(results_path), f"The results file {results_path} does not exist."

    expected_data = [
        {"Threads": "1", "ActualTime": "100.0000", "IdealTime": "100.0000", "Efficiency": "1.0000"},
        {"Threads": "2", "ActualTime": "52.0000", "IdealTime": "50.0000", "Efficiency": "0.9615"},
        {"Threads": "4", "ActualTime": "31.0000", "IdealTime": "25.0000", "Efficiency": "0.8065"},
        {"Threads": "8", "ActualTime": "26.5000", "IdealTime": "12.5000", "Efficiency": "0.4717"},
    ]

    with open(results_path, 'r') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["Threads", "ActualTime", "IdealTime", "Efficiency"], \
            "The header of results.csv is incorrect or missing."

        rows = list(reader)
        assert len(rows) == 4, f"Expected 4 rows of data in results.csv, found {len(rows)}."

        for i, expected_row in enumerate(expected_data):
            for key in expected_row:
                actual_val = rows[i].get(key, "").strip()
                expected_val = expected_row[key]
                assert actual_val == expected_val, \
                    f"Row {i+1} mismatch for {key}: expected {expected_val}, got {actual_val}."


def test_mse_txt_content():
    mse_path = "/home/user/mse.txt"
    assert os.path.exists(mse_path), f"The MSE file {mse_path} does not exist."

    with open(mse_path, 'r') as f:
        content = f.read().strip()

    assert content == "59.0000", f"Expected MSE to be '59.0000', got '{content}'."


def test_profile_script_executes_simulator_and_derives_outputs(tmp_path):
    script = Path("/home/user/profile.sh")
    sim = Path("/home/user/sim.py")
    results = Path("/home/user/results.csv")
    mse_file = Path("/home/user/mse.txt")

    def snapshot(path):
        if path.exists():
            return (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
        return None

    def restore(path, saved):
        if path.exists() or path.is_symlink():
            path.unlink()
        if saved is not None:
            data, mode = saved
            path.write_bytes(data)
            os.chmod(path, mode)

    saved_sim = snapshot(sim)
    saved_results = snapshot(results)
    saved_mse = snapshot(mse_file)

    q = Decimal("0.0001")
    rng = random.SystemRandom()

    def is_rounding_tie(value):
        scaled = value * Decimal(10000)
        return scaled % 1 == Decimal("0.5")

    while True:
        base_units = rng.randrange(800000, 1500001)
        base_units -= base_units % 8
        units = {
            1: base_units,
            2: rng.randrange(base_units * 48 // 100, base_units * 72 // 100),
            4: rng.randrange(base_units * 25 // 100, base_units * 47 // 100),
            8: rng.randrange(base_units * 14 // 100, base_units * 24 // 100),
        }
        actual = {t: Decimal(u) / Decimal(10000) for t, u in units.items()}
        ideal = {t: actual[1] / Decimal(t) for t in (1, 2, 4, 8)}
        efficiency = {t: ideal[t] / actual[t] for t in (1, 2, 4, 8)}
        mse = sum((actual[t] - ideal[t]) ** 2 for t in (1, 2, 4, 8)) / Decimal(4)
        if not any(is_rounding_tie(efficiency[t]) for t in (1, 2, 4, 8)) and not is_rounding_tie(mse):
            break

    def fmt(value):
        return str(value.quantize(q, rounding=ROUND_HALF_UP))

    simulator_values = {t: fmt(actual[t]) for t in (1, 2, 4, 8)}
    log_path = tmp_path / "simulator_calls.jsonl"
    probe = f'''#!/usr/bin/env python3
import argparse
import json
import os

parser = argparse.ArgumentParser()
parser.add_argument("--mesh", type=int, required=True)
args = parser.parse_args()
threads = int(os.environ.get("OMP_NUM_THREADS", "0"))
with open({str(log_path)!r}, "a") as log:
    log.write(json.dumps({{"threads": threads, "mesh": args.mesh}}) + "\\n")
values = {simulator_values!r}
if threads not in values:
    raise SystemExit("unexpected OMP_NUM_THREADS")
print(values[threads])
'''

    try:
        sim.write_text(probe)
        os.chmod(sim, 0o755)
        if results.exists() or results.is_symlink():
            results.unlink()
        if mse_file.exists() or mse_file.is_symlink():
            mse_file.unlink()

        env = os.environ.copy()
        env.pop("OMP_NUM_THREADS", None)
        completed = subprocess.run(
            [str(script)],
            cwd="/home/user",
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert completed.returncode == 0, \
            f"profile.sh failed when executed: stdout={completed.stdout!r}, stderr={completed.stderr!r}"

        assert log_path.exists(), "profile.sh did not execute /home/user/sim.py."
        calls = [json.loads(line) for line in log_path.read_text().splitlines() if line.strip()]
        assert calls == [
            {"threads": 1, "mesh": 1024},
            {"threads": 2, "mesh": 1024},
            {"threads": 4, "mesh": 1024},
            {"threads": 8, "mesh": 1024},
        ], f"Simulator calls were incorrect: {calls!r}"

        assert results.is_file(), "profile.sh did not generate /home/user/results.csv."
        with results.open(newline="") as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames == ["Threads", "ActualTime", "IdealTime", "Efficiency"], \
                "The generated results.csv header is incorrect."
            rows = list(reader)

        assert len(rows) == 4, f"Expected 4 generated CSV rows, found {len(rows)}."
        for index, t in enumerate((1, 2, 4, 8)):
            expected = {
                "Threads": str(t),
                "ActualTime": fmt(actual[t]),
                "IdealTime": fmt(ideal[t]),
                "Efficiency": fmt(efficiency[t]),
            }
            observed = {key: rows[index].get(key, "").strip() for key in expected}
            assert observed == expected, \
                f"Generated row {index + 1} was not derived correctly: expected {expected}, got {observed}."

        assert mse_file.is_file(), "profile.sh did not generate /home/user/mse.txt."
        observed_mse = mse_file.read_text().strip()
        assert observed_mse == fmt(mse), \
            f"Generated MSE was not derived correctly: expected {fmt(mse)}, got {observed_mse!r}."
    finally:
        restore(sim, saved_sim)
        restore(results, saved_results)
        restore(mse_file, saved_mse)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
