#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess
import tempfile
import time
import pytest

SANITIZER = "/home/user/sanitizer"


def run_sanitizer(path):
    try:
        return subprocess.run(
            [SANITIZER, path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Sanitizer timed out while processing {path}")


def test_sanitizer_exists_and_executable():
    source_path = "/home/user/sanitizer.cpp"
    assert os.path.isfile(source_path), f"C++ source missing at {source_path}"
    assert os.path.isfile(SANITIZER), f"Sanitizer executable missing at {SANITIZER}"
    assert os.access(SANITIZER, os.X_OK), f"Sanitizer at {SANITIZER} is not executable"
    with open(SANITIZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer is not a compiled executable"


def test_sanitizer_clean_corpus():
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    assert clean_files, "No files found in clean corpus"

    failed_files = []
    for fpath in clean_files:
        if run_sanitizer(fpath) != 0:
            failed_files.append(os.path.basename(fpath))
    assert not failed_files, (
        f"{len(failed_files)} of {len(clean_files)} clean files rejected "
        f"(expected exit code 0). Offending files: {', '.join(failed_files)}"
    )


def test_sanitizer_evil_corpus():
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]
    assert evil_files, "No files found in evil corpus"

    failed_files = []
    for fpath in evil_files:
        if run_sanitizer(fpath) != 1:
            failed_files.append(os.path.basename(fpath))
    assert not failed_files, (
        f"{len(failed_files)} of {len(evil_files)} evil files bypassed "
        f"(expected exit code 1). Offending files: {', '.join(failed_files)}"
    )


def test_sanitizer_generated_cases():
    nonce = secrets.token_hex(12)
    filler_a = f"setting_{nonce}=enabled"
    filler_b = f"backup_note_{secrets.token_hex(8)}=safe"

    cases = [
        (f"AUTHORISED_BACKUP\n{filler_a}\n", 0),
        (f"{filler_a}\nAUTHORISED_BACKUP\n{filler_b}\n", 0),
        (f"prefix [AUTHORISED_BACKUP] suffix\n{filler_a}\n", 0),
        (f"AUTHORISED_BACKUP\nDROP  TABLE users\n{filler_a}\n", 0),
        (f"AUTHORISED_BACKUP\ndrop table users\n{filler_a}\n", 0),
        (f"AUTHORISED_BACKUP\nrm  -rf /tmp/x\n{filler_a}\n", 0),
        (f"AUTHORISED_BACKUP\nRM -RF /tmp/x\n{filler_a}\n", 0),
        (f"{filler_a}\nAUTHORISED_BACKUP\nDROP TABLE generated_{nonce}\n", 1),
        (f"DROP TABLE generated_{nonce}\nAUTHORISED_BACKUP\n{filler_b}\n", 1),
        (f"AUTHORISED_BACKUP\n{filler_a}\nrm -rf /tmp/{nonce}\n", 1),
        (f"rm -rf /tmp/{nonce}\n{filler_a}\nAUTHORISED_BACKUP\n", 1),
        (f"{filler_a}\n{filler_b}\n", 1),
        ("", 1),
        (f"authorised_backup\n{filler_a}\n", 1),
        (f"AUTHORISED-BACKUP\n{filler_a}\n", 1),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix=f"validation-{nonce}-") as directory:
        failures = []
        for index, (content, expected) in enumerate(cases):
            path = os.path.join(directory, f"input-{secrets.token_hex(10)}.dat")
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            actual = run_sanitizer(path)
            if actual != expected:
                failures.append(f"case {index}: expected {expected}, got {actual}")
        assert not failures, "Generated sanitizer failures: " + "; ".join(failures)


def test_vm_supervisor_script():
    script_path = "/home/user/vm_supervisor.sh"
    assert os.path.isfile(script_path), f"VM supervisor script missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable"

    expected_args = [
        "-m", "256",
        "-drive", "file=/app/dummy_disk.qcow2,format=qcow2",
        "-nographic",
        "-daemonize",
        "-pidfile", "/home/user/qemu.pid",
    ]

    with tempfile.TemporaryDirectory(prefix="qemu-command-check-") as mock_dir:
        log_path = os.path.join(mock_dir, "args.log")
        mock_path = os.path.join(mock_dir, "qemu-system-x86_64")
        with open(mock_path, "w", encoding="utf-8") as f:
            f.write("#!/bin/sh\nprintf '%s\\0' \"$@\" > \"$QEMU_ARGS_LOG\"\n")
        os.chmod(mock_path, 0o755)

        env = os.environ.copy()
        env["PATH"] = mock_dir + os.pathsep + env.get("PATH", "")
        env["QEMU_ARGS_LOG"] = log_path
        try:
            result = subprocess.run(
                [script_path], env=env, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=5
            )
        except subprocess.TimeoutExpired:
            pytest.fail("VM supervisor script did not complete when QEMU was mocked")

        for _ in range(20):
            if os.path.isfile(log_path):
                break
            time.sleep(0.05)
        assert os.path.isfile(log_path), "VM supervisor did not run qemu-system-x86_64"
        raw = open(log_path, "rb").read().split(b"\0")
        if raw and raw[-1] == b"":
            raw.pop()
        actual_args = [part.decode("utf-8") for part in raw]
        assert actual_args == expected_args, (
            f"VM supervisor used incorrect QEMU arguments: {actual_args!r}"
        )
        assert result.returncode == 0, (
            f"VM supervisor exited with code {result.returncode}: "
            f"{result.stderr.decode(errors='replace')}"
        )


def timer_has_fifteen_minute_interval(content):
    section = None
    values = []
    calendars = []
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        if section != "timer" or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.split("#", 1)[0].split(";", 1)[0].strip()
        key = key.strip().lower()
        if key == "onunitactivesec":
            values.append(value.lower().replace(" ", ""))
        elif key == "oncalendar":
            calendars.append(value.lower().replace(" ", ""))

    duration_re = re.compile(r"^(?:15(?:min|mins|minute|minutes|m)|900(?:s|sec|secs|second|seconds)?|00:15:00)$")
    if any(duration_re.fullmatch(value) for value in values):
        return True

    common_calendars = {
        "*:0/15", "*:00/15", "*-*-**:00/15:00",
        "*:00,15,30,45", "*-*-**:00,15,30,45:00",
    }
    return any(value in common_calendars for value in calendars)


def test_systemd_service_and_timer():
    service_path = os.path.expanduser("~user/.config/systemd/user/vm-restore.service")
    timer_path = os.path.expanduser("~user/.config/systemd/user/vm-restore.timer")

    assert os.path.isfile(service_path), f"Service file missing at {service_path}"
    with open(service_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "ExecStart=/home/user/vm_supervisor.sh" in content, (
        "Service file does not contain ExecStart=/home/user/vm_supervisor.sh"
    )

    assert os.path.isfile(timer_path), f"Timer file missing at {timer_path}"
    with open(timer_path, "r", encoding="utf-8") as f:
        timer_content = f.read()
    assert timer_has_fifteen_minute_interval(timer_content), (
        "vm-restore.timer is not configured to run every 15 minutes"
    )

    try:
        result = subprocess.run(
            ["su", "-", "user", "-c",
             "XDG_RUNTIME_DIR=/run/user/$(id -u user) systemctl --user is-active vm-restore.timer"],
            capture_output=True, text=True
        )
        is_active = result.stdout.strip() == "active"
        if not is_active:
            result2 = subprocess.run(
                ["systemctl", "--user", "is-active", "vm-restore.timer"],
                capture_output=True, text=True
            )
            is_active = result2.stdout.strip() == "active"
        assert is_active, "vm-restore.timer is not active"
    except Exception as e:
        pytest.fail(f"Failed to check if timer is active: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
