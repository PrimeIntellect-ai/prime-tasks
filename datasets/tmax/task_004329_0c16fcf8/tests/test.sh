#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import time
import uuid


def test_prod_restored_data():
    path = "/home/user/prod/restored_data.txt"
    assert os.path.exists(path), f"File {path} does not exist. The deployment step may have failed."
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "RESTORE_SUCCESS_99182", f"Content of {path} is incorrect. Expected 'RESTORE_SUCCESS_99182', got '{content}'."


def test_auto_restore_exp():
    path = "/home/user/auto_restore.exp"
    assert os.path.exists(path), f"Expect script {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, "r") as f:
        content = f.read()

    assert "spawn" in content, f"Expect script {path} is missing 'spawn' command."
    assert "expect" in content, f"Expect script {path} is missing 'expect' command."
    assert "send" in content, f"Expect script {path} is missing 'send' command."
    assert "Enter restore password: " in content, "Expect script does not contain the exact password prompt."
    assert "Enter staging directory: " in content, "Expect script does not contain the exact staging prompt."
    assert "backup2023" in content, "Expect script does not provide the required password."
    assert "/home/user/staging" in content, "Expect script does not provide the required staging directory."
    assert "eof" in content.lower(), "Expect script does not wait for EOF."


def test_deploy_restore_rs():
    path = "/home/user/deploy_restore.rs"
    assert os.path.exists(path), f"Rust source file {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, "r") as f:
        content = f.read()

    assert "Command" in content, f"Rust source file {path} does not seem to use std::process::Command."


def test_deploy_restore_executable():
    path = "/home/user/deploy_restore"
    assert os.path.exists(path), f"Compiled Rust executable {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled ELF executable."


def _clear_outputs():
    os.makedirs("/home/user/staging", exist_ok=True)
    os.makedirs("/home/user/prod", exist_ok=True)
    for path in ("/home/user/staging/restored_data.txt", "/home/user/prod/restored_data.txt"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def _run_success(executable, token, marker):
    _clear_outputs()
    try:
        os.unlink(marker)
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env["VERIFY_TOKEN"] = token
    env["VERIFY_MARKER"] = marker
    env["EXPECTED_DEPLOY_EXE"] = os.path.realpath(executable)
    result = subprocess.run([executable], env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=15)
    assert result.returncode == 0, (
        f"{executable} failed during a real restore: stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}, status={result.returncode}"
    )
    assert os.path.isfile(marker), "The legacy restore tool was not run through Expect by the deployment executable."
    with open(marker, "r") as f:
        parts = f.read().strip().split()
    assert len(parts) == 3 and parts[0] == token, "Invalid restore-process attestation."

    output = "/home/user/prod/restored_data.txt"
    assert os.path.isfile(output), "The deployment executable did not create the production file."
    with open(output, "r") as f:
        assert f.read().strip() == token, "The deployment executable did not copy the generated staging data."

    # Both the restore process and its Expect parent must have been reaped.
    for pid in parts[1:]:
        for _ in range(20):
            if not os.path.exists(f"/proc/{pid}"):
                break
            time.sleep(0.05)
        assert not os.path.exists(f"/proc/{pid}"), f"Child process {pid} was left running or unreaped."


def _run_expect_failure(executable):
    _clear_outputs()
    with open("/home/user/staging/restored_data.txt", "w") as f:
        f.write("MUST_NOT_DEPLOY\n")
    result = subprocess.run([executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=10)
    assert result.returncode != 0, "Deployment executable reported success when Expect failed."
    assert not os.path.exists("/home/user/prod/restored_data.txt"), (
        "Deployment executable copied staging data even though Expect failed."
    )


def test_real_pipeline_and_child_status():
    legacy = "/home/user/legacy_restore"
    expect_script = "/home/user/auto_restore.exp"
    submitted = "/home/user/deploy_restore"
    rebuilt = f"/tmp/deploy_restore_rebuilt_{uuid.uuid4().hex}"
    marker = f"/tmp/restore_marker_{uuid.uuid4().hex}"
    token = f"VERIFIER_DYNAMIC_{uuid.uuid4().hex}"

    compile_result = subprocess.run(
        ["rustc", "/home/user/deploy_restore.rs", "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f"Rust source does not compile: {compile_result.stderr}"

    with open(legacy, "rb") as f:
        original_legacy = f.read()
    legacy_mode = stat.S_IMODE(os.stat(legacy).st_mode)
    with open(expect_script, "rb") as f:
        original_expect = f.read()
    expect_mode = stat.S_IMODE(os.stat(expect_script).st_mode)

    instrumented_legacy = r'''#!/bin/bash
read -r -p "Enter restore password: " pass
[ "$pass" = "backup2023" ] || exit 41
read -r -p "Enter staging directory: " staging_dir
[ "$staging_dir" = "/home/user/staging" ] || exit 42
expect_pid=$PPID
expect_exe=$(readlink -f "/proc/$expect_pid/exe") || exit 43
[ "$expect_exe" = "$(readlink -f /usr/bin/expect)" ] || exit 44
cmdline=$(tr '\000' ' ' < "/proc/$expect_pid/cmdline")
case "$cmdline" in
  *"/usr/bin/expect /home/user/auto_restore.exp"*) ;;
  *) exit 45 ;;
esac
deploy_pid=$(awk '{print $4}' "/proc/$expect_pid/stat") || exit 46
deploy_exe=$(readlink -f "/proc/$deploy_pid/exe") || exit 47
[ "$deploy_exe" = "$(readlink -f "$EXPECTED_DEPLOY_EXE")" ] || exit 48
sleep 0.4
mkdir -p "$staging_dir" || exit 49
printf '%s\n' "$VERIFY_TOKEN" > "$staging_dir/restored_data.txt" || exit 50
printf '%s %s %s\n' "$VERIFY_TOKEN" "$$" "$expect_pid" > "$VERIFY_MARKER" || exit 51
echo "Restore complete."
'''

    try:
        with open(legacy, "w") as f:
            f.write(instrumented_legacy)
        os.chmod(legacy, 0o755)

        # Exercise both the submitted artifact and a fresh compilation of its source.
        _run_success(submitted, token, marker)
        second_token = f"VERIFIER_DYNAMIC_{uuid.uuid4().hex}"
        _run_success(rebuilt, second_token, marker)

        # Confirm that Rust checks the Expect child's exit status and does not deploy on failure.
        with open(expect_script, "w") as f:
            f.write("#!/usr/bin/expect -f\nexit 23\n")
        os.chmod(expect_script, 0o755)
        _run_expect_failure(submitted)
        _run_expect_failure(rebuilt)
    finally:
        with open(legacy, "wb") as f:
            f.write(original_legacy)
        os.chmod(legacy, legacy_mode)
        with open(expect_script, "wb") as f:
            f.write(original_expect)
        os.chmod(expect_script, expect_mode)
        for path in (rebuilt, marker):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
