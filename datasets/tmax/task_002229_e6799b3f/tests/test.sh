#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess

import pytest

PROJECT = "/home/user/log_parser"
MANIFEST = os.path.join(PROJECT, "Cargo.toml")
SOURCE = os.path.join(PROJECT, "src/main.rs")
SERVER_LOG = "/home/user/server.log"
OUTPUT = "/home/user/parsed_payloads.txt"

EXPECTED_SERVER = (
    "[08:00:01] (INFO) - Message: <Service started cleanly>\n"
    "[08:00:05] (WARN) - Message: <Missing fallback configuration>\n"
    "[08:00:10] (ERROR) - Message: <Failed to parse payload: <xml><error>Unclosed tag</error></xml>>\n"
    "[08:00:15] (INFO) - Message: <Request complete: status -> success>\n"
    "[08:00:20] (INFO) - Message: <Shutdown sequence initiated>\n"
)

EXPECTED_LINES = [
    "Service started cleanly",
    "Missing fallback configuration",
    "Failed to parse payload: <xml><error>Unclosed tag</error></xml>",
    "Request complete: status -> success",
    "Shutdown sequence initiated",
]


def test_parsed_payloads_exists():
    path = "/home/user/parsed_payloads.txt"
    assert os.path.isfile(path), f"The output file {path} was not created."


def test_parsed_payloads_content():
    path = "/home/user/parsed_payloads.txt"
    assert os.path.isfile(path), f"The output file {path} was not created."

    expected_lines = EXPECTED_LINES

    with open(path, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, (
        "The contents of parsed_payloads.txt do not match the expected payloads. "
        f"Expected {len(expected_lines)} lines, got {len(actual_lines)}. "
        "Check your parsing logic for off-by-one errors and edge cases."
    )


def test_server_log_unmodified():
    path = "/home/user/server.log"
    assert os.path.isfile(path), f"Server log file is missing: {path}"

    expected_content = EXPECTED_SERVER

    with open(path, "r") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), "The original server.log file was modified. It should remain unchanged."


def cargo_command(*args):
    return subprocess.run(
        ["cargo", *args],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )


def test_source_builds_and_repaired_program_is_executed():
    assert os.path.isfile(MANIFEST), f"Missing Rust manifest: {MANIFEST}"
    assert os.path.isfile(SOURCE), f"Missing parser source: {SOURCE}"
    assert stat.S_ISREG(os.stat(SOURCE).st_mode), f"Parser source is not a regular file: {SOURCE}"

    metadata_result = cargo_command("metadata", "--no-deps", "--format-version", "1", "--manifest-path", MANIFEST)
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    source_real = os.path.realpath(SOURCE)
    bin_targets = [
        target["name"]
        for package in metadata["packages"]
        for target in package["targets"]
        if "bin" in target.get("kind", []) and os.path.realpath(target.get("src_path", "")) == source_real
    ]
    assert bin_targets, "Cargo.toml does not define src/main.rs as a binary target."

    build_result = cargo_command("build", "--manifest-path", MANIFEST, "--bin", bin_targets[0])
    assert build_result.returncode == 0, f"The repaired Rust project did not build:\n{build_result.stderr}"

    with open(SERVER_LOG, "rb") as f:
        original_log = f.read()
    assert original_log.decode() == EXPECTED_SERVER

    with open(OUTPUT, "rb") as f:
        submitted_output = f.read()

    try:
        original_run = cargo_command("run", "--quiet", "--manifest-path", MANIFEST, "--bin", bin_targets[0])
        assert original_run.returncode == 0, f"The repaired parser failed when run:\n{original_run.stderr}"
        assert original_run.stdout.encode() == submitted_output, (
            "parsed_payloads.txt is not the standard output produced by the repaired program."
        )
        assert original_run.stdout.splitlines() == EXPECTED_LINES
        with open(SERVER_LOG, "rb") as f:
            assert f.read() == original_log, "Running the parser modified server.log."

        token = secrets.token_hex(12)
        payloads = [
            f"dynamic-{token}",
            f"left>{token}<middle>right",
            f"Request result -> success-{token}",
            f"<xml><item>{token}</item></xml>",
            f"nested <first>{token}</first> and tail>value",
        ]
        generated_log = "".join(
            f"[09:00:{index:02d}] prefix > decoy (INFO) - Message: <{payload}>\n"
            for index, payload in enumerate(payloads, 1)
        )
        with open(SERVER_LOG, "w") as f:
            f.write(generated_log)

        generated_run = cargo_command("run", "--quiet", "--manifest-path", MANIFEST, "--bin", bin_targets[0])
        assert generated_run.returncode == 0, f"The parser failed on generated log records:\n{generated_run.stderr}"
        assert generated_run.stdout.splitlines() == payloads, (
            "The repaired parser did not correctly extract generated payloads containing internal '>' characters."
        )
        with open(SERVER_LOG, "r") as f:
            assert f.read() == generated_log, "Running the parser modified the generated input log."
    finally:
        with open(SERVER_LOG, "wb") as f:
            f.write(original_log)
        with open(OUTPUT, "wb") as f:
            f.write(submitted_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
