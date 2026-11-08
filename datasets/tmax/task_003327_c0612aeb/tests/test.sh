#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import tempfile

EXPECTED_EMULATOR = '''import os
import math

def patch_math():
    if os.environ.get("TARGET_ARCH") == "arm64":
        # Simulate lower precision for ARM emulator
        original_sin = math.sin
        math.sin = lambda x: round(original_sin(x), 2)

patch_math()
'''

EXPECTED_TEST = '''import os
import mobile_emulator # This correctly patches math first
from math import sin

target = os.environ.get("TARGET_ARCH", "x86")
expected = [sin(i * 0.1) for i in range(10)]

try:
    with open(f"lookup_{target}.h", "r") as f:
        lines = f.readlines()[1:-1]
    actual = [float(line.strip().replace("f,", "")) for line in lines]

    if actual == expected:
        print("PASS")
        import sys; sys.exit(0)
    else:
        print("FAIL: Values do not match emulator precision")
        import sys; sys.exit(1)
except Exception as e:
    print(f"FAIL: {e}")
    import sys; sys.exit(1)
'''


def assert_prohibited_files_unchanged():
    base = "/home/user/mobile_pipeline"
    emulator_path = os.path.join(base, "mobile_emulator.py")
    test_path = os.path.join(base, "test_lookup.py")
    assert os.path.isfile(emulator_path), f"{emulator_path} is missing"
    assert os.path.isfile(test_path), f"{test_path} is missing"
    with open(emulator_path, "r") as f:
        assert f.read() == EXPECTED_EMULATOR, "mobile_emulator.py was modified"
    with open(test_path, "r") as f:
        assert f.read() == EXPECTED_TEST, "test_lookup.py was modified"


def parse_and_check_header(header_path):
    with open(header_path, "r") as f:
        content = f.read()

    match = re.fullmatch(
        r"\s*float\s+sin_lookup\s*\[\s*\]\s*=\s*\{(.*?)\}\s*;\s*",
        content,
        flags=re.DOTALL,
    )
    assert match, "Header does not define float sin_lookup[]"

    entries = [entry.strip() for entry in match.group(1).split(",") if entry.strip()]
    assert len(entries) == 10, "Lookup table must contain exactly 10 values"

    values = []
    for entry in entries:
        number = re.fullmatch(
            r"([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)f",
            entry,
        )
        assert number, f"Invalid lookup-table entry: {entry!r}"
        values.append(float(number.group(1)))

    expected = [round(math.sin(i * 0.1), 2) for i in range(10)]
    assert values == expected, f"Incorrect ARM64 lookup values: {values!r}"


def test_00_prohibited_files_unchanged():
    assert_prohibited_files_unchanged()


def test_build_lookup_import_order():
    file_path = "/home/user/mobile_pipeline/build_lookup.py"
    assert os.path.isfile(file_path), f"{file_path} is missing"

    with open(file_path, "r") as f:
        content = f.read()

    # Check that mobile_emulator is imported before math.sin is imported or used
    idx_emulator = content.find("import mobile_emulator")
    idx_sin = content.find("from math import sin")
    if idx_sin == -1:
        idx_sin = content.find("import math")

    assert idx_emulator != -1, "build_lookup.py is missing 'import mobile_emulator'"
    assert idx_sin != -1, "build_lookup.py is missing math import"
    assert idx_emulator < idx_sin, "In build_lookup.py, 'import mobile_emulator' must appear before math is imported to correctly patch it."


def test_build_lookup_executes_and_generates_correct_table():
    env = os.environ.copy()
    env["TARGET_ARCH"] = "arm64"
    env["PYTHONPATH"] = "/home/user/mobile_pipeline"

    with tempfile.TemporaryDirectory() as workdir:
        result = subprocess.run(
            ["python3", "/home/user/mobile_pipeline/build_lookup.py"],
            cwd=workdir,
            env=env,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"build_lookup.py failed:\n{result.stdout}\n{result.stderr}"
        generated = os.path.join(workdir, "lookup_arm64.h")
        assert os.path.isfile(generated), "build_lookup.py did not generate lookup_arm64.h"
        parse_and_check_header(generated)

    assert_prohibited_files_unchanged()


def test_lookup_arm64_header_exists_and_correct():
    header_path = "/home/user/mobile_pipeline/lookup_arm64.h"
    assert os.path.isfile(header_path), f"{header_path} was not generated. Did you run build_lookup.py with TARGET_ARCH=arm64?"

    with open(header_path, "r") as f:
        content = f.read()

    # Check for some rounded values to ensure it was patched
    assert "0.39f," in content or "0.39" in content, "The generated header does not contain the correctly patched (rounded) values."
    assert "0.48f," in content or "0.48" in content, "The generated header does not contain the correctly patched (rounded) values."
    parse_and_check_header(header_path)


def test_test_lookup_passes():
    assert_prohibited_files_unchanged()

    env = os.environ.copy()
    env["TARGET_ARCH"] = "arm64"
    env["PYTHONPATH"] = "/home/user/mobile_pipeline"

    result = subprocess.run(
        ["python3", "/home/user/mobile_pipeline/test_lookup.py"],
        env=env,
        capture_output=True,
        text=True,
        timeout=20,
    )

    assert result.returncode == 0, f"test_lookup.py failed with output:\n{result.stdout}\n{result.stderr}"
    assert "PASS" in result.stdout, "test_lookup.py did not output PASS."
    assert_prohibited_files_unchanged()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
