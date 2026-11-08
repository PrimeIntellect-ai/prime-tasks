#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import difflib

def test_duplicates_log_exists():
    assert os.path.isfile("/home/user/duplicates.log"), "/home/user/duplicates.log does not exist. Did you run your script and create the output file?"

def test_duplicates_log_contents():
    log_path = "/home/user/deploy.log"
    assert os.path.isfile(log_path), f"The file {log_path} is missing, cannot verify correctness."

    with open(log_path, "r") as f:
        log_lines = f.readlines()

    # Extract paths based on the exact format specified
    pattern = re.compile(r"\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[INFO\] Deployed config to (.+)")

    extracted_paths = []
    for line in log_lines:
        match = pattern.match(line.strip())
        if match:
            extracted_paths.append(match.group(1).strip())

    unique_files = []
    expected_duplicates = []

    # Process files in order and find duplicates
    for path in extracted_paths:
        assert os.path.isfile(path), f"Extracted path {path} from deploy.log does not exist."
        with open(path, "r") as f:
            content = f.read()

        is_duplicate = False
        for unique_content in unique_files:
            ratio = difflib.SequenceMatcher(None, content, unique_content).ratio()
            if ratio >= 0.90:
                is_duplicate = True
                break

        if is_duplicate:
            expected_duplicates.append(path)
        else:
            unique_files.append(content)

    # Read the student's output
    duplicates_log_path = "/home/user/duplicates.log"
    assert os.path.isfile(duplicates_log_path), f"{duplicates_log_path} is missing."

    with open(duplicates_log_path, "r") as f:
        actual_duplicates = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_duplicates == expected_duplicates, (
        f"The contents of {duplicates_log_path} do not match the expected duplicate files.\n"
        f"Expected: {expected_duplicates}\n"
        f"Found: {actual_duplicates}"
    )
TEST_EOF

cat << 'BEHAVIOR_EOF' > /tmp/test_script_behavior.py
import difflib
import os
import random
import re
import secrets
import stat
import string
import subprocess
import tempfile

SCRIPT = "/home/user/find_duplicates.py"
DEPLOY_LOG = "/home/user/deploy.log"
OUTPUT = "/home/user/duplicates.log"

assert os.path.exists(SCRIPT), f"{SCRIPT} does not exist"
assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"{SCRIPT} is not a regular file"

rng = random.SystemRandom()
valid_pattern = re.compile(
    r"\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[INFO\] Deployed config to (.+)"
)

def mutate(text):
    chars = list(text)
    for position in rng.sample(range(len(chars) - 1), 2):
        choices = string.ascii_letters.replace(chars[position], "")
        chars[position] = rng.choice(choices)
    return "".join(chars)

def derive_expected(lines):
    paths = []
    for line in lines:
        match = valid_pattern.match(line.strip())
        if match:
            paths.append(match.group(1).strip())

    unique_contents = []
    duplicates = []
    for path in paths:
        with open(path, "r") as handle:
            content = handle.read()
        if any(difflib.SequenceMatcher(None, content, old).ratio() >= 0.90
               for old in unique_contents):
            duplicates.append(path)
        else:
            unique_contents.append(content)
    return duplicates

def run_case(case_number):
    with tempfile.TemporaryDirectory(prefix="duplicate-verifier-") as directory:
        alphabet = string.ascii_letters + string.digits
        bases = ["".join(rng.choice(alphabet) for _ in range(120)) + "\n"
                 for _ in range(4)]

        remaining = {index: [0, 1] for index in range(len(bases))}
        seen = set()
        events = []
        while remaining:
            available = []
            for index, occurrences in remaining.items():
                if occurrences[0] == 0 or index in seen:
                    available.append(index)
            index = rng.choice(available)
            occurrence = remaining[index].pop(0)
            if not remaining[index]:
                del remaining[index]
            seen.add(index)
            events.append((index, occurrence))

        lines = [
            "[2026-01-01 00:00:00] [INFO] Starting deployment pipeline\n",
            "[2026-01-01 00:00:01] [DEBUG] Deployed config to /does/not/exist.conf\n",
            "not a deployment record\n",
        ]

        for sequence, (group, occurrence) in enumerate(events, start=2):
            path = os.path.join(directory, secrets.token_hex(8) + ".conf")
            content = bases[group] if occurrence == 0 else mutate(bases[group])
            with open(path, "w") as handle:
                handle.write(content)
            lines.append(
                f"[2026-01-01 00:00:{sequence:02d}] [INFO] Deployed config to {path}\n"
            )
            if rng.randrange(2):
                lines.append(
                    f"[2026-01-01 00:01:{sequence:02d}] [WARNING] retry status message\n"
                )

        with open(DEPLOY_LOG, "w") as handle:
            handle.writelines(lines)

        expected = derive_expected(lines)
        result = subprocess.run(
            ["python3", SCRIPT],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Executing {SCRIPT} failed in behavioral case {case_number}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(OUTPUT), f"{SCRIPT} did not create {OUTPUT}"
        with open(OUTPUT, "r") as handle:
            actual = [line.strip() for line in handle if line.strip()]
        assert actual == expected, (
            f"Behavioral case {case_number} produced incorrect output.\n"
            f"Expected: {expected}\nFound: {actual}"
        )

for case_number in range(1, 3):
    run_case(case_number)
BEHAVIOR_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 \
   && python3 /tmp/test_script_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
