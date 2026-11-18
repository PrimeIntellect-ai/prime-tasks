#!/bin/bash
set -e
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
import uuid

import pytest

BINARY = "/home/user/tracker/target/debug/tracker"


def run_tracker(src, dest, timestamp):
    try:
        result = subprocess.run(
            [BINARY, src, dest, str(timestamp)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("tracker did not terminate; a symlink loop may not have been prevented")
    assert result.returncode == 0, (
        f"tracker exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_required_backup():
    # Recreate the intended multiline fixtures. The image setup used echo without
    # -e and therefore accidentally stored literal backslash-n sequences.
    src = "/home/user/configs"
    dest = "/home/user/backup"
    os.makedirs(os.path.join(src, "subdir"), exist_ok=True)

    fixtures = {
        os.path.join(src, "app1.conf"): (
            "USER=admin\nPASSWORD=supersecret\nPORT=8080\n",
            1700006400,
        ),
        os.path.join(src, "app2.conf"): (
            "USER=guest\nPASSWORD=guessme\nPORT=8081\n",
            1699574400,
        ),
        os.path.join(src, "subdir", "app3.conf"): (
            "DB_HOST=localhost\nPASSWORD=dbpass456\nDB_NAME=test\n",
            1700438400,
        ),
    }
    for path, (content, mtime) in fixtures.items():
        with open(path, "w") as f:
            f.write(content)
        os.utime(path, (mtime, mtime))

    loop = os.path.join(src, "subdir", "loop_link")
    if os.path.lexists(loop):
        os.unlink(loop)
    os.symlink(src, loop)

    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest)
    run_tracker(src, dest, 1700000000)


def test_rust_project_exists():
    assert os.path.isdir("/home/user/tracker"), "Rust project directory /home/user/tracker does not exist."
    assert os.path.isfile("/home/user/tracker/Cargo.toml"), "Cargo.toml is missing in /home/user/tracker."
    assert os.path.isfile("/home/user/tracker/src/main.rs"), "src/main.rs is missing in /home/user/tracker."


def test_compiled_binary_exists():
    assert os.path.isfile(BINARY), f"Compiled binary not found at {BINARY}. Did you run 'cargo build'?"
    assert os.access(BINARY, os.X_OK), f"File at {BINARY} is not executable."


def test_app1_backup_correct():
    backup_path = "/home/user/backup/app1.conf"
    assert os.path.isfile(backup_path), f"Backup file {backup_path} does not exist."
    with open(backup_path, "r") as f:
        content = f.read()
    lines = [line.strip() for line in content.strip().split("\n")]
    expected_lines = ["USER=admin", "PASSWORD=REDACTED", "PORT=8080"]
    assert lines == expected_lines, f"Content of {backup_path} is incorrect. Expected {expected_lines}, got {lines}."


def test_app3_backup_correct():
    backup_path = "/home/user/backup/subdir/app3.conf"
    assert os.path.isfile(backup_path), f"Backup file {backup_path} does not exist. Make sure intermediate directories are created."
    with open(backup_path, "r") as f:
        content = f.read()
    lines = [line.strip() for line in content.strip().split("\n")]
    expected_lines = ["DB_HOST=localhost", "PASSWORD=REDACTED", "DB_NAME=test"]
    assert lines == expected_lines, f"Content of {backup_path} is incorrect. Expected {expected_lines}, got {lines}."


def test_app2_backup_does_not_exist():
    backup_path = "/home/user/backup/app2.conf"
    assert not os.path.exists(backup_path), f"Backup file {backup_path} should NOT exist because its modification time is older than the threshold."


def test_no_spurious_backup_files():
    nested_path = "/home/user/backup/subdir/subdir"
    assert not os.path.exists(nested_path), "Found nested 'subdir/subdir' in backup, which indicates symlink loop was not properly prevented."

    found = set()
    for root, _, files in os.walk("/home/user/backup"):
        for name in files:
            found.add(os.path.relpath(os.path.join(root, name), "/home/user/backup"))
    assert found == {"app1.conf", os.path.join("subdir", "app3.conf")}, f"Unexpected backup files found: {found}"


def test_binary_on_independent_inputs():
    base = tempfile.mkdtemp(prefix="tracker-verifier-")
    try:
        src = os.path.join(base, "source")
        dest = os.path.join(base, "destination")
        nested = os.path.join(src, "nested")
        external = os.path.join(base, "external")
        os.makedirs(nested)
        os.makedirs(external)

        token = uuid.uuid4().hex
        threshold = 1800000000
        changed_name = f"changed-{token}.conf"
        external_name = f"linked-{token}.conf"

        changed_content = (
            f"TOKEN={token}\n"
            "PASSWORD=first-secret\n"
            " PASSWORD=must-stay\n"
            "XPASSWORD=must-stay\n"
            "PASSWORD=\n"
            "END=yes\n"
        )
        changed_expected = (
            f"TOKEN={token}\n"
            "PASSWORD=REDACTED\n"
            " PASSWORD=must-stay\n"
            "XPASSWORD=must-stay\n"
            "PASSWORD=REDACTED\n"
            "END=yes\n"
        )

        changed = os.path.join(nested, changed_name)
        old = os.path.join(src, f"old-{token}.conf")
        exact = os.path.join(src, f"exact-{token}.conf")
        nonconf = os.path.join(src, f"ignored-{token}.txt")
        linked_source = os.path.join(external, external_name)

        for path, content, mtime in [
            (changed, changed_content, threshold + 20),
            (old, "PASSWORD=old\n", threshold - 1),
            (exact, "PASSWORD=exact\n", threshold),
            (nonconf, "PASSWORD=text\n", threshold + 20),
            (linked_source, f"ID={token}\nPASSWORD=linked-secret\n", threshold + 30),
        ]:
            with open(path, "w") as f:
                f.write(content)
            os.utime(path, (mtime, mtime))

        os.symlink(src, os.path.join(nested, "loop"))
        os.symlink(external, os.path.join(src, "linked_dir"))

        run_tracker(src, dest, threshold)

        changed_output = os.path.join(dest, "nested", changed_name)
        linked_output = os.path.join(dest, "linked_dir", external_name)
        with open(changed_output, "r") as f:
            assert f.read() == changed_expected
        with open(linked_output, "r") as f:
            assert f.read() == f"ID={token}\nPASSWORD=REDACTED\n"

        found = set()
        for root, _, files in os.walk(dest):
            for name in files:
                found.add(os.path.relpath(os.path.join(root, name), dest))
        expected = {
            os.path.join("nested", changed_name),
            os.path.join("linked_dir", external_name),
        }
        assert found == expected, f"Expected only modified .conf files, got {found}"
    finally:
        shutil.rmtree(base, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
