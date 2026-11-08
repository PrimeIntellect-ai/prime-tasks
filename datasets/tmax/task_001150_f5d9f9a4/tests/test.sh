#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_auth_candidate.py
import os
import runpy
import sys

BLOCKED_EVENTS = {
    "subprocess.Popen",
    "os.system",
    "os.posix_spawn",
    "os.fork",
    "os.forkpty",
}

def audit(event, args):
    if event in BLOCKED_EVENTS or event.startswith("os.exec") or event.startswith("os.spawn") or event.startswith("ctypes.dlopen"):
        raise PermissionError(f"External program execution is not allowed: {event}")

sys.addaudithook(audit)
sys.argv = ["/home/user/auth_signer.py", sys.argv[1]]
runpy.run_path("/home/user/auth_signer.py", run_name="__main__")
RUNNER_EOF
chmod 755 /tmp/run_auth_candidate.py

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import io
import os
import pwd
import random
import runpy
import subprocess
import sys

import pexpect


def as_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def test_auto_deploy_success():
    script_path = "/home/user/auto_deploy.py"
    assert os.path.isfile(script_path), f"Missing file: {script_path}"

    result = subprocess.run(["python3", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"auto_deploy.py failed with exit code {result.returncode}.\nStderr: {result.stderr}\nStdout: {result.stdout}"

    output = result.stdout + result.stderr
    assert "Deployment successful" in output, "auto_deploy.py did not cause the legacy deploy script to emit the 'Deployment successful' message."


def test_auto_deploy_really_uses_pexpect_and_legacy_script():
    script_path = "/home/user/auto_deploy.py"
    target = "/app/legacy_deploy.sh"
    assert os.path.isfile(script_path), f"Missing file: {script_path}"

    real_spawn = pexpect.spawn
    real_spawnu = pexpect.spawnu
    launches = []

    class RecordedChild:
        def __init__(self, child, transcript):
            object.__setattr__(self, "_child", child)
            object.__setattr__(self, "_transcript", transcript)

        def __getattr__(self, name):
            return getattr(self._child, name)

        def __setattr__(self, name, value):
            if name == "logfile_read":
                return
            setattr(self._child, name, value)

    def wrap(factory):
        def checked_spawn(command, *args, **kwargs):
            transcript = io.StringIO()
            child = factory(command, *args, **kwargs)
            child.logfile_read = transcript
            launches.append((command, child, transcript))
            return RecordedChild(child, transcript)
        return checked_spawn

    pexpect.spawn = wrap(real_spawn)
    pexpect.spawnu = wrap(real_spawnu)
    old_argv = sys.argv[:]
    captured_out = io.StringIO()
    captured_err = io.StringIO()
    try:
        sys.argv = [script_path]
        with contextlib.redirect_stdout(captured_out), contextlib.redirect_stderr(captured_err):
            try:
                runpy.run_path(script_path, run_name="__main__")
            except SystemExit as exc:
                assert exc.code in (None, 0), f"auto_deploy.py exited with {exc.code}"
    finally:
        sys.argv = old_argv
        pexpect.spawn = real_spawn
        pexpect.spawnu = real_spawnu

    matching = []
    for command, child, transcript in launches:
        command_text = os.fsdecode(command) if isinstance(command, (str, bytes, os.PathLike)) else ""
        if command_text == target:
            child.isalive()
            child.close()
            matching.append((child, transcript.getvalue()))

    assert matching, "auto_deploy.py did not invoke /app/legacy_deploy.sh through pexpect"
    assert any(child.exitstatus == 0 and "Deployment successful" in transcript for child, transcript in matching), (
        "The pexpect-managed legacy deployment did not complete successfully"
    )


def test_auth_signer_fuzz_equivalence():
    agent_script = "/home/user/auth_signer.py"
    oracle_bin = "/app/auth_signer"

    assert os.path.isfile(agent_script), f"Missing file: {agent_script}"
    assert os.path.isfile(oracle_bin), f"Missing oracle binary: {oracle_bin}"

    original_mode = os.stat(oracle_bin).st_mode & 0o7777
    os.chmod(oracle_bin, 0o700)
    try:
        random.seed(42)
        inputs = [str(random.randint(1600000000, 1800000000)) for _ in range(5000)]

        for val in inputs:
            oracle_res = subprocess.run([oracle_bin, val], capture_output=True, text=True)
            agent_res = subprocess.run(
                ["python3", "/tmp/run_auth_candidate.py", val],
                capture_output=True,
                text=True,
                timeout=10,
                preexec_fn=as_user,
            )

            assert agent_res.returncode == 0, f"Agent script failed on input {val}. Stderr: {agent_res.stderr}"
            assert agent_res.stdout == oracle_res.stdout, (
                f"Mismatch on input {val}.\n"
                f"Expected output: {repr(oracle_res.stdout)}\n"
                f"Agent output: {repr(agent_res.stdout)}"
            )
    finally:
        os.chmod(oracle_bin, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
