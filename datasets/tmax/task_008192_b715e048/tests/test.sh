#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess

CPP_FILE = "/home/user/bayesian_updater.cpp"
SCRIPT_FILE = "/home/user/run_pipeline.sh"
DATA_FILE = "/home/user/experiment_data.csv"
OUTPUT_FILE = "/home/user/posteriors.csv"


def run_checked(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, timeout=30, **kwargs)
    assert result.returncode == 0, (
        f"Command {command!r} failed with return code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    return result


def expected_csv(alpha, beta, counts):
    lines = ["variant,alpha_post,beta_post"]
    for variant in ("A", "B"):
        successes, failures = counts[variant]
        lines.append(f"{variant},{alpha + successes},{beta + failures}")
    return "\n".join(lines)


def read_output():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not created."
    with open(OUTPUT_FILE, "r", newline="") as f:
        return f.read().strip()


def make_random_dataset(rng):
    rows = ["uid,variant,converted"]
    counts = {"A": [0, 0], "B": [0, 0]}

    uid = rng.randint(10000, 50000)
    valid_rows = []
    for variant in ("A", "B"):
        for converted in (0, 1):
            valid_rows.append(f"{uid},{variant},{converted}")
            counts[variant][converted == 0] += converted == 0
            counts[variant][converted == 1] += converted == 1
            uid += 1

        for _ in range(rng.randint(3, 8)):
            converted = rng.randint(0, 1)
            valid_rows.append(f"{uid},{variant},{converted}")
            if converted == 1:
                counts[variant][0] += 1
            else:
                counts[variant][1] += 1
            uid += 1

    malformed_rows = [
        f"not_an_integer,A,1",
        f"-7,B,0",
        f"{uid},C,1",
        f"{uid + 1},a,0",
        f"{uid + 2},,1",
        f"{uid + 3},A,2",
        f"{uid + 4},B,-1",
        f"{uid + 5},A,true",
        f"{uid + 6},A",
        f"{uid + 7},B,1,extra",
        "",
    ]
    body = valid_rows + malformed_rows
    rng.shuffle(body)
    rows.extend(body)
    return "\n".join(rows) + "\n", counts


def test_files_exist_and_executable():
    assert os.path.isfile(CPP_FILE), f"C++ source {CPP_FILE} is missing."
    assert os.path.isfile(SCRIPT_FILE), f"Bash script {SCRIPT_FILE} is missing."
    assert os.access(SCRIPT_FILE, os.X_OK), f"Bash script {SCRIPT_FILE} is not executable."


def test_pipeline_execution_and_output():
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    result = subprocess.run([SCRIPT_FILE], capture_output=True, text=True, cwd="/home/user", timeout=30)
    assert result.returncode == 0, (
        f"Pipeline script failed with return code {result.returncode}. Stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not created by the pipeline."

    expected = "variant,alpha_post,beta_post\nA,5,7\nB,4,6"
    actual = read_output()
    assert actual == expected, (
        f"Contents of {OUTPUT_FILE} do not match expected.\nExpected:\n{expected}\nActual:\n{actual}"
    )


def test_compiled_program_and_pipeline_on_unseen_inputs():
    token = secrets.token_hex(8)
    binary = f"/tmp/bayesian_updater_{token}"

    compile_result = subprocess.run(
        ["g++", "-std=c++17", CPP_FILE, "-o", binary],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"The submitted C++ source did not compile with g++ -std=c++17.\n"
        f"Stdout: {compile_result.stdout}\nStderr: {compile_result.stderr}"
    )
    assert os.path.isfile(binary) and os.access(binary, os.X_OK)

    with open(DATA_FILE, "rb") as f:
        original_data = f.read()

    try:
        rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
        for iteration in range(3):
            dataset, counts = make_random_dataset(rng)
            with open(DATA_FILE, "w", newline="") as f:
                f.write(dataset)

            alpha = rng.randint(7, 40)
            beta = rng.randint(50, 90)
            if os.path.exists(OUTPUT_FILE):
                os.remove(OUTPUT_FILE)

            run_checked([binary, str(alpha), str(beta)], cwd="/tmp")
            expected = expected_csv(alpha, beta, counts)
            actual = read_output()
            assert actual == expected, (
                f"Compiled updater produced the wrong result on unseen dataset {iteration}.\n"
                f"Expected:\n{expected}\nActual:\n{actual}"
            )

            if iteration == 0:
                if os.path.exists(OUTPUT_FILE):
                    os.remove(OUTPUT_FILE)
                traced = subprocess.run(
                    ["bash", "-x", SCRIPT_FILE],
                    capture_output=True,
                    text=True,
                    cwd="/home/user",
                    timeout=30,
                )
                assert traced.returncode == 0, (
                    f"Pipeline failed on an unseen dataset.\nStdout: {traced.stdout}\n"
                    f"Stderr: {traced.stderr}"
                )
                pipeline_expected = expected_csv(2, 5, counts)
                pipeline_actual = read_output()
                assert pipeline_actual == pipeline_expected, (
                    "Pipeline did not process the unseen dataset with priors 2 and 5.\n"
                    f"Expected:\n{pipeline_expected}\nActual:\n{pipeline_actual}"
                )

                trace_lines = traced.stderr.splitlines()
                compile_lines = [
                    line for line in trace_lines
                    if re.search(r"(?:^|[\s/])g\+\+(?:\s|$)", line)
                ]
                assert any(
                    "-std=c++17" in line and "bayesian_updater.cpp" in line
                    for line in compile_lines
                ), (
                    "Pipeline did not invoke g++ with -std=c++17 on bayesian_updater.cpp.\n"
                    f"Shell trace:\n{traced.stderr}"
                )
    finally:
        with open(DATA_FILE, "wb") as f:
            f.write(original_data)
        if os.path.exists(binary):
            os.remove(binary)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
