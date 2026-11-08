#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import string
import subprocess
import tempfile

SOURCE = "/home/user/query_processor.cpp"
BINARY = "/home/user/query_processor"
CRASH_INPUT = "/home/user/crashing_input.txt"
REGRESSION = "/home/user/regression_test.sh"
DIAGNOSTICS = "/home/user/diagnostics.log"
BUILT_SOURCE = "/tmp/test_query_processor"


def expected_output(query):
    lines = []
    pos = 0
    while pos < len(query):
        next_amp = query.find("&", pos)
        if next_amp == -1:
            token = query[pos:]
            pos = len(query)
        else:
            token = query[pos:next_amp]
            pos = next_amp + 1

        if "=" in token:
            key, value = token.split("=", 1)
        else:
            key, value = token, ""
        lines.append(f"K:{key} V:{value}\n")
    return "".join(lines)


def run_program(path, query):
    return subprocess.run(
        [path, query], capture_output=True, text=True, timeout=5
    )


def test_files_exist():
    expected_files = [SOURCE, BINARY, CRASH_INPUT, REGRESSION, DIAGNOSTICS]
    for path in expected_files:
        assert os.path.isfile(path), f"File {path} is missing."

    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF binary."


def test_query_processor_fixed_behavior():
    compile_cmd = ["g++", "-O2", "-std=c++17", SOURCE, "-o", BUILT_SOURCE]
    res = subprocess.run(compile_cmd, capture_output=True, text=True, timeout=30)
    assert res.returncode == 0, f"Compilation failed: {res.stderr}"

    # Preserve the original fixed regression assertion.
    res = run_program(BUILT_SOURCE, "a&b=c")
    assert res.returncode == 0, "Program crashed on valid input 'a&b=c'."
    output = res.stdout.strip().split("\n")
    assert len(output) >= 2, "Output does not contain enough lines."
    assert output[0].strip() == "K:a V:", f"Expected 'K:a V:', got '{output[0]}'"
    assert output[1].strip() == "K:b V:c", f"Expected 'K:b V:c', got '{output[1]}'"

    cases = [
        "solo",
        "left=right",
        "x=&y=z",
        "a=b=c&bare",
        "&a=b",
        "a=b&&c",
        "a=b&",
        "first&second&third=value",
        "=value&empty=",
    ]

    alphabet = string.ascii_letters
    for _ in range(40):
        tokens = []
        missing_index = secrets.randbelow(6)
        token_count = missing_index + 1
        for index in range(token_count):
            key = "".join(secrets.choice(alphabet) for _ in range(1 + secrets.randbelow(10)))
            if index == missing_index or secrets.randbelow(3) == 0:
                tokens.append(key)
            else:
                value = "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(10)))
                if secrets.randbelow(5) == 0:
                    value += "=" + "".join(secrets.choice(alphabet) for _ in range(3))
                tokens.append(key + "=" + value)
        cases.append("&".join(tokens))

    for query in cases:
        expected = expected_output(query)
        source_res = run_program(BUILT_SOURCE, query)
        assert source_res.returncode == 0, f"Source build failed for input {query!r}: {source_res.stderr}"
        assert source_res.stdout == expected, (
            f"Source build parsed {query!r} incorrectly.\n"
            f"Expected: {expected!r}\nActual: {source_res.stdout!r}"
        )

        binary_res = run_program(BINARY, query)
        assert binary_res.returncode == 0, f"Submitted binary failed for input {query!r}: {binary_res.stderr}"
        assert binary_res.stdout == expected, (
            f"Submitted binary does not match the fixed source behavior for {query!r}.\n"
            f"Expected: {expected!r}\nActual: {binary_res.stdout!r}"
        )


def test_crashing_input_content():
    with open(CRASH_INPUT, "r") as f:
        content = f.read().strip()

    assert content, "crashing_input.txt is empty."
    tokens = content.split("&")
    has_missing_eq = any("=" not in token for token in tokens)
    assert has_missing_eq, "crashing_input.txt does not contain a token without an '=' sign."

    for executable in (BUILT_SOURCE, BINARY):
        res = run_program(executable, content)
        assert res.returncode == 0, f"{executable} crashes on crashing_input.txt."
        assert res.stdout == expected_output(content), f"{executable} parses crashing_input.txt incorrectly."


def test_regression_test_script():
    assert os.access(REGRESSION, os.X_OK), f"{REGRESSION} is not executable."

    with open(CRASH_INPUT, "r") as f:
        expected_arg = f.read().strip()

    tempdir = tempfile.mkdtemp(prefix="regression_spy_")
    backup = os.path.join(tempdir, "query_processor.real")
    mode_file = os.path.join(tempdir, "mode")
    count_file = os.path.join(tempdir, "count")
    arg_file = os.path.join(tempdir, "arg")

    os.replace(BINARY, backup)
    try:
        spy = f'''#!/bin/sh
n=0
if [ -f "{count_file}" ]; then n=$(cat "{count_file}"); fi
n=$((n + 1))
printf '%s' "$n" > "{count_file}"
printf '%s' "$1" > "{arg_file}"
if [ "$(cat "{mode_file}")" = "fail" ]; then
    exit 37
fi
exit 0
'''
        with open(BINARY, "w") as f:
            f.write(spy)
        os.chmod(BINARY, 0o755)

        with open(mode_file, "w") as f:
            f.write("success")
        res = subprocess.run([REGRESSION], capture_output=True, text=True, timeout=10)
        assert res.returncode == 0, f"{REGRESSION} did not exit with code 0 when the program succeeded."
        assert os.path.exists(count_file), f"{REGRESSION} did not execute {BINARY}."
        with open(arg_file, "r") as f:
            actual_arg = f.read()
        assert actual_arg == expected_arg, "Regression script did not pass crashing_input.txt as the first argument."

        os.remove(count_file)
        if os.path.exists(arg_file):
            os.remove(arg_file)
        with open(mode_file, "w") as f:
            f.write("fail")
        res = subprocess.run([REGRESSION], capture_output=True, text=True, timeout=10)
        assert os.path.exists(count_file), f"{REGRESSION} did not execute {BINARY} on the failure path."
        assert res.returncode == 1, f"{REGRESSION} must exit with code 1 when the program fails."
        with open(arg_file, "r") as f:
            actual_arg = f.read()
        assert actual_arg == expected_arg, "Regression script passed the wrong first argument on the failure path."
    finally:
        if os.path.lexists(BINARY):
            os.remove(BINARY)
        os.replace(backup, BINARY)
        shutil.rmtree(tempdir, ignore_errors=True)


def test_diagnostics_log():
    with open(CRASH_INPUT, "r") as f:
        input_str = f.read().strip()

    res = run_program(BINARY, input_str)
    assert res.returncode == 0, "query_processor crashed on crashing_input.txt."
    expected_from_binary = res.stdout.strip()

    with open(DIAGNOSTICS, "r") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_from_binary, (
        "diagnostics.log content does not match binary output.\n"
        f"Expected:\n{expected_from_binary}\nActual:\n{actual_output}"
    )
    independently_expected = expected_output(input_str).strip()
    assert actual_output == independently_expected, (
        "diagnostics.log does not contain the correctly parsed crashing input.\n"
        f"Expected:\n{independently_expected}\nActual:\n{actual_output}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
