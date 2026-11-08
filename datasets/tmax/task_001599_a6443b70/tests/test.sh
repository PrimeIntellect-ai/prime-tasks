#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import math
import os
import re
import shutil
import subprocess
import tempfile


def test_etl_processor_c_exists():
    path = "/home/user/etl_processor.c"
    assert os.path.isfile(path), f"Source file {path} does not exist."


def test_etl_processor_executable():
    path = "/home/user/etl_processor"
    assert os.path.isfile(path), f"Executable {path} does not exist. Did you compile the C program?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled executable."


def test_pipeline_test_sh_executable():
    path = "/home/user/pipeline_test.sh"
    assert os.path.isfile(path), f"Bash script {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert len(content) > 0, f"Script {path} is empty."


def test_test_result_txt():
    path = "/home/user/test_result.txt"
    assert os.path.isfile(path), f"Result file {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "REPRODUCIBLE: YES", f"Expected 'REPRODUCIBLE: YES' in {path}, got '{content}'."


def test_csv_outputs_format():
    files_to_check = [
        "/home/user/etl_output.csv",
        "/home/user/run1.csv",
        "/home/user/run2.csv"
    ]
    pattern = re.compile(r"^42,-?\d+\.\d{6},\d+\.\d{6}$")
    for path in files_to_check:
        assert os.path.isfile(path), f"Output file {path} does not exist."
        with open(path, "r") as f:
            content = f.read().strip()
        lines = content.splitlines()
        assert len(lines) == 1, f"Expected exactly 1 line in {path}, found {len(lines)}."
        assert pattern.match(lines[0]), (
            f"Content of {path} ('{lines[0]}') does not match the required format "
            "'seed,posterior_mean,bootstrap_se' with 6 decimal places."
        )


libc = ctypes.CDLL(None)
libc.srand.argtypes = [ctypes.c_uint]
libc.rand.argtypes = []
libc.rand.restype = ctypes.c_int


def expected_results(values, seed, bootstraps):
    libc.srand(seed)
    means = []
    n = len(values)
    for _ in range(bootstraps):
        total = 0.0
        for _ in range(n):
            total += values[libc.rand() % n]
        means.append(total / n)
    mu_boot = sum(means) / bootstraps
    squared = sum((x - mu_boot) ** 2 for x in means)
    population_se = math.sqrt(squared / bootstraps)
    sample_se = math.sqrt(squared / (bootstraps - 1)) if bootstraps > 1 else population_se
    posterior = (n * mu_boot) / (0.01 + n)
    return posterior, (population_se, sample_se)


def validate_output(values, seed, bootstraps):
    path = "/home/user/etl_output.csv"
    assert os.path.isfile(path), "Processor did not create /home/user/etl_output.csv"
    with open(path) as f:
        text = f.read().strip()
    match = re.fullmatch(r"(-?\d+),(-?\d+\.\d{6}),(\d+\.\d{6})", text)
    assert match, f"Processor output has incorrect format: {text!r}"
    assert int(match.group(1)) == seed
    actual_post = float(match.group(2))
    actual_se = float(match.group(3))
    expected_post, expected_ses = expected_results(values, seed, bootstraps)
    assert abs(actual_post - expected_post) <= 0.00000051, (
        f"Incorrect posterior mean: got {actual_post}, expected {expected_post:.6f}"
    )
    assert any(abs(actual_se - se) <= 0.00000051 for se in expected_ses), (
        f"Incorrect bootstrap SE: got {actual_se}, expected one of "
        f"{expected_ses[0]:.6f} or {expected_ses[1]:.6f}"
    )


def run_processor(executable, values, seed, bootstraps):
    fd, input_path = tempfile.mkstemp(prefix="etl_input_", suffix=".csv")
    try:
        with os.fdopen(fd, "w") as f:
            for value in values:
                f.write(f"{value}\n")
        try:
            os.remove("/home/user/etl_output.csv")
        except FileNotFoundError:
            pass
        result = subprocess.run(
            [executable, input_path, str(seed), str(bootstraps)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"Processor failed with exit code {result.returncode}: "
            f"{result.stderr.decode(errors='replace')}"
        )
        validate_output(values, seed, bootstraps)
    finally:
        try:
            os.remove(input_path)
        except FileNotFoundError:
            pass


def test_installed_processor_computes_results():
    cases = [
        ([1.25, 2.40, 0.75, -0.50, 1.10], 42, 1000),
        ([3.5, -2.0, 7.25, 0.125], 7, 37),
        ([-8.0, 1.0, 2.0, 9.0, 4.0, -1.0], 123, 53),
    ]
    for values, seed, bootstraps in cases:
        run_processor("/home/user/etl_processor", values, seed, bootstraps)


def test_submitted_source_compiles_and_computes_results():
    build_dir = tempfile.mkdtemp(prefix="etl_build_")
    executable = os.path.join(build_dir, "etl_from_source")
    try:
        result = subprocess.run(
            ["gcc", "/home/user/etl_processor.c", "-o", executable, "-lm"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, (
            "Submitted C source does not compile: " + result.stderr.decode(errors="replace")
        )
        run_processor(executable, [6.0, -3.0, 1.5, 2.25], 19, 61)
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def test_pipeline_really_runs_processor_twice_and_is_reproducible():
    processor = "/home/user/etl_processor"
    backup = "/tmp/etl_processor_verifier_backup"
    log = "/tmp/etl_processor_invocations.log"
    for path in [backup, log, "/home/user/etl_output.csv", "/home/user/run1.csv",
                 "/home/user/run2.csv", "/home/user/test_result.txt"]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    os.replace(processor, backup)
    try:
        with open(processor, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("printf '%s|%s|%s|%s\\n' \"$#\" \"${1-}\" \"${2-}\" \"${3-}\" >> " + log + "\n")
            f.write("exec " + backup + " \"$@\"\n")
        os.chmod(processor, 0o755)
        result = subprocess.run(
            ["bash", "/home/user/pipeline_test.sh"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Pipeline script failed with exit code {result.returncode}: "
            f"{result.stderr.decode(errors='replace')}"
        )
    finally:
        try:
            os.remove(processor)
        except FileNotFoundError:
            pass
        if os.path.exists(backup):
            os.replace(backup, processor)

    assert os.path.isfile(log), "Pipeline did not invoke /home/user/etl_processor"
    with open(log) as f:
        invocations = f.read().splitlines()
    expected_call = "3|/home/user/sensor_data.csv|42|1000"
    assert invocations == [expected_call, expected_call], (
        "Pipeline must invoke etl_processor exactly twice with sensor_data.csv, seed 42, "
        f"and 1000 bootstraps; observed {invocations!r}"
    )

    for path in ["/home/user/run1.csv", "/home/user/run2.csv", "/home/user/etl_output.csv"]:
        assert os.path.isfile(path), f"Pipeline did not create {path}"
    with open("/home/user/run1.csv", "rb") as f:
        run1 = f.read()
    with open("/home/user/run2.csv", "rb") as f:
        run2 = f.read()
    with open("/home/user/etl_output.csv", "rb") as f:
        final_output = f.read()
    assert run1 == run2, "run1.csv and run2.csv are not exactly identical"
    assert run2 == final_output, "run2.csv was not saved from the processor's final output"

    with open("/home/user/test_result.txt") as f:
        assert f.read().strip() == "REPRODUCIBLE: YES"
    validate_output([1.25, 2.40, 0.75, -0.50, 1.10], 42, 1000)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
