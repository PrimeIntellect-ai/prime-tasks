#!/bin/bash
set -u
mkdir -p /logs/verifier

ORIGINAL_GCC="/usr/bin/gcc.verifier-original.$$"
restore_gcc() {
    rm -f /usr/bin/gcc
    if [ -e "$ORIGINAL_GCC" ] || [ -L "$ORIGINAL_GCC" ]; then
        mv "$ORIGINAL_GCC" /usr/bin/gcc
    fi
}
trap restore_gcc EXIT

if ! mv /usr/bin/gcc "$ORIGINAL_GCC"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat > /usr/bin/gcc <<'PY_EOF'
#!/usr/bin/python3
import os
import stat
import subprocess
import sys

REAL_GCC = "__REAL_GCC__"
args = sys.argv[1:]
rc = subprocess.call([REAL_GCC] + args)
if rc != 0:
    raise SystemExit(rc)

# Determine gcc's output path. Wrap produced executables so the verifier can
# observe whether multiple smoothing jobs actually overlap.
compile_only = any(a in ("-c", "-S", "-E") for a in args)
out = "a.out"
for i, arg in enumerate(args):
    if arg == "-o" and i + 1 < len(args):
        out = args[i + 1]
    elif arg.startswith("-o") and len(arg) > 2:
        out = arg[2:]

if not compile_only and os.path.isfile(out) and os.access(out, os.X_OK):
    output = os.path.abspath(out)
    real_output = output + ".verifier-real"
    os.replace(output, real_output)
    wrapper = f'''#!/usr/bin/python3
import fcntl
import os
import subprocess
import sys
import time

state = "/tmp/verifier_parallel"
os.makedirs(state, exist_ok=True)
lock_path = os.path.join(state, "lock")
active_path = os.path.join(state, "active")
max_path = os.path.join(state, "max")

def read_int(path):
    try:
        with open(path) as f:
            return int(f.read().strip() or "0")
    except (OSError, ValueError):
        return 0

with open(lock_path, "a+") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    active = read_int(active_path) + 1
    maximum = max(read_int(max_path), active)
    with open(active_path, "w") as f:
        f.write(str(active))
    with open(max_path, "w") as f:
        f.write(str(maximum))
    fcntl.flock(lock, fcntl.LOCK_UN)

# Keep each invocation alive briefly, making overlap deterministic.
time.sleep(0.35)
try:
    result = subprocess.call([{real_output!r}] + sys.argv[1:])
finally:
    with open(lock_path, "a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        active = max(0, read_int(active_path) - 1)
        with open(active_path, "w") as f:
            f.write(str(active))
        fcntl.flock(lock, fcntl.LOCK_UN)
raise SystemExit(result)
'''
    with open(output, "w") as f:
        f.write(wrapper)
    os.chmod(output, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                    stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
PY_EOF
sed -i "s|__REAL_GCC__|$ORIGINAL_GCC|g" /usr/bin/gcc
chmod 755 /usr/bin/gcc

cat > /tmp/test_final_state.py <<'PYTEST_EOF'
import os
import shutil
import subprocess
from decimal import Decimal

import pytest

HOME = "/home/user"
SENSOR = os.path.join(HOME, "sensor_data")
CLEAN = os.path.join(HOME, "clean_data")
STATE = "/tmp/verifier_parallel"

ORIGINAL_DATA = {
    0: [(1, "10.0"), (5, "12.0"), (9, "11.0")],
    1: [(2, "20.0"), (6, "18.0"), (10, "22.0")],
    2: [(3, "15.0"), (7, "14.0"), (11, "16.0")],
    3: [(4, "30.0"), (8, "28.0"), (12, "32.0")],
}

DYNAMIC_DATA = {
    0: [(40, "1"), (-2, "3"), (105, "8"), (7, "4")],
    1: [(3, "10"), (90, "14"), (12, "20"), (200, "2")],
    2: [(1, "-3"), (60, "-1"), (13, "5"), (150, "8")],
    3: [(2, "100"), (70, "80"), (14, "60"), (120, "40")],
}


def write_inputs(data):
    os.makedirs(SENSOR, exist_ok=True)
    for index in range(4):
        with open(os.path.join(SENSOR, f"data_{index}.csv"), "w") as f:
            for timestamp, value in data[index]:
                f.write(f"{timestamp},{value}\n")


def expected_clean(rows):
    values = []
    result = []
    for timestamp, raw_value in rows:
        values.append(Decimal(raw_value))
        window = values[-3:]
        average = sum(window, Decimal("0")) / Decimal(len(window))
        result.append(f"{timestamp},{average:.2f}")
    return result


def read_nonempty(path):
    with open(path) as f:
        return [line.strip() for line in f if line.strip()]


def expected_merged(data):
    rows = []
    for index in range(4):
        for line in expected_clean(data[index]):
            timestamp = int(line.split(",", 1)[0])
            rows.append((timestamp, line))
    return [line for _, line in sorted(rows, key=lambda item: item[0])]


def reset_outputs_and_state():
    shutil.rmtree(CLEAN, ignore_errors=True)
    for path in (os.path.join(HOME, "final_clean.csv"),
                 os.path.join(HOME, "smoother"),
                 os.path.join(HOME, "smoother.verifier-real")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    shutil.rmtree(STATE, ignore_errors=True)
    os.makedirs(STATE)


def run_pipeline(data):
    write_inputs(data)
    reset_outputs_and_state()
    result = subprocess.run(
        ["bash", "/home/user/pipeline.sh"],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"pipeline.sh failed with exit status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="module", autouse=True)
def run_original_pipeline():
    assert os.path.isfile("/home/user/smoother.c"), "The C program /home/user/smoother.c is missing."
    assert os.path.isfile("/home/user/pipeline.sh"), "The bash script /home/user/pipeline.sh is missing."
    run_pipeline(ORIGINAL_DATA)


def test_c_program_exists():
    assert os.path.isfile("/home/user/smoother.c"), "The C program /home/user/smoother.c is missing."


def test_bash_script_exists():
    assert os.path.isfile("/home/user/pipeline.sh"), "The bash script /home/user/pipeline.sh is missing."


def test_clean_data_directory_and_files():
    assert os.path.isdir("/home/user/clean_data"), "The directory /home/user/clean_data/ was not created."

    expected_files = ["clean_0.csv", "clean_1.csv", "clean_2.csv", "clean_3.csv"]
    for f in expected_files:
        path = os.path.join("/home/user/clean_data", f)
        assert os.path.isfile(path), f"The cleaned file {path} was not created."

    for index in range(4):
        path = os.path.join(CLEAN, f"clean_{index}.csv")
        assert read_nonempty(path) == expected_clean(ORIGINAL_DATA[index]), \
            f"The contents of {path} are incorrect."


def test_final_clean_csv_content():
    final_csv_path = "/home/user/final_clean.csv"
    assert os.path.isfile(final_csv_path), f"The final merged file {final_csv_path} is missing."

    expected_lines = [
        "1,10.00",
        "2,20.00",
        "3,15.00",
        "4,30.00",
        "5,11.00",
        "6,19.00",
        "7,14.50",
        "8,29.00",
        "9,11.00",
        "10,20.00",
        "11,15.00",
        "12,30.00"
    ]

    actual_lines = read_nonempty(final_csv_path)
    assert actual_lines == expected_lines, f"The contents of {final_csv_path} do not match the expected sorted, smoothed output."


def test_original_run_used_parallel_smoothers():
    max_path = os.path.join(STATE, "max")
    assert os.path.isfile(max_path), "pipeline.sh did not execute the compiled smoother."
    with open(max_path) as f:
        maximum = int(f.read().strip())
    assert maximum >= 2, "The four smoothing jobs were not run in parallel as background processes."


def test_dynamic_inputs_clean_files_merge_and_parallelism():
    run_pipeline(DYNAMIC_DATA)

    assert os.path.isdir(CLEAN), "The dynamic run did not create clean_data/."
    for index in range(4):
        path = os.path.join(CLEAN, f"clean_{index}.csv")
        assert os.path.isfile(path), f"The dynamic run did not create {path}."
        assert read_nonempty(path) == expected_clean(DYNAMIC_DATA[index]), \
            f"The smoother produced incorrect rolling averages in {path}."

    final_path = os.path.join(HOME, "final_clean.csv")
    assert os.path.isfile(final_path), "The dynamic run did not create final_clean.csv."
    assert read_nonempty(final_path) == expected_merged(DYNAMIC_DATA), \
        "final_clean.csv is not the correctly numerically sorted merge of the dynamic outputs."

    max_path = os.path.join(STATE, "max")
    assert os.path.isfile(max_path), "The dynamic run did not execute the compiled smoother."
    with open(max_path) as f:
        maximum = int(f.read().strip())
    assert maximum >= 2, "The dynamic smoothing jobs did not overlap."


def test_compiled_smoother_command_line_interface_directly():
    executable = os.path.join(HOME, "smoother")
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), \
        "pipeline.sh did not compile an executable named smoother."

    input_path = "/tmp/verifier_smoother_input.csv"
    output_path = "/tmp/verifier_smoother_output.csv"
    rows = [(9, "2"), (8, "4"), (7, "12"), (6, "20"), (5, "1")]
    with open(input_path, "w") as f:
        for timestamp, value in rows:
            f.write(f"{timestamp},{value}\n")
    try:
        os.remove(output_path)
    except FileNotFoundError:
        pass

    result = subprocess.run([executable, input_path, output_path], timeout=20)
    assert result.returncode == 0, "The compiled smoother failed when called with input and output paths."
    assert os.path.isfile(output_path), "The compiled smoother did not create its requested output file."
    assert read_nonempty(output_path) == expected_clean(rows), \
        "The compiled smoother's direct output is incorrect."
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
