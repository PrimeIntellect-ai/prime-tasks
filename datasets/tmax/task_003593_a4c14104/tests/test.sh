#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import tempfile
from pathlib import Path

import pytest

PARSER = "/home/user/bin/parser"
VERIFIER = "/home/user/bin/verifier"
ARTIFACT = "/home/user/artifacts/app_v1.bin"
REPORT = "/home/user/artifact_report.txt"
PARSER_SRC = "/home/user/src/parser.c"
VERIFIER_SRC = "/home/user/src/verifier.rs"


def run_checked(argv, **kwargs):
    return subprocess.run(
        argv,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        **kwargs,
    )


def checksum(metadata):
    return sum(metadata.encode("utf-8")) & 0xFFFF


def expected_verifier_line(metadata):
    return f"CHECKSUM: {checksum(metadata):04X} for length {len(metadata.encode('utf-8'))}"


def assert_elf(path):
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF binary."


def test_binaries_exist_and_executable():
    parser_path = "/home/user/bin/parser"
    verifier_path = "/home/user/bin/verifier"

    assert os.path.exists(parser_path), f"Binary {parser_path} does not exist."
    assert os.path.isfile(parser_path), f"{parser_path} is not a file."
    assert os.access(parser_path, os.X_OK), f"Binary {parser_path} is not executable."

    assert os.path.exists(verifier_path), f"Binary {verifier_path} does not exist."
    assert os.path.isfile(verifier_path), f"{verifier_path} is not a file."
    assert os.access(verifier_path, os.X_OK), f"Binary {verifier_path} is not executable."

    assert_elf(parser_path)
    assert_elf(verifier_path)


def test_artifact_report_content():
    report_path = "/home/user/artifact_report.txt"
    assert os.path.exists(report_path), f"Report file {report_path} does not exist."
    assert os.path.isfile(report_path), f"{report_path} is not a file."

    with open(report_path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 2, f"Expected exactly 2 lines in {report_path}, found {len(lines)}."

    expected_line1 = "METADATA: Build_v1.0.42_Release"
    expected_line2 = "CHECKSUM: 06FE for length 21"

    assert lines[0] == expected_line1, f"First line of report is incorrect. Expected '{expected_line1}', got '{lines[0]}'."
    assert lines[1] == expected_line2, f"Second line of report is incorrect. Expected '{expected_line2}', got '{lines[1]}'."


def test_source_files_modified():
    parser_src = "/home/user/src/parser.c"
    assert os.path.exists(parser_src), f"Source file {parser_src} missing."
    with open(parser_src, "r") as f:
        content = f.read()
    # Basic heuristic to ensure double-free is likely removed
    assert content.count("free(buf);") <= 1, "parser.c still appears to have a double-free (multiple free(buf); lines)."


def test_submitted_sources_compile_without_warnings_and_are_memory_safe():
    assert os.path.isfile(VERIFIER_SRC), f"Source file {VERIFIER_SRC} missing."

    with tempfile.TemporaryDirectory() as td:
        c_binary = os.path.join(td, "parser_asan")
        rust_binary = os.path.join(td, "verifier")

        run_checked([
            "gcc", "-Wall", "-Wextra", "-Werror", "-O0", "-g",
            "-fsanitize=address,undefined", PARSER_SRC, "-o", c_binary,
        ])
        run_checked([
            "rustc", "-D", "warnings", VERIFIER_SRC, "-o", rust_binary,
        ])

        metadata_values = [
            "X",
            "Build_" + secrets.token_hex(13),
            "release-" + secrets.token_hex(31),
        ]
        asan_env = os.environ.copy()
        asan_env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1"
        asan_env["UBSAN_OPTIONS"] = "halt_on_error=1"

        for index, metadata in enumerate(metadata_values):
            artifact = os.path.join(td, f"artifact-{index}.bin")
            raw = metadata.encode("utf-8")
            Path(artifact).write_bytes(struct.pack("<I", len(raw)) + raw)

            parsed = run_checked([c_binary, artifact], env=asan_env)
            assert parsed.stdout.splitlines() == [f"METADATA: {metadata}"]

            verified = run_checked([rust_binary, metadata])
            assert verified.stdout.splitlines() == [expected_verifier_line(metadata)]


def test_installed_binaries_on_unpredictable_artifact():
    metadata = "ci-" + secrets.token_hex(37)
    raw = metadata.encode("utf-8")

    with tempfile.TemporaryDirectory() as td:
        artifact = os.path.join(td, "dynamic.bin")
        Path(artifact).write_bytes(struct.pack("<I", len(raw)) + raw)

        parsed = run_checked([PARSER, artifact])
        assert parsed.stdout.splitlines() == [f"METADATA: {metadata}"]

        verified = run_checked([VERIFIER, metadata])
        assert verified.stdout.splitlines() == [expected_verifier_line(metadata)]


def test_report_matches_actual_pipeline_on_provided_artifact():
    data = Path(ARTIFACT).read_bytes()
    assert len(data) >= 4, "Provided artifact is missing its length header."
    length = struct.unpack("<I", data[:4])[0]
    assert len(data) >= 4 + length, "Provided artifact metadata is truncated."
    metadata = data[4:4 + length].decode("utf-8")

    parser_result = run_checked([PARSER, ARTIFACT])
    assert parser_result.stdout.splitlines() == [f"METADATA: {metadata}"]

    verifier_result = run_checked([VERIFIER, metadata])
    assert verifier_result.stdout.splitlines() == [expected_verifier_line(metadata)]

    report_lines = Path(REPORT).read_text().splitlines()
    assert report_lines == [
        parser_result.stdout.rstrip("\n"),
        verifier_result.stdout.rstrip("\n"),
    ], "Report does not match the output of the submitted parser/verifier pipeline."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
