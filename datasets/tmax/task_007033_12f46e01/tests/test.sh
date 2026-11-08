#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

import pytest

SCRIPTS = [
    "/home/user/reshape.py",
    "/home/user/rolling.py",
    "/home/user/pipeline.py",
]


def run_pipeline(timeout=30):
    return subprocess.run(
        ["runuser", "-u", "user", "--", "python3", "/home/user/pipeline.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def test_scripts_exist():
    """Verify that all required Python scripts exist."""
    for script in SCRIPTS:
        assert os.path.isfile(script), f"Required script {script} is missing."


def test_pipeline_executes_and_generates_outputs():
    """Execute the submitted pipeline rather than trusting pre-created CSV files."""
    for output in ["/home/user/long_configs.csv", "/home/user/rolling_stats.csv"]:
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

    result = run_pipeline()
    assert result.returncode == 0, (
        f"pipeline.py failed with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile("/home/user/long_configs.csv")
    assert os.path.isfile("/home/user/rolling_stats.csv")


def test_long_configs_output():
    """Verify the output of the reshape phase."""
    file_path = "/home/user/long_configs.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    with open(file_path, "r", newline="") as f:
        reader = list(csv.reader(f))

    assert len(reader) > 1, f"File {file_path} is empty or has no data."
    header = reader[0]
    expected_header = ["date", "app", "metric", "value"]
    assert header == expected_header, f"Incorrect header in {file_path}. Expected {expected_header}, got {header}."

    # First row after header should be 2023-10-01, app1, threads, 16.
    assert reader[1] == ["2023-10-01", "app1", "threads", "16"], f"First data row is incorrect: {reader[1]}"

    # Total rows should be 1 header + 5 dates * 4 metrics = 21.
    assert len(reader) == 21, f"Expected 21 rows in {file_path}, got {len(reader)}."


def test_rolling_stats_output():
    """Verify the output of the rolling statistics phase."""
    file_path = "/home/user/rolling_stats.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    with open(file_path, "r", newline="") as f:
        reader = list(csv.reader(f))

    assert len(reader) > 1, f"File {file_path} is empty or has no data."
    header = reader[0]
    expected_header = ["date", "app", "metric", "value", "rolling_mean"]
    assert header == expected_header, f"Incorrect header in {file_path}. Expected {expected_header}, got {header}."

    data = {}
    for row in reader[1:]:
        date, app, metric, value, rolling_mean = row
        key = (date, app, metric)
        data[key] = float(rolling_mean)

    key1 = ("2023-10-04", "app1", "threads")
    assert key1 in data, f"Missing data for {key1}"
    assert round(data[key1], 2) == 21.33, f"Expected rolling mean 21.33 for {key1}, got {data[key1]}"

    key2 = ("2023-10-03", "app2", "workers")
    assert key2 in data, f"Missing data for {key2}"
    assert round(data[key2], 2) == 3.33, f"Expected rolling mean 3.33 for {key2}, got {data[key2]}"


def test_pipeline_on_derived_unseen_input():
    """Check every reshaped and rolling value on verifier-generated input."""
    raw_path = Path("/home/user/raw_configs.csv")
    original_raw = raw_path.read_bytes()

    dates = [f"2024-02-{day:02d}" for day in range(1, 8)]
    columns = ["app1_workers", "app1_threads", "app2_workers", "app2_threads"]
    seed = secrets.randbelow(1000) + 101
    values = {
        column: [seed + (column_index + 2) * 17 + day_index * (column_index + 3) + day_index ** 2
                 for day_index in range(len(dates))]
        for column_index, column in enumerate(columns)
    }

    try:
        with raw_path.open("w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["date"] + columns)
            for i, date in enumerate(dates):
                writer.writerow([date] + [values[column][i] for column in columns])

        for output in ["/home/user/long_configs.csv", "/home/user/rolling_stats.csv"]:
            try:
                os.remove(output)
            except FileNotFoundError:
                pass

        result = run_pipeline()
        assert result.returncode == 0, (
            f"pipeline.py failed on generated input: stdout={result.stdout!r}, stderr={result.stderr!r}"
        )

        expected_long = []
        for i, date in enumerate(dates):
            for app in ["app1", "app2"]:
                for metric in ["threads", "workers"]:
                    expected_long.append((date, app, metric, float(values[f"{app}_{metric}"][i])))

        with open("/home/user/long_configs.csv", newline="") as f:
            rows = list(csv.reader(f))
        assert rows[0] == ["date", "app", "metric", "value"]
        assert len(rows) == len(expected_long) + 1
        actual_long = [(r[0], r[1], r[2], float(r[3])) for r in rows[1:]]
        assert actual_long == expected_long, "long_configs.csv does not contain the complete sorted reshape"

        expected_rolling = []
        history = {}
        for date, app, metric, value in expected_long:
            key = (app, metric)
            history.setdefault(key, []).append(value)
            mean = round(sum(history[key][-3:]) / len(history[key][-3:]), 2)
            expected_rolling.append((date, app, metric, value, mean))

        with open("/home/user/rolling_stats.csv", newline="") as f:
            rows = list(csv.reader(f))
        assert rows[0] == ["date", "app", "metric", "value", "rolling_mean"]
        assert len(rows) == len(expected_rolling) + 1
        actual_rolling = [
            (r[0], r[1], r[2], float(r[3]), float(r[4])) for r in rows[1:]
        ]
        assert len(actual_rolling) == len(expected_rolling)
        for actual, expected in zip(actual_rolling, expected_rolling):
            assert actual[:4] == expected[:4]
            assert actual[4] == pytest.approx(expected[4], abs=0.0001)
    finally:
        raw_path.write_bytes(original_raw)
        os.chmod(raw_path, 0o777)
        # Restore the requested final outputs from the real input.
        run_pipeline()


def test_pipeline_orders_steps_and_stops_after_failure():
    """Exercise the orchestrator with controlled phase scripts."""
    reshape = Path("/home/user/reshape.py")
    rolling = Path("/home/user/rolling.py")
    original_reshape = reshape.read_bytes()
    original_rolling = rolling.read_bytes()
    reshape_mode = stat.S_IMODE(reshape.stat().st_mode)
    rolling_mode = stat.S_IMODE(rolling.stat().st_mode)
    temp_dir = tempfile.mkdtemp(prefix="pipeline-verifier-")
    os.chmod(temp_dir, 0o777)
    marker = Path(temp_dir) / "order.txt"

    try:
        reshape.write_text(
            "from pathlib import Path\n"
            f"p = Path({str(marker)!r})\n"
            "with p.open('a') as f: f.write('reshape\\n')\n"
        )
        rolling.write_text(
            "from pathlib import Path\n"
            f"p = Path({str(marker)!r})\n"
            "with p.open('a') as f: f.write('rolling\\n')\n"
        )
        os.chmod(reshape, 0o755)
        os.chmod(rolling, 0o755)

        result = run_pipeline()
        assert result.returncode == 0, "pipeline.py did not successfully execute both successful phases"
        assert marker.read_text().splitlines() == ["reshape", "rolling"], (
            "pipeline.py must execute reshape.py before rolling.py exactly once"
        )

        marker.unlink()
        reshape.write_text("import sys\nsys.exit(7)\n")
        rolling.write_text(
            "from pathlib import Path\n"
            f"Path({str(marker)!r}).write_text('rolling ran')\n"
        )
        os.chmod(reshape, 0o755)
        os.chmod(rolling, 0o755)

        result = run_pipeline()
        assert result.returncode != 0, "pipeline.py must return non-zero when reshape.py fails"
        assert not marker.exists(), "pipeline.py executed rolling.py after reshape.py failed"
    finally:
        reshape.write_bytes(original_reshape)
        rolling.write_bytes(original_rolling)
        os.chmod(reshape, reshape_mode)
        os.chmod(rolling, rolling_mode)
        shutil.rmtree(temp_dir, ignore_errors=True)
        run_pipeline()


def test_cron_job_configured():
    """Verify that the cron job is configured correctly for user."""
    try:
        result = subprocess.run(
            ["crontab", "-u", "user", "-l"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        crontab_output = result.stdout
    except Exception as e:
        assert False, f"Failed to check crontab: {e}"

    # Preserve the original minute-0 pipeline assertion.
    pattern = re.compile(r"^0\s+\*\s+\*\s+\*\s+\*.*pipeline\.py", re.MULTILINE)
    assert pattern.search(crontab_output), "Cron job for pipeline.py at minute 0 is not configured properly."

    command_pattern = re.compile(
        r"^\s*0\s+\*\s+\*\s+\*\s+\*\s+(?:/usr/bin/)?python3\s+/home/user/pipeline\.py(?:\s|$)",
        re.MULTILINE,
    )
    assert command_pattern.search(crontab_output), (
        "The user crontab must run /home/user/pipeline.py with Python 3 at minute 0."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
