#!/bin/bash
set -e
mkdir -p /logs/verifier

# The original binary was available to the agent for analysis, but must not be
# available when the replacement is executed by the verifier.
rm -f /app/net_health_checker

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shlex
import string
import subprocess
import tempfile

AGENT_SCRIPT = "/home/user/net_health_checker.py"
LOGROTATE_CONF = "/home/user/logrotate.d/net_health"


def generate_random_ip():
    return ".".join(str(random.randint(0, 255)) for _ in range(4))


def generate_random_timestamp():
    year = random.randint(2020, 2024)
    month = random.randint(1, 12)
    day = random.randint(1, 28)
    hour = random.randint(0, 23)
    minute = random.randint(0, 59)
    second = random.randint(0, 59)
    return f"{year}-{month:02d}-{day:02d}T{hour:02d}:{minute:02d}:{second:02d}Z"


def generate_random_log_file(path, num_lines):
    statuses = ["SUCCESS", "TIMEOUT", "REFUSED", "ERROR", "PENDING"]
    with open(path, "w") as f:
        for _ in range(num_lines):
            if random.random() < 0.1:
                f.write("".join(random.choices(string.ascii_letters + string.digits + " []-:", k=random.randint(10, 50))) + "\n")
            else:
                timestamp = generate_random_timestamp()
                ip = generate_random_ip()
                port = random.randint(1, 65535)
                status = random.choice(statuses)
                f.write(f"[{timestamp}] {ip} {port} {status}\n")


def scan_conversion(line, pos, scanset=False):
    if scanset:
        start = pos
        while pos < len(line) and line[pos] != "]" and pos - start < 255:
            pos += 1
        if pos == start:
            return None, pos
        return line[start:pos], pos

    while pos < len(line) and line[pos].isspace():
        pos += 1
    start = pos
    while pos < len(line) and not line[pos].isspace() and pos - start < 255:
        pos += 1
    if pos == start:
        return None, pos
    return line[start:pos], pos


def parsed_status(line):
    # Model sscanf(line, "[%255[^]]] %255s %255s %255s", ...).
    if not line.startswith("["):
        return None
    pos = 1
    timestamp, pos = scan_conversion(line, pos, scanset=True)
    if timestamp is None or pos >= len(line) or line[pos] != "]":
        return None
    pos += 1

    fields = []
    for _ in range(3):
        while pos < len(line) and line[pos].isspace():
            pos += 1
        field, pos = scan_conversion(line, pos)
        if field is None:
            return None
        fields.append(field)
    return fields[2]


def expected_for_file(path):
    total = 0
    success = 0
    timeout = 0
    with open(path, "r", encoding="ascii") as f:
        for line in f:
            total += 1
            status = parsed_status(line)
            if status == "SUCCESS":
                success += 1
            elif status == "TIMEOUT":
                timeout += 1

    score = (success * 100) // total if total else 0
    stdout = (
        f"Total: {total}\n"
        f"Success: {success}\n"
        f"Timeout: {timeout}\n"
        f"Health Score: {score}%\n"
    )
    return 0, stdout, ""


def test_logrotate_config():
    assert os.path.exists(LOGROTATE_CONF), f"Logrotate config missing at {LOGROTATE_CONF}"
    with open(LOGROTATE_CONF, "r") as f:
        content = f.read()

    # Parse blocks rather than accepting required words in comments or decoys.
    blocks = []
    current_header = None
    current_body = []
    for raw_line in content.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        if current_header is None:
            if line.endswith("{"):
                current_header = line[:-1].strip()
                current_body = []
        elif line == "}":
            blocks.append((current_header, current_body))
            current_header = None
            current_body = []
        else:
            current_body.append(line)

    assert current_header is None, "Unclosed logrotate block"
    target_blocks = [body for header, body in blocks if shlex.split(header) == ["/var/log/net_health.log"]]
    assert target_blocks, "Logrotate config does not target /var/log/net_health.log"

    directives = [shlex.split(line) for line in target_blocks[0]]
    assert ["daily"] in directives, "Logrotate config missing 'daily'"
    assert ["rotate", "7"] in directives, "Logrotate config missing 'rotate 7'"
    assert ["compress"] in directives, "Logrotate config missing 'compress'"
    assert any(parts[:2] == ["create", "0644"] for parts in directives), "Logrotate config missing 'create 0644'"

    # Have logrotate itself validate the complete configuration syntax.
    os.makedirs("/var/log", exist_ok=True)
    open("/var/log/net_health.log", "a").close()
    result = subprocess.run(
        ["logrotate", "--debug", "--state", "/tmp/net_health_logrotate.state", LOGROTATE_CONF],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Invalid logrotate configuration:\n{result.stdout}{result.stderr}"


def test_agent_script_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable"


def run_program(executable, arg):
    cmd = ["python3", executable, arg]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Timeout"


def test_fuzz_equivalence():
    assert not os.path.exists("/app/net_health_checker"), "Oracle remained available during agent execution"
    random.seed(42)

    oracle_code, oracle_out, oracle_err = 1, "", "ERROR: File not found\n"
    agent_code, agent_out, agent_err = run_program(AGENT_SCRIPT, "/non_existent_file.log")
    assert agent_code == oracle_code, f"Exit code mismatch on non-existent file. Oracle: {oracle_code}, Agent: {agent_code}"
    assert agent_out == oracle_out, "Stdout mismatch on non-existent file."
    assert agent_err == oracle_err, "Stderr mismatch on non-existent file."

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(100):
            num_lines = random.randint(0, 1000)
            log_path = os.path.join(tmpdir, f"test_{i}.log")
            generate_random_log_file(log_path, num_lines)

            oracle_code, oracle_out, oracle_err = expected_for_file(log_path)
            agent_code, agent_out, agent_err = run_program(AGENT_SCRIPT, log_path)

            assert agent_code == oracle_code, f"Exit code mismatch on test {i} (lines: {num_lines}). Oracle: {oracle_code}, Agent: {agent_code}"
            assert agent_out == oracle_out, f"Stdout mismatch on test {i} (lines: {num_lines}).\nOracle:\n{oracle_out}\nAgent:\n{agent_out}"
            assert agent_err == oracle_err, f"Stderr mismatch on test {i} (lines: {num_lines}).\nOracle:\n{oracle_err}\nAgent:\n{agent_err}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
