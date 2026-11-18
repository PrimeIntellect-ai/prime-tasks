#!/bin/bash
set -e
mkdir -p /logs/verifier
export RUSTUP_HOME=/opt/rust
export CARGO_HOME=/opt/cargo
export PATH=/opt/cargo/bin:$PATH

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import importlib.machinery
import importlib.metadata
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

PROJECT = Path("/home/user/math_project")
OUTPUT = Path("/home/user/final_output.txt")
RUN_SCRIPT = Path("/home/user/run_math.py")
EXPECTED_FINAL = "GMYDQNDFEQ3DMMJTGMZTI==="


def clean_env():
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    return env


def factors(n):
    result = []
    divisor = 2
    while n > 1:
        while n % divisor == 0:
            result.append(divisor)
            n //= divisor
        divisor += 1
    return result


def encoded(n):
    text = ",".join(map(str, factors(n)))
    return base64.b32encode(text.encode("utf-8")).decode("ascii")


def test_project_sources_build_and_source_import_order():
    for path in (
        PROJECT / "Cargo.toml",
        PROJECT / "setup.py",
        PROJECT / "src/lib.rs",
        PROJECT / "math_encoder/__init__.py",
        PROJECT / "math_encoder/config.py",
        PROJECT / "math_encoder/encoder.py",
    ):
        assert path.is_file(), f"Required project file is missing: {path}"

    subprocess.run(
        ["cargo", "build", "--release"],
        cwd=PROJECT,
        env=clean_env(),
        check=True,
        timeout=300,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    probe = subprocess.run(
        [
            sys.executable,
            "-c",
            "import math_encoder, math_encoder.config; "
            "assert math_encoder.config.IS_INITIALIZED is True; "
            "assert callable(math_encoder.encode_factors); "
            "assert '/home/user/math_project/math_encoder/' in math_encoder.__file__",
        ],
        cwd=PROJECT,
        env=clean_env(),
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert probe.returncode == 0, probe.stdout + probe.stderr


def test_installed_native_extension_and_dynamic_behavior():
    assert importlib.metadata.version("math_encoder") == "0.1.0"

    prime_pool = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43]
    numbers = [1, 97, 314159265]
    for _ in range(6):
        value = 1
        for _ in range(3 + secrets.randbelow(5)):
            value *= secrets.choice(prime_pool)
        numbers.append(value)

    code = r'''
import importlib.machinery
import json
import math_encoder
import math_encoder.config
import rs_math
import sys
assert math_encoder.config.IS_INITIALIZED is True
assert isinstance(rs_math.__spec__.loader, importlib.machinery.ExtensionFileLoader)
assert any(rs_math.__file__.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES)
nums = json.loads(sys.argv[1])
print(json.dumps({
    "factors": [rs_math.get_factors(n) for n in nums],
    "encoded": [math_encoder.encode_factors(n) for n in nums],
}))
'''
    result = subprocess.run(
        [sys.executable, "-c", code, json.dumps(numbers)],
        cwd="/tmp",
        env=clean_env(),
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    payload = json.loads(result.stdout.strip().splitlines()[-1])
    assert payload["factors"] == [factors(n) for n in numbers]
    assert payload["encoded"] == [encoded(n) for n in numbers]


def test_run_script_creates_exact_output():
    assert RUN_SCRIPT.is_file(), f"Required script is missing: {RUN_SCRIPT}"
    OUTPUT.unlink(missing_ok=True)
    result = subprocess.run(
        [sys.executable, str(RUN_SCRIPT)],
        cwd="/tmp",
        env=clean_env(),
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert OUTPUT.is_file(), "run_math.py did not create /home/user/final_output.txt"
    assert OUTPUT.read_text() == EXPECTED_FINAL, "final_output.txt must contain exactly the base32 result and no extra whitespace"


def test_final_output_file():
    """
    Verifies that the final output file exists and contains the correct base32 encoded string
    for the prime factors of 314159265.
    """
    output_file = "/home/user/final_output.txt"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist. The script might not have been run or failed."

    with open(output_file, "r") as f:
        content = f.read().strip()

    expected_content = "GMYDQNDFEQ3DMMJTGMZTI==="
    assert content == expected_content, f"Expected base32 string '{expected_content}', got '{content}'. Check the math and encoding logic."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
