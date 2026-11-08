#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import secrets
import subprocess

SCRIPT_PATH = "/home/user/collect_diagnostics.sh"
REPORT_PATH = "/home/user/diagnostics_report.txt"
REQUIREMENTS_PATH = "/home/user/system_state/app_requirements.txt"
PACKAGES_PATH = "/home/user/system_state/packages.txt"
FRONTEND_PATH = "/home/user/logs/frontend.log"
BACKEND_PATH = "/home/user/logs/backend.log"


def run_script():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        [SCRIPT_PATH], capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"Script executed with non-zero exit code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), (
        f"Report file {REPORT_PATH} was not created by the script."
    )


def read_report_lines():
    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()
    return [line.strip() for line in content.splitlines() if line.strip()]


def derive_expected_report():
    required = {}
    with open(REQUIREMENTS_PATH) as f:
        for line in f:
            line = line.strip()
            if line:
                name, version = line.split("==", 1)
                required[name] = version

    installed = {}
    with open(PACKAGES_PATH) as f:
        for line in f:
            line = line.strip()
            if line:
                name, version = line.split("==", 1)
                installed[name] = version

    conflicts = [
        (name, required_version, installed[name])
        for name, required_version in required.items()
        if name in installed and installed[name] != required_version
    ]
    assert len(conflicts) == 1
    package, required_version, installed_version = conflicts[0]

    events = []
    with open(FRONTEND_PATH) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            timestamp = line.split(None, 1)[0]
            instant = datetime.datetime.strptime(
                timestamp, "%Y-%m-%dT%H:%M:%SZ"
            ).replace(tzinfo=datetime.timezone.utc)
            events.append((instant, line))

    with open(BACKEND_PATH) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            epoch_text = line.split(None, 1)[0]
            instant = datetime.datetime.fromtimestamp(
                int(epoch_text), tz=datetime.timezone.utc
            )
            events.append((instant, line))

    events.sort(key=lambda item: item[0])
    first_fatal = next(instant for instant, line in events if "[FATAL]" in line)
    fatal_timestamp = first_fatal.strftime("%Y-%m-%dT%H:%M:%SZ")

    return [
        f"CONFLICTING_PACKAGE={package}",
        f"REQUIRED_VERSION={required_version}",
        f"INSTALLED_VERSION={installed_version}",
        f"FIRST_FATAL_TIMESTAMP={fatal_timestamp}",
    ]


def iso(epoch):
    return datetime.datetime.fromtimestamp(
        epoch, tz=datetime.timezone.utc
    ).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_dynamic_fixture(frontend_fatal_first):
    token = secrets.token_hex(6)
    conflict = f"conflict_{token}"
    required_version = f"{secrets.randbelow(8) + 1}.{secrets.randbelow(50)}.{secrets.randbelow(50)}"
    installed_version = f"{secrets.randbelow(8) + 10}.{secrets.randbelow(50)}.{secrets.randbelow(50)}"

    with open(REQUIREMENTS_PATH, "w") as f:
        f.write(f"stable_{token}==3.4.5\n")
        f.write(f"{conflict}=={required_version}\n")
        f.write(f"helper_{token}==7.8.9\n")

    with open(PACKAGES_PATH, "w") as f:
        f.write(f"stable_{token}==3.4.5\n")
        f.write(f"extra_{token}==9.9.9\n")
        f.write(f"{conflict}=={installed_version}\n")
        f.write(f"helper_{token}==7.8.9\n")

    base = 1577836800 + secrets.randbelow(150000000)
    frontend_fatal_offset = 35 if frontend_fatal_first else 75
    with open(FRONTEND_PATH, "w") as f:
        f.write(f"{iso(base + 10)} [INFO] Frontend {token} started.\n")
        f.write(f"{iso(base + frontend_fatal_offset)} [FATAL] Frontend failure {token}.\n")
        f.write(f"{iso(base + 90)} [INFO] Frontend stopping.\n")

    with open(BACKEND_PATH, "w") as f:
        f.write(f"{base + 20} [INFO] Backend {token} started.\n")
        f.write(f"{base + 60} [FATAL] Backend failure {token}.\n")
        f.write(f"{base + 80} [INFO] Backend stopping.\n")


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_execution_and_report_generation():
    run_script()


def test_report_content():
    if not os.path.exists(REPORT_PATH):
        subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=15)

    expected_lines = [
        "CONFLICTING_PACKAGE=numpy",
        "REQUIRED_VERSION=1.23.5",
        "INSTALLED_VERSION=1.24.2",
        "FIRST_FATAL_TIMESTAMP=2023-10-25T10:01:02Z",
    ]
    actual_lines = read_report_lines()
    assert actual_lines == expected_lines, (
        "Report content does not match expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_script_handles_changed_inputs():
    paths = [REQUIREMENTS_PATH, PACKAGES_PATH, FRONTEND_PATH, BACKEND_PATH]
    originals = {}
    for path in paths:
        with open(path, "rb") as f:
            originals[path] = f.read()

    try:
        for frontend_fatal_first in (False, True):
            write_dynamic_fixture(frontend_fatal_first)
            expected_lines = derive_expected_report()
            run_script()
            actual_lines = read_report_lines()
            assert actual_lines == expected_lines, (
                "Report was incorrect for dynamically changed package and log inputs.\n"
                f"Expected:\n{chr(10).join(expected_lines)}\n\n"
                f"Actual:\n{chr(10).join(actual_lines)}"
            )
    finally:
        for path, content in originals.items():
            with open(path, "wb") as f:
                f.write(content)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
