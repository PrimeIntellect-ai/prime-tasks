#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

import pytest


@pytest.fixture(scope="module", autouse=True)
def execute_and_probe_aggregator():
    script_path = Path("/home/user/aggregator.py")
    binary_path = Path("/home/user/process_chunk.bin")
    log_path = Path("/home/user/fixed_output.log")

    assert script_path.is_file(), f"{script_path} does not exist or is not a file."
    assert binary_path.is_file(), f"{binary_path} does not exist or is not a file."
    assert binary_path.read_bytes()[:4] == b"\x7fELF", f"{binary_path} is not the compiled executable supplied by the task."

    clean_env = os.environ.copy()
    clean_env.pop("FORCE_SAFE_LOGGING_99", None)

    with tempfile.TemporaryDirectory(prefix="aggregator_probe_") as temp_dir:
        temp_path = Path(temp_dir)
        backup_path = temp_path / "process_chunk.bin.original"
        records_path = temp_path / "records"
        records_path.mkdir()

        os.replace(binary_path, backup_path)
        probe_source = f'''#!/usr/bin/env python3
import json
import os
import sys
import uuid

record = {{
    "argv": sys.argv[1:],
    "safe_value": os.environ.get("FORCE_SAFE_LOGGING_99"),
}}
record_path = os.path.join({str(records_path)!r}, f"{{os.getpid()}}-{{uuid.uuid4().hex}}.json")
with open(record_path, "x", encoding="utf-8") as f:
    json.dump(record, f)
'''
        try:
            binary_path.write_text(probe_source, encoding="utf-8")
            binary_path.chmod(0o755)
            probe_result = subprocess.run(
                [sys.executable, str(script_path)],
                cwd="/home/user",
                env=clean_env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
        finally:
            if binary_path.exists():
                binary_path.unlink()
            os.replace(backup_path, binary_path)

        assert probe_result.returncode == 0, (
            "aggregator.py failed while its subprocess calls were being inspected:\n"
            f"stdout:\n{probe_result.stdout}\nstderr:\n{probe_result.stderr}"
        )

        records = []
        for record_file in records_path.glob("*.json"):
            with record_file.open("r", encoding="utf-8") as f:
                records.append(json.load(f))

        assert len(records) == 10, f"aggregator.py must invoke process_chunk.bin exactly 10 times; observed {len(records)} calls."
        expected_texts = {f"Line_data_from_worker_{i}" for i in range(10)}
        observed_texts = set()
        for record in records:
            assert record["safe_value"] == "1", "Every process_chunk.bin subprocess must receive FORCE_SAFE_LOGGING_99 set exactly to '1'."
            assert len(record["argv"]) == 2, f"process_chunk.bin received unexpected arguments: {record['argv']!r}"
            output_path, text = record["argv"]
            assert output_path == "/home/user/fixed_output.log", "Every worker must target /home/user/fixed_output.log."
            observed_texts.add(text)
        assert observed_texts == expected_texts, "The ten worker subprocesses did not receive the expected worker data."

    if log_path.exists():
        assert log_path.is_file(), f"{log_path} should be a file."
        log_path.unlink()

    run_result = subprocess.run(
        [sys.executable, str(script_path)],
        cwd="/home/user",
        env=clean_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert run_result.returncode == 0, (
        "The fixed aggregator.py did not run successfully with the real process_chunk.bin:\n"
        f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
    )


def test_fixed_output_log_exists_and_correct():
    log_file = "/home/user/fixed_output.log"
    assert os.path.exists(log_file), f"{log_file} does not exist. Did you run the script and change the output path?"
    assert os.path.isfile(log_file), f"{log_file} should be a file."

    with open(log_file, "r") as f:
        content = f.read().strip()

    assert content, f"{log_file} is empty."

    lines = content.split('\n')
    assert len(lines) == 10, f"Log file should contain exactly 10 lines, found {len(lines)}."

    expected_lines = {f"Line_data_from_worker_{i}" for i in range(10)}
    actual_lines = set(lines)

    assert actual_lines == expected_lines, "Log file contains garbled or missing lines due to race condition. Ensure the environment variable is passed correctly."


def test_aggregator_script_modifications():
    script_path = "/home/user/aggregator.py"
    assert os.path.exists(script_path), f"{script_path} does not exist."

    with open(script_path, "r") as f:
        script_content = f.read()

    assert "fixed_output.log" in script_content, "The script does not seem to target 'fixed_output.log'."
    assert "FORCE_SAFE_LOGGING_99" in script_content, "The script does not seem to contain the correct environment variable 'FORCE_SAFE_LOGGING_99'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
