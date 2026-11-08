#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile


def test_anonymized_logs():
    """Test that the anonymized_logs.csv file exists and contains the correct data."""
    log_file = "/home/user/anonymized_logs.csv"
    assert os.path.isfile(log_file), f"The file {log_file} does not exist. Did the pipeline run?"

    expected_content = """100,U01,192.168.*.*,150
105,U01,192.168.*.*,150
110,U01,192.168.*.*,200
101,U02,10.0.*.*,0
106,U02,10.0.*.*,300
100,U03,172.16.*.*,500
108,U03,172.16.*.*,500
115,U03,172.16.*.*,500
102,U04,8.8.*.*,400
103,U04,8.8.*.*,200
104,U04,1.1.*.*,200"""

    with open(log_file, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"The content of {log_file} is incorrect. Expected masked IPs and correctly imputed response times."


def test_top_users():
    """Test that the top_users.txt file exists and contains the correct data."""
    top_users_file = "/home/user/top_users.txt"
    assert os.path.isfile(top_users_file), f"The file {top_users_file} does not exist."

    expected_content = """U03,500.00
U04,266.67
U01,166.67"""

    with open(top_users_file, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"The content of {top_users_file} is incorrect. Expected top 3 users by average response time."


def test_scripts_exist():
    """Test that the requested source files were created."""
    c_script = "/home/user/process_logs.c"
    bash_script = "/home/user/run_pipeline.sh"

    assert os.path.isfile(c_script), f"The C program {c_script} does not exist."
    assert os.path.isfile(bash_script), f"The bash script {bash_script} does not exist."
    assert os.access(bash_script, os.X_OK), f"The bash script {bash_script} is not executable."


def expected_outputs(rows):
    sorted_rows = sorted(rows, key=lambda row: (row[1], int(row[0])))
    most_recent = {}
    output_lines = []
    totals = {}
    counts = {}

    for timestamp, user, ip, response in sorted_rows:
        if response == "":
            response = most_recent.get(user, "0")
        else:
            most_recent[user] = response

        octets = ip.split(".")
        assert len(octets) == 4
        masked_ip = f"{octets[0]}.{octets[1]}.*.*"
        output_lines.append(f"{timestamp},{user},{masked_ip},{response}")
        totals[user] = totals.get(user, 0) + int(response)
        counts[user] = counts.get(user, 0) + 1

    ranked = sorted(totals, key=lambda user: (-totals[user] / counts[user], user))[:3]
    top_lines = [f"{user},{totals[user] / counts[user]:.2f}" for user in ranked]
    return "\n".join(output_lines), "\n".join(top_lines), sorted_rows


def test_c_program_and_pipeline_on_fresh_input():
    rng = random.Random(secrets.randbits(128))
    suffixes = rng.sample(range(100, 999), 6)
    users = [f"R{suffix}" for suffix in suffixes]
    profiles = [
        ["900", "", "900"],
        ["", "600", ""],
        ["500", "500", "500"],
        ["700", "", "700"],
        ["500", "", "500"],
        ["100", "100", "100"],
    ]

    rows = []
    for index, (user, responses) in enumerate(zip(users, profiles)):
        start = rng.randint(1000, 9000)
        timestamps = [start, start + rng.randint(1, 20), start + rng.randint(21, 40)]
        first = rng.randint(1, 223)
        second = rng.randint(0, 255)
        for position, (timestamp, response) in enumerate(zip(timestamps, responses)):
            ip = f"{first}.{second}.{rng.randint(0, 255)}.{rng.randint(1, 254)}"
            rows.append((str(timestamp), user, ip, response))
    rng.shuffle(rows)

    expected_log, expected_top, sorted_rows = expected_outputs(rows)
    sorted_input = "\n".join(",".join(row) for row in sorted_rows) + "\n"

    with tempfile.TemporaryDirectory() as temp_dir:
        test_binary = os.path.join(temp_dir, "process_logs")
        compile_result = subprocess.run(
            ["gcc", "-O2", "/home/user/process_logs.c", "-o", test_binary],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"process_logs.c did not compile:\n{compile_result.stderr}"
        c_result = subprocess.run(
            [test_binary],
            input=sorted_input,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert c_result.returncode == 0, f"Compiled C program failed:\n{c_result.stderr}"
        assert c_result.stdout.strip() == expected_log, "The C program failed masking or per-user imputation on fresh input."

    raw_path = "/home/user/server_logs.csv"
    pipeline_path = "/home/user/run_pipeline.sh"
    binary_path = "/home/user/process_logs"
    with open(raw_path, "rb") as f:
        original_raw = f.read()

    observed_log = None
    observed_top = None
    binary_is_executable = False
    binary_is_elf = False
    try:
        with open(raw_path, "w") as f:
            for row in rows:
                f.write(",".join(row) + "\n")
        if os.path.lexists(binary_path):
            os.remove(binary_path)

        run_result = subprocess.run(
            [pipeline_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
            cwd="/home/user",
        )
        assert run_result.returncode == 0, f"run_pipeline.sh failed on fresh input:\n{run_result.stderr}"

        with open("/home/user/anonymized_logs.csv", "r") as f:
            observed_log = f.read().strip()
        with open("/home/user/top_users.txt", "r") as f:
            observed_top = f.read().strip()
        binary_is_executable = os.path.isfile(binary_path) and os.access(binary_path, os.X_OK)
        if os.path.isfile(binary_path):
            with open(binary_path, "rb") as f:
                binary_is_elf = f.read(4) == b"\x7fELF"
    finally:
        with open(raw_path, "wb") as f:
            f.write(original_raw)
        subprocess.run(
            [pipeline_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
            cwd="/home/user",
            check=True,
        )

    assert observed_log == expected_log, "The pipeline did not sort, mask, and impute fresh input correctly."
    assert observed_top == expected_top, "The pipeline did not calculate and rank fresh per-user averages correctly."
    assert binary_is_executable, "The pipeline did not recreate an executable /home/user/process_logs binary."
    assert binary_is_elf, "The process_logs artifact created by the pipeline is not a compiled executable."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
