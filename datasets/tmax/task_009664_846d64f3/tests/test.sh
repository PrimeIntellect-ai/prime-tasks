#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import subprocess
import tempfile

CRACKER = "/home/user/cracker.go"
SCRIPT = "/home/user/secure_audit.sh"
SERVER = "/home/user/auth_server.go"
LOG = "/home/user/audit_trail.log"
TARGET = "78ea7f858fa3914a844fcbfd70a41f6e2fde431522f1c84f686940a831e3d6e5"
ORIGINAL_TOKEN = "COMPLIANCE_TOKEN_A8F92C"


def derive_pin(target):
    for number in range(10000):
        pin = f"{number:04d}"
        digest = hashlib.sha256(("audit_salt_" + pin).encode()).hexdigest()
        if digest == target:
            return pin
    raise AssertionError("No four-digit PIN matches the configured target hash")


def run(command, timeout=90, env=None):
    result = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        env=env,
    )
    assert result.returncode == 0, (
        f"Command {command!r} failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def assert_output_contains_pin(output, pin):
    pins = re.findall(r"(?<![0-9])[0-9]{4}(?![0-9])", output)
    assert pin in pins, f"Cracker output did not contain recovered PIN {pin!r}. Output was: {output!r}"


def read_log():
    assert os.path.isfile(LOG), f"File {LOG} does not exist. The audit trail log was not generated."
    with open(LOG, "r") as handle:
        return handle.read().splitlines()


def test_00_execute_cracker_and_audit_script():
    assert os.path.isfile(CRACKER), f"File {CRACKER} does not exist. The Go cracker program is missing."
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} does not exist. The bash script is missing."
    assert os.path.isfile(SERVER), f"Provided service source {SERVER} is missing."

    run(["bash", "-n", SCRIPT])

    expected_pin = derive_pin(TARGET)

    # Execute the submitted cracker itself against the required target.
    original_result = run(["go", "run", CRACKER], timeout=60)
    assert_output_contains_pin(original_result.stdout + "\n" + original_result.stderr, expected_pin)

    # Exercise the brute-force implementation against a verifier-chosen target,
    # rather than accepting a program which merely prints the known answer.
    dynamic_pin = f"{secrets.randbelow(10000):04d}"
    while dynamic_pin == expected_pin:
        dynamic_pin = f"{secrets.randbelow(10000):04d}"
    dynamic_hash = hashlib.sha256(("audit_salt_" + dynamic_pin).encode()).hexdigest()

    with open(CRACKER, "r") as handle:
        cracker_source = handle.read()
    assert TARGET in cracker_source, "cracker.go does not contain the target hash it was asked to brute-force."

    with tempfile.TemporaryDirectory() as directory:
        exercised_cracker = os.path.join(directory, "cracker.go")
        with open(exercised_cracker, "w") as handle:
            handle.write(cracker_source.replace(TARGET, dynamic_hash))
        dynamic_result = run(["go", "run", exercised_cracker], timeout=60)
        assert_output_contains_pin(
            dynamic_result.stdout + "\n" + dynamic_result.stderr,
            dynamic_pin,
        )

    with open(SCRIPT, "r") as handle:
        script_source = handle.read()
    normalized_script = script_source.replace("\\\n", " ")
    assert re.search(r"(?:^|[ /])unshare\s+-U\s+-r\s+-n(?:\s|$)", normalized_script, re.M), \
        "secure_audit.sh must invoke unshare -U -r -n."
    assert "127.0.0.1:8080/verify" in script_source, \
        "secure_audit.sh does not request the service's /verify endpoint."
    assert re.search(r"\bcurl\b", script_source), "secure_audit.sh must use curl."
    assert re.search(r"\bgo\s+run\s+/home/user/auth_server\.go\b", normalized_script), \
        "secure_audit.sh must start the provided service with go run."
    assert re.search(r"(?:\bip\b[^\n;]*\blo\b[^\n;]*\bup\b|\bifconfig\s+lo\s+up\b)", normalized_script), \
        "secure_audit.sh must bring up the isolated loopback interface."

    # Change only the service's response token for the first execution. A fresh,
    # unpredictable response proves the log was produced by executing the script
    # and interacting with the service, rather than being a prewritten answer.
    with open(SERVER, "r") as handle:
        server_source = handle.read()
    assert TARGET in server_source, "The provided service's target hash was modified."
    assert ORIGINAL_TOKEN in server_source, "The provided service's compliance token was modified."

    dynamic_token = "VERIFIER_" + secrets.token_hex(16)
    try:
        with open(SERVER, "w") as handle:
            handle.write(server_source.replace(ORIGINAL_TOKEN, dynamic_token))
        if os.path.exists(LOG):
            os.remove(LOG)
        run(["bash", SCRIPT], timeout=120)
        lines = read_log()
        assert len(lines) >= 2, f"Expected at least 2 lines in {LOG}, found {len(lines)}."
        assert lines[0].strip() == expected_pin
        assert json.loads(lines[1].strip()) == {
            "status": "success",
            "token": dynamic_token,
        }, "The script did not capture the fresh raw response from the executed service."
    finally:
        with open(SERVER, "w") as handle:
            handle.write(server_source)

    # Run once more with the original service so the original final-state checks
    # remain applicable.
    if os.path.exists(LOG):
        os.remove(LOG)
    run(["bash", SCRIPT], timeout=120)


def test_audit_trail_log_exists_and_correct():
    log_path = "/home/user/audit_trail.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. The audit trail log was not generated."

    with open(log_path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) >= 2, f"Expected at least 2 lines in {log_path}, found {len(lines)}."

    line1 = lines[0].strip()
    line2 = lines[1].strip()

    assert line1 == "5192", f"Line 1 of {log_path} is incorrect. Expected '5192', got '{line1}'."

    expected_json = {"status": "success", "token": "COMPLIANCE_TOKEN_A8F92C"}
    try:
        actual_json = json.loads(line2)
    except json.JSONDecodeError:
        assert False, f"Line 2 of {log_path} is not valid JSON. Got: '{line2}'"

    assert actual_json == expected_json, f"Line 2 JSON is incorrect. Expected {expected_json}, got {actual_json}."


def test_cracker_go_exists():
    path = "/home/user/cracker.go"
    assert os.path.isfile(path), f"File {path} does not exist. The Go cracker program is missing."


def test_secure_audit_sh_exists():
    path = "/home/user/secure_audit.sh"
    assert os.path.isfile(path), f"File {path} does not exist. The bash script is missing."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
