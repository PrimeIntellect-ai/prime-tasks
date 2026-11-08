#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tempfile
import time

SOURCE = "/home/user/simulator.c"
EXECUTABLE = "/home/user/simulator"
SCRIPT = "/home/user/test_regression.sh"
REPORT = "/home/user/debug_report.txt"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def source_without_comments():
    with open(SOURCE, "r", encoding="utf-8") as f:
        text = f.read()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//.*", "", text)
    return text


def test_simulator_c_exists_and_contains_precision_fix():
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing."
    text = source_without_comments()

    # The state being decremented must have more precision than binary32.
    assert re.search(
        r"\b(?:double|long\s+double)\s+energy\s*=\s*33554432(?:\.0+)?(?:[lL])?\s*;",
        text,
    ), "energy must use double or long double precision while retaining its original value."
    assert not re.search(r"\bfloat\s+energy\b", text), \
        "energy is still stored as a float."
    assert re.search(r"\benergy\s*-=\s*decay_rate\s*;", text), \
        "The original decay operation was not retained."


def test_subtraction_is_numerically_effective():
    with open(SOURCE, "r", encoding="utf-8") as f:
        submitted = f.read()

    operation = re.compile(r"\benergy\s*-=\s*decay_rate\s*;")
    assert len(operation.findall(submitted)) == 1, \
        "Expected exactly one energy decay operation."

    # Exercise the repaired operation itself. After the first subtraction,
    # 33554432 - 1 must be 33554431; binary32 incorrectly rounds it back.
    probe_statement = (
        "energy -= decay_rate; "
        "if ((long double)energy != 33554431.0L) exit(86); "
        "energy = 0;"
    )
    probed = operation.sub(probe_statement, submitted, count=1)

    with tempfile.TemporaryDirectory() as td:
        probe_c = os.path.join(td, "precision_probe.c")
        probe_bin = os.path.join(td, "precision_probe")
        with open(probe_c, "w", encoding="utf-8") as f:
            f.write(probed)
        built = run(["gcc", "-O2", probe_c, "-o", probe_bin], timeout=15)
        assert built.returncode == 0, f"Repaired source failed to compile:\n{built.stderr}"
        result = run([probe_bin], timeout=2.0)
        assert result.returncode == 0, \
            f"The first decay subtraction did not produce 33554431 (exit {result.returncode})."
        assert "Simulation complete." in result.stdout


def test_simulator_executable_exists_and_runs():
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", \
            "simulator must be a compiled ELF executable, not a script."

    try:
        result = run([EXECUTABLE], timeout=2.0)
    except subprocess.TimeoutExpired:
        raise AssertionError("Simulator timed out after 2 seconds.")
    assert result.returncode == 0, f"Simulator exited with code {result.returncode}"
    assert "Simulation complete." in result.stdout, \
        "Simulator did not print expected output."

    # Independently compile and execute the submitted source so a replacement
    # executable cannot hide an unfixed simulator.c.
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "simulator")
        built = run(["gcc", "-O2", SOURCE, "-o", rebuilt], timeout=15)
        assert built.returncode == 0, f"simulator.c failed to compile:\n{built.stderr}"
        try:
            rebuilt_result = run([rebuilt], timeout=2.0)
        except subprocess.TimeoutExpired:
            raise AssertionError("A fresh build of simulator.c timed out after 2 seconds.")
        assert rebuilt_result.returncode == 0
        assert "Simulation complete." in rebuilt_result.stdout


def invoke_regression(timeout=5.0):
    return run([SCRIPT], cwd="/home/user", timeout=timeout)


def test_regression_script_exists_and_runs():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."

    result = invoke_regression()
    assert result.returncode == 0, \
        f"test_regression.sh exited with code {result.returncode}"
    assert "PASS" in result.stdout, "test_regression.sh did not echo PASS."

    backup = EXECUTABLE + ".verifier-backup"
    assert not os.path.exists(backup)
    os.replace(EXECUTABLE, backup)
    try:
        # It must reject a simulator that exits unsuccessfully.
        with open(EXECUTABLE, "w", encoding="utf-8") as f:
            f.write("#!/bin/bash\nexit 7\n")
        os.chmod(EXECUTABLE, 0o755)
        failed = invoke_regression()
        assert failed.returncode != 0, \
            "Regression script passed a simulator that exited non-zero."

        # It must also enforce the requested two-second timeout.
        with open(EXECUTABLE, "w", encoding="utf-8") as f:
            f.write("#!/bin/bash\nsleep 3\necho 'Simulation complete.'\nexit 0\n")
        os.chmod(EXECUTABLE, 0o755)
        started = time.monotonic()
        slow = invoke_regression(timeout=4.5)
        elapsed = time.monotonic() - started
        assert slow.returncode != 0, \
            "Regression script passed a simulator that exceeded two seconds."
        assert elapsed < 3.0, \
            "Regression script did not terminate the slow simulator at two seconds."
    finally:
        if os.path.exists(EXECUTABLE):
            os.unlink(EXECUTABLE)
        os.replace(backup, EXECUTABLE)


def test_debug_report_contents():
    assert os.path.isfile(REPORT), f"{REPORT} is missing."
    with open(REPORT, "r", encoding="utf-8") as f:
        original = f.read()
    content = original.lower()

    assert "float energy = 33554432.0f;" in original, \
        "debug_report.txt must contain the exact original faulty declaration."
    precision_keywords = ["precision", "mantissa", "significand", "ieee", "representable", "ulp", "round"]
    assert any(word in content for word in precision_keywords), \
        "Report does not explain the floating-point precision limitation."
    assert "float" in content, "Report must identify the limited floating-point type."
    assert any(term in content for term in ["subtract", "subtraction", "decay_rate", "decay rate"]), \
        "Report must explain why the decay subtraction failed to change energy."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
