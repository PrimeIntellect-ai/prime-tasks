#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import gzip
import os
import re
import shutil
import subprocess
import uuid
from pathlib import Path

import pytest


def test_script_exists():
    script_path = "/home/user/process_artifacts.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_output_file_exists():
    output_path = "/home/user/corrupted_report.txt.gz"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."


def test_output_file_content():
    output_path = "/home/user/corrupted_report.txt.gz"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

    try:
        with gzip.open(output_path, "rt", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception as e:
        pytest.fail(f"Failed to read {output_path} as a UTF-8 encoded gzip file: {e}")

    # Clean up whitespace/newlines
    lines = [line.strip() for line in lines if line.strip()]

    expected_lines = [
        "[STATE: CORRUPTED] artifact X-102 checksum failed",
        "[STATE: CORRUPTED] artifact Y-201 invalid header"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, but found {len(lines)} in {output_path}."

    for expected_line in expected_lines:
        assert expected_line in lines, f"Expected line '{expected_line}' not found in the output."

    # Verify no other lines are present
    for line in lines:
        assert line in expected_lines, f"Unexpected line '{line}' found in the output."


def test_script_is_bash_pipeline():
    script_path = "/home/user/process_artifacts.sh"
    text = Path(script_path).read_text(encoding="utf-8")

    syntax = subprocess.run(
        ["/bin/bash", "-n", script_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert syntax.returncode == 0, f"Script has invalid Bash syntax: {syntax.stderr}"

    command = lambda name: re.search(r"(?:^|[|;&()\s])(?:[^\s|;&()]+/)?" + name + r"\b", text, re.MULTILINE)
    assert command("iconv"), "Script does not invoke iconv for streaming character conversion."
    assert command("gzip"), "Script does not invoke gzip for output compression."
    assert command("zcat") or command("gunzip") or re.search(
        r"\bgzip\b[^\n|;&]*(?:--decompress|\s-[A-Za-z]*d[A-Za-z]*)", text
    ), "Script does not contain a streaming gzip decompression command."
    assert "[STATE: CORRUPTED]" in text, "Script does not filter for the required exact marker."

    pipe_count = len(re.findall(r"(?<!\|)\|(?!\|)", text))
    assert pipe_count >= 3, "Script does not pipeline the decompression, conversion, filtering, and compression stages."


def test_script_processes_manifest_and_runtime_inputs():
    script_path = "/home/user/process_artifacts.sh"
    artifacts = Path("/home/user/artifacts")
    output = Path("/home/user/corrupted_report.txt.gz")
    backup = Path(f"/home/user/.artifacts-verifier-backup-{uuid.uuid4().hex}")

    token = uuid.uuid4().hex
    filenames = [
        f"runtime_utf16_{token}.log.gz",
        f"runtime_latin1_{token}.log.gz",
        f"runtime_utf8_{token}.log.gz",
    ]
    source_texts = [
        f"[STATE: OK] runtime {token} ignored\n"
        f"[STATE: CORRUPTED] runtime {token} UTF-16 café failure\n",
        f"prefix [STATE: CORRUPTED] runtime {token} Latin-1 jalapeño failure\n"
        f"[STATE: OK] runtime {token} ignored again\n",
        f"[STATE: OK] runtime {token} clean one\n"
        f"[STATE: OK] runtime {token} clean two\n",
    ]
    encodings = ["UTF-16LE", "ISO-8859-1", "UTF-8"]
    expected = [
        f"[STATE: CORRUPTED] runtime {token} UTF-16 café failure",
        f"prefix [STATE: CORRUPTED] runtime {token} Latin-1 jalapeño failure",
    ]

    old_output = output.read_bytes() if output.exists() else None
    artifacts.rename(backup)
    artifacts.mkdir(mode=0o777)

    try:
        for filename, source, encoding in zip(filenames, source_texts, encodings):
            with gzip.open(artifacts / filename, "wb") as stream:
                stream.write(source.encode(encoding))

        manifest = "".join(
            f"{filename},{encoding}\n"
            for filename, encoding in zip(filenames, encodings)
        )
        (artifacts / "encoding_manifest.csv").write_text(manifest, encoding="utf-8")
        os.chmod(artifacts / "encoding_manifest.csv", 0o666)

        if output.exists() or output.is_symlink():
            output.unlink()

        run = subprocess.run(
            ["/bin/bash", script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )

        assert output.is_file(), (
            "Executing the script did not create /home/user/corrupted_report.txt.gz. "
            f"Exit status: {run.returncode}; stderr: {run.stderr}"
        )

        try:
            with gzip.open(output, "rt", encoding="utf-8") as stream:
                actual = [line.rstrip("\r\n") for line in stream if line.rstrip("\r\n")]
        except Exception as exc:
            pytest.fail(f"Runtime output is not a valid UTF-8 gzip stream: {exc}")

        assert actual == expected, (
            "The executed script did not derive the filtered output from the runtime "
            f"manifest and encoded gzip files. Expected {expected!r}, got {actual!r}. "
            f"Exit status: {run.returncode}; stderr: {run.stderr}"
        )

        allowed = set(filenames) | {"encoding_manifest.csv"}
        leftovers = {entry.name for entry in artifacts.iterdir()} - allowed
        assert not leftovers, f"Script left unexpected intermediate files in artifacts/: {sorted(leftovers)}"
    finally:
        if output.exists() or output.is_symlink():
            output.unlink()
        if old_output is not None:
            output.write_bytes(old_output)

        if artifacts.exists():
            shutil.rmtree(artifacts)
        backup.rename(artifacts)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
