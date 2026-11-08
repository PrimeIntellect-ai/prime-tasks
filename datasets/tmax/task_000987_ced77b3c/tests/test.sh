#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import tempfile
from decimal import Decimal, InvalidOperation

API_KEY_FILE = "/home/user/api_key.txt"
PROJECT_DIR = "/home/user/project"
BUILD_SCRIPT = os.path.join(PROJECT_DIR, "build.sh")
PARSER_SCRIPT = os.path.join(PROJECT_DIR, "parse_config.sh")
MRE_SCRIPT = os.path.join(PROJECT_DIR, "mre.sh")
EXPECTED_API_KEY = "xk93_Lz91_deploy_secret_99"


def run_script(path, argument):
    return subprocess.run(
        [path, argument],
        cwd=PROJECT_DIR,
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_api_key_extracted_correctly():
    assert os.path.isfile(API_KEY_FILE), f"API key file not found at {API_KEY_FILE}"

    with open(API_KEY_FILE, "r") as f:
        content = f.read().strip()

    assert content == EXPECTED_API_KEY, (
        f"API key file content is incorrect. Expected '{EXPECTED_API_KEY}', got '{content}'"
    )


def test_build_script_succeeds():
    assert os.path.isfile(BUILD_SCRIPT), f"Build script not found at {BUILD_SCRIPT}"
    assert os.access(BUILD_SCRIPT, os.X_OK), f"Build script at {BUILD_SCRIPT} is not executable"

    result = subprocess.run(
        [BUILD_SCRIPT], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Build script failed with exit code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )


def test_build_script_is_not_a_noop_and_requires_the_key():
    original = open(API_KEY_FILE, "rb").read()
    original_mode = os.stat(API_KEY_FILE).st_mode
    try:
        with open(API_KEY_FILE, "w") as f:
            f.write("definitely_not_the_deployment_key\n")
        result = subprocess.run(
            [BUILD_SCRIPT], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=10
        )
        assert result.returncode != 0, (
            "build.sh returned success with an invalid deployment key; it appears to "
            "have been replaced by a no-op or to bypass the required upload check"
        )
    finally:
        with open(API_KEY_FILE, "wb") as f:
            f.write(original)
        os.chmod(API_KEY_FILE, original_mode)


def test_parser_exists_and_handles_unpredictable_inline_comments_and_floats():
    assert os.path.isfile(PARSER_SCRIPT), f"Parser not found at {PARSER_SCRIPT}"
    assert os.access(PARSER_SCRIPT, os.X_OK), f"Parser at {PARSER_SCRIPT} is not executable"

    rng = random.SystemRandom()
    cases = []
    for _ in range(7):
        base = rng.randint(17, 4093)
        whole = rng.randint(1, 8)
        fraction = rng.randint(1, 999)
        multiplier = f"{whole}.{fraction:03d}"
        cases.append((base, multiplier))

    for base, multiplier in cases:
        with tempfile.TemporaryDirectory() as temp_dir:
            shutil.copy2(PARSER_SCRIPT, os.path.join(temp_dir, "parse_config.sh"))
            marker = secrets.token_hex(10)
            config = (
                "[MEMORY]\n"
                f"BASE_MEM={base}   # randomized base {marker}\n"
                f"MULTIPLIER={multiplier}\t # randomized multiplier {marker}\n"
            )
            with open(os.path.join(temp_dir, "config.ini"), "w") as f:
                f.write(config)

            result = subprocess.run(
                [
                    "/bin/bash",
                    "-c",
                    'source ./parse_config.sh; printf "__MAX_MEMORY__%s\\n" "$MAX_MEMORY"',
                ],
                cwd=temp_dir,
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"parse_config.sh failed for BASE_MEM={base}, MULTIPLIER={multiplier}.\n"
                f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
            )

            result_lines = [
                line[len("__MAX_MEMORY__"):]
                for line in result.stdout.splitlines()
                if line.startswith("__MAX_MEMORY__")
            ]
            assert len(result_lines) == 1, (
                "parse_config.sh did not export exactly one usable MAX_MEMORY value. "
                f"STDOUT was: {result.stdout!r}"
            )
            try:
                actual = Decimal(result_lines[0].strip())
            except InvalidOperation:
                raise AssertionError(
                    f"MAX_MEMORY is not a pure numeric value: {result_lines[0]!r}"
                )
            expected = Decimal(base) * Decimal(multiplier)
            assert actual == expected, (
                f"Incorrect MAX_MEMORY for {base} * {multiplier}: "
                f"expected {expected}, got {actual}"
            )


def test_mre_script_exists_and_executable():
    assert os.path.isfile(MRE_SCRIPT), f"MRE script not found at {MRE_SCRIPT}"
    assert os.access(MRE_SCRIPT, os.X_OK), f"MRE script at {MRE_SCRIPT} is not executable"


def test_mre_script_functionality():
    test_input = "3.14159 # pi"
    expected_output = "3.14159"

    result = run_script(MRE_SCRIPT, test_input)
    assert result.returncode == 0, (
        f"MRE script failed with exit code {result.returncode}.\nSTDERR:\n{result.stderr}"
    )
    output = result.stdout.strip()
    assert output == expected_output, (
        f"MRE script output is incorrect. Expected '{expected_output}', got '{output}'"
    )


def test_mre_script_functionality_no_comment():
    test_input = "2.718"
    expected_output = "2.718"

    result = run_script(MRE_SCRIPT, test_input)
    assert result.returncode == 0, (
        f"MRE script failed with exit code {result.returncode}.\nSTDERR:\n{result.stderr}"
    )
    output = result.stdout.strip()
    assert output == expected_output, (
        f"MRE script output is incorrect. Expected '{expected_output}', got '{output}'"
    )


def test_mre_script_on_unpredictable_values_and_comments():
    rng = random.SystemRandom()
    cases = []
    for _ in range(9):
        value = f"{rng.randint(0, 9999)}.{rng.randint(0, 999999):06d}"
        marker = secrets.token_hex(8)
        if rng.choice([True, False]):
            argument = f"{value}{rng.choice([' ', '   ', '\t'])}# {marker}"
        else:
            argument = f"{value}{rng.choice(['', ' ', '   ', '\t'])}"
        cases.append((argument, value))

    for argument, expected in cases:
        result = run_script(MRE_SCRIPT, argument)
        assert result.returncode == 0, (
            f"MRE script failed for {argument!r} with exit code {result.returncode}.\n"
            f"STDERR:\n{result.stderr}"
        )
        assert result.stdout.strip() == expected, (
            f"MRE script output is incorrect for {argument!r}. "
            f"Expected {expected!r}, got {result.stdout.strip()!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
