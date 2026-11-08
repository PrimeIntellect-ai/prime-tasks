#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile

AUTH_PATH = "/tmp/auth.key"
SECRET = "auth_secret_998877abc"
SOURCE = "/home/user/log_processor/parser.c"
BINARY = "/home/user/log_processor/log_calc"
DATA = "/home/user/log_processor/data.log"
RESULT = "/home/user/final_result.txt"


def run_program(binary, data_path):
    return subprocess.run(
        [binary, data_path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def strip_c_comments(text):
    return re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.S)


def test_auth_key_exists_and_correct():
    assert os.path.isfile(AUTH_PATH), f"The file {AUTH_PATH} does not exist."
    with open(AUTH_PATH, "r") as f:
        content = f.read().strip()
    assert content == SECRET, f"The auth key content is incorrect. Found: {content}"


def test_parser_c_fixed():
    assert os.path.isfile(SOURCE), f"The file {SOURCE} does not exist."
    with open(SOURCE, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert (re.search(r"sscanf\s*\(.*?\)\s*==\s*3", content)
            or re.search(r"3\s*==\s*sscanf\s*\(.*?\)", content)
            or re.search(r"sscanf\s*\(.*?\)\s*!=\s*3", content)), \
        "parser.c does not check if sscanf successfully parsed 3 integers."
    assert re.search(r"assert\s*\(.*?!=?\s*0\s*\)", content) or re.search(r"assert\s*\(.*?\)", content), \
        "parser.c does not contain an assert statement for the divisor."
    assert "continue" in content or "if" in content, \
        "parser.c does not seem to have logic to skip malformed or zero-divisor lines."

    # Require the checks to be executable C rather than comments.
    code = strip_c_comments(content)
    assert (re.search(r"sscanf\s*\([^;]*\)\s*==\s*3", code, re.S)
            or re.search(r"3\s*==\s*sscanf\s*\([^;]*\)", code, re.S)
            or re.search(r"sscanf\s*\([^;]*\)\s*!=\s*3", code, re.S)), \
        "The three-value sscanf check is not present in executable code."

    assertion_before_division = False
    for match in re.finditer(r"assert\s*\(\s*([A-Za-z_]\w*)\s*!=\s*0\s*\)\s*;", code):
        divisor = re.escape(match.group(1))
        following_statement = code[match.end():].split(";", 1)[0]
        if re.search(r"/\s*\(?\s*" + divisor + r"\b", following_statement):
            assertion_before_division = True
            break
    assert assertion_before_division, \
        "An assert(divisor != 0) must occur immediately before the division statement."


def test_source_compiles_and_both_binaries_are_real():
    assert os.path.isfile(BINARY), f"The compiled program {BINARY} does not exist."
    assert os.access(BINARY, os.X_OK), f"The compiled program {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_calc is not a compiled ELF program."

    compiled = "/tmp/verifier_log_calc"
    result = subprocess.run(
        ["gcc", "-o", compiled, SOURCE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, f"parser.c does not compile:\n{result.stderr}"
    with open(compiled, "rb") as f:
        assert f.read(4) == b"\x7fELF"


def test_authentication_is_enforced_by_programs():
    compiled = "/tmp/verifier_log_calc"
    with open(AUTH_PATH, "rb") as f:
        original = f.read()
    try:
        with open(AUTH_PATH, "w") as f:
            f.write("wrong_key")
        for binary in (BINARY, compiled):
            result = run_program(binary, DATA)
            assert result.returncode != 0, f"{binary} accepts an incorrect authentication key."
            assert "Total:" not in result.stdout
    finally:
        with open(AUTH_PATH, "wb") as f:
            f.write(original)


def test_programs_handle_generated_valid_corrupt_and_zero_inputs():
    rng = random.Random(817263)
    lines = []
    expected = 0
    for i in range(24):
        a = rng.randint(-100, 100)
        b = rng.randint(-30, 30)
        c = rng.choice([-9, -7, -3, -1, 1, 2, 4, 8])
        lines.append(f"{a},{b},{c}\n")
        expected += int((a * b) / c)  # C integer division truncates toward zero.
        if i % 3 == 0:
            lines.extend([
                "CORRUPTED_LOG_LINE_MISSING_DATA\n",
                "12,X,3\n",
                "7,8\n",
                "50,2,0\n",
            ])

    fd, path = tempfile.mkstemp(prefix="calc_input_", suffix=".log")
    try:
        with os.fdopen(fd, "w") as f:
            f.writelines(lines)
        wanted = f"Total: {expected}\n"
        for binary in (BINARY, "/tmp/verifier_log_calc"):
            result = run_program(binary, path)
            assert result.returncode == 0, \
                f"{binary} failed on valid/corrupt mixed input: {result.stderr}"
            assert result.stdout == wanted, \
                f"{binary} produced {result.stdout!r}; expected {wanted!r}"
    finally:
        os.unlink(path)


def test_final_result():
    assert os.path.isfile(RESULT), f"The file {RESULT} does not exist."
    with open(RESULT, "r") as f:
        content = f.read().strip()
    assert content == "Total: 61", \
        f"The final result is incorrect. Expected 'Total: 61', got '{content}'."

    result = run_program(BINARY, DATA)
    assert result.returncode == 0, f"The submitted log_calc fails on data.log: {result.stderr}"
    assert result.stdout == "Total: 61\n"
    with open(RESULT, "rb") as f:
        assert f.read() == result.stdout.encode(), \
            "final_result.txt is not exactly the redirected output of log_calc."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
