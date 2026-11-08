#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
from pathlib import Path

import pytest

SOURCE = Path("/home/user/find_chains.cpp")
EXECUTABLE = Path("/home/user/find_chains")
INPUT = Path("/home/user/pipeline_deps.tsv")
OUTPUT = Path("/home/user/chains.txt")

EXPECTED_ORIGINAL = [
    "Extract_Root -> Clean_Data -> Transform_Agg -> Load_Final",
    "Extract_Root -> Clean_Data -> Transform_Join -> Load_Final",
    "Extract_Root -> Clean_Data -> Transform_Join -> Side_Effect_Task -> Load_Final",
    "Extract_Root -> Validate_Schema -> Transform_Join -> Load_Final",
    "Extract_Root -> Validate_Schema -> Transform_Join -> Side_Effect_Task -> Load_Final",
]


def run_program():
    if OUTPUT.exists():
        OUTPUT.unlink()
    subprocess.run([str(EXECUTABLE)], check=True, timeout=10)
    assert OUTPUT.is_file(), f"Program did not create output file {OUTPUT}."


@pytest.fixture(scope="module", autouse=True)
def compile_and_run_submission():
    # Preserve the original existence assertions before rebuilding anything.
    assert SOURCE.is_file(), f"C++ source file {SOURCE} is missing."
    assert EXECUTABLE.is_file(), f"Compiled executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    assert OUTPUT.is_file(), f"Output file {OUTPUT} is missing."

    original_input = INPUT.read_bytes()

    subprocess.run(
        ["g++", "-O2", "-std=c++17", str(SOURCE), "-o", str(EXECUTABLE)],
        check=True,
        timeout=30,
    )
    assert EXECUTABLE.is_file(), "Compilation did not produce the required executable."
    assert os.access(EXECUTABLE, os.X_OK), "Compiled file is not executable."

    run_program()
    yield

    INPUT.write_bytes(original_input)
    try:
        run_program()
    except Exception:
        pass


def test_cpp_file_exists():
    """Check if the C++ source file exists."""
    assert SOURCE.is_file(), f"C++ source file {SOURCE} is missing."


def test_executable_exists():
    """Check if the compiled executable exists and is executable."""
    assert EXECUTABLE.is_file(), f"Compiled executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_output_file_exists():
    """Check if the output chains.txt file exists."""
    assert OUTPUT.is_file(), f"Output file {OUTPUT} is missing."


def test_output_file_content():
    """Check if chains.txt has the correct original content and is sorted."""
    with OUTPUT.open("r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == EXPECTED_ORIGINAL, (
        f"Content of {OUTPUT} does not match the expected chains or is not sorted properly.\n"
        f"Expected:\n{chr(10).join(EXPECTED_ORIGINAL)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def derive_expected(edges):
    adjacency = {}
    for source, target in edges:
        adjacency.setdefault(source, []).append(target)

    paths = []

    def dfs(node, path, active):
        if node == "Load_Final":
            paths.append(" -> ".join(path))
            return
        for target in adjacency.get(node, []):
            if target not in active:
                dfs(target, path + [target], active | {target})

    dfs("Extract_Root", ["Extract_Root"], {"Extract_Root"})
    return sorted(paths)


def test_recompiled_program_parses_and_traverses_additional_graphs():
    cases = [
        [
            ("Extract_Root", "Stage_B"),
            ("Stage_A", "Load_Final"),
            ("Extract_Root", "Stage_A"),
            ("Stage_B", "Shared"),
            ("Stage_A", "Shared"),
            ("Shared", "Load_Final"),
            ("Unrelated", "Load_Final"),
        ],
        [
            ("Extract_Root", "One"),
            ("One", "Two"),
            ("Two", "Three"),
            ("Three", "Load_Final"),
            ("One", "Alternate"),
            ("Alternate", "Four"),
            ("Four", "Load_Final"),
            ("Two", "Dead_End"),
        ],
        [
            ("Extract_Root", "No_Load_Here"),
            ("No_Load_Here", "Dead_End"),
            ("Other_Root", "Load_Final"),
        ],
    ]

    for edges in cases:
        INPUT.write_text("".join(f"{source}\t{target}\n" for source, target in edges))
        expected = derive_expected(edges)
        run_program()
        actual = OUTPUT.read_text().splitlines()
        assert actual == expected, (
            "Program produced incorrect paths for a verification graph.\n"
            f"Expected: {expected}\nActual: {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
