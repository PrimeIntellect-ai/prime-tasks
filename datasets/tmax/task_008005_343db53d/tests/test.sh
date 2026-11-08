#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import random
import re
import subprocess
import tempfile


def test_analyzer_c_exists():
    path = "/home/user/analyzer.c"
    assert os.path.isfile(path), f"Source file {path} does not exist."


def test_analyzer_executable_exists():
    path = "/home/user/analyzer"
    assert os.path.isfile(path), f"Compiled executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled ELF executable."


def parse_reference(path):
    match = re.fullmatch(r"config_(\d{4}-\d{2}-\d{2})\.txt", os.path.basename(path))
    assert match, f"Unexpected configuration filename: {path}"
    value = None
    with open(path, "r") as f:
        for line in f:
            fields = line.split()
            if len(fields) >= 2 and fields[0].casefold() == "max_connections":
                value = int(fields[1], 0)
                break
    assert value is not None, f"No MAX_CONNECTIONS value in {path}"
    return match.group(1), value


def run_and_check(program, paths):
    expected = [f"{date} {value}" for date, value in map(parse_reference, paths)]
    result = subprocess.run(
        [program, *paths], text=True, capture_output=True, timeout=10, check=False
    )
    assert result.returncode == 0, (
        f"{program} exited with {result.returncode}; stderr: {result.stderr}"
    )
    assert result.stdout.splitlines() == expected, (
        f"Unexpected output from {program}. Expected {expected!r}, got "
        f"{result.stdout.splitlines()!r}."
    )


def test_analyzer_behavior_and_source_build():
    rebuilt = "/tmp/analyzer_rebuilt"
    compile_result = subprocess.run(
        ["gcc", "/home/user/analyzer.c", "-o", rebuilt],
        text=True,
        capture_output=True,
        timeout=20,
        check=False,
    )
    assert compile_result.returncode == 0, (
        f"analyzer.c did not compile: {compile_result.stderr}"
    )

    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="analyzer_inputs_") as directory:
        start = datetime.date(rng.randint(2030, 2080), rng.randint(1, 10), rng.randint(1, 20))
        keys = ["MAX_CONNECTIONS", "max_connections", "Max_Connections", "mAx_CoNnEcTiOnS"]
        paths = []
        for index, key in enumerate(keys):
            date = start + datetime.timedelta(days=index)
            value = rng.randint(301, 50000)
            rendered = hex(value) if index % 2 else str(value)
            path = os.path.join(directory, f"config_{date.isoformat()}.txt")
            with open(path, "w") as f:
                f.write(f"port {rng.randint(1000, 9999)}\n")
                f.write(f"MAX_CONNECTIONS_BACKUP {rng.randint(1, 100)}\n")
                f.write(f"{key} {rendered}\n")
                f.write("timeout 30\n")
            paths.append(path)

        run_and_check("/home/user/analyzer", paths)
        run_and_check(rebuilt, paths)


def test_analyzer_on_supplied_configs_and_changepoint():
    config_dir = "/home/user/configs"
    paths = sorted(
        os.path.join(config_dir, name)
        for name in os.listdir(config_dir)
        if name.endswith(".txt")
    )
    assert paths, "No supplied configuration files found."
    run_and_check("/home/user/analyzer", paths)

    records = [parse_reference(path) for path in paths]
    expected_anomaly = None
    for (previous_date, previous), (date, current) in zip(records, records[1:]):
        if current * 2 > previous * 3:
            expected_anomaly = date
            break
    assert expected_anomaly is not None, "Supplied data has no qualifying changepoint."

    with open("/home/user/anomaly.txt", "r") as f:
        content = f.read().strip()
    assert content == expected_anomaly, (
        f"Expected derived changepoint {expected_anomaly!r}, got {content!r}."
    )


def test_anomaly_txt_content():
    path = "/home/user/anomaly.txt"
    assert os.path.isfile(path), f"Output file {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    expected_date = "2023-10-05"
    assert content == expected_date, f"Expected '{expected_date}' in {path}, but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
