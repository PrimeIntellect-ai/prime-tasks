#!/bin/bash
set -e
mkdir -p /logs/verifier

original_auth=$(mktemp)
cp /home/user/auth_sys.log "$original_auth"
trap 'cp "$original_auth" /home/user/auth_sys.log; rm -f "$original_auth"' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import uuid

AUTH = "/home/user/auth_sys.log"
CSV = "/home/user/hourly_failures.csv"
SOURCE = "/home/user/parser.c"
SCRIPT = "/home/user/run_parser.sh"
BINARY = "/home/user/parser"

ORIGINAL_FIXTURE = """[2023-10-24 14:15:00] Event: FAILED_LOGIN User: Admin_2 IP: 192.168.1.50 Msg: Bad password
[2023-10-24 14:35:12] Event: FAILED_LOGIN User: ADMIN_2 IP: 192.168.1.50 Msg: Bad password
[2023-10-24 14:45:00] Event: SUCCESS_LOGIN User: Admin_2 IP: 192.168.1.50 Msg: Success
[2023-10-24 14:50:00] Event: FAILED_LOGIN User: Bo IP: 10.0.0.1 Msg: User too short
[2023-10-24 14:51:00] Event: FAILED_LOGIN User: Toolongusername_123 IP: 10.0.0.1 Msg: User too long
[2023-10-24 14:55:00] Event: FAILED_LOGIN User: Invalid@User IP: 10.0.0.1 Msg: Invalid chars
[2023-10-24 15:05:00] Event: FAILED_LOGIN User: Valid_User IP: 999.999.999.999 Msg: Valid format IP
[2023-10-24 15:10:00] Event: FAILED_LOGIN User: Valid_User IP: 10.0.0.a Msg: Invalid format IP
[2023-10-24 15:15:00] Event: FAILED_LOGIN User: Valid_User IP: 10.0.0.1.5 Msg: Invalid format IP
[2023-10-24 16:01:00] Event: FAILED_LOGIN User: Bob IP: 10.0.0.2 Msg: Failed
[2023-10-24 16:05:00] Event: FAILED_LOGIN User: bob IP: 10.0.0.2 Msg: Failed
[2023-10-24 16:10:00] Event: FAILED_LOGIN User: alice IP: 192.168.0.1 Msg: Failed
"""


def read_csv():
    assert os.path.exists(CSV), f"Output file {CSV} is missing."
    with open(CSV, "r") as f:
        return [line.strip() for line in f if line.strip()]


def run(command):
    return subprocess.run(command, check=True, text=True, capture_output=True, timeout=20)


def test_parser_source_and_pipeline_run_on_original_fixture():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} is missing."
    with open(AUTH, "w") as f:
        f.write(ORIGINAL_FIXTURE)
    for path in (BINARY, CSV):
        if os.path.exists(path):
            os.remove(path)
    run([SCRIPT])
    assert os.path.isfile(BINARY), f"Pipeline did not create {BINARY}."
    assert os.access(BINARY, os.X_OK), f"Compiled parser {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled native executable."


def test_hourly_failures_csv_content():
    csv_path = "/home/user/hourly_failures.csv"
    assert os.path.exists(csv_path), f"Output file {csv_path} is missing."

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "2023-10-24 14:00:00,192.168.1.50,admin_2,2",
        "2023-10-24 15:00:00,999.999.999.999,valid_user,1",
        "2023-10-24 16:00:00,10.0.0.2,bob,2",
        "2023-10-24 16:00:00,192.168.0.1,alice,1"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {csv_path}, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch in {csv_path}.\nExpected: {expected}\nActual:   {actual}"


def test_run_parser_sh_executable():
    script_path = "/home/user/run_parser.sh"
    assert os.path.exists(script_path), f"Script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable (+x)."


def test_log_cron_configuration():
    cron_path = "/home/user/log_cron"
    assert os.path.exists(cron_path), f"Cron configuration file {cron_path} is missing."

    with open(cron_path, "r") as f:
        content = f.read()

    valid_cron_pattern = re.compile(r"^0\s+\*\s+\*\s+\*\s+\*.*", re.MULTILINE)

    assert valid_cron_pattern.search(content), (
        f"File {cron_path} does not contain the correct cron expression ('0 * * * *').\n"
        f"Found content:\n{content}"
    )
    command_pattern = re.compile(
        r"^\s*0\s+\*\s+\*\s+\*\s+\*\s+/home/user/run_parser\.sh\s*$",
        re.MULTILINE,
    )
    assert command_pattern.search(content), (
        "The hourly cron entry must execute /home/user/run_parser.sh.\n"
        f"Found content:\n{content}"
    )


def test_c_program_and_pipeline_on_runtime_generated_input():
    token = uuid.uuid4().hex
    user = "U" + token[:7]
    other = "Zed_" + token[7:12]
    ip1 = f"10.{int(token[12:14], 16)}.{int(token[14:16], 16)}.7"
    ip2 = f"172.16.{int(token[16:18], 16)}.9"

    records = [
        ("2031-07-08 09:58:59", "FAILED_LOGIN", user, ip1),
        ("2031-07-08 09:01:02", "FAILED_LOGIN", user.swapcase(), ip1),
        ("2031-07-08 09:30:00", "FAILED_LOGIN", other, ip2),
        ("2031-07-08 08:59:59", "FAILED_LOGIN", "Bob_7", "999.1.2.3"),
        ("2031-07-08 09:10:00", "SUCCESS_LOGIN", "Ignored", "1.2.3.4"),
        ("2031-07-08 09:11:00", "FAILED_LOGIN", "ab", "1.2.3.4"),
        ("2031-07-08 09:12:00", "FAILED_LOGIN", "abcdefghijklmnop", "1.2.3.4"),
        ("2031-07-08 09:13:00", "FAILED_LOGIN", "Bad@Name", "1.2.3.4"),
        ("2031-07-08 09:14:00", "FAILED_LOGIN", "Valid_1", "1.2.3.4.5"),
        ("2031-07-08 09:15:00", "FAILED_LOGIN", "Valid_2", "1.2.3.a"),
    ]
    with open(AUTH, "w") as f:
        for timestamp, event, username, ip in records:
            f.write(f"[{timestamp}] Event: {event} User: {username} IP: {ip} Msg: generated {token}\n")

    counts = {}
    for timestamp, event, username, ip in records[:4]:
        key = (timestamp[:13] + ":00:00", ip, username.lower())
        counts[key] = counts.get(key, 0) + 1
    expected = [f"{bucket},{ip},{username},{count}" for (bucket, ip, username), count in sorted(counts.items())]

    candidate = "/tmp/submission_parser"
    run(["gcc", SOURCE, "-o", candidate])
    if os.path.exists(CSV):
        os.remove(CSV)
    run([candidate])
    assert read_csv() == expected, "The independently compiled parser.c failed generated input."

    for path in (BINARY, CSV):
        if os.path.exists(path):
            os.remove(path)
    run([SCRIPT])
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "run_parser.sh did not compile the parser."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "run_parser.sh did not produce a compiled native parser."
    assert read_csv() == expected, "run_parser.sh did not run the parser correctly on generated input."

    extra_time = "2031-07-08 10:00:01"
    with open(AUTH, "a") as f:
        f.write(f"[{extra_time}] Event: FAILED_LOGIN User: {user} IP: {ip1} Msg: direct binary test\n")
    expected.append(f"2031-07-08 10:00:00,{ip1},{user.lower()},1")
    run([BINARY])
    assert read_csv() == expected, "The executable produced by run_parser.sh does not process changed input."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
