#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/run_forensics_submission.py
import hashlib
import json
import os
import secrets
import stat
import subprocess
import sys

HOME = "/home/user"
SUSPECT_DIR = "/home/user/suspect_dir"
IOC_PATH = "/home/user/ioc_hashes.txt"
REPORT_PATH = "/home/user/forensics_report.json"
EXPECTED_PATH = "/tmp/forensics_expected.json"
MARKER_PATH = "/tmp/forensics_script_executed"


def find_python_scripts():
    candidates = []
    excluded = {IOC_PATH, REPORT_PATH}
    for root, dirs, files in os.walk(HOME):
        if root == SUSPECT_DIR or root.startswith(SUSPECT_DIR + os.sep):
            dirs[:] = []
            continue
        for name in files:
            path = os.path.join(root, name)
            if path in excluded or not os.path.isfile(path):
                continue
            try:
                with open(path, "rb") as f:
                    source = f.read(10 * 1024 * 1024 + 1)
                if len(source) > 10 * 1024 * 1024:
                    continue
                compile(source, path, "exec")
            except (OSError, SyntaxError, ValueError, TypeError, UnicodeError):
                continue
            candidates.append(path)
    return sorted(candidates, key=lambda p: (not p.endswith(".py"), p))


def make_flag():
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return "EVIDENCE_FLAG_" + "".join(secrets.choice(alphabet) for _ in range(16))


nonce = secrets.token_hex(6)
sgid_name = f"sgid_{nonce}.bin"
ioc_name = f"ioc_{nonce}.dat"
ww_name = f"ww_{nonce}.tmp"
normal_name = f"normal_{nonce}.txt"
sgid_flag = make_flag()
ioc_flag = make_flag()


def prepare_fixture():
    if os.path.lexists(SUSPECT_DIR):
        if os.path.islink(SUSPECT_DIR):
            os.unlink(SUSPECT_DIR)
        else:
            import shutil
            shutil.rmtree(SUSPECT_DIR)
    os.makedirs(os.path.join(SUSPECT_DIR, "subdir"), exist_ok=True)

    files = {
        os.path.join(SUSPECT_DIR, "config.txt"): b"Just a normal config file.\n",
        os.path.join(SUSPECT_DIR, "backdoor_script.sh"): b"echo 'backdoor'\n",
        os.path.join(SUSPECT_DIR, "suid_dropper.bin"): b"Binary blob with SUID... EVIDENCE_FLAG_Q1W2E3R4T5Y6U7I8 hidden inside.\n",
        os.path.join(SUSPECT_DIR, "subdir", "payload.so"): b"Malicious payload... EVIDENCE_FLAG_Z9Y8X7W6V5U4T3S2 embedded here.\n",
        os.path.join(SUSPECT_DIR, "subdir", ww_name): b"world writable challenge\n",
        os.path.join(SUSPECT_DIR, "subdir", sgid_name): ("SGID challenge " + sgid_flag + "\n").encode(),
        os.path.join(SUSPECT_DIR, "subdir", ioc_name): ("IOC challenge " + ioc_flag + "\n").encode(),
        os.path.join(SUSPECT_DIR, "subdir", normal_name): b"ordinary challenge file\n",
    }
    for path, content in files.items():
        with open(path, "wb") as f:
            f.write(content)

    os.chmod(SUSPECT_DIR, 0o777)
    os.chmod(os.path.join(SUSPECT_DIR, "subdir"), 0o777)
    os.chmod(os.path.join(SUSPECT_DIR, "config.txt"), 0o644)
    os.chmod(os.path.join(SUSPECT_DIR, "backdoor_script.sh"), 0o777)
    os.chmod(os.path.join(SUSPECT_DIR, "suid_dropper.bin"), 0o4755)
    os.chmod(os.path.join(SUSPECT_DIR, "subdir", "payload.so"), 0o755)
    os.chmod(os.path.join(SUSPECT_DIR, "subdir", ww_name), 0o606)
    os.chmod(os.path.join(SUSPECT_DIR, "subdir", sgid_name), 0o2640)
    os.chmod(os.path.join(SUSPECT_DIR, "subdir", ioc_name), 0o644)
    os.chmod(os.path.join(SUSPECT_DIR, "subdir", normal_name), 0o644)

    payload_hash = hashlib.sha256(files[os.path.join(SUSPECT_DIR, "subdir", "payload.so")]).hexdigest()
    challenge_hash = hashlib.sha256(files[os.path.join(SUSPECT_DIR, "subdir", ioc_name)]).hexdigest()
    with open(IOC_PATH, "w", encoding="ascii") as f:
        f.write(payload_hash + "\n")
        f.write(challenge_hash + "\n")
        f.write("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n")
    os.chmod(IOC_PATH, 0o777)

    try:
        os.unlink(REPORT_PATH)
    except FileNotFoundError:
        pass


expected = {
    "world_writable_files": sorted([
        os.path.join(SUSPECT_DIR, "backdoor_script.sh"),
        os.path.join(SUSPECT_DIR, "subdir", ww_name),
    ]),
    "suid_sgid_files": sorted([
        os.path.join(SUSPECT_DIR, "suid_dropper.bin"),
        os.path.join(SUSPECT_DIR, "subdir", sgid_name),
    ]),
    "ioc_matches": sorted([
        os.path.join(SUSPECT_DIR, "subdir", "payload.so"),
        os.path.join(SUSPECT_DIR, "subdir", ioc_name),
    ]),
    "extracted_flags": sorted([
        "EVIDENCE_FLAG_Q1W2E3R4T5Y6U7I8",
        "EVIDENCE_FLAG_Z9Y8X7W6V5U4T3S2",
        sgid_flag,
        ioc_flag,
    ]),
}

scripts = find_python_scripts()
if not scripts:
    print("No submitted Python script was found.", file=sys.stderr)
    sys.exit(1)

accepted = None
for script in scripts:
    try:
        prepare_fixture()
        result = subprocess.run(
            [sys.executable, script],
            cwd=HOME,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            check=False,
        )
        if result.returncode != 0 or not os.path.isfile(REPORT_PATH):
            continue
        with open(REPORT_PATH, "r", encoding="utf-8") as f:
            report = json.load(f)
        if not isinstance(report, dict):
            continue
        if all(report.get(key) == value for key, value in expected.items()):
            accepted = script
            break
    except (OSError, ValueError, json.JSONDecodeError, subprocess.TimeoutExpired):
        continue

if accepted is None:
    print("No submitted Python script produced an accurate report when executed.", file=sys.stderr)
    sys.exit(1)

with open(EXPECTED_PATH, "w", encoding="utf-8") as f:
    json.dump(expected, f, sort_keys=True)
with open(MARKER_PATH, "w", encoding="utf-8") as f:
    f.write(accepted + "\n")
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pytest

REPORT_PATH = "/home/user/forensics_report.json"
EXPECTED_PATH = "/tmp/forensics_expected.json"
MARKER_PATH = "/tmp/forensics_script_executed"


@pytest.fixture(scope="module")
def report_data():
    assert os.path.exists(REPORT_PATH), f"Report file not found at {REPORT_PATH}"
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Report file {REPORT_PATH} is not valid JSON.")
    return data


@pytest.fixture(scope="module")
def expected_data():
    with open(EXPECTED_PATH, "r") as f:
        return json.load(f)


def test_python_script_was_executed():
    assert os.path.isfile(MARKER_PATH), "No submitted Python script was successfully executed"
    with open(MARKER_PATH, "r") as f:
        script_path = f.read().strip()
    assert script_path and os.path.isfile(script_path), "Executed Python script no longer exists"


def test_report_structure(report_data):
    expected_keys = {"world_writable_files", "suid_sgid_files", "ioc_matches", "extracted_flags"}
    actual_keys = set(report_data.keys())
    assert expected_keys.issubset(actual_keys), f"Report is missing keys: {expected_keys - actual_keys}"


def test_world_writable_files(report_data, expected_data):
    actual = report_data.get("world_writable_files", [])
    expected = expected_data["world_writable_files"]
    assert actual == expected, f"Expected world_writable_files to be {expected}, but got {actual}"


def test_suid_sgid_files(report_data, expected_data):
    actual = report_data.get("suid_sgid_files", [])
    expected = expected_data["suid_sgid_files"]
    assert actual == expected, f"Expected suid_sgid_files to be {expected}, but got {actual}"


def test_ioc_matches(report_data, expected_data):
    actual = report_data.get("ioc_matches", [])
    expected = expected_data["ioc_matches"]
    assert actual == expected, f"Expected ioc_matches to be {expected}, but got {actual}"


def test_extracted_flags(report_data, expected_data):
    actual = report_data.get("extracted_flags", [])
    expected = expected_data["extracted_flags"]
    assert actual == expected, f"Expected extracted_flags to be {expected}, but got {actual}"
TEST_EOF

if python3 /tmp/run_forensics_submission.py && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
