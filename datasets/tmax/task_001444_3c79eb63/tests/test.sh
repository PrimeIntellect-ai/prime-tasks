#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import secrets
import subprocess

C_SOURCE = "/home/user/log_processor.c"
C_BINARY = "/home/user/log_processor"
STATS_FILE = "/home/user/hourly_stats.csv"
RAW_FILE = "/home/user/raw_logs.txt"


def run_processor(binary, input_text):
    result = subprocess.run(
        [binary],
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert result.returncode == 0, (
        f"{binary} exited with status {result.returncode}.\n"
        f"stderr: {result.stderr}"
    )
    return result.stdout.splitlines()


def read_stats():
    rows = []
    with open(STATS_FILE, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                rows.append(row)
    return rows


def test_c_program_exists():
    c_source = "/home/user/log_processor.c"
    c_binary = "/home/user/log_processor"

    assert os.path.exists(c_source), f"The C source file {c_source} does not exist."
    assert os.path.exists(c_binary), f"The compiled binary {c_binary} does not exist."
    assert os.access(c_binary, os.X_OK), f"The file {c_binary} is not executable."

    assert os.path.isfile(c_source), f"The C source file {c_source} is not a regular file."
    assert os.path.isfile(c_binary), f"The compiled binary {c_binary} is not a regular file."
    with open(c_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"The file {c_binary} is not a compiled ELF binary."


def test_source_compiles(tmp_path):
    rebuilt = tmp_path / "log_processor_rebuilt"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", C_SOURCE, "-o", str(rebuilt)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert result.returncode == 0, f"log_processor.c does not compile:\n{result.stderr}"
    assert rebuilt.exists() and os.access(rebuilt, os.X_OK)


def test_processor_validation_and_normalization(tmp_path):
    rebuilt = tmp_path / "log_processor_rebuilt"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", C_SOURCE, "-o", str(rebuilt)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=False,
    )
    assert compile_result.returncode == 0, (
        f"log_processor.c does not compile:\n{compile_result.stderr}"
    )

    rng = secrets.SystemRandom()
    cases = []
    for i in range(24):
        timestamp = rng.randrange(1_000_000, 2_100_000_000)
        ip_value = rng.randrange(0, 2**32)
        ip_hex = f"0x{ip_value:08X}"
        user = f"R{rng.randrange(100000, 999999)}_{i:02d}"
        response = rng.randrange(0, 100000)
        status = rng.choice([200, 201, 299, 404, 500, 599])
        line = f"{timestamp}|{ip_hex}|{user}|GET|{response}|{status}"
        dotted = ".".join(str((ip_value >> shift) & 255) for shift in (24, 16, 8, 0))
        expected = f"{timestamp // 3600},{dotted},{user},{response}"
        cases.append((line, expected))

    base_ts = rng.randrange(1_000_000, 2_100_000_000)
    base_ip = f"0x{rng.randrange(0, 2**32):08X}"
    cases.extend([
        (f"{base_ts}|{base_ip}|BADNEG|GET|-1|200", None),
        (f"{base_ts}|{base_ip}|BADLOW|GET|10|199", None),
        (f"{base_ts}|{base_ip}|BADHIGH|GET|10|600", None),
        (f"{base_ts}|{base_ip}|BADTEXT|GET|10|OK", None),
        (f"{base_ts}|{base_ip}|MISSING|GET|10", None),
        (f"{base_ts}|{base_ip}|EXTRA|GET|10|200|unexpected", None),
    ])
    rng.shuffle(cases)

    input_text = "\n".join(line for line, _ in cases) + "\n"
    expected_lines = [expected for _, expected in cases if expected is not None]

    for binary in (C_BINARY, str(rebuilt)):
        actual_lines = run_processor(binary, input_text)
        assert actual_lines == expected_lines, (
            f"Processor output from {binary} is incorrect.\n"
            f"Expected: {expected_lines}\nActual: {actual_lines}"
        )


def test_processor_on_provided_raw_logs():
    with open(RAW_FILE, "r") as f:
        raw_input = f.read()

    expected_clean = [
        "472222,127.0.0.1,U1,150",
        "472222,127.0.0.1,U1,200",
        "472222,192.168.1.1,U2,50",
        "472223,8.8.8.8,U1,300",
        "472223,255.255.255.255,U4,0",
        "472224,0.0.0.0,U4,10",
    ]
    actual_clean = run_processor(C_BINARY, raw_input)
    assert actual_clean == expected_clean, (
        f"The compiled processor does not correctly process {RAW_FILE}.\n"
        f"Expected: {expected_clean}\nActual: {actual_clean}"
    )

    groups = {}
    for line in actual_clean:
        hour, _ip, user, response = line.split(",")
        key = (int(hour), user)
        groups.setdefault(key, []).append(int(response))
    derived_stats = [
        [str(hour), user, str(len(values)), str(sum(values) // len(values))]
        for (hour, user), values in sorted(groups.items(), key=lambda item: (item[0][0], item[0][1]))
    ]
    assert read_stats() == derived_stats, (
        "hourly_stats.csv is not the correctly sorted aggregation of the compiled "
        "processor's output for raw_logs.txt."
    )


def test_hourly_stats_exists():
    stats_file = "/home/user/hourly_stats.csv"
    assert os.path.exists(stats_file), f"The output file {stats_file} does not exist."
    assert os.path.isfile(stats_file), f"The path {stats_file} is not a file."


def test_hourly_stats_content():
    stats_file = "/home/user/hourly_stats.csv"

    expected_content = [
        ["472222", "U1", "2", "175"],
        ["472222", "U2", "1", "50"],
        ["472223", "U1", "1", "300"],
        ["472223", "U4", "1", "0"],
        ["472224", "U4", "1", "10"]
    ]

    actual_content = []
    with open(stats_file, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if row:
                actual_content.append(row)

    assert actual_content == expected_content, (
        f"The contents of {stats_file} do not match the expected output.\n"
        f"Expected: {expected_content}\n"
        f"Actual: {actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
