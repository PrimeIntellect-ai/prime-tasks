#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import hashlib
import glob
import secrets
import subprocess
import sys
from datetime import datetime, timedelta
import pytest

# Add an unpredictable shard after the agent has finished so the submitted script
# must actually process the current inputs rather than rely on a prebuilt output.
_probe_id = secrets.token_hex(6)
_probe_sensor = f"VERIFY_{_probe_id}"
_probe_path = f"/home/user/sensor_data/shard_verifier_{_probe_id}.csv"
_base_temp = 10.0 + secrets.randbelow(150) / 10.0
with open(_probe_path, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["event_time", "sensor_id", "temperature", "ingested_at"])
    writer.writerows([
        ["2031-02-01 01:00:00", _probe_sensor, f"{_base_temp:.1f}", 100],
        ["2031-02-01 01:00:00", _probe_sensor, f"{_base_temp:.1f}", 900],
        ["2031-02-02 01:00:00", _probe_sensor, f"{_base_temp + 3.0:.1f}", 200],
        ["2031-02-04 01:00:00", _probe_sensor, f"{_base_temp + 6.0:.1f}", 300],
    ])

HOOK_SOURCE = r'''
import builtins
import io
import os
import threading

_owner = os.environ.get("VERIFIER_SCRIPT_PID")
if _owner is None:
    _owner = str(os.getpid())
    os.environ["VERIFIER_SCRIPT_PID"] = _owner
_owner = int(_owner)
_api_marker = "/tmp/verifier_parallel_api_used"
_read_marker = "/tmp/verifier_parallel_reads"
_sensor_root = os.path.realpath("/home/user/sensor_data") + os.sep
_orig_open = builtins.open
_orig_io_open = io.open

def _append(path, text):
    try:
        with _orig_open(path, "a", encoding="utf-8") as marker:
            marker.write(text + "\n")
    except Exception:
        pass

def _mark_api():
    _append(_api_marker, str(os.getpid()))

def _parallel_context():
    return os.getpid() != _owner or threading.current_thread() is not threading.main_thread()

def _track(file, mode):
    if not _parallel_context():
        return
    if any(flag in str(mode) for flag in ("w", "a", "x")):
        return
    try:
        path = os.path.realpath(os.fspath(file))
    except (TypeError, ValueError):
        return
    if path.startswith(_sensor_root) and path.endswith(".csv"):
        _append(_read_marker, path)

def _open(file, mode="r", *args, **kwargs):
    _track(file, mode)
    return _orig_open(file, mode, *args, **kwargs)

def _io_open(file, mode="r", *args, **kwargs):
    _track(file, mode)
    return _orig_io_open(file, mode, *args, **kwargs)

builtins.open = _open
io.open = _io_open

try:
    import concurrent.futures
    for _cls in (concurrent.futures.ThreadPoolExecutor,
                 concurrent.futures.ProcessPoolExecutor):
        _old_submit = _cls.submit
        def _make_submit(old):
            def submit(self, *args, **kwargs):
                _mark_api()
                return old(self, *args, **kwargs)
            return submit
        _cls.submit = _make_submit(_old_submit)
except Exception:
    pass

try:
    import multiprocessing.process
    _old_start = multiprocessing.process.BaseProcess.start
    def _start(self, *args, **kwargs):
        _mark_api()
        return _old_start(self, *args, **kwargs)
    multiprocessing.process.BaseProcess.start = _start
except Exception:
    pass

try:
    import multiprocessing.pool
    for _name in ("map", "map_async", "imap", "imap_unordered", "starmap", "starmap_async"):
        if hasattr(multiprocessing.pool.Pool, _name):
            _old = getattr(multiprocessing.pool.Pool, _name)
            def _make_pool_call(old):
                def call(self, *args, **kwargs):
                    _mark_api()
                    return old(self, *args, **kwargs)
                return call
            setattr(multiprocessing.pool.Pool, _name, _make_pool_call(_old))
except Exception:
    pass
'''

def test_script_exists():
    assert os.path.exists("/home/user/process_sensors.py"), "The script /home/user/process_sensors.py is missing."
    assert os.path.isfile("/home/user/process_sensors.py"), "/home/user/process_sensors.py is not a file."

def test_script_executes_and_reads_shards_in_parallel():
    hook_dir = "/tmp/verifier_hooks"
    os.makedirs(hook_dir, exist_ok=True)
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(HOOK_SOURCE)

    for marker in ("/tmp/verifier_parallel_api_used", "/tmp/verifier_parallel_reads"):
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass

    try:
        os.remove("/home/user/rolling_averages.json")
    except FileNotFoundError:
        pass

    required_shards = {os.path.realpath(p) for p in glob.glob("/home/user/sensor_data/shard_*.csv")}
    env = os.environ.copy()
    env.pop("VERIFIER_SCRIPT_PID", None)
    env["PYTHONPATH"] = hook_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")

    try:
        result = subprocess.run(
            [sys.executable, "/home/user/process_sensors.py"],
            cwd="/home/user",
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("process_sensors.py did not finish within 60 seconds.")

    assert result.returncode == 0, (
        "process_sensors.py failed when executed.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile("/home/user/rolling_averages.json"), (
        "Executing process_sensors.py did not generate rolling_averages.json."
    )
    assert os.path.isfile("/tmp/verifier_parallel_api_used"), (
        "The script did not invoke multiprocessing or concurrent.futures parallel work."
    )

    parallel_reads = set()
    if os.path.isfile("/tmp/verifier_parallel_reads"):
        with open("/tmp/verifier_parallel_reads", "r", encoding="utf-8") as f:
            parallel_reads = {line.strip() for line in f if line.strip()}
    missing = required_shards - parallel_reads
    assert not missing, (
        "Not all CSV shards were opened from parallel workers: " + ", ".join(sorted(missing))
    )

def test_output_json_exists():
    assert os.path.exists("/home/user/rolling_averages.json"), "The output file /home/user/rolling_averages.json is missing."
    assert os.path.isfile("/home/user/rolling_averages.json"), "/home/user/rolling_averages.json is not a file."

def test_output_json_content():
    # Read and process data to compute expected result
    files = glob.glob("/home/user/sensor_data/shard_*.csv")
    assert files, "No shard files found in /home/user/sensor_data/"

    records_by_hash = {}

    for file_path in files:
        with open(file_path, "r", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                event_time = row["event_time"]
                sensor_id = row["sensor_id"]
                temperature = float(row["temperature"])
                ingested_at = int(row["ingested_at"])

                hash_str = f"{event_time}{sensor_id}{temperature:.1f}"
                row_hash = hashlib.md5(hash_str.encode("utf-8")).hexdigest()

                if row_hash not in records_by_hash:
                    records_by_hash[row_hash] = row
                else:
                    if ingested_at > int(records_by_hash[row_hash]["ingested_at"]):
                        records_by_hash[row_hash] = row

    # Group by sensor and date
    daily_data = {}
    for row in records_by_hash.values():
        sensor_id = row["sensor_id"]
        date_str = row["event_time"][:10]
        temp = float(row["temperature"])

        if sensor_id not in daily_data:
            daily_data[sensor_id] = {}
        if date_str not in daily_data[sensor_id]:
            daily_data[sensor_id][date_str] = []

        daily_data[sensor_id][date_str].append(temp)

    # Calculate daily averages
    daily_averages = {}
    for sensor, dates in daily_data.items():
        daily_averages[sensor] = {}
        for date_str, temps in dates.items():
            daily_averages[sensor][date_str] = sum(temps) / len(temps)

    # Calculate 3-day rolling averages
    expected_result = {}
    for sensor, dates in daily_averages.items():
        expected_result[sensor] = {}
        sorted_dates = sorted(dates.keys())

        for date_str in sorted_dates:
            current_date = datetime.strptime(date_str, "%Y-%m-%d").date()
            window_dates = [
                (current_date - timedelta(days=i)).strftime("%Y-%m-%d")
                for i in range(3)
            ]

            window_temps = [
                daily_averages[sensor][d]
                for d in window_dates
                if d in daily_averages[sensor]
            ]

            rolling_avg = sum(window_temps) / len(window_temps)
            expected_result[sensor][date_str] = round(rolling_avg, 2)

    # Read student's output
    with open("/home/user/rolling_averages.json", "r", encoding="utf-8") as f:
        try:
            student_result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/rolling_averages.json is not valid JSON.")

    # Compare
    for sensor, dates in expected_result.items():
        assert sensor in student_result, f"Sensor {sensor} missing from output."
        for date_str, expected_val in dates.items():
            assert date_str in student_result[sensor], f"Date {date_str} for sensor {sensor} missing from output."
            student_val = student_result[sensor][date_str]
            assert abs(student_val - expected_val) < 1e-5, f"Mismatch for {sensor} on {date_str}: expected {expected_val}, got {student_val}."

    for sensor in student_result:
        assert sensor in expected_result, f"Unexpected sensor {sensor} in output."
        for date_str in student_result[sensor]:
            assert date_str in expected_result[sensor], f"Unexpected date {date_str} for sensor {sensor} in output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
