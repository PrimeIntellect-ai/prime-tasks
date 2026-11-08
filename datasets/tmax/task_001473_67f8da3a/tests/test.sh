#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import uuid
import pytest

PROJECT_DIR = "/home/user/poly-parser"


def test_build_rs_configured():
    build_rs_path = os.path.join(PROJECT_DIR, "build.rs")
    assert os.path.isfile(build_rs_path), f"build.rs is missing at {build_rs_path}."
    with open(build_rs_path, "r") as f:
        content = f.read()

    assert "cc::Build" in content or "cc::" in content, "build.rs does not seem to use the 'cc' crate to build the C code."
    assert "fast_parse.c" in content, "build.rs does not reference 'fast_parse.c'."
    assert "fast_parse" in content, "build.rs does not name the compiled static library 'fast_parse'."


def test_lib_rs_bug_fixed():
    lib_rs_path = os.path.join(PROJECT_DIR, "src", "lib.rs")
    assert os.path.isfile(lib_rs_path), f"lib.rs is missing at {lib_rs_path}."
    with open(lib_rs_path, "r") as f:
        content = f.read()

    assert "capacity()" not in content, "The bug using 'capacity()' is still present in lib.rs."
    assert "len()" in content, "The fix using 'len()' was not found in lib.rs."


def _active_yaml_lines(content):
    result = []
    for raw in content.splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if line.strip():
            result.append(line)
    return result


def _workflow_has_test_job(content):
    lines = _active_yaml_lines(content)
    jobs_index = next((i for i, line in enumerate(lines) if re.fullmatch(r"jobs\s*:\s*", line)), None)
    if jobs_index is None:
        return False

    for i in range(jobs_index + 1, len(lines)):
        line = lines[i]
        indent = len(line) - len(line.lstrip())
        if indent == 0:
            break
        if not re.fullmatch(r"\s+[A-Za-z0-9_.-]+\s*:\s*", line):
            continue

        job_indent = indent
        block = []
        for candidate in lines[i + 1:]:
            candidate_indent = len(candidate) - len(candidate.lstrip())
            if candidate_indent <= job_indent:
                break
            block.append(candidate)

        if not any(re.fullmatch(r"\s*runs-on\s*:\s*ubuntu-latest\s*", item) for item in block):
            continue

        steps_pos = next((j for j, item in enumerate(block) if re.fullmatch(r"\s*steps\s*:\s*", item)), None)
        if steps_pos is None:
            continue
        steps_indent = len(block[steps_pos]) - len(block[steps_pos].lstrip())
        step_block = []
        for item in block[steps_pos + 1:]:
            item_indent = len(item) - len(item.lstrip())
            if item_indent <= steps_indent:
                break
            step_block.append(item)

        for j, item in enumerate(step_block):
            match = re.fullmatch(r"\s*(?:-\s*)?run\s*:\s*(.*)", item)
            if not match:
                continue
            value = match.group(1).strip()
            if "cargo test" in value:
                return True
            if value in ("|", ">", "|-", ">-"):
                run_indent = len(item) - len(item.lstrip())
                for command in step_block[j + 1:]:
                    command_indent = len(command) - len(command.lstrip())
                    if command_indent <= run_indent:
                        break
                    if "cargo test" in command:
                        return True
    return False


def test_ci_workflow_created():
    ci_yml_path = os.path.join(PROJECT_DIR, ".github", "workflows", "ci.yml")
    assert os.path.isfile(ci_yml_path), f"CI workflow file is missing at {ci_yml_path}."

    with open(ci_yml_path, "r") as f:
        content = f.read()

    assert "ubuntu-latest" in content, "The CI workflow does not specify 'ubuntu-latest'."
    assert "cargo test" in content, "The CI workflow does not run 'cargo test'."
    assert _workflow_has_test_job(content), "The CI file must define a job on ubuntu-latest with a step that runs cargo test."


def test_review_completed_file():
    review_file = "/home/user/review_completed.txt"
    assert os.path.isfile(review_file), f"Review completed file is missing at {review_file}."

    with open(review_file, "r") as f:
        content = f.read().strip()

    assert content == "PR fixed and tested", f"Review completed file content is incorrect. Expected 'PR fixed and tested', got '{content}'."


def test_real_c_integration_and_length():
    c_path = os.path.join(PROJECT_DIR, "src", "c_src", "fast_parse.c")
    assert os.path.isfile(c_path), f"C source is missing at {c_path}."
    with open(c_path, "rb") as f:
        original_c = f.read()

    test_name = "verifier_dynamic_" + uuid.uuid4().hex
    tests_dir = os.path.join(PROJECT_DIR, "tests")
    os.makedirs(tests_dir, exist_ok=True)
    test_path = os.path.join(tests_dir, test_name + ".rs")
    secret = secrets.randbelow(50000) + 10000
    inputs = ["", "a", "abc", "length-seven", "x" * 65, "Rust_FFI_123"]

    def expected(value):
        data = value.encode("ascii")
        h = secret + len(data) * 17
        for index, byte in enumerate(data):
            h = (h * 131 + byte + index + secret) % 2147483647
        return h

    c_program = f'''#include <stdint.h>
int sum_ascii_values(const char* buf, int len) {{
    uint64_t h = {secret}u + ((uint64_t)len * 17u);
    for (int i = 0; i < len; i++) {{
        h = (h * 131u + (unsigned char)buf[i] + (uint64_t)i + {secret}u) % 2147483647u;
    }}
    return (int)h;
}}
'''
    assertions = "\n".join(
        f'    assert_eq!(poly_parser::process_data({json.dumps(value)}), {expected(value)});'
        for value in inputs
    )
    rust_test = f'''#[test]
fn process_data_calls_compiled_c_with_exact_length() {{
{assertions}
}}
'''

    try:
        with open(c_path, "w") as f:
            f.write(c_program)
        with open(test_path, "w") as f:
            f.write(rust_test)

        subprocess.run(["cargo", "clean"], cwd=PROJECT_DIR, capture_output=True, text=True, check=True)
        result = subprocess.run(
            ["cargo", "test", "-vv", "--test", test_name],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            timeout=180,
        )
        output = result.stdout + "\n" + result.stderr
        assert result.returncode == 0, f"The Rust wrapper did not use the compiled C routine correctly:\n{output}"
        assert (
            "rustc-link-lib=static=fast_parse" in output
            or "-l static=fast_parse" in output
            or "-lfast_parse" in output
        ), f"The build did not link a static library named fast_parse:\n{output}"
    finally:
        with open(c_path, "wb") as f:
            f.write(original_c)
        if os.path.exists(test_path):
            os.remove(test_path)
        subprocess.run(["cargo", "clean"], cwd=PROJECT_DIR, capture_output=True, text=True)


def test_cargo_test_passes():
    try:
        subprocess.run(
            ["cargo", "test"],
            cwd=PROJECT_DIR,
            capture_output=True,
            text=True,
            check=True,
            timeout=180,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"'cargo test' failed. Output:\n{e.stdout}\n{e.stderr}")

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
