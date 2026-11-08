#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import shlex
import stat
import subprocess
import tempfile

import pytest


def test_api_key_recovered():
    key_file = "/home/user/api_key.txt"
    assert os.path.isfile(key_file), f"File {key_file} does not exist."
    with open(key_file, "r") as f:
        content = f.read().strip()
    assert content == "sk_live_9f8e7d6c5b4a3f2e1d0c", f"Incorrect API key recovered. Found: {content}"


def test_calc_c_fixed_math():
    calc_file = "/home/user/calc_service/calc.c"
    assert os.path.isfile(calc_file), f"File {calc_file} does not exist."
    with open(calc_file, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "+" in content and "sqrt" in content, "The C file does not seem to contain the stable mathematical formula."
    assert "sqrt(x * x + 1.0) - x" not in content.replace(" ", ""), "The unstable formula is still present in the code."

    # Also perform the intended whitespace-insensitive checks.
    unstable = re.compile(
        r"sqrt\s*\(\s*x\s*\*\s*x\s*\+\s*1(?:\.0*)?\s*\)\s*-\s*x"
    )
    assert not unstable.search(content), "The unstable subtraction sqrt(x*x+1)-x is still present."

    compact = re.sub(r"\s+", "", content)
    has_stable_denominator = (
        "/(" in compact
        and "sqrt(" in compact
        and (")+x" in compact or "x+sqrt(" in compact)
    )
    assert has_stable_denominator, (
        "calc.c does not contain the rationalized stable form using division by "
        "sqrt(x*x+1)+x."
    )


def test_calc_compiles_and_runs():
    calc_file = "/home/user/calc_service/calc.c"
    out_file = "/home/user/calc_service/calc"

    # Preserve the original compilation check.
    compile_res = subprocess.run(
        ["gcc", "-lm", calc_file, "-o", out_file],
        capture_output=True,
        text=True
    )
    assert compile_res.returncode == 0, f"Compilation failed:\n{compile_res.stderr}"

    # Preserve the original fixed-input execution and finite-number checks.
    run_res = subprocess.run(
        [out_file, "100000000"],
        capture_output=True,
        text=True,
        timeout=2.0
    )
    assert run_res.returncode == 0, f"Execution failed with code {run_res.returncode}:\n{run_res.stderr}"

    output = run_res.stdout.strip()
    assert output, "No output from calc program."
    assert "nan" not in output.lower(), "Output is NaN."
    assert "inf" not in output.lower(), "Output is Inf."
    try:
        val = float(output)
        assert math.isfinite(val), "Output value is not finite."
    except ValueError:
        pytest.fail(f"Output '{output}' is not a valid float.")

    # Exercise unpredictable large inputs and derive the expected first stable
    # sequence update. At these magnitudes IEEE double rounds sqrt(x*x+1) to x,
    # so the stable update is exactly -x and subsequent convergence is immediate.
    rng = secrets.SystemRandom()
    inputs = [100000000] + [rng.randrange(100000001, 900000000) for _ in range(7)]
    for n in inputs:
        x = float(n)
        expected = x - (math.sqrt(x * x + 1.0) + x)
        res = subprocess.run(
            [out_file, str(n)],
            capture_output=True,
            text=True,
            timeout=2.0
        )
        assert res.returncode == 0, f"calc failed for input {n}: {res.stderr}"
        text = res.stdout.strip()
        try:
            got = float(text)
        except ValueError:
            pytest.fail(f"Output '{text}' for input {n} is not a valid float.")
        assert math.isfinite(got), f"Non-finite output for input {n}: {text}"
        assert math.isclose(got, expected, rel_tol=0.0, abs_tol=0.001), (
            f"Wrong sequence result for input {n}: expected {expected}, got {got}"
        )


def _run_regression_script(script_source, calc_source, expected_code, limit=5.0):
    with tempfile.TemporaryDirectory(prefix="calc-test-") as td:
        script = os.path.join(td, "test.sh")
        calc = os.path.join(td, "calc.c")
        bindir = os.path.join(td, "bin")
        trace = os.path.join(td, "trace.log")
        os.mkdir(bindir)

        with open(script, "w") as f:
            f.write(script_source)
        os.chmod(script, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)
        with open(calc, "w") as f:
            f.write(calc_source)

        wrappers = {
            "gcc": "#!/bin/bash\necho gcc \"$@\" >> \"$TRACE_FILE\"\nexec /usr/bin/gcc \"$@\"\n",
            "timeout": "#!/bin/bash\necho timeout \"$@\" >> \"$TRACE_FILE\"\nexec /usr/bin/timeout \"$@\"\n",
        }
        for name, body in wrappers.items():
            path = os.path.join(bindir, name)
            with open(path, "w") as f:
                f.write(body)
            os.chmod(path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)

        env = os.environ.copy()
        env["PATH"] = bindir + os.pathsep + env.get("PATH", "")
        env["TRACE_FILE"] = trace
        result = subprocess.run(
            ["bash", script], cwd=td, env=env,
            capture_output=True, text=True, timeout=limit
        )
        assert result.returncode == expected_code, (
            f"Regression script returned {result.returncode}, expected {expected_code}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        trace_text = ""
        if os.path.exists(trace):
            with open(trace, "r") as f:
                trace_text = f.read()
        lines = [shlex.split(line) for line in trace_text.splitlines() if line.strip()]
        gcc_calls = [line for line in lines if line and line[0] == "gcc"]
        timeout_calls = [line for line in lines if line and line[0] == "timeout"]
        assert any(any(arg.endswith("calc.c") for arg in call[1:]) and "-o" in call for call in gcc_calls), (
            "test.sh did not actually compile calc.c with gcc."
        )
        assert timeout_calls, "test.sh did not actually execute the timeout command."
        assert any(
            any(re.fullmatch(r"2(?:\.0+)?s?", arg) for arg in call[1:])
            and "100000000" in call[1:]
            for call in timeout_calls
        ), "test.sh must run input 100000000 under a 2-second timeout."


def test_test_script():
    script_file = "/home/user/calc_service/test.sh"
    calc_file = "/home/user/calc_service/calc.c"
    assert os.path.isfile(script_file), f"Script {script_file} does not exist."
    assert os.access(script_file, os.X_OK), f"Script {script_file} is not executable."

    with open(script_file, "r") as f:
        content = f.read()
    assert "timeout" in content, "The test script does not use the 'timeout' command."

    # Preserve the original execution assertion.
    run_res = subprocess.run(
        ["bash", script_file],
        cwd="/home/user/calc_service",
        capture_output=True,
        text=True
    )
    assert run_res.returncode == 0, f"Test script failed with code {run_res.returncode}:\n{run_res.stderr}\n{run_res.stdout}"

    with open(calc_file, "r") as f:
        fixed_calc = f.read()

    # Confirm that the script really compiles, invokes timeout, accepts valid
    # numeric output, rejects invalid output, and translates timeout failure to 1.
    _run_regression_script(content, fixed_calc, 0)
    _run_regression_script(
        content,
        '#include <stdio.h>\nint main(void) { puts("garbage"); return 0; }\n',
        1
    )
    _run_regression_script(
        content,
        'int main(void) { volatile int keep_running = 1; while (keep_running) {} return 0; }\n',
        1
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
