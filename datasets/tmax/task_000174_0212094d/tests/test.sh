#!/bin/bash
set -e
mkdir -p /logs/verifier

# Prevent a submission from relying on a daemon started during the agent phase.
pkill -KILL -u user 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import random
import string
import tempfile

ORACLE_PATH = "/app/traffic_oracle"
AGENT_PATH = "/home/user/ids_logic"
SOURCE_PATH = "/home/user/ids_logic.c"
NUM_ITERATIONS = 10000


def generate_valid_pins():
    valid_pins = []
    for d1 in range(10):
        for d2 in range(10):
            for d3 in range(10):
                for d4 in range(10):
                    if (d1 * 11 + d2 * 7 + d3 * 3 + d4) % 100 == 42:
                        valid_pins.append(f"{d1}{d2}{d3}{d4}")
    return valid_pins


VALID_PINS = generate_valid_pins()


def generate_random_input():
    choices = [
        "short",
        "invalid_pin_format",
        "invalid_pin_hash",
        "valid_pin_clean",
        "valid_pin_xss",
        "valid_pin_sqli",
        "completely_random",
    ]
    choice = random.choice(choices)
    printable = string.ascii_letters + string.digits + string.punctuation + " "

    if choice == "short":
        length = random.randint(0, 7)
        return "".join(random.choices(printable, k=length))
    elif choice == "invalid_pin_format":
        prefix = "".join(random.choices(string.ascii_letters, k=4))
        length = random.randint(4, 252)
        return prefix + "".join(random.choices(printable, k=length))
    elif choice == "invalid_pin_hash":
        while True:
            prefix = "".join(random.choices(string.digits, k=4))
            if prefix not in VALID_PINS:
                break
        length = random.randint(4, 252)
        return prefix + "".join(random.choices(printable, k=length))
    elif choice == "valid_pin_clean":
        prefix = random.choice(VALID_PINS)
        length = random.randint(4, 252)
        return prefix + "".join(random.choices(string.ascii_letters, k=length))
    elif choice == "valid_pin_xss":
        prefix = random.choice(VALID_PINS)
        xss = random.choice(["<script>", "javascript:"])
        length = random.randint(4, 252 - len(xss))
        payload = "".join(random.choices(printable, k=length))
        insert_pos = random.randint(0, len(payload))
        return prefix + payload[:insert_pos] + xss + payload[insert_pos:]
    elif choice == "valid_pin_sqli":
        prefix = random.choice(VALID_PINS)
        sqli = random.choice(["UNION SELECT", "' OR '1'='1"])
        length = random.randint(4, 252 - len(sqli))
        payload = "".join(random.choices(printable, k=length))
        insert_pos = random.randint(0, len(payload))
        return prefix + payload[:insert_pos] + sqli + payload[insert_pos:]
    else:
        length = random.randint(0, 256)
        return "".join(random.choices(printable, k=length))


def run_target(executable, arg=None):
    cmd = [executable]
    if arg is not None:
        cmd.append(arg)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "Timeout"


def test_submission():
    assert os.path.exists(AGENT_PATH), f"Missing executable: {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Path is not a file: {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"File is not executable: {AGENT_PATH}"

    source_stat = os.lstat(SOURCE_PATH)
    assert stat.S_ISREG(source_stat.st_mode), f"C source is not a regular file: {SOURCE_PATH}"
    assert source_stat.st_size > 0, f"C source is empty: {SOURCE_PATH}"

    with open(ORACLE_PATH, "rb") as oracle_file, open(AGENT_PATH, "rb") as agent_file:
        assert oracle_file.read() != agent_file.read(), "Submission is byte-identical to the oracle"

    random.seed(42)
    inputs = [generate_random_input() for _ in range(NUM_ITERATIONS)]

    # Obtain all oracle answers first, then remove the oracle before compiling or
    # executing the submitted source. This preserves the differential checks while
    # preventing a wrapper from delegating to /app/traffic_oracle.
    expected_no_arg = run_target(ORACLE_PATH)
    expected = [run_target(ORACLE_PATH, value) for value in inputs]
    os.unlink(ORACLE_PATH)

    fd, rebuilt_path = tempfile.mkstemp(prefix="ids_logic_rebuilt_", dir="/tmp")
    os.close(fd)
    os.unlink(rebuilt_path)
    try:
        build = subprocess.run(
            ["/usr/bin/gcc", "-O2", SOURCE_PATH, "-o", rebuilt_path],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, (
            f"Failed to compile {SOURCE_PATH}:\nstdout: {build.stdout}\nstderr: {build.stderr}"
        )
        assert os.path.isfile(rebuilt_path), "Compiler did not produce an executable"
        assert os.access(rebuilt_path, os.X_OK), "Rebuilt program is not executable"
        os.replace(rebuilt_path, AGENT_PATH)

        o_code, o_out, o_err = expected_no_arg
        a_code, a_out, a_err = run_target(AGENT_PATH)
        assert o_code == a_code, f"Exit code mismatch on no arguments. Oracle: {o_code}, Agent: {a_code}"
        assert o_out == a_out, f"Stdout mismatch on no arguments. Oracle: {o_out!r}, Agent: {a_out!r}"
        assert o_err == a_err, f"Stderr mismatch on no arguments. Oracle: {o_err!r}, Agent: {a_err!r}"

        for i, test_input in enumerate(inputs):
            o_code, o_out, o_err = expected[i]
            a_code, a_out, a_err = run_target(AGENT_PATH, test_input)
            assert o_code == a_code, f"Exit code mismatch on iteration {i}. Input: {test_input!r}\nOracle: {o_code}\nAgent: {a_code}"
            assert o_out == a_out, f"Stdout mismatch on iteration {i}. Input: {test_input!r}\nOracle: {o_out!r}\nAgent: {a_out!r}"
            assert o_err == a_err, f"Stderr mismatch on iteration {i}. Input: {test_input!r}\nOracle: {o_err!r}\nAgent: {a_err!r}"
    finally:
        if os.path.exists(rebuilt_path):
            os.unlink(rebuilt_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
