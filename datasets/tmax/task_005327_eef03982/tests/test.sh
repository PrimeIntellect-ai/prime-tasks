#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shlex
import stat
import subprocess
import secrets
import pytest

HOME = "/home/user"
API_PATH = os.path.join(HOME, "api_response.json")
RESULT_PATH = os.path.join(HOME, "variance_result.txt")
PROFILE_PATH = os.path.join(HOME, "memory_profile.txt")
EXCLUDED = {API_PATH, RESULT_PATH, PROFILE_PATH}

INTERPRETERS = {
    ".py": ["python3"],
    ".sh": ["bash"],
    ".bash": ["bash"],
    ".awk": ["awk", "-f"],
    ".pl": ["perl"],
    ".rb": ["ruby"],
    ".js": ["node"],
    ".php": ["php"],
    ".lua": ["lua"],
}


def expected_variance(data):
    values = [d["value"] for d in data if d.get("status") == "SUCCESS"]
    mean = sum(values) / len(values)
    variance = sum((value - mean) ** 2 for value in values) / len(values)
    return f"{variance:.4f}"


def invocation_options(path):
    extension = os.path.splitext(path)[1].lower()
    if extension in INTERPRETERS:
        return [INTERPRETERS[extension] + [path]]

    try:
        with open(path, "rb") as source:
            first_line = source.readline(4096).decode("utf-8", "replace").strip()
    except OSError:
        return []

    if first_line.startswith("#!"):
        try:
            shebang = shlex.split(first_line[2:].strip())
        except ValueError:
            shebang = []
        if shebang:
            return [shebang + [path]]

    # A script need not have an extension or executable bit. Try the two
    # interpreters explicitly installed for this task.
    return [["python3", path], ["bash", path]]


def candidate_scripts():
    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for name in files:
            path = os.path.abspath(os.path.join(root, name))
            if path in EXCLUDED:
                continue
            try:
                info = os.lstat(path)
            except OSError:
                continue
            if stat.S_ISREG(info.st_mode) and info.st_size > 0:
                candidates.append(path)
    return sorted(candidates)


def run_profiled(command, payload):
    with open(API_PATH, "w") as data_file:
        json.dump(payload, data_file)

    for path in (RESULT_PATH, PROFILE_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    try:
        with open(PROFILE_PATH, "wb") as profile:
            completed = subprocess.run(
                ["/usr/bin/time", "-v"] + command,
                cwd=HOME,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=profile,
                timeout=30,
                check=False,
            )
    except (OSError, subprocess.TimeoutExpired):
        return False

    if completed.returncode != 0 or not os.path.isfile(RESULT_PATH):
        return False

    try:
        with open(RESULT_PATH, "r") as result_file:
            actual = result_file.read().strip()
        with open(PROFILE_PATH, "r", errors="replace") as profile_file:
            profile = profile_file.read()
    except OSError:
        return False

    return actual == expected_variance(payload) and "Maximum resident set size" in profile


def test_script_exists_and_is_executable_on_derived_inputs():
    """Locate the submitted script and execute it under /usr/bin/time -v."""
    assert os.path.isfile(API_PATH), f"File {API_PATH} is missing."
    with open(API_PATH, "rb") as original_file:
        original_bytes = original_file.read()
    original_data = json.loads(original_bytes)

    rng = secrets.SystemRandom()
    probes = []
    for count in (17, 29):
        records = []
        for i in range(count):
            status = "SUCCESS" if i % 4 != 1 else "ERROR"
            value = rng.uniform(-5000.0, 9000.0) + i / 37.0
            records.append({"id": i, "status": status, "value": value})
        probes.append(records)

    candidates = candidate_scripts()
    assert candidates, "No script was written under /home/user."

    selected = None
    try:
        for candidate in candidates:
            for command in invocation_options(candidate):
                if all(run_profiled(command, probe) for probe in probes):
                    selected = command
                    break
            if selected is not None:
                break

        assert selected is not None, (
            "No submitted script successfully computed population variance "
            "for independently generated inputs."
        )

        assert run_profiled(selected, original_data), (
            "The submitted script did not successfully process the original "
            "API response under /usr/bin/time -v."
        )
    finally:
        with open(API_PATH, "wb") as original_file:
            original_file.write(original_bytes)


def test_variance_result():
    """Test that variance_result.txt contains the correct population variance."""
    api_response_path = "/home/user/api_response.json"
    result_path = "/home/user/variance_result.txt"

    assert os.path.isfile(api_response_path), f"File {api_response_path} is missing."
    assert os.path.isfile(result_path), f"File {result_path} is missing. The script did not create the output file."

    # Calculate the expected variance
    with open(api_response_path, 'r') as f:
        data = json.load(f)

    success_vals = [d['value'] for d in data if d.get('status') == 'SUCCESS']
    assert len(success_vals) > 0, "No SUCCESS records found in the data."

    mean = sum(success_vals) / len(success_vals)
    variance = sum((x - mean) ** 2 for x in success_vals) / len(success_vals)
    expected_variance = f"{variance:.4f}"

    # Read the actual result
    with open(result_path, 'r') as f:
        actual_result = f.read().strip()

    assert actual_result == expected_variance, (
        f"Incorrect variance in {result_path}. "
        f"Expected '{expected_variance}', but got '{actual_result}'."
    )


def test_memory_profile():
    """Test that memory_profile.txt contains the output from /usr/bin/time -v."""
    profile_path = "/home/user/memory_profile.txt"

    assert os.path.isfile(profile_path), f"File {profile_path} is missing. Did you redirect the profiling output?"

    with open(profile_path, 'r') as f:
        content = f.read()

    assert "Maximum resident set size" in content, (
        f"File {profile_path} does not contain 'Maximum resident set size'. "
        "Make sure you ran the script with '/usr/bin/time -v' and redirected stderr."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
