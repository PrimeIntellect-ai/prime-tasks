#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import site
import string
import subprocess
import tempfile
import tomllib

import pexpect

AGENT_PATH = "/home/user/auto_restore.py"
PACKAGE_PATH = "/app/py-restore-util-1.2.0"


def restore_command():
    candidates = [
        shutil.which("restore-util"),
        os.path.join(site.USER_BASE, "bin", "restore-util"),
        "/root/.local/bin/restore-util",
        "/home/user/.local/bin/restore-util",
    ]
    for candidate in candidates:
        if candidate and os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    raise AssertionError("The installed restore-util command was not found")


def expected_files(backup_id):
    return sorted([
        f"/data/backup_{backup_id}/config.yaml",
        f"/data/backup_{backup_id}/database.db",
        f"/data/backup_{backup_id}/media/image1.png",
    ])


def run_agent(backup_id, env=None):
    return subprocess.run(
        ["/usr/bin/python3", AGENT_PATH, backup_id],
        capture_output=True,
        text=True,
        env=env,
        timeout=15,
    )


def assert_strict_result(proc, expected):
    assert proc.returncode == 0, f"Agent exited with {proc.returncode}. stderr: {proc.stderr}"
    assert proc.stderr == "", f"Agent printed to stderr: {proc.stderr}"
    try:
        result = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"Agent stdout is not valid JSON: {proc.stdout!r}") from exc
    assert isinstance(result, dict) and set(result) == {"restored_files"}, result
    assert result == {"restored_files": expected}, result


def test_auto_restore_script_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent script missing at {AGENT_PATH}. Did you create it?"


def test_vendored_package_configuration_is_fixed_and_cli_runs():
    with open(os.path.join(PACKAGE_PATH, "pyproject.toml"), "rb") as handle:
        config = tomllib.load(handle)
    assert config["project"]["scripts"]["restore-util"] == "restore_util.cli:main"

    backup_id = "VerifierInstall7"
    env = os.environ.copy()
    env.pop("REQUIRE_SSH_KEY", None)
    child = pexpect.spawn(
        restore_command(),
        ["extract", backup_id],
        env=env,
        encoding="utf-8",
        timeout=10,
    )
    child.expect_exact("Archive Password: ")
    child.sendline("OperatorDeploy99!")
    child.expect(pexpect.EOF)
    output = child.before
    child.close()
    assert child.exitstatus == 0, output
    files = sorted(line.strip() for line in output.splitlines() if line.strip().startswith("/data/"))
    assert files == expected_files(backup_id)


def test_agent_really_invokes_interactive_restore_util():
    backup_id = "RuntimeProbe9"
    nonce = os.urandom(12).hex()
    expected = sorted([
        f"/data/runtime_{nonce}/z-last.bin",
        f"/data/runtime_{nonce}/a-first.conf",
        f"/data/runtime_{nonce}/middle.db",
    ])

    with tempfile.TemporaryDirectory() as directory:
        wrapper = os.path.join(directory, "restore-util")
        log_path = os.path.join(directory, "invocation.json")
        wrapper_source = f'''#!/usr/bin/python3
import json
import os
import sys

record = {{"args": sys.argv[1:]}}
sys.stdout.write("Archive Password: ")
sys.stdout.flush()
record["password"] = sys.stdin.readline().rstrip("\\r\\n")
with open(os.environ["RESTORE_TEST_LOG"], "w") as handle:
    json.dump(record, handle)
if record["args"] != ["extract", {backup_id!r}] or record["password"] != "OperatorDeploy99!":
    sys.exit(1)
print({expected[2]!r})
print({expected[0]!r})
print({expected[1]!r})
'''
        with open(wrapper, "w") as handle:
            handle.write(wrapper_source)
        os.chmod(wrapper, 0o755)

        env = os.environ.copy()
        env["PATH"] = directory + os.pathsep + env.get("PATH", "")
        env["RESTORE_TEST_LOG"] = log_path
        proc = run_agent(backup_id, env)
        assert_strict_result(proc, expected)
        assert os.path.isfile(log_path), "auto_restore.py did not invoke restore-util"
        with open(log_path) as handle:
            invocation = json.load(handle)
        assert invocation == {
            "args": ["extract", backup_id],
            "password": "OperatorDeploy99!",
        }


def test_fuzz_equivalence():
    random.seed(42)
    chars = string.ascii_letters + string.digits

    for _ in range(100):
        length = random.randint(8, 16)
        fuzz_input = "".join(random.choice(chars) for _ in range(length))
        proc = run_agent(fuzz_input)
        assert_strict_result(proc, expected_files(fuzz_input))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
