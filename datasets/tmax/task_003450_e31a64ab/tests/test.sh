#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import shutil
import stat
import subprocess
import uuid

EXPECT_SCRIPT = "/home/user/check_vm.exp"
PROJECT_DIR = "/home/user/vm_monitor"
BINARY_PATH = "/home/user/vm_monitor/target/debug/vm_monitor"
MOCK_QEMU = "/home/user/bin/mock_qemu"
LOG_PATH = "/home/user/alerts.log"
ALERT_LINE = "ALERT: VM boot failed\n"


def run(cmd, timeout=20):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def test_01_expect_script_interacts_with_mock_qemu():
    assert os.path.exists(EXPECT_SCRIPT), f"{EXPECT_SCRIPT} does not exist."

    # Retain the original successful-boot assertion.
    result = run(["expect", EXPECT_SCRIPT])
    assert "BOOT SUCCESS" in result.stdout, (
        "Expect script failed to boot the VM successfully. Output:\n" + result.stdout
    )
    assert result.returncode == 0, "Expect script did not exit cleanly."

    # Replace mock_qemu with an unpredictable interaction challenge. A decoy
    # prompt detects scripts that send 'c' before the exact prompt appears.
    backup = MOCK_QEMU + ".verifier_backup"
    marker = "/tmp/mock_invoked_" + uuid.uuid4().hex
    input_marker = "/tmp/mock_input_" + uuid.uuid4().hex
    nonce = uuid.uuid4().hex
    shutil.copy2(MOCK_QEMU, backup)
    try:
        challenge = f'''#!/bin/bash
printf %s invoked > {shlex.quote(marker)}
echo "Initializing challenge {nonce}"
echo -n "Press 'c' to continue boot.. "
if read -r -t 0.6 premature; then
    printf %s "$premature" > {shlex.quote(input_marker)}
    echo
    echo "KERNEL PANIC - input sent before exact prompt"
    exit 1
fi
echo
sleep 0.2
echo -n "Press 'c' to continue boot... "
if read -r -t 3 input; then
    printf %s "$input" > {shlex.quote(input_marker)}
else
    printf %s TIMEOUT > {shlex.quote(input_marker)}
    echo
    echo "KERNEL PANIC - no input"
    exit 1
fi
if [ "$input" = "c" ]; then
    echo
    echo "BOOT SUCCESS {nonce}"
    exit 0
fi
echo
echo "KERNEL PANIC - wrong input"
exit 1
'''
        with open(MOCK_QEMU, "w") as f:
            f.write(challenge)
        os.chmod(MOCK_QEMU, 0o755)

        result = run(["expect", EXPECT_SCRIPT])
        assert result.returncode == 0, result.stdout + result.stderr
        assert os.path.exists(marker), "Expect script did not execute /home/user/bin/mock_qemu."
        assert os.path.exists(input_marker), "mock_qemu never received input."
        with open(input_marker) as f:
            sent = f.read()
        assert sent == "c", f"Expected the script to send exactly 'c', got {sent!r}."
        assert f"BOOT SUCCESS {nonce}" in result.stdout, (
            "Expect script did not wait for and print the challenge process's final output."
        )
    finally:
        if os.path.exists(backup):
            shutil.move(backup, MOCK_QEMU)
        for path in (marker, input_marker):
            if os.path.exists(path):
                os.remove(path)


def test_02_rust_project_builds_real_binary():
    # Retain the original binary existence and executability assertions.
    assert os.path.exists(BINARY_PATH), f"Rust binary not found at {BINARY_PATH}."
    assert os.access(BINARY_PATH, os.X_OK), f"Rust binary at {BINARY_PATH} is not executable."

    manifest = os.path.join(PROJECT_DIR, "Cargo.toml")
    source = os.path.join(PROJECT_DIR, "src", "main.rs")
    assert os.path.isfile(manifest), "Cargo.toml is missing from the Rust project."
    assert os.path.isfile(source), "src/main.rs is missing from the Rust project."

    clean = run(["cargo", "clean", "--manifest-path", manifest], timeout=60)
    assert clean.returncode == 0, clean.stdout + clean.stderr
    build = run([
        "cargo", "build", "--manifest-path", manifest,
        "--target-dir", os.path.join(PROJECT_DIR, "target")
    ], timeout=120)
    assert build.returncode == 0, "cargo build failed:\n" + build.stdout + build.stderr
    assert os.path.isfile(BINARY_PATH), "cargo build did not produce the required binary."
    assert os.access(BINARY_PATH, os.X_OK), "The Cargo-built binary is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The Cargo-built vm_monitor is not a native binary."


def test_03_rust_binary_original_success_and_failure_cases():
    backup = MOCK_QEMU + ".verifier_backup"
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    # Retain the original success case.
    result = run([BINARY_PATH])
    assert result.returncode == 0, "Monitor must exit 0 after a successful boot."
    if os.path.exists(LOG_PATH):
        with open(LOG_PATH) as f:
            content = f.read()
        assert "ALERT: VM boot failed" not in content, (
            "Alert logged when boot should have succeeded."
        )

    shutil.copy2(MOCK_QEMU, backup)
    try:
        with open(MOCK_QEMU, "w") as f:
            f.write("#!/bin/bash\necho 'KERNEL PANIC - not syncing'\nexit 1\n")
        os.chmod(MOCK_QEMU, 0o755)
        if os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)

        result = run([BINARY_PATH])
        assert result.returncode == 0, "Monitor must exit 0 after recording an alert."
        assert os.path.exists(LOG_PATH), "Alert log not created on failure."
        with open(LOG_PATH) as f:
            content = f.read()
        assert "ALERT: VM boot failed" in content, (
            "Alert log does not contain the correct message on failure."
        )
        assert content == ALERT_LINE, "Failure must append exactly the required alert line."
    finally:
        if os.path.exists(backup):
            shutil.move(backup, MOCK_QEMU)


def write_expect_probe(body, marker):
    script = f'''#!/usr/bin/expect -f
set fd [open "{marker}" w]
puts $fd "invoked"
close $fd
{body}
'''
    with open(EXPECT_SCRIPT, "w") as f:
        f.write(script)
    os.chmod(EXPECT_SCRIPT, 0o755)


def assert_exact_single_append(initial):
    assert os.path.exists(LOG_PATH), "Alert log was not created."
    with open(LOG_PATH) as f:
        actual = f.read()
    assert actual == initial + ALERT_LINE, (
        f"Expected exactly one appended alert line, got {actual!r}."
    )


def test_04_rust_executes_expect_script_and_handles_derived_cases():
    backup = EXPECT_SCRIPT + ".verifier_backup"
    shutil.copy2(EXPECT_SCRIPT, backup)
    original_mode = stat.S_IMODE(os.stat(EXPECT_SCRIPT).st_mode)
    try:
        # Dynamic success: proves the monitor executes the required path rather
        # than inspecting the fixed mock_qemu file.
        marker = "/tmp/expect_probe_" + uuid.uuid4().hex
        nonce = uuid.uuid4().hex
        write_expect_probe(f'puts "BOOT SUCCESS {nonce}"\nexit 0', marker)
        initial = "existing log entry\n"
        with open(LOG_PATH, "w") as f:
            f.write(initial)
        result = run([BINARY_PATH])
        assert result.returncode == 0
        assert os.path.exists(marker), "Rust monitor did not execute /home/user/check_vm.exp."
        with open(LOG_PATH) as f:
            assert f.read() == initial, "Successful boot must not modify alerts.log."
        os.remove(marker)

        # A panic must alert even when the child itself exits successfully.
        marker = "/tmp/expect_probe_" + uuid.uuid4().hex
        panic_nonce = uuid.uuid4().hex
        write_expect_probe(f'puts "KERNEL PANIC {panic_nonce}"\nexit 0', marker)
        with open(LOG_PATH, "w") as f:
            f.write(initial)
        result = run([BINARY_PATH])
        assert result.returncode == 0
        assert os.path.exists(marker), "Rust monitor did not run the panic probe."
        assert_exact_single_append(initial)
        os.remove(marker)

        # A failed/timeout-like Expect invocation must alert even without panic text.
        marker = "/tmp/expect_probe_" + uuid.uuid4().hex
        fail_nonce = uuid.uuid4().hex
        write_expect_probe(f'puts "expect timeout {fail_nonce}"\nexit 7', marker)
        with open(LOG_PATH, "w") as f:
            f.write(initial)
        result = run([BINARY_PATH])
        assert result.returncode == 0
        assert os.path.exists(marker), "Rust monitor did not run the failure probe."
        assert_exact_single_append(initial)
        os.remove(marker)
    finally:
        if os.path.exists(backup):
            shutil.move(backup, EXPECT_SCRIPT)
            os.chmod(EXPECT_SCRIPT, original_mode)


def test_05_cron_schedule_has_exactly_one_job():
    cron_file = "/home/user/monitor_cron"
    assert os.path.exists(cron_file), f"{cron_file} not found."
    with open(cron_file) as f:
        content = f.read()

    # Retain the original schedule assertion.
    pattern = r"^\s*\*/5\s+\*\s+\*\s+\*\s+\*\s+/home/user/vm_monitor/target/debug/vm_monitor\s*$"
    assert re.search(pattern, content, re.MULTILINE) is not None, (
        "Cron schedule is incorrect or missing in /home/user/monitor_cron."
    )

    jobs = [line.strip() for line in content.splitlines()
            if line.strip() and not line.lstrip().startswith("#")]
    assert len(jobs) == 1, f"monitor_cron must contain exactly one cron job; found {len(jobs)}."
    assert re.fullmatch(pattern, jobs[0]) is not None, "The sole cron job is incorrect."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
