#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import shutil
import stat
import subprocess
import tempfile

OPT_DIR = "/home/user/optimizer"
BINARY = os.path.join(OPT_DIR, "cost_function")
SCRIPT = os.path.join(OPT_DIR, "gradient_descent.py")
CALLS = []


def test_0_gradient_descent_is_fixed_and_executable():
    """Run the submitted optimizer from a clean output state and verify real finite-difference convergence."""
    assert os.path.exists(SCRIPT), f"File {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"Path {SCRIPT} is not a file."

    compile(open(SCRIPT, "rb").read(), SCRIPT, "exec")

    assert os.path.exists(BINARY), f"File {BINARY} does not exist."
    mode = os.stat(BINARY).st_mode
    assert stat.S_ISREG(mode), f"Path {BINARY} is not a regular file."
    assert mode & 0o111, f"File {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {BINARY} is not an ELF executable."

    # Confirm that the supplied executable still implements the expected cost
    # function before instrumenting calls made by the optimizer.
    for x in (-7.25, 0.0, 100.125):
        result = subprocess.run(
            [BINARY, str(x)], capture_output=True, text=True, timeout=5, check=True
        )
        observed = float(result.stdout.strip())
        expected = (x - 42.42) ** 2 + 13.37
        assert math.isclose(observed, expected, rel_tol=0.0, abs_tol=1e-7), (
            f"cost_function returned {observed} for x={x}, expected {expected}."
        )

    fd, backup = tempfile.mkstemp(prefix="cost_function_original_", dir="/tmp")
    os.close(fd)
    os.unlink(backup)
    log_path = tempfile.mktemp(prefix="optimizer_calls_", dir="/tmp")
    output_path = os.path.join(OPT_DIR, "optimal_x.txt")

    shutil.copy2(BINARY, backup)
    try:
        with open(BINARY, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"printf '%s\\n' \"$1\" >> {log_path!r}\n")
            f.write(f"exec {backup!r} \"$@\"\n")
        os.chmod(BINARY, 0o755)

        if os.path.lexists(output_path):
            os.unlink(output_path)

        result = subprocess.run(
            ["python3", SCRIPT],
            cwd=OPT_DIR,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            "gradient_descent.py failed when executed:\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(output_path), (
            "Executing gradient_descent.py did not create optimal_x.txt."
        )

        if os.path.exists(log_path):
            with open(log_path) as f:
                raw_calls = [line.strip() for line in f if line.strip()]
        else:
            raw_calls = []
    finally:
        shutil.copy2(backup, BINARY)
        os.unlink(backup)
        if os.path.exists(log_path):
            os.unlink(log_path)

    assert raw_calls, "gradient_descent.py never invoked ./cost_function."
    try:
        calls = [float(value) for value in raw_calls]
    except ValueError as exc:
        raise AssertionError(f"Optimizer passed a non-numeric argument to cost_function: {exc}")

    finite_calls = [x for x in calls if math.isfinite(x)]
    assert len(set(finite_calls)) >= 4, (
        "Optimizer did not evaluate enough distinct points to perform an optimization."
    )
    assert any(abs(x) < 1e-9 for x in finite_calls), (
        "Optimizer did not begin from its configured initial point near x=0."
    )
    assert any(abs(x - 42.42) < 0.01 for x in finite_calls), (
        "Optimizer never converged to and evaluated a point near the minimum."
    )
    assert any(
        0.0 < abs(a - b) <= 0.1
        for i, a in enumerate(finite_calls)
        for b in finite_calls[i + 1:]
    ), "No nearby pair of cost evaluations was observed for a finite-difference gradient."


def test_optimal_x_file():
    """Check if optimal_x.txt exists and contains the correct optimal x value."""
    file_path = "/home/user/optimizer/optimal_x.txt"
    assert os.path.exists(file_path), f"File {file_path} does not exist. Did you modify gradient_descent.py to write the output?"
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected = "42.4200"
    assert content == expected, f"Expected {file_path} to contain '{expected}', but found '{content}'."


def test_secret_file():
    """Check that secret.txt contains the token actually exposed by the binary's magic input."""
    file_path = "/home/user/optimizer/secret.txt"
    assert os.path.exists(file_path), f"File {file_path} does not exist. Did you run the binary with the magic number and save the output?"
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    # Derive the backdoor token from the executable rather than relying only on
    # the submitted file. Normal inputs are numeric; the magic input is not.
    discovered = []
    for candidate in range(0, 2001):
        result = subprocess.run(
            [BINARY, str(candidate)], capture_output=True, text=True, timeout=5
        )
        if result.returncode != 0:
            continue
        output = result.stdout.strip()
        try:
            float(output)
        except ValueError:
            discovered.append((candidate, output))

    assert discovered == [(1337, "TOKEN_90210_XYZ")], (
        f"Unexpected backdoor behavior from cost_function: {discovered!r}"
    )
    assert content == discovered[0][1], (
        f"Expected {file_path} to contain the token emitted by cost_function, but found '{content}'."
    )

    expected = "TOKEN_90210_XYZ"
    assert content == expected, f"Expected {file_path} to contain '{expected}', but found '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
