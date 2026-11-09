#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import socket
import subprocess
import threading

ORACLE_PATH = "/app/legacy_processor"
AGENT_SCRIPT = "/home/user/new_processor.py"
CHECK_SCRIPT = "/home/user/check_and_run.sh"
LOGROTATE_CONF = "/home/user/logrotate.conf"
REPO_DIR = "/home/user/migration_repo"
PRE_COMMIT_HOOK = os.path.join(REPO_DIR, ".git/hooks/pre-commit")
INCOMING_DIR = "/home/user/incoming_logs"
PROCESSED_DIR = "/home/user/processed"


def run_processor(command, data):
    proc = subprocess.run(command, input=data, capture_output=True, timeout=10)
    assert proc.returncode == 0, f"Processor failed for input {data[:100]!r}: {proc.stderr!r}"
    return proc.stdout


def oracle_output(data):
    return run_processor([ORACLE_PATH], data)


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Missing agent script at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_PATH), f"Missing oracle binary at {ORACLE_PATH}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Script is not executable: {AGENT_SCRIPT}"

    charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !@#$%^&*()_+-=[]{}|;':,./<>?"
    random.seed(42)

    for _ in range(1000):
        length = random.randint(1, 1000)
        input_str = "".join(random.choices(charset, k=length))
        input_bytes = input_str.encode("utf-8")

        oracle_out = run_processor([ORACLE_PATH], input_bytes)
        agent_out = run_processor(["python3", AGENT_SCRIPT], input_bytes)

        assert oracle_out == agent_out, (
            f"Output mismatch for input: {input_str!r}\n"
            f"Oracle output: {oracle_out!r}\n"
            f"Agent output: {agent_out!r}"
        )

    # Exercise empty input, line-oriented input, UTF-8, every byte value, NULs,
    # invalid UTF-8, and deterministic arbitrary binary streams.
    binary_cases = [
        b"",
        b"\n",
        b"first line\nSecond 123\r\nthird\n",
        "héllö 世界 Καλημέρα\n".encode("utf-8"),
        bytes(range(256)),
        bytes(range(255, -1, -1)),
        b"\x00A9z\xff\x80\n\r\x00",
    ]
    rng = random.Random(8675309)
    for length in [1, 2, 3, 7, 31, 255, 256, 1024, 4096]:
        binary_cases.append(bytes(rng.randrange(256) for _ in range(length)))
    for _ in range(40):
        length = rng.randint(0, 4096)
        binary_cases.append(bytes(rng.randrange(256) for _ in range(length)))

    for input_bytes in binary_cases:
        oracle_out = run_processor([ORACLE_PATH], input_bytes)
        agent_out = run_processor(["python3", AGENT_SCRIPT], input_bytes)
        assert oracle_out == agent_out, (
            f"Binary output mismatch for input {input_bytes[:100]!r}; "
            f"oracle={oracle_out[:100]!r}, agent={agent_out[:100]!r}"
        )

    # The executable script itself must also work, not only when passed to Python.
    direct_input = b"Direct execution 019\n\xff\x00"
    assert run_processor([AGENT_SCRIPT], direct_input) == oracle_output(direct_input)


def test_check_and_run_script_port_closed():
    assert os.path.isfile(CHECK_SCRIPT), f"Missing script at {CHECK_SCRIPT}"
    assert os.access(CHECK_SCRIPT, os.X_OK), f"Script is not executable: {CHECK_SCRIPT}"

    # Verify that the port can be bound and then close it, leaving it unreachable.
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    probe.bind(("127.0.0.1", 8080))
    probe.close()

    error_log = os.path.join(PROCESSED_DIR, "error.log")
    os.makedirs(PROCESSED_DIR, exist_ok=True)
    prefix = b"existing error data\n"
    with open(error_log, "wb") as f:
        f.write(prefix)

    res = subprocess.run([CHECK_SCRIPT], shell=True, executable="/bin/bash", timeout=15)
    assert res.returncode == 0, f"Connectivity script failed with status {res.returncode}"

    assert os.path.exists(error_log), f"Missing error log: {error_log}"
    with open(error_log, "rb") as f:
        content_bytes = f.read()
    content = content_bytes.decode("utf-8", errors="replace")
    assert "ERROR: Port 8080 unreachable" in content, "Error log does not contain correct message"

    appended = content_bytes[len(prefix):]
    assert appended in (
        b"ERROR: Port 8080 unreachable",
        b"ERROR: Port 8080 unreachable\n",
    ), f"Closed-port branch appended unexpected data: {appended!r}"
    assert content_bytes.startswith(prefix), "Closed-port branch did not append to the existing error log"


def test_check_and_run_script_port_open():
    assert os.path.isfile(CHECK_SCRIPT), f"Missing script at {CHECK_SCRIPT}"
    assert os.access(CHECK_SCRIPT, os.X_OK), f"Script is not executable: {CHECK_SCRIPT}"

    shutil.rmtree(INCOMING_DIR, ignore_errors=True)
    os.makedirs(INCOMING_DIR, exist_ok=True)
    os.makedirs(PROCESSED_DIR, exist_ok=True)

    payload_a = b"Alpha 012\nsecond LINE\n\x00\xff"
    payload_b = "Migration héllo 987\n".encode("utf-8")
    with open(os.path.join(INCOMING_DIR, "a.log"), "wb") as f:
        f.write(payload_a)
    with open(os.path.join(INCOMING_DIR, "b.log"), "wb") as f:
        f.write(payload_b)
    with open(os.path.join(INCOMING_DIR, "ignored.txt"), "wb") as f:
        f.write(b"THIS MUST NOT BE PROCESSED 123")

    master_log = os.path.join(PROCESSED_DIR, "master.log")
    prefix = b"existing master data\n"
    with open(master_log, "wb") as f:
        f.write(prefix)

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 8080))
    server.listen(8)
    stop = threading.Event()

    def accept_conn():
        server.settimeout(0.2)
        while not stop.is_set():
            try:
                conn, _ = server.accept()
                conn.close()
            except socket.timeout:
                continue
            except OSError:
                break

    t = threading.Thread(target=accept_conn)
    t.start()

    try:
        res = subprocess.run([CHECK_SCRIPT], shell=True, executable="/bin/bash", timeout=20)
    finally:
        stop.set()
        server.close()
        t.join(timeout=5)

    assert res.returncode == 0, f"Connectivity script failed with status {res.returncode}"
    assert os.path.exists(master_log), f"Missing master log: {master_log}"

    with open(master_log, "rb") as f:
        actual = f.read()
    transformed_a = oracle_output(payload_a)
    transformed_b = oracle_output(payload_b)
    valid_outputs = {
        prefix + transformed_a + transformed_b,
        prefix + transformed_b + transformed_a,
    }
    assert actual in valid_outputs, (
        "master.log did not contain exactly the appended transformed contents of all .log files; "
        f"actual={actual!r}, expected one of {valid_outputs!r}"
    )


def test_logrotate_conf():
    assert os.path.isfile(LOGROTATE_CONF), f"Missing logrotate.conf at {LOGROTATE_CONF}"
    with open(LOGROTATE_CONF, "r") as f:
        content = f.read().lower()

    # Preserve the original assertions.
    assert "daily" in content, "Missing 'daily' directive in logrotate.conf"
    assert "rotate 7" in content, "Missing 'rotate 7' directive in logrotate.conf"
    assert "compress" in content, "Missing 'compress' directive in logrotate.conf"
    assert "delaycompress" in content, "Missing 'delaycompress' directive in logrotate.conf"
    assert "missingok" in content, "Missing 'missingok' directive in logrotate.conf"

    # Comments do not count as directives. Locate a stanza that targets the
    # processed directory and combine it with any valid global directives.
    uncommented = re.sub(r"#.*$", "", content, flags=re.MULTILINE)
    first_brace = uncommented.find("{")
    globals_text = uncommented[:first_brace] if first_brace >= 0 else uncommented
    blocks = re.findall(r"([^{}\n]*?/home/user/processed/[^{}\n]*)\{([^{}]*)\}", uncommented, re.DOTALL)
    assert blocks, "No logrotate stanza manages files in /home/user/processed/"

    directive_patterns = {
        "daily": r"(?m)^\s*daily\s*$",
        "rotate 7": r"(?m)^\s*rotate\s+7\s*$",
        "compress": r"(?m)^\s*compress\s*$",
        "delaycompress": r"(?m)^\s*delaycompress\s*$",
        "missingok": r"(?m)^\s*missingok\s*$",
    }
    matching = []
    for selector, body in blocks:
        effective = globals_text + "\n" + body
        if all(re.search(pattern, effective) for pattern in directive_patterns.values()):
            matching.append((selector, body))
    assert matching, "Required directives are not active for logs in /home/user/processed/"

    # Have logrotate itself parse the configuration and confirm that a real log
    # in the requested directory is selected by it.
    os.makedirs(PROCESSED_DIR, exist_ok=True)
    probe_log = os.path.join(PROCESSED_DIR, "verifier_probe.log")
    with open(probe_log, "w") as f:
        f.write("probe data\n")
    state_file = "/tmp/verifier-logrotate.state"
    if os.path.exists(state_file):
        os.remove(state_file)
    parsed = subprocess.run(
        ["logrotate", "--debug", "--state", state_file, LOGROTATE_CONF],
        capture_output=True,
        text=True,
        timeout=15,
    )
    parsed_output = parsed.stdout + parsed.stderr
    assert parsed.returncode == 0, f"logrotate rejected the configuration:\n{parsed_output}"
    assert probe_log in parsed_output, "logrotate configuration does not select processed .log files"


def test_git_pre_commit_hook():
    assert os.path.isdir(REPO_DIR), f"Missing git repo at {REPO_DIR}"
    assert os.path.isdir(os.path.join(REPO_DIR, ".git")), f"Not a git repository: {REPO_DIR}"
    assert os.path.isfile(PRE_COMMIT_HOOK), f"Missing pre-commit hook at {PRE_COMMIT_HOOK}"
    assert os.access(PRE_COMMIT_HOOK, os.X_OK), f"pre-commit hook is not executable"

    test_file_valid = os.path.join(REPO_DIR, "test_valid.py")
    with open(test_file_valid, "w") as f:
        f.write("print('Hello World')\n")

    subprocess.run(["git", "add", "test_valid.py"], cwd=REPO_DIR, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=REPO_DIR)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=REPO_DIR)

    res_valid = subprocess.run(["git", "commit", "-m", "Valid commit"], cwd=REPO_DIR, capture_output=True, text=True)
    assert res_valid.returncode == 0, f"Valid commit was rejected: {res_valid.stderr}"

    test_file_invalid = os.path.join(REPO_DIR, "test_invalid.py")
    with open(test_file_invalid, "w") as f:
        f.write("DEBUG_MODE=True\n")

    subprocess.run(["git", "add", "test_invalid.py"], cwd=REPO_DIR, check=True)
    res_invalid = subprocess.run(["git", "commit", "-m", "Invalid commit"], cwd=REPO_DIR, capture_output=True, text=True)

    assert res_invalid.returncode == 1, "Commit with DEBUG_MODE=True was not rejected"
    assert "No debug code allowed!" in res_invalid.stdout or "No debug code allowed!" in res_invalid.stderr, "Hook did not print the correct error message"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
