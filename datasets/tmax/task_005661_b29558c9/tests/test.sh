#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

SCRIPT_PATH = '/home/user/pipeline_tool.sh'
DATA_DIR = '/home/user/ci_data'
REPORT_PATH = '/home/user/report.txt'
FIXED_MAKEFILE = os.path.join(DATA_DIR, 'Makefile.fixed')


def write_inputs(commit_sha, error_code, error_line, duration_expr, coverage_expr):
    with open(os.path.join(DATA_DIR, 'build.log'), 'w') as f:
        f.write(
            f"Triggered by: https://ci.example.com/webhook?repo=backend&branch=develop&user=admin&commit_sha={commit_sha}\n"
            "Compiling rust_project v0.1.0\n"
            f"error[{error_code}]: use of moved value: `config`\n"
            f"  --> src/main.rs:{error_line}:15\n"
            "   |\n"
            f"{error_line - 1} |     let config = load_config();\n"
            f"{error_line} |     process(config);\n"
        )

    with open(os.path.join(DATA_DIR, 'metrics.txt'), 'w') as f:
        f.write(f"test_duration={duration_expr}\ncoverage={coverage_expr}\n")

    with open(os.path.join(DATA_DIR, 'Makefile.broken'), 'w') as f:
        f.write("all: main.c\n    gcc -wall -o app main.c\n")


def run_tool():
    for path in (REPORT_PATH, FIXED_MAKEFILE):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        [SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"pipeline_tool.sh exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def assert_outputs(expected_lines):
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is missing. The script did not generate the report."

    with open(REPORT_PATH, 'r') as f:
        content = f.read().strip()
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    for expected in expected_lines:
        assert expected in actual_lines, f"Expected line '{expected}' not found in {REPORT_PATH}."

    assert os.path.isfile(FIXED_MAKEFILE), f"{FIXED_MAKEFILE} is missing. The Makefile was not fixed."
    with open(FIXED_MAKEFILE, 'r') as f:
        makefile_content = f.read()

    lines = makefile_content.splitlines()
    assert len(lines) >= 2, f"{FIXED_MAKEFILE} does not have enough lines."
    assert lines[0].strip() == "all: main.c", "First line of Makefile.fixed is incorrect."
    assert lines[1].startswith("\tgcc"), "Second line of Makefile.fixed must start with a tab character followed by 'gcc'."
    assert "-Wall" in lines[1], "Second line of Makefile.fixed must contain '-Wall' instead of '-wall'."
    assert "-wall" not in lines[1], "Second line of Makefile.fixed still contains the invalid '-wall' flag."


def test_pipeline_tool_executes_and_processes_inputs():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable."

    write_inputs('f9a8b7c6', 'E0382', 42, '15+25*4', '850/10')
    run_tool()
    assert_outputs([
        "COMMIT_SHA: f9a8b7c6",
        "RUST_ERROR_CODE: E0382",
        "RUST_ERROR_LINE: 42",
        "test_duration: 115",
        "coverage: 85",
    ])

    commit_sha = secrets.token_hex(8)
    error_code = f"E{secrets.randbelow(10000):04d}"
    error_line = 50 + secrets.randbelow(850)
    a = 10 + secrets.randbelow(40)
    b = 2 + secrets.randbelow(15)
    c = 2 + secrets.randbelow(10)
    divisor = 2 + secrets.randbelow(8)
    coverage = 50 + secrets.randbelow(50)

    write_inputs(
        commit_sha,
        error_code,
        error_line,
        f"{a}+{b}*{c}",
        f"{coverage * divisor}/{divisor}",
    )
    run_tool()
    assert_outputs([
        f"COMMIT_SHA: {commit_sha}",
        f"RUST_ERROR_CODE: {error_code}",
        f"RUST_ERROR_LINE: {error_line}",
        f"test_duration: {a + b * c}",
        f"coverage: {coverage}",
    ])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
