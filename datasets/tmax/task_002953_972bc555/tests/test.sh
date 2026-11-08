#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import subprocess
import time


def test_diagnostic_seed_extracted():
    seed_file = "/home/user/diagnostic_seed.txt"
    assert os.path.isfile(seed_file), f"Seed file {seed_file} does not exist."
    with open(seed_file, "r") as f:
        content = f.read().strip()
    assert content == "A7F9B2C4", f"Expected seed 'A7F9B2C4', but got '{content}'."


def test_monitor_storage_script_exists_and_executable():
    script_path = "/home/user/monitor_storage.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert not os.path.islink(script_path), f"Script {script_path} must not be a symlink."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_monitor_storage_logic():
    script_path = "/home/user/monitor_storage.sh"
    telemetry_dir = "/home/user/telemetry_data"
    mbox_path = "/home/user/admin_alerts.mbox"

    os.makedirs(telemetry_dir, exist_ok=True)
    for entry in os.scandir(telemetry_dir):
        if entry.is_file() or entry.is_symlink():
            os.unlink(entry.path)
        elif entry.is_dir():
            import shutil
            shutil.rmtree(entry.path)

    if os.path.lexists(mbox_path):
        os.unlink(mbox_path)

    # Six 10 MiB files exceed 50 MiB. Give them unambiguous oldest-to-newest mtimes.
    base_time = int(time.time()) - 1000
    names = []
    for i in range(6):
        name = f"test_file_{i}.dat"
        path = os.path.join(telemetry_dir, name)
        with open(path, "wb") as f:
            f.write(os.urandom(10 * 1024 * 1024))
        os.utime(path, (base_time + i, base_time + i))
        names.append(name)

    size_before = sum(entry.stat().st_size for entry in os.scandir(telemetry_dir) if entry.is_file())
    assert size_before >= 50 * 1024 * 1024, "Failed to set up storage monitor test files."

    started = int(time.time())
    proc = subprocess.run([script_path], capture_output=True, text=True, timeout=30)
    finished = int(time.time())
    assert proc.returncode == 0, f"Storage monitor script failed: {proc.stderr}"

    remaining = sorted(entry.name for entry in os.scandir(telemetry_dir) if entry.is_file())
    assert remaining == names[3:], (
        f"Cleanup must delete the oldest files first; expected {names[3:]}, got {remaining}."
    )

    size_after = sum(entry.stat().st_size for entry in os.scandir(telemetry_dir) if entry.is_file())
    assert size_after < 40 * 1024 * 1024, f"Directory size {size_after} is not under 40 MiB."

    assert os.path.isfile(mbox_path), f"Alert mbox {mbox_path} was not created."
    with open(mbox_path, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == 1, f"Expected exactly one appended alert line, got {lines!r}."
    match = re.fullmatch(r"ALERT: Storage cleanup executed at ([0-9]+)", lines[0])
    assert match, f"Alert has incorrect format: {lines[0]!r}."
    timestamp = int(match.group(1))
    assert started <= timestamp <= finished, f"Alert timestamp {timestamp} is not the execution time."


def test_crontab_configured():
    proc = subprocess.run(["crontab", "-u", "user", "-l"], capture_output=True, text=True)
    assert proc.returncode == 0, "Failed to read user crontab. Has it been configured?"

    valid_minutes = {"*/5", "0,5,10,15,20,25,30,35,40,45,50,55"}
    found = False
    for raw_line in proc.stdout.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split(None, 5)
        if len(fields) != 6:
            continue
        minute, hour, day_of_month, month, day_of_week, command = fields
        if (
            minute in valid_minutes
            and hour == "*"
            and day_of_month == "*"
            and month == "*"
            and day_of_week == "*"
            and command.strip() == "/home/user/monitor_storage.sh"
        ):
            found = True
            break

    assert found, "User crontab lacks an exact every-five-minutes entry for monitor_storage.sh."


def expected_output(payload):
    seed = b"A7F9B2C4"
    encoded = bytes(value ^ seed[i % len(seed)] for i, value in enumerate(payload)).hex()
    return (
        "Match User iot_admin\n"
        "  PubkeyAuthentication yes\n"
        f"  AuthorizedKeysCommand /usr/bin/validate_payload {encoded}\n"
        "  AuthorizedKeysCommandUser nobody\n"
    ).encode()


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.digest()


def test_acl_compiler_fuzz_equivalence():
    oracle_path = "/app/bin/legacy_acl_compiler"
    source_path = "/home/user/acl_compiler.go"
    agent_path = "/home/user/acl_compiler"
    rebuilt_path = "/tmp/rebuilt_acl_compiler"

    assert os.path.isfile(source_path), f"Go source {source_path} not found."
    assert not os.path.islink(source_path), f"Go source {source_path} must not be a symlink."
    assert os.path.isfile(agent_path), f"Compiled agent binary {agent_path} not found."
    assert not os.path.islink(agent_path), f"Compiled agent binary {agent_path} must not be a symlink."
    assert os.access(agent_path, os.X_OK), f"Agent binary {agent_path} is not executable."
    assert not os.path.samefile(agent_path, oracle_path), "Agent binary must not be the legacy binary."
    assert sha256(agent_path) != sha256(oracle_path), "Agent binary is byte-identical to the legacy binary."

    go_info = subprocess.run(["go", "version", "-m", agent_path], capture_output=True, text=True)
    assert go_info.returncode == 0, f"Submitted executable is not a Go binary: {go_info.stderr}"

    build = subprocess.run(
        ["go", "build", "-o", rebuilt_path, source_path],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, f"acl_compiler.go does not build: {build.stderr}"
    assert os.path.isfile(rebuilt_path) and os.access(rebuilt_path, os.X_OK)

    random.seed(1337)
    inputs = [b"", b"\x00", bytes(range(256))]
    for _ in range(1000):
        length = random.randint(10, 500)
        inputs.append(bytes(random.getrandbits(8) for _ in range(length)))

    # Preserve oracle equivalence testing while also checking independently derived answers.
    oracle_results = []
    for payload in inputs:
        proc = subprocess.run([oracle_path], input=payload, capture_output=True, timeout=10)
        oracle_results.append((proc.returncode, proc.stdout, proc.stderr))
        assert proc.returncode == 0
        assert proc.stdout == expected_output(payload), "Legacy oracle disagrees with derived specification."

    # The replacement and rebuilt source must work without invoking the unstable legacy binary.
    hidden_oracle = "/tmp/legacy_acl_compiler.hidden_for_verification"
    if os.path.lexists(hidden_oracle):
        os.unlink(hidden_oracle)
    os.rename(oracle_path, hidden_oracle)
    try:
        for payload, oracle_result in zip(inputs, oracle_results):
            expected_rc, expected_stdout, _ = oracle_result
            for executable in (agent_path, rebuilt_path):
                proc = subprocess.run([executable], input=payload, capture_output=True, timeout=10)
                assert proc.returncode == expected_rc, (
                    f"Return code mismatch from {executable} on input {payload.hex()[:32]}..."
                )
                assert proc.stdout == expected_stdout, (
                    f"Output mismatch from {executable} on input {payload.hex()[:32]}...\n"
                    f"Expected: {expected_stdout!r}\nGot: {proc.stdout!r}"
                )
    finally:
        os.rename(hidden_oracle, oracle_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
