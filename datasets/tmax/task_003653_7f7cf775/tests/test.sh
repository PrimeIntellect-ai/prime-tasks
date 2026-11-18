#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import posixpath
import random
import stat
import string
import subprocess


def test_setup_restore_script_exists():
    script_path = "/home/user/setup_restore.sh"
    assert os.path.exists(script_path), f"Missing script: {script_path}"
    assert os.path.isfile(script_path), f"Not a file: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_setup_restore_state():
    script_path = "/home/user/setup_restore.sh"
    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"

    releases_dir = "/home/user/backup_staging/releases"
    v1_dir = "/home/user/backup_staging/releases/v1"
    v2_dir = "/home/user/backup_staging/releases/v2"
    current_link = "/home/user/backup_staging/current"

    assert os.path.isdir(releases_dir), f"Missing directory: {releases_dir}"
    assert os.path.isdir(v1_dir), f"Missing directory: {v1_dir}"
    assert os.path.isdir(v2_dir), f"Missing directory: {v2_dir}"

    assert stat.S_IMODE(os.stat(releases_dir).st_mode) == 0o755, f"Incorrect permissions on {releases_dir}"
    assert stat.S_IMODE(os.stat(v1_dir).st_mode) == 0o700, f"Incorrect permissions on {v1_dir}"
    assert stat.S_IMODE(os.stat(v2_dir).st_mode) == 0o700, f"Incorrect permissions on {v2_dir}"

    assert os.path.islink(current_link), f"Not a symlink: {current_link}"
    target = os.readlink(current_link)
    assert target == "/home/user/backup_staging/releases/v1", f"Symlink points to wrong target: {target}"


def expected_output(inp):
    cleaned = posixpath.normpath(inp)
    if inp.startswith("/") and cleaned.startswith("//"):
        cleaned = "/" + cleaned.lstrip("/")

    if "KRAKEN99" in cleaned:
        return "ACL: 0777\n"
    if cleaned == "/restricted" or cleaned.startswith("/restricted/"):
        return "ACL: 0600\n"

    digest = hashlib.md5(cleaned.encode()).hexdigest()
    return f"ACL: 0644 HASH: {digest[:4]}\n"


def test_path_validator_fuzz_equivalence():
    agent_bin = "/home/user/path_validator"
    agent_source = "/home/user/path_validator.go"
    rebuilt_bin = "/tmp/path_validator_from_source"

    assert os.path.exists(agent_bin), f"Missing agent executable: {agent_bin}"
    assert os.path.isfile(agent_bin), f"Agent executable is not a file: {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent executable is not executable: {agent_bin}"
    assert os.path.exists(agent_source), f"Missing Go source: {agent_source}"
    assert os.path.isfile(agent_source), f"Go source is not a file: {agent_source}"

    build_res = subprocess.run(
        ["go", "build", "-o", rebuilt_bin, agent_source],
        capture_output=True,
        text=True,
    )
    assert build_res.returncode == 0, f"Go source failed to compile: {build_res.stderr}"

    random.seed(42)
    charset = string.ascii_letters + string.digits + "/._-"

    inputs = []
    for _ in range(150):
        length = random.randint(5, 60)
        inputs.append("".join(random.choice(charset) for _ in range(length)))

    inputs.append("/restricted/foo/bar")
    inputs.append("/restricted")
    inputs.append("foo/bar/KRAKEN99/baz")
    inputs.append("/restricted/KRAKEN99")
    inputs.append("KRAKEN99")
    inputs.append("/restricted/../KRAKEN99")
    inputs.append("/foo/../restricted")

    for _ in range(43):
        length = random.randint(5, 60)
        inputs.append("".join(random.choice(charset) for _ in range(length)))

    for inp in inputs:
        expected = expected_output(inp)
        for candidate in (agent_bin, rebuilt_bin):
            result = subprocess.run([candidate, inp], capture_output=True, text=True)
            assert result.returncode == 0, f"Return code mismatch from {candidate} on input '{inp}'"
            assert result.stdout == expected, (
                f"Output mismatch from {candidate} on input '{inp}'. "
                f"Expected '{expected}', got '{result.stdout}'"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
