#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import gzip
import io
import json
import os
import shlex
import shutil
import subprocess
import tarfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/project/process_logs.sh"
ARCHIVE_PATH = "/home/user/project/logs.tar.gz"
OUTPUT_PATH = "/home/user/project/error_logs.csv.gz"
PROJECT_DIR = "/home/user/project"


def run_script(env=None):
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd=PROJECT_DIR,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_script_exists_and_executable():
    """Check if the bash script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_runs_and_generates_output():
    """Remove any prebuilt result and require the submitted script to recreate it."""
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_script()


def test_output_file_exists():
    """Check if the output gzip file exists."""
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."


def test_output_file_contents():
    """Check if the output gzip file contains the correct filtered CSV data."""
    expected_lines = [
        '"2023-10-01T10:05:00Z","db","Connection timeout"',
        '"2023-10-01T10:10:00Z","auth","Invalid credentials provided"'
    ]

    try:
        with gzip.open(OUTPUT_PATH, 'rt', encoding='utf-8') as f:
            content = f.read().strip()
    except Exception as e:
        pytest.fail(f"Failed to read {OUTPUT_PATH} as a gzip file: {e}")

    actual_lines = [line.strip() for line in content.split('\n') if line.strip()]

    assert sorted(actual_lines) == sorted(expected_lines), (
        "The contents of the error_logs.csv.gz do not match the expected CSV format or filtered records."
    )


def install_tracer(command, trace_path, backups):
    executable = os.path.realpath(shutil.which(command))
    backup = executable + ".verifier-real-" + uuid.uuid4().hex
    os.replace(executable, backup)
    wrapper = f"""#!/bin/sh
{{
  printf 'BEGIN\\n'
  printf 'FD0=%s\\n' "$(readlink /proc/$$/fd/0 2>/dev/null || true)"
  printf 'FD1=%s\\n' "$(readlink /proc/$$/fd/1 2>/dev/null || true)"
  printf 'ARG=%s\\n' "$@"
  printf 'END\\n'
}} >> {shlex.quote(trace_path)}
exec {shlex.quote(backup)} "$@"
"""
    with open(executable, "w", encoding="utf-8") as f:
        f.write(wrapper)
    os.chmod(executable, 0o755)
    backups.append((executable, backup))


def read_calls(path):
    calls = []
    current = None
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if line == "BEGIN":
                current = {"args": []}
            elif line == "END" and current is not None:
                calls.append(current)
                current = None
            elif current is not None and line.startswith("FD0="):
                current["fd0"] = line[4:]
            elif current is not None and line.startswith("FD1="):
                current["fd1"] = line[4:]
            elif current is not None and line.startswith("ARG="):
                current["args"].append(line[4:])
    return calls


def test_dynamic_archive_is_processed_with_streaming_tools(tmp_path):
    token = uuid.uuid4().hex
    member_names = [f"dynamic-{token}-a.jsonl", f"dynamic-{token}-b.jsonl"]
    records_by_member = [
        [
            {"timestamp": f"{token}-ignore", "level": "INFO", "service": "ignored", "message": "not an error"},
            {"timestamp": f"{token}-01", "level": "ERROR", "service": "billing,api", "message": "failed with spaces"},
        ],
        [
            {"timestamp": f"{token}-02", "level": "ERROR", "service": "auth", "message": "quoted \"value\", retry"},
            {"timestamp": f"{token}-ignore-2", "level": "error", "service": "ignored", "message": "wrong case"},
        ],
    ]
    expected = [
        [f"{token}-01", "billing,api", "failed with spaces"],
        [f"{token}-02", "auth", "quoted \"value\", retry"],
    ]

    original_archive = open(ARCHIVE_PATH, "rb").read()
    original_output = open(OUTPUT_PATH, "rb").read() if os.path.isfile(OUTPUT_PATH) else None
    traces = {name: str(tmp_path / f"{name}.trace") for name in ("tar", "jq", "gzip")}
    backups = []

    try:
        with tarfile.open(ARCHIVE_PATH, "w:gz") as archive:
            for name, records in zip(member_names, records_by_member):
                payload = "".join(json.dumps(r) + "\n" for r in records).encode("utf-8")
                info = tarfile.TarInfo(name)
                info.size = len(payload)
                archive.addfile(info, io.BytesIO(payload))

        for name in member_names:
            assert not os.path.exists(os.path.join(PROJECT_DIR, name))
        if os.path.lexists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        for command in ("tar", "jq", "gzip"):
            install_tracer(command, traces[command], backups)

        run_script(os.environ.copy())

        assert os.path.isfile(OUTPUT_PATH), "The script did not generate the output file."
        with gzip.open(OUTPUT_PATH, "rt", encoding="utf-8", newline="") as f:
            actual = list(csv.reader(f))
        assert sorted(actual) == sorted(expected), (
            "The script did not correctly process verifier-generated JSONL records."
        )

        for name in member_names:
            assert not os.path.exists(os.path.join(PROJECT_DIR, name)), (
                f"Archive member {name} was extracted to disk instead of streamed."
            )

        jq_calls = read_calls(traces["jq"])
        assert jq_calls, "The script did not execute jq to parse and transform the JSON records."

        tar_calls = read_calls(traces["tar"])
        streamed = False
        for call in tar_calls:
            args = call["args"]
            has_extract = any(a == "--extract" or (a.startswith("-") and "x" in a) for a in args)
            has_stdout = any(a == "--to-stdout" or (a.startswith("-") and "O" in a) for a in args)
            if has_extract and has_stdout:
                streamed = True
                break
        assert streamed, "The archive was not read using tar's streaming-to-stdout mode."

        gzip_calls = read_calls(traces["gzip"])
        direct_pipeline = any(
            call.get("fd0", "").startswith("pipe:")
            and os.path.realpath(call.get("fd1", "")) == os.path.realpath(OUTPUT_PATH)
            for call in gzip_calls
        )
        assert direct_pipeline, "CSV data was not piped directly into gzip at the requested output path."
    finally:
        for executable, backup in reversed(backups):
            try:
                if os.path.lexists(executable):
                    os.remove(executable)
                os.replace(backup, executable)
            except FileNotFoundError:
                pass
        with open(ARCHIVE_PATH, "wb") as f:
            f.write(original_archive)
        if original_output is None:
            if os.path.lexists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
