#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import stat
import subprocess
import tempfile
import time
import pytest

APP_DIR = "/home/user/app"
KEY_TXT = os.path.join(APP_DIR, "key.txt")
ANALYZER_CPP = os.path.join(APP_DIR, "analyzer.cpp")
TEST_SH = os.path.join(APP_DIR, "test.sh")
ANALYZER_BIN = os.path.join(APP_DIR, "analyzer")


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30, **kwargs)


def test_key_extracted_correctly():
    assert os.path.exists(KEY_TXT), f"File {KEY_TXT} does not exist."
    assert os.path.isfile(KEY_TXT), f"{KEY_TXT} is not a file."

    with open(KEY_TXT, 'r') as f:
        content = f.read().strip()

    assert content == "TEST_KEY_849302", f"Expected key 'TEST_KEY_849302', but found '{content}' in {KEY_TXT}."


def test_analyzer_cpp_fixed():
    assert os.path.exists(ANALYZER_CPP), f"File {ANALYZER_CPP} does not exist."

    with open(ANALYZER_CPP, 'r') as f:
        content = f.read()

    assert "(1.0 - k)" in content, f"The corrected EMA formula containing '(1.0 - k)' was not found in {ANALYZER_CPP}."
    assert "(1.0 + k)" not in content, f"The buggy EMA formula containing '(1.0 + k)' is still present in {ANALYZER_CPP}."


def test_analyzer_compiles_runs_and_calculates_ema():
    with tempfile.TemporaryDirectory() as td:
        default_bin = os.path.join(td, "analyzer_default")
        result = run(["g++", "-std=c++17", "-O2", ANALYZER_CPP, "-o", default_bin])
        assert result.returncode == 0, f"analyzer.cpp failed to compile:\n{result.stderr}"

        result = run([default_bin])
        assert result.returncode == 0, f"Compiled analyzer failed:\n{result.stderr}"
        assert result.stdout.strip() == "EMA: 11.5556", f"Unexpected analyzer output: {result.stdout!r}"

        obj = os.path.join(td, "analyzer.o")
        harness_cpp = os.path.join(td, "harness.cpp")
        harness_bin = os.path.join(td, "harness")
        with open(harness_cpp, "w") as f:
            f.write(r'''#include <iostream>
#include <iomanip>
#include <vector>
double calculate_ema(const std::vector<double>&, double);
int main() {
    int n;
    double period;
    if (!(std::cin >> n >> period) || n < 0) return 2;
    std::vector<double> prices(static_cast<size_t>(n));
    for (double &v : prices) if (!(std::cin >> v)) return 2;
    std::cout << std::setprecision(17) << calculate_ema(prices, period) << "\n";
    return 0;
}
''')

        result = run(["g++", "-std=c++17", "-O2", "-Dmain=agent_analyzer_main", "-c", ANALYZER_CPP, "-o", obj])
        assert result.returncode == 0, f"Could not compile analyzer.cpp for function testing:\n{result.stderr}"
        result = run(["g++", "-std=c++17", "-O2", harness_cpp, obj, "-o", harness_bin])
        assert result.returncode == 0, f"Could not link calculate_ema test harness:\n{result.stderr}"

        rng = random.SystemRandom()
        cases = [([], 2.0), ([5.25], 7.0)]
        for _ in range(10):
            prices = [rng.uniform(-500.0, 500.0) for _ in range(rng.randint(2, 12))]
            period = rng.uniform(1.1, 25.0)
            cases.append((prices, period))

        for prices, period in cases:
            expected = 0.0
            if prices:
                k = 2.0 / (period + 1.0)
                expected = prices[0]
                for price in prices[1:]:
                    expected = price * k + expected * (1.0 - k)
            data = f"{len(prices)} {period:.17g}\n" + " ".join(f"{x:.17g}" for x in prices) + "\n"
            result = run([harness_bin], input=data)
            assert result.returncode == 0, f"EMA harness failed:\n{result.stderr}"
            try:
                actual = float(result.stdout.strip())
            except ValueError:
                pytest.fail(f"calculate_ema produced non-numeric output: {result.stdout!r}")
            assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
                f"calculate_ema returned {actual}, expected {expected} for prices={prices}, period={period}"
            )


def test_test_script_exists_and_executable():
    assert os.path.exists(TEST_SH), f"Script {TEST_SH} does not exist."
    assert os.path.isfile(TEST_SH), f"{TEST_SH} is not a file."

    st = os.stat(TEST_SH)
    assert bool(st.st_mode & stat.S_IXUSR), f"{TEST_SH} does not have executable permissions."


def test_test_script_execution():
    if not os.path.exists(TEST_SH) or not os.access(TEST_SH, os.X_OK):
        pytest.fail(f"Cannot execute {TEST_SH} because it is missing or not executable.")

    if os.path.lexists(ANALYZER_BIN):
        os.unlink(ANALYZER_BIN)
    started = time.time()
    result = run([TEST_SH], cwd=APP_DIR)

    assert result.returncode == 0, (
        f"{TEST_SH} failed with exit code {result.returncode}.\n"
        f"STDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    )
    assert os.path.isfile(ANALYZER_BIN), "test.sh did not create the analyzer executable."
    assert os.access(ANALYZER_BIN, os.X_OK), "The analyzer produced by test.sh is not executable."
    assert os.path.getmtime(ANALYZER_BIN) >= started - 1.0, "test.sh did not freshly create analyzer."
    with open(ANALYZER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The analyzer produced by test.sh is not a compiled ELF executable."
    analyzer_result = run([ANALYZER_BIN], cwd=APP_DIR)
    assert analyzer_result.returncode == 0
    assert analyzer_result.stdout.strip() == "EMA: 11.5556"


def test_test_script_detects_bad_output_and_compile_failure():
    with open(ANALYZER_CPP, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(ANALYZER_CPP).st_mode)
    try:
        with open(ANALYZER_CPP, "w") as f:
            f.write('#include <iostream>\nint main(){ std::cout << "WRONG\\n"; return 0; }\n')
        if os.path.lexists(ANALYZER_BIN):
            os.unlink(ANALYZER_BIN)
        result = run([TEST_SH], cwd=APP_DIR)
        assert result.returncode == 1, "test.sh must exit 1 when analyzer output does not match."

        with open(ANALYZER_CPP, "w") as f:
            f.write("this is intentionally invalid C++\n")
        if os.path.lexists(ANALYZER_BIN):
            os.unlink(ANALYZER_BIN)
        result = run([TEST_SH], cwd=APP_DIR)
        assert result.returncode == 1, "test.sh must exit 1 when analyzer.cpp fails to compile."
    finally:
        with open(ANALYZER_CPP, "wb") as f:
            f.write(original)
        os.chmod(ANALYZER_CPP, original_mode)
        if os.path.lexists(ANALYZER_BIN):
            os.unlink(ANALYZER_BIN)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
