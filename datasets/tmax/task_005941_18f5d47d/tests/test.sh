#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

RAW_PATH = Path("/home/user/data/raw_logs.jsonl")
OUTPUT_PATH = Path("/home/user/data/normalized_logs.jsonl")
SCRIPT_PATH = Path("/home/user/run_pipeline.sh")
BINARY_PATH = Path("/home/user/log_processor/target/release/log_processor")

STATIC_RAW = "\n".join([
    '{"id": 1, "temp_f": 104.0, "notes": "normal log"}',
    '{"id": 2, "temp_f": 50.0, "notes": "malformed \\u001 sequence"}',
    '{"id": 3, "temp_f": 86.0, "notes": "all good here"}',
    '{"id": 4, "temp_f": 32.0, "notes": "another \\u001 issue"}',
    '{"id": 5, "temp_f": 98.6, "notes": "human body temp"}',
]) + "\n"


def test_normalized_logs_exists_and_content():
    """Run the pipeline and verify the normalized fixture output."""
    RAW_PATH.write_text(STATIC_RAW, encoding="utf-8")
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()
    subprocess.run([str(SCRIPT_PATH)], check=True, timeout=30)

    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."

    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        lines = f.read().strip().split("\n")

    assert len(lines) == 5, f"Expected 5 lines in {OUTPUT_PATH}, found {len(lines)}."

    expected_data = [
        {"id": 1, "temp_c": 40.0, "notes": "normal log"},
        {"id": 2, "temp_c": 10.0, "notes": "malformed \u0001 sequence"},
        {"id": 3, "temp_c": 30.0, "notes": "all good here"},
        {"id": 4, "temp_c": 0.0, "notes": "another \u0001 issue"},
        {"id": 5, "temp_c": 37.0, "notes": "human body temp"},
    ]

    for i, line in enumerate(lines):
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} is not valid JSON: {line}")

        expected_obj = expected_data[i]
        assert "temp_f" not in obj, f"Line {i+1} still contains 'temp_f'."
        assert "temp_c" in obj, f"Line {i+1} is missing 'temp_c'."
        assert "id" in obj, f"Line {i+1} is missing 'id'."
        assert "notes" in obj, f"Line {i+1} is missing 'notes'."
        assert obj["id"] == expected_obj["id"], f"Line {i+1} has incorrect 'id'."
        assert abs(obj["temp_c"] - expected_obj["temp_c"]) < 1e-5, f"Line {i+1} has incorrect 'temp_c'."
        assert obj["notes"] == expected_obj["notes"], f"Line {i+1} has incorrect 'notes'."


def test_run_pipeline_script():
    """Verify the run_pipeline.sh script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_rust_binary_exists():
    """Verify the Rust application was built as a release executable."""
    assert os.path.isfile(BINARY_PATH), f"Rust release binary {BINARY_PATH} does not exist."
    assert os.access(BINARY_PATH, os.X_OK), f"Rust release binary {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY_PATH} is not a compiled ELF binary."


def test_binary_processes_derived_inputs():
    """Execute the compiled binary on non-fixture records and derive expected results."""
    old_raw = RAW_PATH.read_bytes() if RAW_PATH.exists() else None
    old_output = OUTPUT_PATH.read_bytes() if OUTPUT_PATH.exists() else None
    raw_lines = []
    expected = []

    for i in range(53):
        record = {
            "id": f"dynamic-{i}",
            "temp_f": i * 7.13 - 91.7,
            "notes": f"record {i}",
            "nested": {"index": i, "even": i % 2 == 0},
            "enabled": i % 3 != 0,
            "optional": None,
        }
        if i % 7 == 2:
            record["notes"] = f"legacy \\u001 marker {i}"

        line = json.dumps(record, ensure_ascii=False, separators=(",", ":"))
        if i % 7 == 2:
            # Turn JSON's escaped literal backslash into the sensor's malformed
            # single-backslash unicode escape.
            line = line.replace("\\\\u001 ", "\\u001 ")
        raw_lines.append(line)

        corrected = line.replace("\\u001 ", "\\u0001 ")
        normalized = json.loads(corrected)
        temp_f = normalized.pop("temp_f")
        normalized["temp_c"] = round((temp_f - 32.0) * 5.0 / 9.0, 2)
        expected.append(normalized)

    try:
        RAW_PATH.write_text("\n".join(raw_lines) + "\n", encoding="utf-8")
        if OUTPUT_PATH.exists():
            OUTPUT_PATH.unlink()

        subprocess.run([str(BINARY_PATH)], check=True, timeout=30)
        assert OUTPUT_PATH.is_file(), "The executed binary did not create the output file."
        produced_lines = OUTPUT_PATH.read_text(encoding="utf-8").splitlines()
        assert len(produced_lines) == len(expected)

        for index, (line, expected_obj) in enumerate(zip(produced_lines, expected)):
            try:
                actual = json.loads(line)
            except json.JSONDecodeError as exc:
                pytest.fail(f"Dynamic output line {index + 1} is invalid JSON: {exc}")

            assert "temp_f" not in actual
            assert set(actual) == set(expected_obj), f"Fields were not preserved on dynamic line {index + 1}."
            for key, value in expected_obj.items():
                if key == "temp_c":
                    assert isinstance(actual[key], (int, float)) and not isinstance(actual[key], bool)
                    assert abs(actual[key] - value) < 1e-9, f"Incorrect conversion on dynamic line {index + 1}."
                else:
                    assert actual[key] == value, f"Field {key!r} changed on dynamic line {index + 1}."
    finally:
        if old_raw is None:
            RAW_PATH.unlink(missing_ok=True)
        else:
            RAW_PATH.write_bytes(old_raw)
        if old_output is None:
            OUTPUT_PATH.unlink(missing_ok=True)
        else:
            OUTPUT_PATH.write_bytes(old_output)


def test_script_invokes_required_binary():
    """Verify the shell script actually invokes the binary at the required path."""
    backup = BINARY_PATH.with_name("log_processor.verifier-backup")
    marker = Path("/tmp/log_processor_invoked")
    marker.unlink(missing_ok=True)
    shutil.copy2(BINARY_PATH, backup)
    try:
        BINARY_PATH.write_text(
            "#!/bin/sh\nprintf invoked > /tmp/log_processor_invoked\n",
            encoding="utf-8",
        )
        BINARY_PATH.chmod(0o755)
        subprocess.run([str(SCRIPT_PATH)], check=True, timeout=30)
        assert marker.read_text(encoding="utf-8") == "invoked", (
            "run_pipeline.sh did not invoke /home/user/log_processor/target/release/log_processor"
        )
    finally:
        shutil.move(str(backup), str(BINARY_PATH))
        marker.unlink(missing_ok=True)


def test_cron_job_installed():
    """Verify the cron job is installed with the correct schedule."""
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Is it installed?")

    expected_cron = "30 2 * * * /home/user/run_pipeline.sh"
    matching_lines = [
        line.strip()
        for line in crontab_output.strip().split("\n")
        if expected_cron in line
    ]
    assert len(matching_lines) > 0, f"Crontab does not contain the expected job: '{expected_cron}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
