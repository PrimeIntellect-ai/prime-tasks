#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

SCRIPT_PATH = "/home/user/pipeline.sh"
EXE_PATH = "/home/user/sim_src/simulate"
H5_PATH = "/home/user/sim_src/synth_data.h5"
OUTPUT_PATH = "/home/user/ci_output.txt"
PIPELINE_RESULT = None


def setup_module(module):
    global PIPELINE_RESULT

    # Require this invocation of the pipeline to create every output checked below.
    for path in (EXE_PATH, H5_PATH, OUTPUT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    if os.path.isfile(SCRIPT_PATH) and os.access(SCRIPT_PATH, os.X_OK):
        env = os.environ.copy()
        # Do not let the verifier accidentally supply the required setting.
        env["OMP_NUM_THREADS"] = "8"
        PIPELINE_RESULT = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )


def _read_signal_values():
    result = subprocess.run(
        ["h5dump", "-d", "/features/signal", H5_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"h5dump failed: {result.stderr}"

    values = []
    in_data = False
    number = re.compile(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?")
    for line in result.stdout.splitlines():
        stripped = line.strip()
        if not in_data:
            if stripped == "DATA {":
                in_data = True
            continue
        if stripped == "}":
            break
        # Remove the h5dump coordinate, e.g. '(0):'.
        payload = re.sub(r"^\s*\([^)]*\):\s*", "", line)
        values.extend(float(token) for token in number.findall(payload))

    assert in_data, "Dataset /features/signal has no readable DATA section."
    return values


def _independent_ci(values):
    values_path = "/tmp/verifier_signal_values.txt"
    with open(values_path, "w") as f:
        for value in values:
            f.write(f"{value:.17g}\n")

    command = r'''awk 'BEGIN { srand(1234) }
        { a[++N] = $1 }
        END {
            for (b = 1; b <= 100; b++) {
                sum = 0
                for (i = 1; i <= N; i++)
                    sum += a[int(rand() * N) + 1]
                print sum / N
            }
        }' /tmp/verifier_signal_values.txt | sort -n | awk '
        NR == 5 { lower = $1 }
        NR == 96 { upper = $1 }
        END { printf "CI: [%.4f, %.4f]", lower, upper }
    '''
    result = subprocess.run(
        ["bash", "-c", command],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"Independent CI calculation failed: {result.stderr}"
    return result.stdout.strip()


def test_pipeline_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_pipeline_executed_successfully():
    assert PIPELINE_RESULT is not None, "Pipeline could not be executed."
    assert PIPELINE_RESULT.returncode == 0, (
        f"Pipeline exited with status {PIPELINE_RESULT.returncode}.\n"
        f"stdout:\n{PIPELINE_RESULT.stdout}\n"
        f"stderr:\n{PIPELINE_RESULT.stderr}"
    )


def test_simulation_compiled():
    assert os.path.isfile(EXE_PATH), f"Simulation executable {EXE_PATH} was not compiled."
    assert os.access(EXE_PATH, os.X_OK), f"Simulation executable {EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The generated simulation executable is not an ELF binary."


def test_hdf5_file_generated():
    assert os.path.isfile(H5_PATH), f"HDF5 file {H5_PATH} was not generated."


def test_generated_signal_dataset():
    values = _read_signal_values()
    assert len(values) == 500, f"Expected 500 signal values, found {len(values)}."

    # With one OpenMP thread the source simulation adds 6.125 to its base pattern.
    expected = [16.125 + (i % 10) * 0.5 for i in range(500)]
    for index, (actual, wanted) in enumerate(zip(values, expected)):
        assert math.isfinite(actual), f"Signal value {index} is not finite."
        assert abs(actual - wanted) <= 1e-6, (
            f"Signal value {index} is {actual}, expected {wanted} from the provided simulation."
        )


def test_ci_output_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."


def test_ci_output_format_and_values():
    assert os.path.isfile(OUTPUT_PATH), "Output file missing."

    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()

    # Expected format: CI: [Lower, Upper]
    pattern = r"^CI:\s*\[(\d+\.\d{4}),\s*(\d+\.\d{4})\]$"
    match = re.match(pattern, content)
    assert match, f"Output format is incorrect. Expected 'CI: [Lower, Upper]' with 4 decimal places, got: '{content}'"

    lower_str, upper_str = match.groups()
    lower = float(lower_str)
    upper = float(upper_str)

    assert lower <= upper, "Lower bound must be less than or equal to upper bound."

    # The true mean is 18.375. The bootstrap CI bounds should be close to this.
    assert 17.5 <= lower <= 19.0, f"Lower bound {lower} is not in the expected range for the mean 18.375."
    assert 17.5 <= upper <= 19.0, f"Upper bound {upper} is not in the expected range for the mean 18.375."

    values = _read_signal_values()
    expected_content = _independent_ci(values)
    assert content == expected_content, (
        f"Incorrect bootstrap confidence interval. Expected '{expected_content}', got '{content}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
