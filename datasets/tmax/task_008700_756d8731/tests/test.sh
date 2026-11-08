#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import uuid
from collections import defaultdict

SCRIPT_PATH = "/home/user/process_assets.sh"
SOURCE_PATH = "/home/user/manifest_parser.c"
PARSER_PATH = "/home/user/parser"
MANIFEST_DIR = "/home/user/manifests"
SUMMARY_PATH = "/home/user/summary.log"


def run_script():
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:abort_on_error=1"
    return subprocess.run(
        [SCRIPT_PATH], capture_output=True, text=True, timeout=30, env=env
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_declares_associative_array_and_requests_asan():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        script = f.read()

    active_lines = []
    for line in script.splitlines():
        stripped = line.lstrip()
        if not stripped.startswith("#"):
            active_lines.append(line)
    active = "\n".join(active_lines)

    assert re.search(r"(?:^|[;&|\n]\s*)(?:declare|typeset)\s+(?:-[A-Za-z]*A[A-Za-z]*|-A)\s+", active), \
        "process_assets.sh must declare and use a Bash associative array."
    assert re.search(r"\bgcc\b", active), "process_assets.sh must compile with gcc."
    assert "-fsanitize=address" in active, \
        "process_assets.sh must compile manifest_parser.c with -fsanitize=address."
    assert "manifest_parser.c" in active and "parser" in active, \
        "process_assets.sh must compile manifest_parser.c into parser."


def test_script_execution():
    result = run_script()
    assert result.returncode == 0, \
        f"Script failed to execute or ASAN error occurred. Stderr: {result.stderr}"
    assert "AddressSanitizer" not in result.stderr, \
        f"AddressSanitizer reported an error: {result.stderr}"

    assert os.path.isfile(PARSER_PATH), f"Compiled parser {PARSER_PATH} does not exist."
    assert os.access(PARSER_PATH, os.X_OK), f"Compiled parser {PARSER_PATH} is not executable."
    with open(PARSER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "parser is not a compiled ELF executable."

    symbols = subprocess.run(
        ["nm", "-D", PARSER_PATH], capture_output=True, text=True, timeout=10
    )
    assert symbols.returncode == 0 and "__asan_init" in symbols.stdout, \
        "The generated parser was not compiled with AddressSanitizer."


def test_summary_log_contents():
    assert os.path.isfile(SUMMARY_PATH), f"Summary log {SUMMARY_PATH} does not exist."

    with open(SUMMARY_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_lines = [
        "AUDIO: 640",
        "METADATA: 64",
        "MODEL: 5120",
        "TEXTURE: 3072",
        "TEXTURE_HIGH_RESOLUTION_ASSET_NAME_OVER_SIXTEEN_CHARS: 8192"
    ]
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert actual_lines == expected_lines, (
        f"Contents of {SUMMARY_PATH} do not match expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_repaired_source_handles_256_character_names_without_asan_errors_or_leaks():
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} does not exist."
    token = uuid.uuid4().hex.upper()
    long_name = ("LONG_" + token + "X" * 256)[:256]

    with tempfile.TemporaryDirectory() as td:
        binary = os.path.join(td, "parser")
        manifest = os.path.join(td, "manifest.txt")
        compile_result = subprocess.run(
            ["gcc", "-fsanitize=address", "-g", SOURCE_PATH, "-o", binary],
            capture_output=True, text=True, timeout=30
        )
        assert compile_result.returncode == 0, \
            f"manifest_parser.c does not compile with ASAN: {compile_result.stderr}"

        with open(manifest, "w", encoding="utf-8") as f:
            f.write(f"{long_name} 12345\nSHORT_{token} 7\n")

        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:abort_on_error=1"
        result = subprocess.run(
            [binary, manifest], capture_output=True, text=True, timeout=20, env=env
        )
        assert result.returncode == 0, \
            f"Repaired parser failed under ASAN: {result.stderr}"
        assert "AddressSanitizer" not in result.stderr and "LeakSanitizer" not in result.stderr, \
            f"Parser produced an ASAN/LeakSanitizer error: {result.stderr}"
        assert result.stdout.splitlines() == [
            f"ASSET: {long_name} 12345",
            f"ASSET: SHORT_{token} 7",
        ], "Parser did not safely preserve and print asset names up to 256 characters."


def test_dynamic_manifests_are_parsed_and_aggregated():
    token = uuid.uuid4().hex.upper()
    type_a = "DYNAMIC_" + token
    type_b = ("Z" * (256 - len(token) - 1)) + "_" + token
    manifest_path = os.path.join(MANIFEST_DIR, f"dynamic_{uuid.uuid4().hex}.txt")

    try:
        with open(manifest_path, "w", encoding="utf-8") as f:
            f.write(f"{type_a} 137\n")
            f.write(f"{type_b} 1009\n")
            f.write(f"{type_a} 863\n")

        expected = defaultdict(int)
        for filename in os.listdir(MANIFEST_DIR):
            if not filename.endswith(".txt"):
                continue
            with open(os.path.join(MANIFEST_DIR, filename), "r", encoding="utf-8") as f:
                for line in f:
                    fields = line.split()
                    assert len(fields) == 2, f"Invalid verifier fixture line: {line!r}"
                    expected[fields[0]] += int(fields[1])

        result = run_script()
        assert result.returncode == 0, \
            f"Script failed on dynamic manifests or triggered ASAN: {result.stderr}"
        assert "AddressSanitizer" not in result.stderr, \
            f"AddressSanitizer reported an error on dynamic input: {result.stderr}"

        assert os.path.isfile(SUMMARY_PATH), "Script did not create summary.log."
        with open(SUMMARY_PATH, "r", encoding="utf-8") as f:
            actual = [line.rstrip("\n") for line in f if line.strip()]
        wanted = [f"{name}: {expected[name]}" for name in sorted(expected)]
        assert actual == wanted, (
            "summary.log did not aggregate every .txt manifest or was not sorted/formatted "
            f"correctly. Expected {wanted!r}, got {actual!r}"
        )
    finally:
        if os.path.exists(manifest_path):
            os.unlink(manifest_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
