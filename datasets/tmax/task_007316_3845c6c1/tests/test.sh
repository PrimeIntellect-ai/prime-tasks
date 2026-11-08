#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import resource
import subprocess


def test_rolling_loads_csv():
    """Verify the output CSV file is correct for the shipped fixture."""
    csv_path = "/home/user/output/rolling_loads.csv"
    assert os.path.isfile(csv_path), f"Output file {csv_path} does not exist."

    expected_csv = [
        "ts,server,rolling_load",
        "1,srv_alpha,2.0",
        "1,srv_beta,4.0",
        "2,srv_alpha,3.0",
        "2,srv_beta,5.0",
        "3,srv_alpha,5.0",
        "3,srv_beta,4.0",
        "4,srv_alpha,3.5",
        "4,srv_beta,5.0"
    ]

    with open(csv_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_csv, "The contents of rolling_loads.csv do not match the expected output."


def test_scripts_exist_and_executable():
    """Verify process.sh and setup_cron.sh exist and are executable."""
    process_sh = "/home/user/process.sh"
    setup_cron_sh = "/home/user/setup_cron.sh"

    assert os.path.isfile(process_sh), f"Script {process_sh} does not exist."
    assert os.access(process_sh, os.X_OK), f"Script {process_sh} is not executable."

    assert os.path.isfile(setup_cron_sh), f"Script {setup_cron_sh} does not exist."
    assert os.access(setup_cron_sh, os.X_OK), f"Script {setup_cron_sh} is not executable."


def test_cron_setup():
    """Verify setup_cron.sh correctly sets up the crontab."""
    setup_cron_sh = "/home/user/setup_cron.sh"

    result = subprocess.run([setup_cron_sh], capture_output=True, text=True)
    assert result.returncode == 0, f"Execution of {setup_cron_sh} failed."

    crontab_result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert crontab_result.returncode == 0, "Failed to read crontab."

    cron_lines = crontab_result.stdout.strip().split("\n")
    expected_cron = "0 * * * * /home/user/process.sh"

    found = False
    for line in cron_lines:
        normalized_line = " ".join(line.strip().split())
        if expected_cron in normalized_line:
            found = True
            break

    assert found, f"Crontab does not contain the expected entry: '{expected_cron}'. Current crontab:\n{crontab_result.stdout}"


def test_process_executes_on_changed_input():
    """Execute the submitted processor on a different malformed-JSON fixture."""
    input_path = "/home/user/data/config_changes.jsonl"
    output_path = "/home/user/output/rolling_loads.csv"
    process_sh = "/home/user/process.sh"

    records = [
        {"ts": 10, "states": {"srv_beta": {"load": 7.0, "mem": 2}, "srv_alpha": {"load": 1.0, "mem": 1}}, "note": "BAD_ONE and BAD_TWO"},
        {"ts": 11, "states": {"srv_gamma": {"load": 8.0, "mem": 3}, "srv_alpha": {"load": 3.0, "mem": 1}}, "note": "valid smile: ☺"},
        {"ts": 12, "states": {"srv_gamma": {"load": 4.0, "mem": 3}, "srv_beta": {"load": 5.0, "mem": 2}, "srv_alpha": {"load": 9.0, "mem": 1}}, "note": "BAD_THREE"}
    ]

    with open(input_path, "w", encoding="utf-8", newline="\n") as f:
        for record in records:
            line = json.dumps(record, ensure_ascii=True)
            line = line.replace("BAD_ONE", r"\uZZZZ")
            line = line.replace("BAD_TWO", r"\u12G4")
            line = line.replace("BAD_THREE", r"\uXX99")
            f.write(line + "\n")

    if os.path.exists(output_path):
        os.remove(output_path)
    result = subprocess.run([process_sh], cwd="/home/user", capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"process.sh failed on changed input:\nstdout={result.stdout}\nstderr={result.stderr}"
    assert os.path.isfile(output_path), "process.sh did not create rolling_loads.csv"

    history = {}
    expected = [["ts", "server", "rolling_load"]]
    for record in sorted(records, key=lambda item: item["ts"]):
        for server in sorted(record["states"]):
            load = float(record["states"][server]["load"])
            previous = history.get(server)
            rolling = load if previous is None else (previous + load) / 2.0
            history[server] = load
            expected.append([str(record["ts"]), server, f"{rolling:.1f}"])

    with open(output_path, "r", encoding="utf-8", newline="") as f:
        actual = list(csv.reader(f))
    assert actual == expected, f"Unexpected output for changed input: {actual!r}"


def test_process_streams_large_input_under_memory_limit():
    """Ensure the raw JSON-lines file is not loaded into memory as a whole."""
    input_path = "/home/user/data/config_changes.jsonl"
    output_path = "/home/user/output/rolling_loads.csv"
    process_sh = "/home/user/process.sh"
    count = 35000
    padding = "x" * 4096

    with open(input_path, "w", encoding="utf-8", newline="\n") as f:
        for ts in range(1, count + 1):
            load = ts % 10
            f.write('{"ts":%d,"states":{"bulk":{"load":%d,"mem":1}},"note":"%s\\uZZZZ"}\n' % (ts, load, padding))

    if os.path.exists(output_path):
        os.remove(output_path)

    memory_limit = 96 * 1024 * 1024

    def apply_limit():
        resource.setrlimit(resource.RLIMIT_AS, (memory_limit, memory_limit))

    result = subprocess.run(
        [process_sh],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=120,
        preexec_fn=apply_limit,
    )
    assert result.returncode == 0, f"process.sh failed streaming test:\nstdout={result.stdout[-2000:]}\nstderr={result.stderr[-2000:]}"
    assert os.path.isfile(output_path), "process.sh did not create output for the large input"

    with open(output_path, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        assert next(reader, None) == ["ts", "server", "rolling_load"]
        previous = None
        rows = 0
        for ts, row in enumerate(reader, start=1):
            load = ts % 10
            rolling = float(load) if previous is None else (previous + load) / 2.0
            assert row == [str(ts), "bulk", f"{rolling:.1f}"], f"Incorrect large-input row at ts={ts}: {row!r}"
            previous = float(load)
            rows += 1
        assert rows == count, f"Expected {count} data rows, got {rows}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
