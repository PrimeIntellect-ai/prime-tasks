#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import stat
import subprocess

WORKSPACE_DIR = "/home/user/math_util"
BUILD_SCRIPT = os.path.join(WORKSPACE_DIR, "build.sh")
MAIN_GO = os.path.join(WORKSPACE_DIR, "main.go")
RUNNER = os.path.join(WORKSPACE_DIR, "math_runner")
RESULT_FILE = os.path.join(WORKSPACE_DIR, "result.txt")
ASM_FILE = os.path.join(WORKSPACE_DIR, "fast_math.s")


def compute_expected():
    m = 1000000007
    seed = 12345
    total = 0
    for i in range(1, 100001):
        seed = (seed * i) % m
        total = (total + seed) % m
    return str(total)


EXPECTED = compute_expected()


def clean_build_outputs():
    if os.path.lexists(RUNNER):
        os.remove(RUNNER)
    for path in glob.glob(os.path.join(WORKSPACE_DIR, "*.o")):
        os.remove(path)


def run_build():
    subprocess.run(
        [BUILD_SCRIPT],
        cwd=WORKSPACE_DIR,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert os.path.isfile(RUNNER), f"build.sh did not create {RUNNER}"
    assert os.access(RUNNER, os.X_OK), f"math_runner at {RUNNER} is not executable"
    with open(RUNNER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "math_runner is not a compiled ELF executable"


def run_runner():
    completed = subprocess.run(
        [RUNNER],
        cwd=WORKSPACE_DIR,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    output = completed.stdout.strip()
    assert re.fullmatch(r"[0-9]+", output), f"math_runner output is not a single integer: {completed.stdout!r}"
    return output


def test_build_sh_exists_and_executable():
    assert os.path.isfile(BUILD_SCRIPT), f"build.sh is missing at {BUILD_SCRIPT}"
    assert os.access(BUILD_SCRIPT, os.X_OK), f"build.sh at {BUILD_SCRIPT} is not executable"


def test_main_go_exists_and_uses_cgo():
    assert os.path.isfile(MAIN_GO), f"main.go is missing at {MAIN_GO}"
    with open(MAIN_GO, "r") as f:
        content = f.read()
    assert '"C"' in content, "main.go does not seem to use CGO (missing import \"C\")"
    assert re.search(r"\bC\.fast_mult\s*\(", content), "main.go does not call C.fast_mult"


def test_math_runner_exists_and_executable():
    assert os.path.isfile(RUNNER), f"math_runner executable is missing at {RUNNER}"
    assert os.access(RUNNER, os.X_OK), f"math_runner at {RUNNER} is not executable"


def test_result_txt_matches_expected():
    assert os.path.isfile(RESULT_FILE), f"result.txt is missing at {RESULT_FILE}"
    with open(RESULT_FILE, "r") as f:
        result_content = f.read().strip()
    assert result_content == EXPECTED, (
        f"result.txt content '{result_content}' does not match expected '{EXPECTED}'"
    )


def test_build_and_runner_use_fast_mult():
    with open(ASM_FILE, "rb") as f:
        original_asm = f.read()
    original_mode = stat.S_IMODE(os.stat(ASM_FILE).st_mode)

    try:
        clean_build_outputs()
        run_build()
        assert run_runner() == EXPECTED, "freshly built math_runner produced the wrong result"

        instrumented_asm = b""".global fast_mult
.text
fast_mult:
    xor %eax, %eax
    ret
"""
        with open(ASM_FILE, "wb") as f:
            f.write(instrumented_asm)

        clean_build_outputs()
        run_build()
        assert run_runner() == "0", (
            "math_runner output did not change when fast_mult was replaced; "
            "the Go calculation is not using the assembly function"
        )
    finally:
        with open(ASM_FILE, "wb") as f:
            f.write(original_asm)
        os.chmod(ASM_FILE, original_mode)
        clean_build_outputs()
        run_build()

    assert run_runner() == EXPECTED, "restored build produced the wrong result"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
