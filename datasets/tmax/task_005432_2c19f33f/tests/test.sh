#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import uuid

BAD_LINE = "2023-10-01 12:00:03 [ERROR] \"SELECT * FROM orders WHERE user_id = 12345 AND status = 'pending' AND created_at > '2023-01-01'\""
SERVER_LOG = "/home/user/server.log"


def expected_stdout(log_text):
    output = []
    for line in log_text.splitlines():
        start = line.find('"')
        end = line.rfind('"')
        if start != -1 and start != end:
            output.append(f"Processed query: {line[start + 1:end]}\n")
    return "".join(output)


def run_program(exe_path, log_text):
    original_log = open(SERVER_LOG, "rb").read()
    try:
        with open(SERVER_LOG, "w", encoding="utf-8", newline="") as f:
            f.write(log_text)
        proc = subprocess.run(
            [exe_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
    finally:
        with open(SERVER_LOG, "wb") as f:
            f.write(original_log)

    assert proc.returncode == 0, (
        f"Execution failed or crashed. Return code: {proc.returncode}\n"
        f"Stderr: {proc.stderr}"
    )
    assert proc.stdout == expected_stdout(log_text), (
        "Program produced incorrect stdout.\n"
        f"Expected: {expected_stdout(log_text)!r}\n"
        f"Actual:   {proc.stdout!r}"
    )


def test_bad_line_txt():
    path = "/home/user/bad_line.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8", newline="") as f:
        content = f.read()

    assert BAD_LINE in content, f"{path} does not contain the correct offending log line."
    assert content in (BAD_LINE, BAD_LINE + "\n"), (
        f"{path} must contain exactly the single raw offending log line."
    )


def test_fixed_c_compiles_and_processes_logs(tmp_path):
    src_path = "/home/user/log_processor_fixed.c"
    assert os.path.isfile(src_path), f"File {src_path} does not exist."
    assert stat.S_ISREG(os.stat(src_path, follow_symlinks=False).st_mode), (
        f"File {src_path} must be a regular C source file."
    )

    exe_path = str(tmp_path / "log_processor_fixed")
    compile_proc = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-o", exe_path, src_path],
        capture_output=True,
        text=True,
    )
    assert compile_proc.returncode == 0, f"Compilation failed:\n{compile_proc.stderr}"

    with open(SERVER_LOG, "r", encoding="utf-8", newline="") as f:
        original_text = f.read()
    run_program(exe_path, original_text)

    token = uuid.uuid4().hex
    long_query = "SELECT " + (token + "_") * 4 + "FROM generated_table"
    generated_log = (
        "generated line without a query\n"
        "generated line with only one quote \"\n"
        f"2099-01-01 00:00:00 [INFO] \"SELECT '{token}' AS marker\"\n"
        f"2099-01-01 00:00:01 [ERROR] \"{long_query}\"\n"
        f"2099-01-01 00:00:02 [INFO] \"UPDATE t SET value='{token}'\"\n"
    )
    run_program(exe_path, generated_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
