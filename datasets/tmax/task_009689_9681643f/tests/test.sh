#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import shlex
import subprocess
import uuid

import matplotlib.image as mpimg
import numpy as np
import pytest

PROCESS_SCRIPT = "/home/user/process.sh"
RUN_TESTS_SCRIPT = "/home/user/run_tests.sh"
SIM_DIR = "/home/user/sim_data"
PLOT_DIR = "/home/user/plots"
REPORT_FILE = "/home/user/regression_report.txt"
REFERENCE_FILE = os.path.join(SIM_DIR, "reference.csv")


def write_log(path, mass, frequency, samples=1000, dt=0.01):
    with open(path, "w") as f:
        f.write("Simulation ID: verifier\n")
        f.write(f"Mass (kg): {mass:.6f}\n")
        f.write("-- DATA START --\n")
        for i in range(samples):
            t = i * dt
            # The requested frequency is the unambiguously dominant component.
            val = (
                math.sin(2 * math.pi * frequency * t)
                + 0.08 * math.sin(2 * math.pi * 9.0 * t)
                + 0.02 * math.cos(2 * math.pi * 12.0 * t)
            )
            f.write(f"t={t:.3f}, val={val:.8f}\n")


def assert_valid_png(path):
    assert os.path.isfile(path), f"The plot {path} was not generated."
    assert os.path.getsize(path) > 0, f"The plot {path} is empty."
    with open(path, "rb") as f:
        assert f.read(8) == b"\x89PNG\r\n\x1a\n", f"{path} is not a PNG file."
    image = mpimg.imread(path)
    assert image.ndim in (2, 3), f"The plot {path} is not a readable image."
    assert image.shape[0] >= 100 and image.shape[1] >= 100, f"The plot {path} is implausibly small."
    assert float(np.nanstd(image)) > 0.001, f"The plot {path} contains no visible plot content."


@pytest.fixture(scope="session", autouse=True)
def execute_regression_suite():
    assert os.path.isfile(PROCESS_SCRIPT), f"The script {PROCESS_SCRIPT} does not exist."
    assert os.access(PROCESS_SCRIPT, os.X_OK), f"The script {PROCESS_SCRIPT} is not executable."
    assert os.path.isfile(RUN_TESTS_SCRIPT), f"The script {RUN_TESTS_SCRIPT} does not exist."
    assert os.access(RUN_TESTS_SCRIPT, os.X_OK), f"The script {RUN_TESTS_SCRIPT} is not executable."

    token = uuid.uuid4().hex
    extra_name = f"exp_verify_{token}.log"
    extra_path = os.path.join(SIM_DIR, extra_name)
    extra_plot = os.path.join(PLOT_DIR, f"exp_verify_{token}_spectrum.png")
    mass = 1.0 + secrets.randbelow(250) / 100.0
    frequency = (13 + secrets.randbelow(35)) / 10.0
    expected = mass * (2 * math.pi * frequency) ** 2
    expected_text = f"{expected:.2f}"

    with open(REFERENCE_FILE, "rb") as f:
        original_reference = f.read()

    write_log(extra_path, mass, frequency)
    with open(REFERENCE_FILE, "ab") as f:
        if original_reference and not original_reference.endswith(b"\n"):
            f.write(b"\n")
        f.write(f"{extra_name},{expected_text}\n".encode())

    for path in (
        REPORT_FILE,
        os.path.join(PLOT_DIR, "exp_1_spectrum.png"),
        os.path.join(PLOT_DIR, "exp_2_spectrum.png"),
        extra_plot,
    ):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    real_process = f"/home/user/.process_verifier_{token}.sh"
    trace_file = f"/tmp/process_trace_{token}"
    os.rename(PROCESS_SCRIPT, real_process)
    try:
        with open(PROCESS_SCRIPT, "w") as f:
            f.write("#!/bin/bash\n")
            f.write(f"printf '%s\\n' \"$1\" >> {shlex.quote(trace_file)}\n")
            f.write(f"exec {shlex.quote(real_process)} \"$@\"\n")
        os.chmod(PROCESS_SCRIPT, 0o755)

        result = subprocess.run(
            [RUN_TESTS_SCRIPT],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
        )
        assert result.returncode == 0, (
            f"run_tests.sh exited with {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )

        assert os.path.isfile(trace_file), "run_tests.sh did not execute process.sh."
        with open(trace_file) as f:
            calls = [os.path.basename(line.strip()) for line in f if line.strip()]
        for required in ("exp_1.log", "exp_2.log", extra_name):
            assert required in calls, f"run_tests.sh did not execute process.sh for {required}."

        assert os.path.isfile(REPORT_FILE), "run_tests.sh did not generate regression_report.txt."
        with open(REPORT_FILE) as f:
            report = f.read()
        pattern = re.compile(
            rf"^\[(PASS|FAIL)\]\s+{re.escape(extra_name)}:\s+"
            rf"Expected\s+{re.escape(expected_text)},\s+Got\s+([-+]?[0-9]+(?:\.[0-9]+)?)\s*$",
            re.MULTILINE,
        )
        match = pattern.search(report)
        assert match is not None, "run_tests.sh did not create a correctly formatted line for an additional exp_*.log file."
        assert match.group(1) == "PASS", "The additional regression case was not marked PASS."
        assert abs(float(match.group(2)) - expected) <= 5.0, "The additional regression result is incorrect."
        assert_valid_png(extra_plot)
    finally:
        try:
            os.remove(PROCESS_SCRIPT)
        except FileNotFoundError:
            pass
        if os.path.exists(real_process):
            os.rename(real_process, PROCESS_SCRIPT)
        with open(REFERENCE_FILE, "wb") as f:
            f.write(original_reference)
        for path in (extra_path, extra_plot, trace_file):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_scripts_exist_and_executable():
    process_script = "/home/user/process.sh"
    run_tests_script = "/home/user/run_tests.sh"

    assert os.path.isfile(process_script), f"The script {process_script} does not exist."
    assert os.access(process_script, os.X_OK), f"The script {process_script} is not executable."

    assert os.path.isfile(run_tests_script), f"The script {run_tests_script} does not exist."
    assert os.access(run_tests_script, os.X_OK), f"The script {run_tests_script} is not executable."


def test_process_script_on_derived_inputs():
    # Exercise independent, randomized logs whose answers are derived here and
    # are not present in reference.csv.
    for _ in range(2):
        token = uuid.uuid4().hex
        log_path = f"/tmp/oscillator_{token}.log"
        plot_path = os.path.join(PLOT_DIR, f"oscillator_{token}_spectrum.png")
        mass = 0.75 + secrets.randbelow(300) / 100.0
        frequency = (11 + secrets.randbelow(38)) / 10.0
        expected = mass * (2 * math.pi * frequency) ** 2
        write_log(log_path, mass, frequency)
        try:
            result = subprocess.run(
                [PROCESS_SCRIPT, log_path],
                cwd="/home/user",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=60,
            )
            assert result.returncode == 0, (
                f"process.sh exited with {result.returncode}. stderr:\n{result.stderr}"
            )
            assert re.fullmatch(r"[0-9]+\.[0-9]{2}\n?", result.stdout), (
                "process.sh must print only the calculated k rounded to exactly two decimal places; "
                f"got {result.stdout!r}."
            )
            calculated = float(result.stdout.strip())
            assert abs(calculated - expected) <= 0.10, (
                f"process.sh returned {calculated}, expected approximately {expected:.2f}."
            )
            assert_valid_png(plot_path)
        finally:
            for path in (log_path, plot_path):
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass


def test_plots_generated():
    plot1 = "/home/user/plots/exp_1_spectrum.png"
    plot2 = "/home/user/plots/exp_2_spectrum.png"

    assert os.path.isfile(plot1), f"The plot {plot1} was not generated."
    assert os.path.getsize(plot1) > 0, f"The plot {plot1} is empty."

    assert os.path.isfile(plot2), f"The plot {plot2} was not generated."
    assert os.path.getsize(plot2) > 0, f"The plot {plot2} is empty."

    assert_valid_png(plot1)
    assert_valid_png(plot2)


def test_regression_report_content():
    report_file = "/home/user/regression_report.txt"
    assert os.path.isfile(report_file), f"The report file {report_file} does not exist."

    with open(report_file, "r") as f:
        content = f.read()

    # Check for exp_1.log
    match1 = re.search(r'\[(PASS|FAIL)\]\s+exp_1\.log:\s+Expected\s+315\.83,\s+Got\s+([0-9\.]+)', content)
    assert match1 is not None, "Could not find properly formatted report line for exp_1.log in regression_report.txt."

    status1, got1_str = match1.groups()
    got1 = float(got1_str)
    assert abs(got1 - 315.83) <= 5.0, f"Calculated k for exp_1.log ({got1}) is not within 5.0 of expected 315.83."
    assert status1 == "PASS", f"Expected PASS for exp_1.log, but got {status1}."

    # Check for exp_2.log
    match2 = re.search(r'\[(PASS|FAIL)\]\s+exp_2\.log:\s+Expected\s+725\.71,\s+Got\s+([0-9\.]+)', content)
    assert match2 is not None, "Could not find properly formatted report line for exp_2.log in regression_report.txt."

    status2, got2_str = match2.groups()
    got2 = float(got2_str)
    assert abs(got2 - 725.71) <= 5.0, f"Calculated k for exp_2.log ({got2}) is not within 5.0 of expected 725.71."
    assert status2 == "PASS", f"Expected PASS for exp_2.log, but got {status2}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
