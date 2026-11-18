#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest

SOURCE = "/home/user/analyze.c"
DATA = "/home/user/spectroscopy_data.csv"
RESULTS = "/home/user/analysis_results.txt"

REFERENCE_C = r'''
#include <stdio.h>
#include <stdlib.h>

int compare(const void *a, const void *b) {
    double da = *(const double *)a;
    double db = *(const double *)b;
    if (da < db) return -1;
    if (da > db) return 1;
    return 0;
}

int main(void) {
    FILE *f = fopen("/home/user/spectroscopy_data.csv", "r");
    if (!f) return 1;

    double data[100];
    int t;
    for (int i = 0; i < 100; i++) {
        if (fscanf(f, "%d,%lf", &t, &data[i]) != 2) {
            fclose(f);
            return 2;
        }
    }
    fclose(f);

    double S[100];
    for (int i = 0; i < 100; i++) S[i] = data[i];
    for (int i = 2; i < 98; i++) {
        S[i] = (data[i-2] + data[i-1] + data[i] + data[i+1] + data[i+2]) / 5.0;
    }

    double C[100];
    C[0] = 1.0;
    for (int i = 1; i < 100; i++) {
        C[i] = C[i-1] + 0.1 * C[i-1] * (1.0 - C[i-1] / 100.0);
    }

    double E[100];
    double mse = 0.0;
    for (int i = 0; i < 100; i++) {
        E[i] = (S[i] - C[i]) * (S[i] - C[i]);
        mse += E[i];
    }
    mse /= 100.0;

    srand(42);
    double bootstrap_means[1000];
    for (int b = 0; b < 1000; b++) {
        double sum = 0.0;
        for (int i = 0; i < 100; i++) {
            int idx = rand() % 100;
            sum += E[idx];
        }
        bootstrap_means[b] = sum / 100.0;
    }

    qsort(bootstrap_means, 1000, sizeof(double), compare);
    printf("MSE: %.4f%c", mse, 10);
    printf("CI_LOWER: %.4f%c", bootstrap_means[24], 10);
    printf("CI_UPPER: %.4f%c", bootstrap_means[974], 10);
    return 0;
}
'''


def compile_program(source, output):
    result = subprocess.run(
        ["gcc", source, "-o", output, "-lm"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, "Failed to compile C code:\n" + result.stderr


def run_program(binary):
    result = subprocess.run(
        [binary], cwd="/home/user", capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"Program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def reference_output(reference_binary):
    result = subprocess.run(
        [reference_binary], capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, "Failed to run reference C code."
    return result.stdout


def parse_output(text):
    values = {}
    for line in text.strip().splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            values[key.strip()] = float(value.strip())
    return values


def assert_correct(actual_text, expected_text):
    expected = parse_output(expected_text)
    actual = parse_output(actual_text)
    assert "MSE" in expected, "Reference code failed to produce MSE."
    for key in ["MSE", "CI_LOWER", "CI_UPPER"]:
        assert key in actual, f"Missing {key} in /home/user/analysis_results.txt"
        assert abs(expected[key] - actual[key]) < 0.001, (
            f"Expected {key} to be close to {expected[key]:.4f}, "
            f"but got {actual[key]:.4f}."
        )


@pytest.fixture(scope="session")
def built_programs(tmp_path_factory):
    assert os.path.isfile(SOURCE), "The file /home/user/analyze.c does not exist."
    build_dir = tmp_path_factory.mktemp("build")
    submission = str(build_dir / "analyze")
    reference_source = str(build_dir / "reference.c")
    reference = str(build_dir / "reference")

    with open(reference_source, "w") as f:
        f.write(REFERENCE_C)

    compile_program(SOURCE, submission)
    compile_program(reference_source, reference)
    return submission, reference


@pytest.fixture(scope="session", autouse=True)
def execute_submission(built_programs):
    submission, reference = built_programs
    with open(DATA, "rb") as f:
        data_before = f.read()
    expected = reference_output(reference)

    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    run_program(submission)

    assert os.path.isfile(RESULTS), (
        "The executed C program did not generate /home/user/analysis_results.txt."
    )
    with open(DATA, "rb") as f:
        assert f.read() == data_before, "The C program modified its input dataset."
    return expected, data_before


def test_analyze_c_exists():
    assert os.path.isfile(SOURCE), "The file /home/user/analyze.c does not exist."


def test_analysis_results_exists():
    assert os.path.isfile(RESULTS), "The file /home/user/analysis_results.txt does not exist."


def test_analysis_results_correctness(execute_submission):
    expected, _ = execute_submission
    with open(RESULTS, "r") as f:
        actual = f.read()
    assert_correct(actual, expected)


def test_compiled_program_processes_input(built_programs, execute_submission):
    submission, reference = built_programs
    original_expected, original_data = execute_submission

    synthetic = "".join(
        f"{i},{3.0 + i * 0.73 + ((i * 37) % 13) * 0.19:.4f}\n"
        for i in range(100)
    ).encode()

    try:
        with open(DATA, "wb") as f:
            f.write(synthetic)
        expected = reference_output(reference)
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        run_program(submission)
        assert os.path.isfile(RESULTS), "The C program did not regenerate the results file."
        with open(DATA, "rb") as f:
            assert f.read() == synthetic, "The C program modified its input dataset."
        with open(RESULTS, "r") as f:
            actual = f.read()
        assert_correct(actual, expected)
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        if os.path.exists(RESULTS):
            os.remove(RESULTS)
        run_program(submission)

    assert os.path.isfile(RESULTS), "The C program did not regenerate the original results."
    with open(RESULTS, "r") as f:
        assert_correct(f.read(), original_expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
