#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import shutil
import secrets
import statistics
import subprocess


def test_scripts_exist_and_executable():
    python_script = "/home/user/clean_metrics.py"
    bash_script = "/home/user/run_pipeline.sh"

    assert os.path.exists(python_script), f"{python_script} does not exist."
    assert os.path.isfile(python_script), f"{python_script} is not a file."

    assert os.path.exists(bash_script), f"{bash_script} does not exist."
    assert os.path.isfile(bash_script), f"{bash_script} is not a file."
    assert os.access(bash_script, os.X_OK), f"{bash_script} is not executable."


def test_venv_exists():
    venv_dir = "/home/user/venv"
    assert os.path.exists(venv_dir), f"Virtual environment directory {venv_dir} does not exist."
    assert os.path.isdir(venv_dir), f"{venv_dir} is not a directory."

    python_bin = os.path.join(venv_dir, "bin", "python")
    assert os.path.exists(python_bin), f"Python executable not found in {venv_dir}/bin/python."


def test_clean_metrics_csv_content():
    csv_file = "/home/user/clean_metrics.csv"
    assert os.path.exists(csv_file), f"{csv_file} does not exist."
    assert os.path.isfile(csv_file), f"{csv_file} is not a file."

    expected_data = [
        {"timestamp": "2023-10-01T10:00:00", "cpu_usage": 45.2, "memory_usage": 1000.0, "response_time": 120.0},
        {"timestamp": "2023-10-01T10:02:00", "cpu_usage": 40.1, "memory_usage": 2000.0, "response_time": 110.0},
        {"timestamp": "2023-10-01T10:04:00", "cpu_usage": 60.5, "memory_usage": 3000.0, "response_time": 140.0},
        {"timestamp": "2023-10-01T10:06:00", "cpu_usage": 55.0, "memory_usage": 4000.0, "response_time": 180.0},
    ]

    with open(csv_file, "r") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert len(rows) == len(expected_data), f"Expected {len(expected_data)} rows in {csv_file}, but found {len(rows)}."

    for i, (actual, expected) in enumerate(zip(rows, expected_data)):
        assert actual["timestamp"] == expected["timestamp"], f"Row {i+1}: expected timestamp {expected['timestamp']}, got {actual.get('timestamp')}"

        try:
            cpu = float(actual["cpu_usage"])
            mem = float(actual["memory_usage"])
            resp = float(actual["response_time"])
        except (ValueError, KeyError) as e:
            assert False, f"Row {i+1}: error parsing numerical values: {e}"

        assert abs(cpu - expected["cpu_usage"]) < 1e-6, f"Row {i+1}: expected cpu_usage {expected['cpu_usage']}, got {cpu}"
        assert abs(mem - expected["memory_usage"]) < 1e-6, f"Row {i+1}: expected memory_usage {expected['memory_usage']}, got {mem}"
        assert abs(resp - expected["response_time"]) < 1e-6, f"Row {i+1}: expected response_time {expected['response_time']}, got {resp}"


def test_pipeline_executes_on_unseen_input_and_builds_real_venv():
    raw_path = "/home/user/raw_metrics.csv"
    output_path = "/home/user/clean_metrics.csv"
    script_path = "/home/user/run_pipeline.sh"
    venv_path = "/home/user/venv"
    backup_venv = f"/home/user/venv.verifier-backup-{secrets.token_hex(8)}"

    with open(raw_path, "rb") as f:
        original_raw = f.read()
    with open(output_path, "rb") as f:
        original_output = f.read()

    token = secrets.token_hex(8)
    base = secrets.randbelow(5000) + 1000
    fieldnames = ["timestamp", "cpu_usage", "memory_usage", "response_time"]
    source_rows = [
        {"timestamp": f"{token}-a", "cpu_usage": "50.25", "memory_usage": "", "response_time": "10.5"},
        {"timestamp": f"{token}-b", "cpu_usage": "150.0", "memory_usage": str(base + 1), "response_time": "20.5"},
        {"timestamp": f"{token}-c", "cpu_usage": "0.0", "memory_usage": str(base + 3), "response_time": "30.5"},
        {"timestamp": f"{token}-d", "cpu_usage": "100.0", "memory_usage": str(base + 5), "response_time": "40.5"},
        {"timestamp": f"{token}-e", "cpu_usage": "-0.01", "memory_usage": str(base + 7), "response_time": "50.5"},
        {"timestamp": f"{token}-f", "cpu_usage": "", "memory_usage": str(base + 9), "response_time": "60.5"},
        {"timestamp": f"{token}-g", "cpu_usage": "75.75", "memory_usage": str(base + 11), "response_time": "70.5"},
        {"timestamp": "", "cpu_usage": "25.0", "memory_usage": "", "response_time": "80.5"},
        {"timestamp": f"{token}-i", "cpu_usage": "65.0", "memory_usage": str(base + 13), "response_time": ""},
    ]

    valid_memory = [float(r["memory_usage"]) for r in source_rows if r["memory_usage"] != ""]
    memory_median = statistics.median(valid_memory)
    expected = []
    for source in source_rows:
        row = dict(source)
        if row["memory_usage"] == "":
            row["memory_usage"] = str(memory_median)
        if row["cpu_usage"] != "":
            cpu = float(row["cpu_usage"])
            if cpu > 100.0 or cpu < 0.0:
                continue
        if any(row[column] == "" for column in fieldnames):
            continue
        expected.append({
            "timestamp": row["timestamp"],
            "cpu_usage": float(row["cpu_usage"]),
            "memory_usage": float(row["memory_usage"]),
            "response_time": float(row["response_time"]),
        })

    os.rename(venv_path, backup_venv)
    try:
        with open(raw_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(source_rows)
        os.remove(output_path)

        result = subprocess.run(
            [script_path],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=240,
        )
        assert result.returncode == 0, f"run_pipeline.sh failed with exit code {result.returncode}:\n{result.stdout}"
        assert os.path.isfile(output_path), "run_pipeline.sh did not produce /home/user/clean_metrics.csv"

        new_python = os.path.join(venv_path, "bin", "python")
        assert os.path.exists(new_python), "run_pipeline.sh did not create /home/user/venv/bin/python"
        import_result = subprocess.run(
            [new_python, "-c", "import pandas; print(pandas.__version__)"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
        assert import_result.returncode == 0, f"pandas is not installed in the newly created virtual environment:\n{import_result.stdout}"

        with open(output_path, newline="") as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames == fieldnames, f"Unexpected CSV columns: {reader.fieldnames}"
            actual_rows = list(reader)

        assert len(actual_rows) == len(expected), f"Expected {len(expected)} dynamic rows, got {len(actual_rows)}"
        for i, (actual, wanted) in enumerate(zip(actual_rows, expected), 1):
            assert actual["timestamp"] == wanted["timestamp"], f"Dynamic row {i} has wrong timestamp"
            for column in ("cpu_usage", "memory_usage", "response_time"):
                try:
                    value = float(actual[column])
                except (KeyError, TypeError, ValueError) as exc:
                    assert False, f"Dynamic row {i} has invalid {column}: {exc}"
                assert math.isfinite(value), f"Dynamic row {i} has non-finite {column}"
                assert abs(value - wanted[column]) < 1e-6, f"Dynamic row {i}: expected {column}={wanted[column]}, got {value}"
    finally:
        with open(raw_path, "wb") as f:
            f.write(original_raw)
        with open(output_path, "wb") as f:
            f.write(original_output)
        if os.path.lexists(venv_path):
            if os.path.isdir(venv_path) and not os.path.islink(venv_path):
                shutil.rmtree(venv_path)
            else:
                os.unlink(venv_path)
        if os.path.exists(backup_venv):
            os.rename(backup_venv, venv_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
