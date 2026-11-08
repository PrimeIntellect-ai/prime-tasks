#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import sys

import pytest


def test_raw_data_downloaded():
    """Test that raw data files were downloaded to /home/user/raw_data."""
    raw_dir = "/home/user/raw_data"
    assert os.path.isdir(raw_dir), f"Directory {raw_dir} is missing. Did you download the data?"

    expected_files = {"log1.json", "log2.json", "log3.json"}
    actual_files = set(os.listdir(raw_dir))

    missing = expected_files - actual_files
    assert not missing, f"Missing files in {raw_dir}: {missing}"

    # Ensure the named files are the data exposed by the upstream server, not
    # empty placeholders.
    for name in expected_files:
        downloaded = os.path.join(raw_dir, name)
        upstream = os.path.join("/tmp/remote_data", name)
        with open(downloaded, "r", encoding="utf-8") as f:
            downloaded_data = json.load(f)
        with open(upstream, "r", encoding="utf-8") as f:
            upstream_data = json.load(f)
        assert downloaded_data == upstream_data, f"{name} does not match the upstream JSON data"


def test_etl_script_exists_and_uses_parallelism():
    """Test that the ETL script exists and uses multiprocessing or concurrent.futures."""
    script_path = "/home/user/etl.py"
    assert os.path.isfile(script_path), f"ETL script {script_path} is missing."

    with open(script_path, "r", encoding="utf-8") as f:
        content = f.read()

    has_multiprocessing = "multiprocessing" in content
    has_concurrent = "concurrent.futures" in content

    assert has_multiprocessing or has_concurrent, (
        f"The script {script_path} must use 'multiprocessing' or 'concurrent.futures' "
        "to process the files in parallel."
    )


def test_hourly_max_csv():
    """Test that the output CSV exists and contains the correct aggregated data."""
    csv_path = "/home/user/hourly_max.csv"
    assert os.path.isfile(csv_path), f"Output file {csv_path} is missing."

    expected_lines = [
        "2023-10-01T08:00:00Z,19.1",
        "2023-10-01T09:00:00Z,25.1",
        "2023-10-01T10:00:00Z,17.8",
        "2023-10-01T11:00:00Z,14.2"
    ]

    with open(csv_path, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"The contents of {csv_path} do not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_etl_executes_on_new_data_and_invokes_parallel_api(tmp_path):
    """Run the submitted ETL against verifier-generated data."""
    raw_dir = "/home/user/raw_data"
    csv_path = "/home/user/hourly_max.csv"
    backup_raw = tmp_path / "raw_backup"
    backup_csv = tmp_path / "hourly_max_backup.csv"

    shutil.copytree(raw_dir, backup_raw)
    had_csv = os.path.isfile(csv_path)
    if had_csv:
        shutil.copy2(csv_path, backup_csv)

    records_by_file = {
        "batch_alpha.json": [
            {"timestamp": "2025-02-03T17:59:59Z", "value": -4.2},
            {"timestamp": "2025-02-03T18:00:01Z", "value": 3.14},
        ],
        "batch_beta.json": [
            {"timestamp": "2025-02-03T17:00:00Z", "value": -1.1},
            {"timestamp": "2025-02-04T00:12:10Z", "value": 91.04},
        ],
        "batch_gamma.json": [
            {"timestamp": "2024-12-31T23:45:00Z", "value": 8.25},
            {"timestamp": "2025-02-03T18:42:11Z", "value": 7.86},
        ],
        "batch_delta.json": [
            {"timestamp": "2025-02-04T00:59:59Z", "value": 91.16},
            {"timestamp": "2025-02-03T17:30:30Z", "value": -2.0},
        ],
        "batch_epsilon.json": [
            {"timestamp": "2026-07-09T06:01:02Z", "value": 0.04},
            {"timestamp": "2026-07-09T06:58:00Z", "value": 0.06},
        ],
        "batch_zeta.json": [
            {"timestamp": "2024-12-31T23:59:59Z", "value": 10.75}
        ],
    }

    maxima = {}
    for records in records_by_file.values():
        for record in records:
            hour = record["timestamp"][:13] + ":00:00Z"
            maxima[hour] = max(maxima.get(hour, float("-inf")), record["value"])
    expected_lines = [f"{hour},{maxima[hour]:.1f}" for hour in sorted(maxima)]

    trace_dir = tmp_path / "trace_site"
    trace_dir.mkdir()
    trace_file = tmp_path / "parallel_used.txt"
    sitecustomize = trace_dir / "sitecustomize.py"
    sitecustomize.write_text(r'''
import os

_trace = os.environ.get("ETL_PARALLEL_TRACE")

def _mark(kind):
    if _trace:
        with open(_trace, "a", encoding="utf-8") as f:
            f.write(kind + "\n")

try:
    import multiprocessing
    import multiprocessing.process
    _original_start = multiprocessing.process.BaseProcess.start
    def _traced_start(self, *args, **kwargs):
        _mark("multiprocessing.Process.start")
        return _original_start(self, *args, **kwargs)
    multiprocessing.process.BaseProcess.start = _traced_start
except Exception:
    pass

try:
    import concurrent.futures
    import concurrent.futures.process
    import concurrent.futures.thread

    _OriginalProcessPool = concurrent.futures.process.ProcessPoolExecutor
    class TracedProcessPoolExecutor(_OriginalProcessPool):
        def submit(self, *args, **kwargs):
            _mark("concurrent.futures.ProcessPoolExecutor.submit")
            return super().submit(*args, **kwargs)
        def map(self, *args, **kwargs):
            _mark("concurrent.futures.ProcessPoolExecutor.map")
            return super().map(*args, **kwargs)

    _OriginalThreadPool = concurrent.futures.thread.ThreadPoolExecutor
    class TracedThreadPoolExecutor(_OriginalThreadPool):
        def submit(self, *args, **kwargs):
            _mark("concurrent.futures.ThreadPoolExecutor.submit")
            return super().submit(*args, **kwargs)
        def map(self, *args, **kwargs):
            _mark("concurrent.futures.ThreadPoolExecutor.map")
            return super().map(*args, **kwargs)

    concurrent.futures.ProcessPoolExecutor = TracedProcessPoolExecutor
    concurrent.futures.process.ProcessPoolExecutor = TracedProcessPoolExecutor
    concurrent.futures.ThreadPoolExecutor = TracedThreadPoolExecutor
    concurrent.futures.thread.ThreadPoolExecutor = TracedThreadPoolExecutor
except Exception:
    pass
''', encoding="utf-8")

    try:
        shutil.rmtree(raw_dir)
        os.makedirs(raw_dir)
        for name, records in records_by_file.items():
            with open(os.path.join(raw_dir, name), "w", encoding="utf-8") as f:
                json.dump(records, f)
        if os.path.exists(csv_path):
            os.remove(csv_path)

        env = os.environ.copy()
        old_pythonpath = env.get("PYTHONPATH")
        env["PYTHONPATH"] = str(trace_dir) + (os.pathsep + old_pythonpath if old_pythonpath else "")
        env["ETL_PARALLEL_TRACE"] = str(trace_file)

        result = subprocess.run(
            [sys.executable, "/home/user/etl.py"],
            cwd="/home/user",
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Running /home/user/etl.py failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(csv_path), "Running etl.py did not create /home/user/hourly_max.csv"
        with open(csv_path, "r", encoding="utf-8") as f:
            actual_lines = [line.strip() for line in f if line.strip()]
        assert actual_lines == expected_lines, (
            "etl.py did not correctly aggregate the verifier-generated JSON files.\n"
            f"Expected: {expected_lines}\nActual: {actual_lines}"
        )
        assert trace_file.is_file() and trace_file.read_text(encoding="utf-8").strip(), (
            "etl.py did not invoke a multiprocessing process or a concurrent.futures executor "
            "while processing the files"
        )
    finally:
        if os.path.exists(raw_dir):
            shutil.rmtree(raw_dir)
        shutil.copytree(backup_raw, raw_dir)
        if had_csv:
            shutil.copy2(backup_csv, csv_path)
        elif os.path.exists(csv_path):
            os.remove(csv_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
