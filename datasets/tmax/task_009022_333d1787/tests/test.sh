#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

SOURCE_PATH = "/home/user/engine/calc.c"
EXECUTABLE_PATH = "/home/user/engine/calc"
REBUILT_PATH = "/tmp/calc_rebuilt"


def run_calc(path, base, delta):
    try:
        return subprocess.run(
            [path, base, delta],
            capture_output=True,
            text=True,
            timeout=2,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"{path} crashed or returned an error for {base} {delta}. "
            f"Return code: {e.returncode}. stdout: {e.stdout!r}; stderr: {e.stderr!r}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{path} timed out for {base} {delta}.")


@pytest.fixture(scope="session")
def rebuilt_calc():
    result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", REBUILT_PATH],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        "calc.c does not compile with the required gcc command. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.isfile(REBUILT_PATH)
    assert os.access(REBUILT_PATH, os.X_OK)
    return REBUILT_PATH


def test_answer_txt_content():
    path = "/home/user/answer.txt"
    assert os.path.isfile(path), f"File {path} does not exist. The task requires writing the final integer output here."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "10000000", f"Expected answer '10000000' in {path}, but found '{content}'."


def test_calc_executable_fixed():
    executable_path = "/home/user/engine/calc"
    assert os.path.isfile(executable_path), f"Executable {executable_path} does not exist."
    assert os.access(executable_path, os.X_OK), f"File {executable_path} is not executable."

    # Run the executable with the crashing arguments
    result = run_calc(executable_path, "100000.0", "0.001")
    output = result.stdout.strip()
    assert output == "10000000", f"Expected the fixed executable to output '10000000', but got '{output}'."


def test_calc_c_modified():
    source_path = "/home/user/engine/calc.c"
    assert os.path.isfile(source_path), f"Source file {source_path} does not exist."

    with open(source_path, "r") as f:
        content = f.read()

    assert len(content) > 0, f"Source file {source_path} is empty."


def test_calc_is_native_executable():
    # Reject a shell/Python script that merely prints the known answer.
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "calc must be a compiled native executable, not a script."


def test_source_rebuild_handles_original_case(rebuilt_calc):
    # Ensure the checked behavior is actually produced by the submitted C source.
    result = run_calc(rebuilt_calc, "100000.0", "0.001")
    assert result.stdout.strip() == "10000000"


def test_formula_on_derived_precision_cases(rebuilt_calc):
    # Generate cases where delta is below a float ULP at base, but all values and
    # expected integer results are exactly representable. A float-cancellation
    # implementation or a constant-output replacement cannot pass these cases.
    rng = random.SystemRandom()
    cases = [("10", "2", 5000), ("50", "5", 2000), ("0", "0.5", 20000)]

    for _ in range(12):
        exponent = rng.randint(16, 22)
        base_value = rng.randint(1 << exponent, (1 << (exponent + 1)) - 1)
        divisor_power = rng.choice((2, 3))
        delta_value = 2.0 ** (exponent - 23 - divisor_power)
        expected = int(10000.0 / delta_value)
        cases.append((str(base_value), format(delta_value, ".17g"), expected))

    for executable in (EXECUTABLE_PATH, rebuilt_calc):
        for base, delta, expected in cases:
            result = run_calc(executable, base, delta)
            output = result.stdout.strip()
            assert output == str(expected), (
                f"{executable} produced {output!r} for {base} {delta}; "
                f"expected {expected} from the calculation formula."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
