#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import textwrap

PROJECT = "/home/user/pipeline"
ORIGINAL_PARSER = '''#include "parser.h"
int parse_device_state(int event) {
    static int state = 0;
    if (state == 0 && event == 1) { state = 1; return state; }
    if (state == 1 && event == 2) { state = 2; return state; }
    if (state == 2 && event == 3) { state = -1; return state; }
    return -1;
}
'''


def run_checked(args, **kwargs):
    result = subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
        **kwargs,
    )
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(args)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def apply_unified_diff(original, diff_text):
    source = original.splitlines(keepends=True)
    lines = diff_text.splitlines(keepends=True)
    output = []
    source_pos = 0
    hunk_count = 0
    i = 0

    while i < len(lines):
        match = re.match(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", lines[i])
        if not match:
            i += 1
            continue

        hunk_count += 1
        old_start = int(match.group(1))
        old_expected = int(match.group(2) or "1")
        new_expected = int(match.group(4) or "1")
        target_pos = old_start - 1
        assert target_pos >= source_pos, "Patch hunks overlap or are out of order"
        output.extend(source[source_pos:target_pos])
        source_pos = target_pos
        old_seen = 0
        new_seen = 0
        i += 1

        while i < len(lines) and not lines[i].startswith("@@ "):
            line = lines[i]
            if line.startswith("\\ No newline at end of file"):
                i += 1
                continue
            if line.startswith("--- ") or line.startswith("+++ "):
                break
            assert line and line[0] in " +-", f"Malformed unified diff line: {line!r}"
            marker, payload = line[0], line[1:]
            if marker == " ":
                assert source_pos < len(source) and source[source_pos] == payload, "Patch context does not match original parser.c"
                output.append(source[source_pos])
                source_pos += 1
                old_seen += 1
                new_seen += 1
            elif marker == "-":
                assert source_pos < len(source) and source[source_pos] == payload, "Patch deletion does not match original parser.c"
                source_pos += 1
                old_seen += 1
            else:
                output.append(payload)
                new_seen += 1
            i += 1

        assert old_seen == old_expected, f"Patch hunk expected {old_expected} old lines but contained {old_seen}"
        assert new_seen == new_expected, f"Patch hunk expected {new_expected} new lines but contained {new_seen}"

    assert hunk_count > 0, "Patch contains no unified-diff hunks"
    output.extend(source[source_pos:])
    return "".join(output)


def test_test_result_log():
    log_path = "/home/user/test_result.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "SUCCESS" in content, f"Expected 'SUCCESS' in {log_path}, but found: {content}"


def test_parser_patch_exists_and_valid():
    patch_path = "/home/user/pipeline/parser.patch"
    assert os.path.isfile(patch_path), f"Patch file {patch_path} does not exist"
    with open(patch_path, "r") as f:
        content = f.read()
    assert "---" in content and "+++" in content, f"File {patch_path} does not appear to be a unified diff patch"
    assert "state = 3;" in content or "state = -1;" in content, f"Patch {patch_path} doesn't seem to contain the expected state change"

    with open("/home/user/pipeline/src/parser.c", "r") as f:
        current_parser = f.read()
    patched_parser = apply_unified_diff(ORIGINAL_PARSER, content)
    assert patched_parser == current_parser, "parser.patch does not validly transform the original parser.c into the submitted parser.c"


def test_executable_built():
    exe_path = "/home/user/pipeline/build/mobile_test"
    assert os.path.isfile(exe_path), f"Executable {exe_path} does not exist. Did the build succeed?"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable"


def test_parser_c_fixed():
    parser_path = "/home/user/pipeline/src/parser.c"
    assert os.path.isfile(parser_path), f"File {parser_path} does not exist"
    with open(parser_path, "r") as f:
        content = f.read()
    assert re.search(r"if\s*\(\s*state\s*==\s*2\s*&&\s*event\s*==\s*3\s*\)\s*\{\s*state\s*=\s*3\s*;", content), \
        f"File {parser_path} does not seem to have the correct state transition fix for event 3."


def test_cmakelists_fixed():
    cmake_path = "/home/user/pipeline/CMakeLists.txt"
    assert os.path.isfile(cmake_path), f"File {cmake_path} does not exist"
    with open(cmake_path, "r") as f:
        content = f.read()
    has_link_dir = "target_link_directories" in content or "link_directories" in content
    has_find_lib = "find_library" in content
    has_direct_path = "vendor/lib" in content
    assert has_link_dir or has_find_lib or has_direct_path, \
        "CMakeLists.txt does not seem to be modified to link the vendor/lib directory properly."


def test_parser_behavior_independently():
    harness = "/tmp/parser_harness.c"
    binary = "/tmp/parser_harness"
    with open(harness, "w") as f:
        f.write(textwrap.dedent('''
            #include <stdio.h>
            #include "parser.h"
            int main(void) {
                int a = parse_device_state(1);
                int b = parse_device_state(2);
                int c = parse_device_state(3);
                if (a != 1 || b != 2 || c != 3) {
                    fprintf(stderr, "%d %d %d\\n", a, b, c);
                    return 1;
                }
                return 0;
            }
        '''))
    run_checked([
        "gcc", "-Wall", "-Werror", "-I", os.path.join(PROJECT, "include"),
        harness, os.path.join(PROJECT, "src/parser.c"), "-o", binary,
    ])
    run_checked([binary])


def test_clean_build_linkage_and_execution():
    build_dir = os.path.join(PROJECT, "build")
    if os.path.lexists(build_dir):
        if os.path.isdir(build_dir) and not os.path.islink(build_dir):
            shutil.rmtree(build_dir)
        else:
            os.unlink(build_dir)
    os.mkdir(build_dir)

    run_checked(["cmake", ".."], cwd=build_dir)
    run_checked(["make"], cwd=build_dir)

    exe_path = os.path.join(build_dir, "mobile_test")
    assert os.path.isfile(exe_path), "Clean CMake build did not produce mobile_test"
    assert os.access(exe_path, os.X_OK), "Clean CMake build produced a non-executable mobile_test"

    elf = run_checked(["readelf", "-h", exe_path])
    assert "ELF" in elf.stdout, "mobile_test is not an ELF executable"
    dynamic = run_checked(["readelf", "-d", exe_path])
    assert re.search(r"NEEDED.*(?:lib)?device_proto", dynamic.stdout), \
        "mobile_test is not dynamically linked to device_proto"

    ldd = run_checked(["ldd", exe_path])
    assert re.search(r"/home/user/pipeline/vendor/lib/libdevice_proto\.so", ldd.stdout), \
        f"device_proto did not resolve from vendor/lib at runtime:\n{ldd.stdout}"

    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    result = run_checked([exe_path], cwd=build_dir, env=env)
    assert result.stdout.strip() == "SUCCESS", f"Expected executed mobile_test to print SUCCESS, got: {result.stdout!r}"

    with open("/home/user/test_result.log", "r") as f:
        logged = f.read().strip()
    assert logged == result.stdout.strip(), "test_result.log does not match the successful mobile_test output"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
