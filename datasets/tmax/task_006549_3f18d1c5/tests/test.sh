#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import secrets
import subprocess
import tempfile
import pytest

CPP_PATH = "/home/user/sorter.cpp"
BIN_PATH = "/home/user/sorter_bin"
LOG_PATH = "/home/user/sorted_versions.log"
VERSIONS_PATH = "/home/user/versions.txt"


def expected_output(versions, prefix=None):
    ordered = sorted(versions, key=lambda value: tuple(int(part) for part in value.split('.')))
    if prefix is not None:
        ordered = [prefix + " " + value for value in ordered]
    return "".join(value + "\n" for value in ordered)


def run_program(path, versions, prefix=None):
    data = "".join(value + "\n" for value in versions)
    try:
        result = subprocess.run(
            [path], input=data, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=5, check=False
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{path} timed out while sorting input")
    assert result.returncode == 0, f"{path} exited with {result.returncode}: {result.stderr}"
    assert result.stderr == "", f"{path} wrote unexpected stderr: {result.stderr!r}"
    assert result.stdout == expected_output(versions, prefix), \
        f"{path} did not numerically sort semantic versions correctly"


def generated_versions():
    rng = secrets.SystemRandom()
    values = [
        "1.2.0", "1.10.0", "1.2.1", "0.0.0", "10.0.0",
        "2.0.10", "2.0.2", "12.11.10", "12.11.2", "3.3.3", "3.3.3"
    ]
    for _ in range(70):
        values.append(f"{rng.randrange(0, 40)}.{rng.randrange(0, 60)}.{rng.randrange(0, 80)}")
    rng.shuffle(values)
    return values


def test_sorted_versions_log():
    log_path = "/home/user/sorted_versions.log"
    assert os.path.isfile(log_path), f"Output file {log_path} does not exist."

    expected_lines = [
        "ORG_SYS 0.9.9",
        "ORG_SYS 1.2.3",
        "ORG_SYS 1.2.14",
        "ORG_SYS 1.10.1",
        "ORG_SYS 2.0.0",
        "ORG_SYS 2.1.0",
        "ORG_SYS 2.10.0",
        "ORG_SYS 10.0.0",
        "ORG_SYS 10.0.1"
    ]

    with open(log_path, "r") as f:
        content = f.read()

    lines = content.strip().split('\n')
    assert lines == expected_lines, f"The content of {log_path} does not match the expected sorted output."


def strip_comments_and_literals(code):
    token = re.compile(
        r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
        re.MULTILINE | re.DOTALL
    )
    return token.sub(lambda match: "\n" * match.group(0).count("\n"), code)


def test_sorter_cpp_constraints():
    cpp_path = "/home/user/sorter.cpp"
    assert os.path.isfile(cpp_path), f"Source file {cpp_path} does not exist."

    with open(cpp_path, "r") as f:
        code = f.read()

    # Preserve the original forbidden-component checks.
    forbidden_terms = ["<algorithm>", "std::sort", "std::set", "std::map"]
    for term in forbidden_terms:
        assert term not in code, f"Forbidden term '{term}' found in {cpp_path}."

    # Check the explicitly forbidden vector/array storage as well, allowing
    # ordinary string indexing used solely while parsing a version.
    cleaned = strip_comments_and_literals(code)
    assert not re.search(r'\bstd\s*::\s*(?:vector|array)\b', cleaned), \
        f"Forbidden vector or array container found in {cpp_path}."
    assert not re.search(r'#\s*include\s*[<\"]\s*(?:vector|array)\s*[>\"]', cleaned), \
        f"Forbidden vector or array header found in {cpp_path}."
    array_decl = re.compile(
        r'\b(?:char|wchar_t|char16_t|char32_t|bool|short|int|long|float|double|'
        r'unsigned|signed|auto|std\s*::\s*\w+|[A-Z]\w*)'
        r'(?:\s+|\s*[*&]\s*)[A-Za-z_]\w*\s*\['
    )
    assert not array_decl.search(cleaned), f"Forbidden C-style array declaration found in {cpp_path}."
    assert not re.search(r'\bnew\s+[A-Za-z_:][\w:<>]*\s*\[', cleaned), \
        f"Forbidden dynamically allocated array found in {cpp_path}."

    # Preserve the original conditional-compilation assertion.
    assert re.search(r'#\s*if(def|\s+defined\s*\()\s*PLATFORM_PREFIX', code), \
        f"Conditional compilation for PLATFORM_PREFIX not found in {cpp_path}."

    # Preserve the original custom-structure assertion.
    assert re.search(r'\b(class|struct)\s+\w+', code), \
        f"No custom class or struct found in {cpp_path}."

    # Require evidence of a dynamically linked, self-referential node type,
    # rather than accepting an unrelated dummy struct.
    type_names = re.findall(r'\b(?:class|struct)\s+([A-Za-z_]\w*)', cleaned)
    linked_node_found = False
    for name in type_names:
        link_pattern = rf'(?:\b{name}\s*\*|\b(?:unique_ptr|shared_ptr)\s*<\s*{name}\s*>)'
        allocation_pattern = rf'(?:\bnew\s+{name}\b|\bmake_(?:unique|shared)\s*<\s*{name}\s*>)'
        if len(re.findall(link_pattern, cleaned)) >= 2 and re.search(allocation_pattern, cleaned):
            linked_node_found = True
            break
    assert linked_node_found, "No dynamically linked custom BST node structure was found."


def test_sorter_bin_executable():
    bin_path = "/home/user/sorter_bin"
    assert os.path.isfile(bin_path), f"Executable file {bin_path} does not exist."

    st = os.stat(bin_path)
    assert bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)), \
        f"File {bin_path} is not executable."
    with open(bin_path, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", f"{bin_path} is not a compiled ELF executable."


def test_submitted_binary_behavior_and_required_run():
    with open(VERSIONS_PATH, "r") as source:
        supplied = [line.strip() for line in source if line.strip()]
    run_program(BIN_PATH, supplied, "ORG_SYS")

    with open(LOG_PATH, "r") as output_file:
        recorded = output_file.read()
    assert recorded == expected_output(supplied, "ORG_SYS"), \
        "sorted_versions.log is not the exact output required for versions.txt"

    run_program(BIN_PATH, generated_versions(), "ORG_SYS")


def test_source_builds_with_and_without_platform_prefix():
    cases = generated_versions()
    with tempfile.TemporaryDirectory() as directory:
        plain_bin = os.path.join(directory, "sorter_plain")
        prefixed_bin = os.path.join(directory, "sorter_prefixed")

        plain_build = subprocess.run(
            ["g++", CPP_PATH, "-o", plain_bin],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert plain_build.returncode == 0, f"Source failed to compile without PLATFORM_PREFIX: {plain_build.stderr}"

        prefixed_build = subprocess.run(
            ["g++", '-DPLATFORM_PREFIX="VERIFY_SYS"', CPP_PATH, "-o", prefixed_bin],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert prefixed_build.returncode == 0, f"Source failed to compile with PLATFORM_PREFIX: {prefixed_build.stderr}"

        run_program(plain_bin, cases, None)
        run_program(prefixed_bin, cases, "VERIFY_SYS")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
