#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess
import tempfile

import pytest

HOOK_PATH = "/home/user/metrics-dashboard.git/hooks/post-receive"
DATA_DIR = "/home/user/dashboard_data"
LOG_FILE = "/home/user/dashboard_data/push_events.jsonl"
REPO_PATH = "/home/user/metrics-dashboard.git"


def run_hook(input_text):
    return subprocess.run(
        [HOOK_PATH],
        input=input_text,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def clean_data_dir():
    if os.path.exists(DATA_DIR):
        shutil.rmtree(DATA_DIR)


def test_hook_exists_and_executable():
    assert os.path.exists(HOOK_PATH), f"Hook not found at {HOOK_PATH}"
    assert os.path.isfile(HOOK_PATH), f"{HOOK_PATH} is not a file"

    st = os.stat(HOOK_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Hook at {HOOK_PATH} is not executable"
    assert stat.S_IMODE(st.st_mode) == 0o755, (
        f"Expected permissions 755 for {HOOK_PATH}, got {oct(stat.S_IMODE(st.st_mode))}"
    )

    with open(HOOK_PATH, "rb") as f:
        binary = f.read()
    assert binary.startswith(b"\x7fELF"), "Hook must be a natively compiled ELF executable"
    rust_markers = (b"rust_eh_personality", b"library/std/src", b"/rustc/")
    assert any(marker in binary for marker in rust_markers), (
        "Hook does not appear to be a native Rust executable"
    )


def test_hook_invalid_input():
    process = run_hook("bad data\n")
    assert process.returncode == 1, f"Expected exit code 1 for invalid input, got {process.returncode}"
    assert "Invalid input" in process.stderr, f"Expected 'Invalid input' in stderr, got: {process.stderr}"


@pytest.mark.parametrize("bad_input", [
    "one\n",
    "one two three four\n",
    "\n",
])
def test_hook_rejects_other_invalid_field_counts(bad_input):
    process = run_hook(bad_input)
    assert process.returncode == 1, f"Expected exit code 1 for {bad_input!r}, got {process.returncode}"
    assert "Invalid input" in process.stderr, f"Expected 'Invalid input' in stderr, got: {process.stderr}"


def test_hook_valid_input():
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)
    if os.path.exists(DATA_DIR):
        shutil.rmtree(DATA_DIR)

    old_rev = "0000000000000000000000000000000000000000"
    new_rev = "1111111111111111111111111111111111111111"
    ref = "refs/heads/main"

    process = run_hook(f"{old_rev} {new_rev} {ref}\n")
    assert process.returncode == 0, f"Expected exit code 0 for valid input, got {process.returncode}"

    assert os.path.isdir(DATA_DIR), f"Directory {DATA_DIR} was not created"
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} was not created"

    st = os.stat(LOG_FILE)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o644, f"Expected permissions 644 for {LOG_FILE}, got {oct(perms)}"

    with open(LOG_FILE, "r") as f:
        lines = f.readlines()

    assert len(lines) >= 1, "Log file is empty"
    last_line = lines[-1].strip()
    expected_json = '{"event":"push","ref":"refs/heads/main","new_commit":"1111111111111111111111111111111111111111"}'
    assert last_line == expected_json, f"Expected JSON {expected_json}, got {last_line}"


def test_random_multiple_lines_and_append():
    clean_data_dir()

    records = []
    input_lines = []
    for _ in range(3):
        old_rev = secrets.token_hex(20)
        new_rev = secrets.token_hex(20)
        ref = f"refs/heads/audit-{secrets.token_hex(8)}"
        input_lines.append(f"{old_rev} {new_rev} {ref}\n")
        records.append(f'{{"event":"push","ref":"{ref}","new_commit":"{new_rev}"}}\n')

    first = run_hook("".join(input_lines[:2]))
    assert first.returncode == 0, f"Multiple valid lines failed: {first.stderr}"
    assert os.path.isfile(LOG_FILE), "Log file was not created for multiple input lines"
    with open(LOG_FILE, "r") as f:
        assert f.readlines() == records[:2], "Hook did not emit one exact JSON record per input line"

    second = run_hook(input_lines[2])
    assert second.returncode == 0, f"Append invocation failed: {second.stderr}"
    with open(LOG_FILE, "r") as f:
        assert f.readlines() == records, "Hook did not append without replacing existing records"

    assert stat.S_IMODE(os.stat(LOG_FILE).st_mode) == 0o644, "Log file permissions are not exactly 644"


def configure_identity(repo):
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo, check=True)


def test_end_to_end_git_push():
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)

    with tempfile.TemporaryDirectory() as tmpdir:
        clone_dir = os.path.join(tmpdir, "test-clone")
        subprocess.run(["git", "clone", REPO_PATH, clone_dir], check=True, capture_output=True)

        test_file = os.path.join(clone_dir, "test.txt")
        with open(test_file, "w") as f:
            f.write("test\n")

        subprocess.run(["git", "add", "test.txt"], cwd=clone_dir, check=True, capture_output=True)
        configure_identity(clone_dir)
        subprocess.run(["git", "commit", "-m", "Test commit"], cwd=clone_dir, check=True, capture_output=True)
        expected_commit = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=clone_dir, check=True, capture_output=True, text=True
        ).stdout.strip()

        push_result = subprocess.run(
            ["git", "push", "origin", "master"], cwd=clone_dir, capture_output=True, text=True
        )
        assert push_result.returncode == 0, f"Git push failed: {push_result.stderr}"
        assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} was not created after git push"

        with open(LOG_FILE, "r") as f:
            lines = f.readlines()
        assert len(lines) >= 1, "Log file is empty after git push"
        last_line = lines[-1].strip()

        try:
            data = json.loads(last_line)
        except json.JSONDecodeError:
            pytest.fail(f"Log line is not valid JSON: {last_line}")

        assert data.get("event") == "push", "event should be 'push'"
        assert data.get("ref") == "refs/heads/master", "ref should be 'refs/heads/master'"
        assert "new_commit" in data, "new_commit missing in JSON"
        assert len(data["new_commit"]) == 40, "new_commit should be a 40-character hash"
        assert data["new_commit"] == expected_commit, "new_commit does not match the commit actually pushed"
        expected_line = f'{{"event":"push","ref":"refs/heads/master","new_commit":"{expected_commit}"}}'
        assert last_line == expected_line, f"Expected exact JSON {expected_line}, got {last_line}"

        branch = f"audit-{secrets.token_hex(8)}"
        subprocess.run(["git", "checkout", "-b", branch], cwd=clone_dir, check=True, capture_output=True)
        with open(test_file, "a") as f:
            f.write(secrets.token_hex(16) + "\n")
        subprocess.run(["git", "add", "test.txt"], cwd=clone_dir, check=True, capture_output=True)
        subprocess.run(["git", "commit", "-m", "Random branch commit"], cwd=clone_dir, check=True, capture_output=True)
        branch_commit = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=clone_dir, check=True, capture_output=True, text=True
        ).stdout.strip()

        push_result = subprocess.run(
            ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
            cwd=clone_dir,
            capture_output=True,
            text=True,
        )
        assert push_result.returncode == 0, f"Random-ref Git push failed: {push_result.stderr}"

        with open(LOG_FILE, "r") as f:
            random_line = f.readlines()[-1].strip()
        expected_random = f'{{"event":"push","ref":"refs/heads/{branch}","new_commit":"{branch_commit}"}}'
        assert random_line == expected_random, f"Expected exact JSON {expected_random}, got {random_line}"


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
