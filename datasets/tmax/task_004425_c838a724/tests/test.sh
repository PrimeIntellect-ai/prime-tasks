#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import calendar
import datetime
import os
import secrets
import shutil
import stat
import string
import subprocess

import pytest

PARSER_C = "/home/user/parser.c"
PARSER = "/home/user/parser"
PROCESS_SH = "/home/user/process.sh"
RAW = "/home/user/logs/raw_events.jsonl"
OUTPUT = "/home/user/processed_logins.csv"
COMPILED_SOURCE = "/tmp/parser_from_source"


def run(cmd, *, input_text=None, timeout=20):
    return subprocess.run(
        cmd,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
    )


def iso(epoch):
    return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def escaped_user(value):
    return "".join("\\u%04X" % ord(ch) for ch in value)


def record(epoch, event, user):
    return '{"timestamp":"%s","event":"%s","user":"%s"}' % (
        iso(epoch), event, escaped_user(user)
    )


def test_parser_c_exists():
    path = "/home/user/parser.c"
    assert os.path.isfile(path), f"File {path} does not exist. You must create the C program."


def test_parser_executable_exists():
    path = "/home/user/parser"
    assert os.path.isfile(path), f"File {path} does not exist. You must compile the C program."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled executable."


def test_process_sh_exists():
    path = "/home/user/process.sh"
    assert os.path.isfile(path), f"File {path} does not exist. You must create the bash script."


def test_parser_source_and_binary_behavior():
    run(["gcc", "-O2", "-std=gnu11", PARSER_C, "-o", COMPILED_SOURCE])

    token = "".join(secrets.choice(string.ascii_letters) for _ in range(10)) + "!_"
    base = 1700000000 + secrets.randbelow(5000000)
    lines = [
        record(base + 9, "login", token),
        record(base + 2, "logout", "ignored"),
        record(base + 17, "login", "A z~"),
    ]
    expected = f"{base + 9},{token}\n{base + 17},A z~\n"

    for executable in (PARSER, COMPILED_SOURCE):
        result = run([executable], input_text="\n".join(lines) + "\n")
        assert result.stdout == expected, (
            f"{executable} did not parse login events, timestamps, and Unicode escapes correctly. "
            f"stderr: {result.stderr}"
        )


def test_processed_logins_csv_content():
    path = "/home/user/processed_logins.csv"
    assert os.path.isfile(path), f"File {path} does not exist. Your bash script must generate this file."

    os.unlink(path)
    run(["bash", PROCESS_SH], timeout=30)
    assert os.path.isfile(path), f"File {path} does not exist. Your bash script must generate this file."

    expected_content = """1698062400,sysadmin
1698135330,admin!
1698135335,hacker
1698135365,test_user
1698135420,normal
1698195600,zoo"""

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {path} does not match the expected output. Expected:\n{expected_content}\nGot:\n{content}"


def test_process_script_on_derived_input_and_parallel_chunks():
    raw_backup = open(RAW, "rb").read()
    parser_backup = open(PARSER, "rb").read()
    parser_mode = stat.S_IMODE(os.stat(PARSER).st_mode)
    output_existed = os.path.exists(OUTPUT)
    output_backup = open(OUTPUT, "rb").read() if output_existed else None
    invocation_log = "/tmp/parser_invocations.log"

    seed = secrets.randbelow(1000000)
    base = 1710000000 + seed
    rows = []
    expected_rows = []
    for i in range(36):
        epoch = base + i * 7
        username = "u" + secrets.token_hex(4) + "_" + str(i)
        rows.append(record(epoch, "login", username))
        expected_rows.append((epoch, username))
    for i in range(12):
        rows.append(record(base + i * 11 + 3, "logout", "skip" + str(i)))
    secrets.SystemRandom().shuffle(rows)

    wrapper = f'''#!/bin/bash
echo "S,$$" >> {invocation_log}
sleep 0.25
"{COMPILED_SOURCE}" "$@"
status=$?
echo "E,$$" >> {invocation_log}
exit $status
'''.encode()

    try:
        with open(RAW, "w") as f:
            f.write("\n".join(rows) + "\n")
        with open(PARSER, "wb") as f:
            f.write(wrapper)
        os.chmod(PARSER, 0o755)
        if os.path.exists(invocation_log):
            os.unlink(invocation_log)
        if os.path.exists(OUTPUT):
            os.unlink(OUTPUT)
        shutil.rmtree("/home/user/tmp_chunks", ignore_errors=True)
        os.makedirs("/home/user/tmp_chunks", exist_ok=True)

        run(["bash", PROCESS_SH], timeout=45)

        assert os.path.isfile(OUTPUT), "process.sh did not generate processed_logins.csv"
        expected = "\n".join(f"{epoch},{user}" for epoch, user in sorted(expected_rows))
        with open(OUTPUT) as f:
            actual = f.read().strip()
        assert actual == expected, "process.sh did not derive and numerically sort the expected CSV"

        assert os.path.isfile(invocation_log), "process.sh did not invoke /home/user/parser"
        active = set()
        maximum_active = 0
        starts = 0
        with open(invocation_log) as f:
            events = [line.strip().split(",", 1) for line in f if line.strip()]
        for kind, pid in events:
            if kind == "S":
                starts += 1
                active.add(pid)
                maximum_active = max(maximum_active, len(active))
            elif kind == "E":
                active.discard(pid)
        assert starts >= 2, "process.sh did not split the input into multiple parser jobs"
        assert maximum_active >= 2, "process.sh did not run parser jobs in parallel"
    finally:
        with open(RAW, "wb") as f:
            f.write(raw_backup)
        with open(PARSER, "wb") as f:
            f.write(parser_backup)
        os.chmod(PARSER, parser_mode)
        if output_existed:
            with open(OUTPUT, "wb") as f:
                f.write(output_backup)
        elif os.path.exists(OUTPUT):
            os.unlink(OUTPUT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
