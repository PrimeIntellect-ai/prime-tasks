#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import subprocess
import tempfile
import uuid

import pytest

LEGACY_DIR = "/home/user/legacy_tool"
C_BINARY = os.path.join(LEGACY_DIR, "fast-stat")
WRAPPER_DIR = "/home/user/wrapper"
MANIFEST = os.path.join(WRAPPER_DIR, "Cargo.toml")
REPORT = "/home/user/report.json"


def run(command, **kwargs):
    kwargs.setdefault("text", True)
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("timeout", 60)
    return subprocess.run(command, **kwargs)


def load_report():
    assert os.path.isfile(REPORT), f"The report file {REPORT} was not generated."
    with open(REPORT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT} does not contain valid JSON.")
    assert type(data) is dict, "The JSON report must be an object."
    return data


def assert_strict_report(data, expected):
    assert set(data) == {"records", "anomalies", "duration"}, "The JSON report does not use the required strict schema."
    for key, value in expected.items():
        assert type(data[key]) is int, f"The JSON value for {key} must be an integer."
        assert data[key] == value, f"Expected {key}={value}, but got {data[key]}."


def parse_c_report(output):
    match = re.fullmatch(
        r"--- STAT REPORT ---\nRecords: (\d+)\nAnomalies: (\d+)\nDuration: (\d+)\n--- END ---\n?",
        output,
    )
    assert match, f"fast-stat produced output in an unexpected format: {output!r}"
    return tuple(int(value) for value in match.groups())


def test_fast_stat_executable():
    binary_path = "/home/user/legacy_tool/fast-stat"
    assert os.path.isfile(binary_path), f"The compiled binary {binary_path} does not exist. Did you run make?"
    assert os.access(binary_path, os.X_OK), f"The file {binary_path} is not executable."


def test_makefile_fixed():
    makefile_path = "/home/user/legacy_tool/Makefile"
    assert os.path.isfile(makefile_path), f"Makefile {makefile_path} is missing."

    with open(makefile_path, "r") as f:
        lines = f.readlines()

    content = "".join(lines)
    assert "-Wmissing-headers" not in content, "The invalid '-Wmissing-headers' flag is still in the Makefile."

    has_tab_indent = any(line.startswith("\tgcc") for line in lines)
    assert has_tab_indent, "The Makefile does not have a properly tab-indented 'gcc' command for the fast-stat target."


def test_c_file_fixed():
    c_file_path = "/home/user/legacy_tool/fast-stat.c"
    assert os.path.isfile(c_file_path), f"C source file {c_file_path} is missing."

    with open(c_file_path, "r") as f:
        content = f.read()

    assert "/var/log/legacy_telemetry.log" not in content, "The hardcoded file path is still present in the C source code."
    assert "DATA_FILE" in content, "The C source code does not seem to read the 'DATA_FILE' environment variable."
    assert "<stdlib.h>" in content, "The C source code is missing the <stdlib.h> include."
    assert "<string.h>" in content, "The C source code is missing the <string.h> include."


def test_make_really_builds_and_c_binary_behaves():
    if os.path.lexists(C_BINARY):
        os.remove(C_BINARY)
    result = run(["make"], cwd=LEGACY_DIR)
    assert result.returncode == 0, f"Running make failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.isfile(C_BINARY), "make did not create the fast-stat binary."
    assert os.access(C_BINARY, os.X_OK), "The fast-stat output from make is not executable."

    env = os.environ.copy()
    env.pop("DATA_FILE", None)
    missing_env = run([C_BINARY], env=env)
    assert missing_env.returncode == 1, f"fast-stat must exit with code 1 when DATA_FILE is unset, but returned {missing_env.returncode}."

    record_count = random.SystemRandom().randint(3, 12)
    anomaly_indices = set(random.SystemRandom().sample(range(record_count), random.SystemRandom().randint(1, record_count - 1)))
    lines = ["DATA_START"]
    for index in range(record_count):
        status = "ANOMALY" if index in anomaly_indices else "OK"
        lines.append(f"rec_dynamic_{index}: {status}")
    lines.append("DATA_END")

    fd, data_path = tempfile.mkstemp(prefix="telemetry-", suffix=".txt")
    try:
        with os.fdopen(fd, "w") as data_file:
            data_file.write("\n".join(lines) + "\n")
        env["DATA_FILE"] = data_path
        result = run([C_BINARY], env=env)
        assert result.returncode == 0, f"fast-stat failed on a valid DATA_FILE:\n{result.stderr}"
        assert parse_c_report(result.stdout) == (record_count, len(anomaly_indices), 42)
    finally:
        if os.path.exists(data_path):
            os.remove(data_path)


def test_rust_project_exists_builds_and_declares_dependencies():
    assert os.path.isfile(MANIFEST), "The Rust wrapper Cargo.toml is missing."
    assert os.path.isfile(os.path.join(WRAPPER_DIR, "src", "main.rs")), "The Rust wrapper src/main.rs is missing."

    metadata_result = run(["cargo", "metadata", "--manifest-path", MANIFEST, "--no-deps", "--format-version", "1"])
    assert metadata_result.returncode == 0, f"Cargo could not read the wrapper project:\n{metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    packages = [package for package in metadata["packages"] if package["manifest_path"] == MANIFEST]
    assert packages, "Cargo metadata does not contain the telemetry_parser package."
    package = packages[0]
    assert package["name"] == "telemetry_parser", "The Rust project must be named telemetry_parser."
    dependency_names = {dependency["name"] for dependency in package["dependencies"]}
    assert "serde" in dependency_names, "The Rust project does not declare the serde dependency."
    assert "serde_json" in dependency_names, "The Rust project does not declare the serde_json dependency."

    build = run(["cargo", "build", "--manifest-path", MANIFEST])
    assert build.returncode == 0, f"The Rust wrapper failed to build:\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    wrapper_binary = os.path.join(metadata["target_directory"], "debug", "telemetry_parser")
    assert os.path.isfile(wrapper_binary), "Cargo did not produce the telemetry_parser executable."
    assert os.access(wrapper_binary, os.X_OK), "The telemetry_parser output is not executable."


def test_wrapper_executes_fast_stat_sets_environment_and_parses_output():
    metadata_result = run(["cargo", "metadata", "--manifest-path", MANIFEST, "--no-deps", "--format-version", "1"])
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    wrapper_binary = os.path.join(metadata["target_directory"], "debug", "telemetry_parser")
    assert os.path.isfile(wrapper_binary), "The compiled Rust wrapper is missing."

    rng = random.SystemRandom()
    expected = {
        "records": rng.randint(101, 999),
        "anomalies": rng.randint(11, 99),
        "duration": rng.randint(1001, 9999),
    }
    marker = os.path.join(tempfile.gettempdir(), f"fast-stat-ran-{uuid.uuid4().hex}")
    backup = os.path.join(tempfile.gettempdir(), f"fast-stat-backup-{uuid.uuid4().hex}")
    shutil.copy2(C_BINARY, backup)

    mock = f'''#!/bin/sh
if [ "$DATA_FILE" != "/home/user/data/input.txt" ]; then
    exit 23
fi
printf 'ran' > '{marker}'
printf '%s\\n' '--- STAT REPORT ---' 'Records: {expected["records"]}' 'Anomalies: {expected["anomalies"]}' 'Duration: {expected["duration"]}' '--- END ---'
'''
    try:
        with open(C_BINARY, "w") as mock_file:
            mock_file.write(mock)
        os.chmod(C_BINARY, 0o755)
        if os.path.exists(REPORT):
            os.remove(REPORT)

        result = run([wrapper_binary], cwd=WRAPPER_DIR)
        assert result.returncode == 0, f"The Rust wrapper failed while executing fast-stat:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        assert os.path.isfile(marker), "The Rust wrapper did not execute /home/user/legacy_tool/fast-stat."
        assert_strict_report(load_report(), expected)
    finally:
        if os.path.exists(backup):
            os.replace(backup, C_BINARY)
        if os.path.exists(marker):
            os.remove(marker)


def test_report_json():
    metadata_result = run(["cargo", "metadata", "--manifest-path", MANIFEST, "--no-deps", "--format-version", "1"])
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    wrapper_binary = os.path.join(metadata["target_directory"], "debug", "telemetry_parser")

    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = run([wrapper_binary], cwd=WRAPPER_DIR)
    assert result.returncode == 0, f"The compiled Rust wrapper failed on the provided input:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"

    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"The report file {report_path} was not generated."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} does not contain valid JSON.")

    assert "records" in data, "The JSON report is missing the 'records' key."
    assert "anomalies" in data, "The JSON report is missing the 'anomalies' key."
    assert "duration" in data, "The JSON report is missing the 'duration' key."

    assert data["records"] == 7, f"Expected 7 records, but got {data['records']}."
    assert data["anomalies"] == 2, f"Expected 2 anomalies, but got {data['anomalies']}."
    assert data["duration"] == 42, f"Expected duration of 42, but got {data['duration']}."
    assert_strict_report(data, {"records": 7, "anomalies": 2, "duration": 42})
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
