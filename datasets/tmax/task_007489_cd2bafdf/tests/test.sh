#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/anonymize.sh"

EMAIL_RE = re.compile(r"[-A-Za-z0-9._+]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}")
PHONE_RE = re.compile(r"(?:[0-9]{3}-[0-9]{3}-[0-9]{4}|\([0-9]{3}\) [0-9]{3}-[0-9]{4})")

def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

def test_script_execution_and_output():
    test_input = """  User ALICE reached out at Alice.Smith+123@domain.com for support.  
Call me at 555-123-4567 regarding the server issue.
  user alice reached out at alice.smith+123@domain.com for support.
Contact billing at (800) 555-9999 or admin@corp.net immediately!


We need more RAM.
we need more ram.  
"""

    expected_output = """call me at [phone] regarding the server issue.
contact billing at [phone] or [email] immediately!
user alice reached out at [email] for support.
we need more ram.
"""

    with tempfile.NamedTemporaryFile(mode="w", delete=False) as infile:
        infile.write(test_input)
        in_path = infile.name

    out_path = in_path + "_out"

    try:
        result = subprocess.run(
            [SCRIPT_PATH, in_path, out_path],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Script failed with return code {result.returncode}.\nStderr: {result.stderr}"

        assert os.path.exists(out_path), "Script did not create the output file."

        with open(out_path, "r") as f:
            actual_output = f.read()

        assert actual_output == expected_output, (
            f"Output file content does not match expected.\n"
            f"Expected:\n{expected_output}\n"
            f"Actual:\n{actual_output}"
        )
    finally:
        if os.path.exists(in_path):
            os.remove(in_path)
        if os.path.exists(out_path):
            os.remove(out_path)

def oracle(raw):
    normalized = []
    for line in raw.splitlines():
        line = line.lower().strip()
        if not line:
            continue
        line = EMAIL_RE.sub("[email]", line)
        line = PHONE_RE.sub("[phone]", line)
        normalized.append(line)
    return "\n".join(sorted(set(normalized))) + "\n"

def run_dynamic_case(raw, directory, case_name):
    input_path = os.path.join(directory, f"{case_name}.input")
    output_path = os.path.join(directory, f"{case_name}.result")
    with open(input_path, "w", encoding="utf-8") as f:
        f.write(raw)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("stale output that must be replaced\n")

    env = os.environ.copy()
    env["LC_ALL"] = "C"
    result = subprocess.run(
        [SCRIPT_PATH, input_path, output_path],
        capture_output=True,
        text=True,
        timeout=10,
        env=env,
    )
    assert result.returncode == 0, (
        f"Dynamic case {case_name} failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.isfile(output_path), f"Dynamic case {case_name} did not create its output file."
    with open(output_path, "r", encoding="utf-8") as f:
        actual = f.read()
    expected = oracle(raw)
    assert actual == expected, (
        f"Dynamic case {case_name} produced incorrect output.\n"
        f"Expected:\n{expected}\nActual:\n{actual}"
    )

def test_generated_inputs_multiple_matches_dedup_and_sorting():
    nonce = secrets.token_hex(8)
    first = f"agent.{nonce}+one@Example-Domain.COM"
    second = f"backup_{nonce}@Support{nonce}.NET"

    case_one = f"""\t  Zeta {nonce}: email {first}, then {second}; phones 321-654-0987 and (765) 432-1098.   

  Alpha {nonce} duplicate: FIRST-{nonce}@host.io / 111-222-3333  
alpha {nonce} duplicate: second_{nonce}@other.org / (444) 555-6666
\tMixed CASE and trailing whitespace {nonce}\t
Not PII {nonce}: x@y.c and 123 456 7890
"""

    case_two = f"""  Gamma {nonce} (202) 555-0148 and Person+{nonce}@mail-zone.co  
Beta {nonce}: 999-000-1234, next (303) 404-5050, emails a.{nonce}@one.dev b-{nonce}@two-tech.info
  gamma {nonce} (202) 555-0148 and person+{nonce}@mail-zone.co
\t\t
Omega {nonce} has no pii.
"""

    with tempfile.TemporaryDirectory() as directory:
        run_dynamic_case(case_one, directory, "first-random-case")
        run_dynamic_case(case_two, directory, "second-random-case")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
