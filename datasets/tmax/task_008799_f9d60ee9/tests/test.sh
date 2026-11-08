#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import secrets
import subprocess
import pytest


def test_service_c_recovered():
    recovered_path = "/home/user/logs/service_c_recovered.log"
    assert os.path.isfile(recovered_path), f"Recovered log file {recovered_path} is missing."

    with open(recovered_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "1698242520 Database query started",
        "1698242820 Database query completed"
    ]

    for line in expected_lines:
        assert line in content, f"Expected line '{line}' missing from {recovered_path}."

    # Verify the recovery against the still-open deleted file rather than only
    # trusting hardcoded expected lines.
    deleted_contents = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except (FileNotFoundError, PermissionError):
            continue
        for fd in fds:
            fd_path = f"{fd_dir}/{fd}"
            try:
                target = os.readlink(fd_path)
            except (FileNotFoundError, PermissionError, OSError):
                continue
            if target == "/home/user/logs/service_c.log (deleted)":
                try:
                    with open(fd_path, "rb") as held_file:
                        deleted_contents.append(held_file.read())
                except (FileNotFoundError, PermissionError, OSError):
                    pass

    assert deleted_contents, "Could not find the still-open deleted service_c.log in /proc."
    with open(recovered_path, "rb") as recovered_file:
        recovered_bytes = recovered_file.read()
    assert recovered_bytes in deleted_contents, \
        "service_c_recovered.log does not exactly match the deleted file held open by the emitter."


def test_unified_log_exists_and_correct():
    unified_path = "/home/user/logs/unified.log"
    assert os.path.isfile(unified_path), f"Unified log file {unified_path} is missing."

    with open(unified_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "1698242400 ServiceA System initialized",
        "1698242460 ServiceB Authentication request received",
        "1698242520 ServiceC Database query started",
        "1698242700 ServiceA Connection established",
        "1698242760 ServiceB User logged in successfully",
        "1698242820 ServiceC Database query completed"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {unified_path}, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        actual_stripped = actual.replace("[", "").replace("]", "")
        expected_stripped = expected.replace("[", "").replace("]", "")
        assert actual_stripped == expected_stripped, f"Line {i+1} mismatch. Expected '{expected}', got '{actual}'."


def test_emitter_process_still_running():
    try:
        output = subprocess.check_output(["pgrep", "-f", "service_c_emitter"]).decode("utf-8")
        assert output.strip() != "", "service_c_emitter process is no longer running."
    except subprocess.CalledProcessError:
        pytest.fail("service_c_emitter process is no longer running (pgrep returned non-zero).")


def test_aggregate_script_exists():
    script_path = "/home/user/scripts/aggregate.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."
    with open(script_path, "rb") as script_file:
        first_line = script_file.readline().decode("utf-8", errors="replace").strip()
    assert first_line in ("#!/bin/bash", "#!/usr/bin/env bash"), \
        f"{script_path} must be a Bash script."


def test_aggregate_script_parses_and_sorts_fresh_inputs():
    script_path = "/home/user/scripts/aggregate.sh"
    paths = [
        "/home/user/logs/service_a.log",
        "/home/user/logs/service_b.log",
        "/home/user/logs/service_c_recovered.log",
        "/home/user/logs/unified.log",
    ]
    originals = {}
    for path in paths:
        with open(path, "rb") as f:
            originals[path] = f.read()

    # Vary both timestamps and messages so a script that merely reproduces the
    # incident's six known output lines cannot pass.
    base = 1609459200 + secrets.randbelow(120000000)
    base -= base % 60
    token = secrets.token_hex(8)
    events = [
        (base + 300, "ServiceA", f"alpha {token}"),
        (base + 900, "ServiceA", f"omega {token}"),
        (base + 100, "ServiceB", f"bravo {token}"),
        (base + 700, "ServiceB", f"delta {token}"),
        (base + 500, "ServiceC", f"charlie {token}"),
        (base + 1100, "ServiceC", f"final {token}"),
    ]

    utc = datetime.timezone.utc
    offset = datetime.timezone(datetime.timedelta(hours=-3, minutes=-30))

    def utc_text(epoch):
        return datetime.datetime.fromtimestamp(epoch, utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    def offset_text(epoch):
        local = datetime.datetime.fromtimestamp(epoch, offset)
        return local.strftime("%Y-%m-%d %H:%M:%S") + "-03:30"

    a_lines = [f"{utc_text(epoch)} {message}" for epoch, service, message in events if service == "ServiceA"]
    b_lines = [f"{offset_text(epoch)} {message}" for epoch, service, message in events if service == "ServiceB"]
    c_lines = [f"{epoch} {message}" for epoch, service, message in events if service == "ServiceC"]
    expected = [f"{epoch} {service} {message}" for epoch, service, message in sorted(events)]

    try:
        with open(paths[0], "w") as f:
            f.write("\n".join(a_lines) + "\n")
        with open(paths[1], "w") as f:
            f.write("\n".join(b_lines) + "\n")
        with open(paths[2], "w") as f:
            f.write("\n".join(c_lines) + "\n")
        os.unlink(paths[3])

        result = subprocess.run(
            ["/bin/bash", script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, \
            f"aggregate.sh failed with exit {result.returncode}: {result.stderr}"
        assert os.path.isfile(paths[3]), "aggregate.sh did not create unified.log."

        with open(paths[3], "r") as f:
            actual = [line.strip() for line in f if line.strip()]
        normalized = [line.replace("[", "").replace("]", "") for line in actual]
        assert normalized == expected, \
            f"aggregate.sh did not correctly parse and chronologically sort fresh inputs. Expected {expected}, got {actual}."

        assert subprocess.run(["pgrep", "-f", "service_c_emitter"], stdout=subprocess.DEVNULL).returncode == 0, \
            "service_c_emitter was stopped while aggregate.sh ran."
    finally:
        for path, data in originals.items():
            with open(path, "wb") as f:
                f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
