#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path
from secrets import SystemRandom

import pytest


def test_run_pipeline_exists_and_executable():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_path} does not have execute permissions for the user."


def test_log_analyzer_exists_and_is_file():
    analyzer_path = "/home/user/log_analyzer.py"
    assert os.path.exists(analyzer_path), f"The analyzer {analyzer_path} does not exist."
    assert os.path.isfile(analyzer_path), f"{analyzer_path} is not a file."


def test_data_web_log_exists():
    log_path = "/home/user/data/web.log"
    assert os.path.exists(log_path), f"The copied log file {log_path} does not exist. Did the pipeline run?"
    assert os.path.isfile(log_path), f"{log_path} is not a file."
    assert os.path.getsize(log_path) > 0, f"{log_path} is empty."


def test_anomalies_csv_content():
    csv_path = "/home/user/anomalies.csv"
    assert os.path.exists(csv_path), f"The anomalies file {csv_path} does not exist."

    expected_rows = [
        ["Timestamp", "IP", "ResponseTime"],
        ["2023-10-01T12:00:06", "192.168.1.100", "150"],
        ["2023-10-01T12:00:09", "192.168.1.101", "200"],
    ]

    with open(csv_path, "r", newline="") as f:
        actual_rows = list(csv.reader(f))

    assert actual_rows == expected_rows, f"The content of {csv_path} does not match the expected anomalies."


def test_crontab_configured():
    try:
        output = subprocess.check_output(["crontab", "-l"], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to run 'crontab -l' or no crontab exists for the user.")

    lines = [line.strip() for line in output.split("\n") if line.strip() and not line.strip().startswith("#")]
    found = False
    for line in lines:
        parts = line.split()
        if len(parts) >= 6:
            minute = parts[0]
            command = " ".join(parts[5:])
            if (minute == "*/5" or minute == "0,5,10,15,20,25,30,35,40,45,50,55") and "/home/user/run_pipeline.sh" in command:
                found = True
                break

    assert found, "Could not find a crontab entry running /home/user/run_pipeline.sh every 5 minutes."


def make_case():
    rng = SystemRandom()
    values = [rng.randint(11, 39) for _ in range(5)]
    # Exercise the strict boundary, then a value just above the moving threshold.
    values.append((3 * sum(values[-5:])) // 5)
    values.append((3 * sum(values[-5:])) // 5 + 1)
    values.extend(rng.randint(5, 35) for _ in range(4))
    values.append((3 * sum(values[-5:])) // 5 + rng.randint(2, 20))
    values.extend([rng.randint(6, 30), rng.randint(6, 30)])

    nonce = rng.randint(20, 220)
    records = []
    for i, response_time in enumerate(values):
        timestamp = f"2026-07-15T09:{i:02d}:{(i * 7) % 60:02d}"
        ip = f"10.{nonce}.{(i * 17 + nonce) % 255}.{(i * 29 + 3) % 254 + 1}"
        records.append((timestamp, ip, response_time))

    expected = [["Timestamp", "IP", "ResponseTime"]]
    for i, (timestamp, ip, response_time) in enumerate(records):
        if i >= 5 and response_time * 5 > 3 * sum(r[2] for r in records[i - 5:i]):
            expected.append([timestamp, ip, str(response_time)])

    text = "".join(
        f"[{timestamp}] IP: {ip} | User-Agent: Verifier/{nonce}-{i} | ResponseTime: {response_time}ms\n"
        for i, (timestamp, ip, response_time) in enumerate(records)
    )
    return text, expected


def read_csv(path):
    with open(path, "r", newline="") as f:
        return list(csv.reader(f))


def test_analyzer_computes_dynamic_cases():
    data_dir = Path("/home/user/data")
    data_dir.mkdir(parents=True, exist_ok=True)

    for _ in range(2):
        log_text, expected = make_case()
        (data_dir / "web.log").write_text(log_text)
        output = Path("/home/user/anomalies.csv")
        output.unlink(missing_ok=True)

        result = subprocess.run(
            ["python3", "/home/user/log_analyzer.py"],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, f"log_analyzer.py failed:\n{result.stdout}\n{result.stderr}"
        assert output.is_file(), "log_analyzer.py did not create /home/user/anomalies.csv"
        assert read_csv(output) == expected, "log_analyzer.py produced incorrect results for a dynamic log"


def test_pipeline_copies_remote_log_and_executes_analyzer():
    remote = Path("/opt/remote/web.log")
    local = Path("/home/user/data/web.log")
    output = Path("/home/user/anomalies.csv")
    analyzer = Path("/home/user/log_analyzer.py")

    log_text, expected = make_case()
    remote.write_text(log_text)
    local.parent.mkdir(parents=True, exist_ok=True)
    local.write_text("stale local data\n")
    output.write_text("stale output\n")

    original_bytes = analyzer.read_bytes()
    original_mode = stat.S_IMODE(analyzer.stat().st_mode)
    marker = Path(tempfile.gettempdir()) / ("analyzer-called-" + uuid.uuid4().hex)
    backup = Path(tempfile.gettempdir()) / ("analyzer-backup-" + uuid.uuid4().hex + ".py")
    backup.write_bytes(original_bytes)
    wrapper = (
        "#!/usr/bin/env python3\n"
        "from pathlib import Path\n"
        "import runpy\n"
        f"Path({str(marker)!r}).write_text('called')\n"
        f"runpy.run_path({str(backup)!r}, run_name='__main__')\n"
    )

    try:
        analyzer.write_text(wrapper)
        analyzer.chmod(0o755)
        result = subprocess.run(
            ["/home/user/run_pipeline.sh"],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, f"run_pipeline.sh failed:\n{result.stdout}\n{result.stderr}"
        assert marker.is_file(), "run_pipeline.sh did not execute /home/user/log_analyzer.py"
        assert local.is_file(), "run_pipeline.sh did not create /home/user/data/web.log"
        assert local.read_bytes() == remote.read_bytes(), "run_pipeline.sh did not copy the remote log exactly"
        assert output.is_file(), "The pipeline did not create /home/user/anomalies.csv"
        assert read_csv(output) == expected, "The pipeline produced incorrect anomalies for a dynamic remote log"
    finally:
        analyzer.write_bytes(original_bytes)
        analyzer.chmod(original_mode)
        marker.unlink(missing_ok=True)
        backup.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
