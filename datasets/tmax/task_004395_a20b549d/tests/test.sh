#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import uuid

WORKSPACE_DIR = "/home/user/backend_feature"
VALGRIND_REPORT = "/home/user/valgrind_report.txt"
BUILD_SCRIPT = os.path.join(WORKSPACE_DIR, "build.py")


def run_build():
    result = subprocess.run(
        ["python3", BUILD_SCRIPT],
        cwd=WORKSPACE_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        "Executing build.py failed.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def remove_build_outputs():
    for name in ("libparser.o", "processor_native", "processor_web"):
        path = os.path.join(WORKSPACE_DIR, name)
        if os.path.lexists(path):
            os.remove(path)


def assert_elf(path, expected_type):
    assert os.path.isfile(path), f"Build output missing: {path}"
    with open(path, "rb") as f:
        header = f.read(20)
    assert header[:4] == b"\x7fELF", f"{path} is not an ELF file"
    byteorder = "little" if header[5] == 1 else "big"
    elf_type = int.from_bytes(header[16:18], byteorder)
    assert elf_type in expected_type, f"Unexpected ELF type for {path}: {elf_type}"


def test_00_build_script_rebuilds_from_supplied_sources_and_object():
    assert os.path.isfile(BUILD_SCRIPT), f"Build script missing: {BUILD_SCRIPT}"

    processor_path = os.path.join(WORKSPACE_DIR, "processor.cpp")
    parser_path = os.path.join(WORKSPACE_DIR, "libparser.c")
    with open(processor_path, "rb") as f:
        original_processor = f.read()
    with open(parser_path, "rb") as f:
        original_parser = f.read()

    # First require a clean build of the submitted sources.
    remove_build_outputs()
    run_build()
    assert_elf(os.path.join(WORKSPACE_DIR, "libparser.o"), {1})
    assert_elf(os.path.join(WORKSPACE_DIR, "processor_native"), {2, 3})
    assert_elf(os.path.join(WORKSPACE_DIR, "processor_web"), {2, 3})

    token = uuid.uuid4().hex
    native_marker = "Native_" + token
    web_marker = "Web_" + token
    parser_marker = "Parser_" + token

    probe_processor = f'''#include <cstdlib>
#include <iostream>
#include "libparser.h"
int main() {{
#ifdef TARGET_WEB
    std::cout << "{web_marker}" << std::endl;
#elif defined(TARGET_NATIVE)
    std::cout << "{native_marker}" << std::endl;
#else
    std::cout << "WrongTarget" << std::endl;
#endif
    char* parsed = parse_request("probe request");
    std::cout << "Processed: " << parsed << std::endl;
    std::free(parsed);
    return 0;
}}
'''
    probe_parser = f'''#include "libparser.h"
#include <stdlib.h>
#include <string.h>
char* parse_request(const char* input) {{
    (void)input;
    const char* value = "{parser_marker}";
    char* result = (char*)malloc(strlen(value) + 1);
    strcpy(result, value);
    return result;
}}
'''

    probe_error = None
    try:
        with open(processor_path, "w") as f:
            f.write(probe_processor)
        with open(parser_path, "w") as f:
            f.write(probe_parser)

        remove_build_outputs()
        run_build()

        obj = os.path.join(WORKSPACE_DIR, "libparser.o")
        native = os.path.join(WORKSPACE_DIR, "processor_native")
        web = os.path.join(WORKSPACE_DIR, "processor_web")
        assert_elf(obj, {1})
        assert_elf(native, {2, 3})
        assert_elf(web, {2, 3})

        native_result = subprocess.run([native], capture_output=True, text=True, timeout=10)
        web_result = subprocess.run([web], capture_output=True, text=True, timeout=10)
        assert native_result.returncode == 0
        assert web_result.returncode == 0
        assert native_marker in native_result.stdout
        assert web_marker in web_result.stdout
        assert parser_marker in native_result.stdout
        assert parser_marker in web_result.stdout

        symbols = subprocess.run(["nm", obj], capture_output=True, text=True, timeout=10)
        assert symbols.returncode == 0
        assert re.search(r"\bT\s+parse_request\b", symbols.stdout), \
            "libparser.o does not define parse_request"
    except Exception as exc:
        probe_error = exc
    finally:
        with open(processor_path, "wb") as f:
            f.write(original_processor)
        with open(parser_path, "wb") as f:
            f.write(original_parser)
        remove_build_outputs()
        run_build()

    if probe_error is not None:
        raise probe_error


def test_valgrind_report_exists_and_contains_leak():
    assert os.path.isfile(VALGRIND_REPORT), f"Valgrind report missing at {VALGRIND_REPORT}"
    with open(VALGRIND_REPORT, "r") as f:
        content = f.read().lower()
    assert "valgrind" in content, "The file does not appear to be a valgrind report."
    assert "definitely lost:" in content, "Valgrind report does not seem to indicate the initial memory leak ('definitely lost:')."
    assert "heap summary:" in content, "Valgrind report is missing its heap summary."
    match = re.search(r"definitely lost:\s*([0-9,]+) bytes in ([0-9,]+) blocks", content)
    assert match, "Valgrind report has no parseable definitely-lost summary."
    assert int(match.group(1).replace(",", "")) > 0
    assert int(match.group(2).replace(",", "")) > 0


def test_binaries_exist():
    native_bin = os.path.join(WORKSPACE_DIR, "processor_native")
    web_bin = os.path.join(WORKSPACE_DIR, "processor_web")
    assert os.path.isfile(native_bin), f"Compiled binary missing: {native_bin}"
    assert os.path.isfile(web_bin), f"Compiled binary missing: {web_bin}"
    assert os.access(native_bin, os.X_OK), f"Binary {native_bin} is not executable."
    assert os.access(web_bin, os.X_OK), f"Binary {web_bin} is not executable."
    assert_elf(native_bin, {2, 3})
    assert_elf(web_bin, {2, 3})


def test_native_binary_output():
    native_bin = os.path.join(WORKSPACE_DIR, "processor_native")
    result = subprocess.run([native_bin], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {native_bin} failed."
    output = result.stdout.strip()
    assert "Mode: Native" in output, f"processor_native output incorrect. Expected 'Mode: Native', got:\n{output}"
    assert "Processed: GET / HTTP/1.1" in output, f"processor_native output missing 'Processed: GET / HTTP/1.1', got:\n{output}"


def test_web_binary_output():
    web_bin = os.path.join(WORKSPACE_DIR, "processor_web")
    result = subprocess.run([web_bin], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {web_bin} failed."
    output = result.stdout.strip()
    assert "Mode: Web" in output, f"processor_web output incorrect. Expected 'Mode: Web', got:\n{output}"
    assert "Processed: GET / HTTP/1.1" in output, f"processor_web output missing 'Processed: GET / HTTP/1.1', got:\n{output}"


def test_memory_leak_fixed():
    native_bin = os.path.join(WORKSPACE_DIR, "processor_native")
    result = subprocess.run(
        ["valgrind", "--leak-check=full", native_bin],
        capture_output=True,
        text=True
    )
    stderr_output = result.stderr
    assert "definitely lost: 0 bytes in 0 blocks" in stderr_output, \
        "Memory leak not fixed. Valgrind output does not show '0 bytes in 0 blocks' definitely lost."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
