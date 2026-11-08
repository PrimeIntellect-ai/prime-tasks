#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import uuid

MANIFEST_PATH = "/home/user/workspace/backup_manifest.log"
APP_SERVICE_PATH = "/home/user/workspace/app.service"
STATUS_PATH = "/home/user/workspace/restore_status.txt"
SCRIPT_PATH = "/home/user/fix_service.py"


def get_extracted_service_name():
    assert os.path.exists(MANIFEST_PATH), f"File {MANIFEST_PATH} is missing."
    with open(MANIFEST_PATH, "r") as f:
        for line in f:
            if line.startswith("Requires System Service: "):
                return line.split("Requires System Service: ")[1].strip()
    return None


def section_lines(path, wanted_section):
    result = []
    current_section = None
    with open(path, "r") as f:
        for raw_line in f:
            stripped = raw_line.strip()
            if stripped.startswith("[") and stripped.endswith("]"):
                current_section = stripped[1:-1]
            elif current_section == wanted_section:
                result.append(stripped)
    return result


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."


def test_app_service_modified():
    service_name = get_extracted_service_name()
    assert service_name is not None, "Could not find expected service name in backup_manifest.log"

    assert os.path.exists(APP_SERVICE_PATH), f"File {APP_SERVICE_PATH} does not exist."
    with open(APP_SERVICE_PATH, "r") as f:
        content = f.read()

    assert f"After={service_name}" in content, f"app.service is missing 'After={service_name}'"
    assert f"Wants={service_name}" in content, f"app.service is missing 'Wants={service_name}'"

    unit = section_lines(APP_SERVICE_PATH, "Unit")
    assert unit.count(f"After={service_name}") == 1, \
        f"Expected exactly one 'After={service_name}' line under [Unit]."
    assert unit.count(f"Wants={service_name}") == 1, \
        f"Expected exactly one 'Wants={service_name}' line under [Unit]."


def test_restore_status_file():
    service_name = get_extracted_service_name()
    assert os.path.exists(STATUS_PATH), f"File {STATUS_PATH} does not exist."

    with open(STATUS_PATH, "r") as f:
        status = f.read().strip()

    assert status in [f"SUCCESS: Added {service_name}", "SUCCESS: Already configured"], \
        f"restore_status.txt contains incorrect content: {status}"


def test_script_idempotency():
    service_name = get_extracted_service_name()

    result = subprocess.run(["python3", SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script execution failed with error: {result.stderr}"

    with open(STATUS_PATH, "r") as f:
        status = f.read().strip()

    assert status == "SUCCESS: Already configured", \
        f"Expected 'SUCCESS: Already configured' in {STATUS_PATH} after second run, got '{status}'"

    with open(APP_SERVICE_PATH, "r") as f:
        content = f.read()

    after_count = content.count(f"After={service_name}")
    wants_count = content.count(f"Wants={service_name}")

    assert after_count == 1, f"Found {after_count} 'After={service_name}' lines in app.service, expected exactly 1."
    assert wants_count == 1, f"Found {wants_count} 'Wants={service_name}' lines in app.service, expected exactly 1."


def run_script():
    result = subprocess.run(["python3", SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, \
        f"Script execution failed with stdout={result.stdout!r}, stderr={result.stderr!r}"


def assert_status(expected):
    with open(STATUS_PATH, "r") as f:
        value = f.read()
    assert value in (expected, expected + "\n"), \
        f"Expected restore_status.txt to contain one line {expected!r}, got {value!r}"


def test_dynamic_manifest_parsing_section_placement_and_idempotency():
    original_manifest = open(MANIFEST_PATH, "rb").read()
    original_service = open(APP_SERVICE_PATH, "rb").read()
    status_existed = os.path.exists(STATUS_PATH)
    original_status = open(STATUS_PATH, "rb").read() if status_existed else None

    try:
        service_name = f"db-{uuid.uuid4().hex}.service"
        with open(MANIFEST_PATH, "w") as f:
            f.write(
                "Backup Job ID: dynamic-test\n"
                "Unrelated Service: should-not-be-used.service\n"
                f"Requires System Service: {service_name}\n"
                "Status: OK\n"
            )
        with open(APP_SERVICE_PATH, "w") as f:
            f.write(
                "[Unit]\n"
                "Description=Dynamic restore test\n"
                "Documentation=https://example.invalid/restore\n"
                "After=network.target\n"
                "X-Custom=preserve-me\n"
                "\n"
                "[Service]\n"
                f"After={service_name}\n"
                f"Wants={service_name}\n"
                "ExecStart=/opt/example --flag\n"
                "Restart=on-failure\n"
                "\n"
                "[Install]\n"
                "WantedBy=multi-user.target\n"
            )

        run_script()
        assert_status(f"SUCCESS: Added {service_name}")
        unit = section_lines(APP_SERVICE_PATH, "Unit")
        assert unit.count(f"After={service_name}") == 1
        assert unit.count(f"Wants={service_name}") == 1

        with open(APP_SERVICE_PATH, "r") as f:
            first_result = f.read()
        for preserved in (
            "Description=Dynamic restore test",
            "Documentation=https://example.invalid/restore",
            "After=network.target",
            "X-Custom=preserve-me",
            "ExecStart=/opt/example --flag",
            "Restart=on-failure",
            "WantedBy=multi-user.target",
        ):
            assert preserved in first_result, f"Existing setting was removed: {preserved}"

        run_script()
        assert_status("SUCCESS: Already configured")
        with open(APP_SERVICE_PATH, "r") as f:
            second_result = f.read()
        assert second_result == first_result, "app.service changed on an idempotent second run"
        unit = section_lines(APP_SERVICE_PATH, "Unit")
        assert unit.count(f"After={service_name}") == 1
        assert unit.count(f"Wants={service_name}") == 1

        partial_service = f"cache-{uuid.uuid4().hex}.service"
        with open(MANIFEST_PATH, "w") as f:
            f.write(f"Requires System Service: {partial_service}\n")
        with open(APP_SERVICE_PATH, "w") as f:
            f.write(
                "[Unit]\n"
                "Description=Partial dependency test\n"
                f"After={partial_service}\n"
                "\n"
                "[Service]\n"
                "ExecStart=/bin/true\n"
            )

        run_script()
        assert_status(f"SUCCESS: Added {partial_service}")
        unit = section_lines(APP_SERVICE_PATH, "Unit")
        assert unit.count(f"After={partial_service}") == 1, "Existing After line was duplicated"
        assert unit.count(f"Wants={partial_service}") == 1, "Missing Wants line was not added"
    finally:
        with open(MANIFEST_PATH, "wb") as f:
            f.write(original_manifest)
        with open(APP_SERVICE_PATH, "wb") as f:
            f.write(original_service)
        if status_existed:
            with open(STATUS_PATH, "wb") as f:
                f.write(original_status)
        elif os.path.exists(STATUS_PATH):
            os.remove(STATUS_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
