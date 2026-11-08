#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/project/check_abi.sh"
REPORT_PATH = "/home/user/project/report.json"
PLUGIN_PATH = "/home/user/project/plugin.so"
RULES_PATH = "/home/user/project/rules.json"


def version_tuple(value):
    return tuple(int(part) for part in value.split("."))


def analyze_library(path):
    objdump = subprocess.run(
        ["objdump", "-T", path], text=True, capture_output=True, check=True
    )
    versions = re.findall(r"GLIBC_([0-9]+(?:\.[0-9]+)+)", objdump.stdout)
    assert versions, f"No GLIBC versions found in {path}"
    highest = max(versions, key=version_tuple)

    nm = subprocess.run(
        ["nm", "-D", "--defined-only", path],
        text=True,
        capture_output=True,
        check=True,
    )
    text_exports = set()
    for line in nm.stdout.splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[-2] == "T":
            text_exports.add(fields[-1].split("@", 1)[0])
    return highest, text_exports


def expected_for(so_path, rules_path):
    with open(rules_path) as f:
        rules = json.load(f)
    highest, exports = analyze_library(so_path)
    missing = [name for name in rules["required_exports"] if name not in exports]
    passes = version_tuple(highest) <= version_tuple(rules["max_glibc_version"]) and not missing
    return {
        "status": "PASS" if passes else "FAIL",
        "highest_glibc_detected": highest,
        "missing_exports": missing,
    }, 0 if passes else 1


def execute_and_check(so_path, rules_path):
    if os.path.exists(REPORT_PATH):
        os.unlink(REPORT_PATH)

    expected, expected_code = expected_for(so_path, rules_path)
    result = subprocess.run(
        [SCRIPT_PATH, so_path, rules_path],
        cwd="/home/user/project",
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == expected_code, (
        f"Expected exit code {expected_code}, got {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(REPORT_PATH), "Script did not generate report.json"
    with open(REPORT_PATH) as f:
        data = json.load(f)
    assert set(data) == {"status", "highest_glibc_detected", "missing_exports"}
    assert data == expected


@pytest.fixture(scope="session", autouse=True)
def exercise_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with tempfile.TemporaryDirectory() as tmpdir:
        suffix = uuid.uuid4().hex
        export_one = "verify_export_" + suffix
        export_two = "verify_second_" + suffix
        absent = "verify_missing_" + uuid.uuid4().hex
        source_path = os.path.join(tmpdir, "fixture.c")
        so_path = os.path.join(tmpdir, "fixture.so")
        rules_path = os.path.join(tmpdir, "rules.json")

        with open(source_path, "w") as f:
            f.write(
                "#include <stdio.h>\n"
                f"void {export_one}(void) {{ puts(\"fixture\"); }}\n"
                f"int {export_two}(int x) {{ return x + 1; }}\n"
            )
        subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", so_path, source_path], check=True
        )
        highest, _ = analyze_library(so_path)

        with open(rules_path, "w") as f:
            json.dump(
                {
                    "max_glibc_version": highest,
                    "required_exports": [export_one, export_two],
                },
                f,
            )
        execute_and_check(so_path, rules_path)

        with open(rules_path, "w") as f:
            json.dump(
                {
                    "max_glibc_version": highest,
                    "required_exports": [export_one, absent],
                },
                f,
            )
        execute_and_check(so_path, rules_path)

        with open(rules_path, "w") as f:
            json.dump(
                {
                    "max_glibc_version": "0.0",
                    "required_exports": [export_one, export_two],
                },
                f,
            )
        execute_and_check(so_path, rules_path)

    no_args = subprocess.run(
        [SCRIPT_PATH], cwd="/home/user/project", capture_output=True, timeout=20
    )
    assert no_args.returncode != 0, "Script must reject calls with no arguments"
    three_args = subprocess.run(
        [SCRIPT_PATH, PLUGIN_PATH, RULES_PATH, "extra"],
        cwd="/home/user/project",
        capture_output=True,
        timeout=20,
    )
    assert three_args.returncode != 0, "Script must reject calls with more than two arguments"

    # Leave the required final report generated from the original project inputs.
    execute_and_check(PLUGIN_PATH, RULES_PATH)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_report_exists_and_valid():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."

    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

    assert "status" in data, "'status' key missing in report.json"
    assert "highest_glibc_detected" in data, "'highest_glibc_detected' key missing in report.json"
    assert "missing_exports" in data, "'missing_exports' key missing in report.json"


def test_report_content():
    with open(REPORT_PATH, 'r') as f:
        data = json.load(f)

    assert data.get("status") == "FAIL", f"Expected status 'FAIL', got '{data.get('status')}'"

    missing = data.get("missing_exports", [])
    assert isinstance(missing, list), "'missing_exports' must be a list"
    assert "cleanup" in missing, "'cleanup' should be in 'missing_exports'"
    assert len(missing) == 1, f"Expected exactly 1 missing export ('cleanup'), got {len(missing)}"

    glibc = data.get("highest_glibc_detected")
    assert isinstance(glibc, str) and len(glibc) > 0, "'highest_glibc_detected' should be a non-empty string"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
