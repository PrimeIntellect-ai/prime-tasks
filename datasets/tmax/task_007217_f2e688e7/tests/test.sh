#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import stat
import subprocess
from collections import defaultdict

import pytest

WORKSPACE_DIR = "/home/user/workspace"
RAW_METRICS_FILE = os.path.join(WORKSPACE_DIR, "raw_metrics.csv")
SUMMARY_FILE = os.path.join(WORKSPACE_DIR, "summary.csv")
SCRIPTS = ["1_filter.sh", "2_impute.sh", "3_aggregate.sh", "run_pipeline.sh"]


def run_script(name, timeout=15):
    return subprocess.run(
        [os.path.join(WORKSPACE_DIR, name)],
        cwd=WORKSPACE_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def compute_expected_summary(path=RAW_METRICS_FILE):
    assert os.path.isfile(path), "raw_metrics.csv missing, cannot compute expected state."
    valid_statuses = {"200", "301", "404", "500"}
    server_data = defaultdict(list)
    last_known = {}

    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row["status_code"] not in valid_statuses:
                continue
            server_id = row["server_id"]
            cpu_raw = row["cpu_usage"]
            mem_raw = row["mem_usage"]
            cpu = last_known[server_id]["cpu"] if cpu_raw == "-" else float(cpu_raw)
            mem = last_known[server_id]["mem"] if mem_raw == "-" else float(mem_raw)
            last_known[server_id] = {"cpu": cpu, "mem": mem}
            server_data[server_id].append((cpu, mem))

    expected = []
    for server_id in sorted(server_data):
        values = server_data[server_id]
        avg_cpu = sum(v[0] for v in values) / len(values)
        avg_mem = sum(v[1] for v in values) / len(values)
        expected.append(f"{server_id},{avg_cpu:.2f},{avg_mem:.2f}")
    return expected


def read_nonempty_lines(path):
    with open(path) as f:
        return [line.strip() for line in f if line.strip()]


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline_before_checks():
    result = run_script("run_pipeline.sh")
    assert result.returncode == 0, (
        f"run_pipeline.sh failed with code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert "Pipeline Success" in result.stdout + result.stderr


def test_scripts_exist_and_executable():
    """Verify that all required scripts exist and are executable."""
    for script in SCRIPTS:
        script_path = os.path.join(WORKSPACE_DIR, script)
        assert os.path.isfile(script_path), f"Missing script: {script_path} does not exist."
        assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_summary_file_exists():
    """Verify that the final output file summary.csv exists."""
    assert os.path.isfile(SUMMARY_FILE), f"Missing output file: {SUMMARY_FILE} does not exist."


def test_summary_content():
    """Verify that summary.csv contains correctly filtered, imputed, aggregated data."""
    expected_lines = compute_expected_summary()
    actual_lines = read_nonempty_lines(SUMMARY_FILE)
    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} rows in summary.csv, found {len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Row {i+1} mismatch in summary.csv.\nExpected: {expected}\nActual:   {actual}"
        )


def test_phases_and_dag_on_fresh_inputs():
    script_paths = [os.path.join(WORKSPACE_DIR, name) for name in SCRIPTS]
    backups = {
        path: (open(path, "rb").read(), stat.S_IMODE(os.stat(path).st_mode))
        for path in script_paths
    }
    with open(RAW_METRICS_FILE, "rb") as f:
        original_raw = f.read()

    token = secrets.token_hex(5).upper()
    a, b, c = f"A{token}", f"B{token}", f"C{token}"
    offset = secrets.randbelow(30) + 10
    rows = [
        ["1", a, f"{offset}.0", str(1000 + offset), "200"],
        ["2", b, f"{offset + 40}.0", str(2000 + offset), "301"],
        ["3", a, "-", str(1010 + offset), "404"],
        ["4", b, f"{offset + 42}.0", "-", "500"],
        ["5", c, f"{offset + 70}.0", str(3000 + offset), "200"],
        ["6", a, f"{offset + 4}.0", "-", "301"],
        ["7", c, "-", str(3010 + offset), "404"],
        ["8", b, "-", str(2030 + offset), "500"],
        ["9", a, f"{offset + 6}.0", str(1030 + offset), "200"],
        ["10", c, f"{offset + 74}.0", "-", "301"],
        ["11", b, f"{offset + 46}.0", str(2050 + offset), "404"],
        ["12", c, "-", "-", "500"],
        ["13", a, "999.0", "9999", "999"],
        ["14", b, "888.0", "8888", "503"],
    ]
    header = ["timestamp", "server_id", "cpu_usage", "mem_usage", "status_code"]

    def write_raw(data_rows):
        with open(RAW_METRICS_FILE, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(header)
            writer.writerows(data_rows)

    def restore_scripts():
        for path, (content, mode) in backups.items():
            with open(path, "wb") as f:
                f.write(content)
            os.chmod(path, mode)

    try:
        write_raw(rows)
        for output in ("filtered.csv", "imputed.csv", "summary.csv"):
            path = os.path.join(WORKSPACE_DIR, output)
            if os.path.exists(path):
                os.remove(path)

        result = run_script("1_filter.sh")
        assert result.returncode == 0, result.stdout + result.stderr
        expected_filtered = [",".join(header)] + [",".join(r) for r in rows if r[4] in {"200", "301", "404", "500"}]
        assert read_nonempty_lines(os.path.join(WORKSPACE_DIR, "filtered.csv")) == expected_filtered

        result = run_script("2_impute.sh")
        assert result.returncode == 0, result.stdout + result.stderr
        expected_imputed = [",".join(header)]
        last = {}
        for row in rows:
            if row[4] not in {"200", "301", "404", "500"}:
                continue
            current = list(row)
            if current[2] == "-":
                current[2] = last[current[1]][0]
            if current[3] == "-":
                current[3] = last[current[1]][1]
            last[current[1]] = (current[2], current[3])
            expected_imputed.append(",".join(current))
        assert read_nonempty_lines(os.path.join(WORKSPACE_DIR, "imputed.csv")) == expected_imputed

        result = run_script("3_aggregate.sh")
        assert result.returncode == 0, result.stdout + result.stderr
        assert read_nonempty_lines(SUMMARY_FILE) == compute_expected_summary()

        os.remove(SUMMARY_FILE)
        result = run_script("run_pipeline.sh")
        assert result.returncode == 0, result.stdout + result.stderr
        assert "Pipeline Success" in result.stdout + result.stderr
        assert read_nonempty_lines(SUMMARY_FILE) == compute_expected_summary()

        short_rows = [[str(i), a, f"{offset + i}.0", str(1000 + i), "200"] for i in range(1, 10)]
        write_raw(short_rows)
        result = run_script("1_filter.sh")
        assert result.returncode != 0
        assert "Quality Gate Failed: Insufficient Data" in result.stderr

        for output in ("imputed.csv", "summary.csv"):
            path = os.path.join(WORKSPACE_DIR, output)
            if os.path.exists(path):
                os.remove(path)
        result = run_script("run_pipeline.sh")
        assert result.returncode == 1
        assert "Pipeline Failed at step 1" in result.stdout + result.stderr
        assert not os.path.exists(os.path.join(WORKSPACE_DIR, "imputed.csv"))
        assert not os.path.exists(SUMMARY_FILE)

        phase_names = ["1_filter.sh", "2_impute.sh", "3_aggregate.sh"]
        for failing_step in (1, 2, 3):
            marker_paths = []
            for step, name in enumerate(phase_names, 1):
                marker = os.path.join(WORKSPACE_DIR, f".verifier_step_{step}")
                marker_paths.append(marker)
                if os.path.exists(marker):
                    os.remove(marker)
                code = 7 if step == failing_step else 0
                content = f"#!/bin/bash\necho called > {marker!r}\nexit {code}\n"
                path = os.path.join(WORKSPACE_DIR, name)
                with open(path, "w") as f:
                    f.write(content)
                os.chmod(path, 0o755)

            result = run_script("run_pipeline.sh")
            assert result.returncode == 1
            assert f"Pipeline Failed at step {failing_step}" in result.stdout + result.stderr
            for step, marker in enumerate(marker_paths, 1):
                assert os.path.exists(marker) == (step <= failing_step), (
                    f"DAG execution was incorrect when step {failing_step} failed"
                )
            restore_scripts()
    finally:
        restore_scripts()
        with open(RAW_METRICS_FILE, "wb") as f:
            f.write(original_raw)
        for name in (".verifier_step_1", ".verifier_step_2", ".verifier_step_3"):
            path = os.path.join(WORKSPACE_DIR, name)
            if os.path.exists(path):
                os.remove(path)
        result = run_script("run_pipeline.sh")
        assert result.returncode == 0, result.stdout + result.stderr
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
