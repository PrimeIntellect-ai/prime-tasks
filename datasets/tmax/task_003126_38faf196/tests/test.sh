#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import pytest

HOME = "/home/user"
SOURCE = os.path.join(HOME, "optimize_protein.cpp")
BINARY = os.path.join(HOME, "optimize_protein")
RESULT = os.path.join(HOME, "result.txt")


def run_program(path):
    completed = subprocess.run(
        [path], cwd=HOME, capture_output=True, text=True, timeout=20, check=True
    )
    return completed.stdout.strip()


def strip_comments(source):
    return re.sub(r"//[^\n]*|/\*.*?\*/", "", source, flags=re.S)


def test_source_implements_ordered_threaded_reduction():
    assert os.path.isfile(SOURCE), f"Missing {SOURCE}"
    with open(SOURCE, "r", encoding="utf-8") as f:
        source = strip_comments(f.read())

    assert re.search(r"(?:std::)?thread\s*[<(]", source), \
        "The submitted source no longer uses worker threads."
    join_match = re.search(r"\.join\s*\(", source)
    assert join_match, "The submitted source does not join its worker threads."

    declaration = re.search(r"\bdouble\s+total_power\s*=\s*0(?:\.0)?\s*;", source)
    assert declaration, "The original total_power calculation is missing."

    before_join = source[declaration.end():join_match.start()]
    assert not re.search(r"\btotal_power\s*(?:\+=|-=|\*=|/=|=(?!=))", before_join), \
        "Worker threads still modify total_power before they are joined."
    assert "compute_dft_power" in before_join, \
        "The DFT segment powers are not computed by the threaded section."

    # Workers must publish their result to a slot selected by the segment index.
    assignments = []
    for match in re.finditer(
        r"\b([A-Za-z_]\w*)\s*\[\s*([A-Za-z_]\w*)\s*\]\s*=\s*([^;]+);",
        before_join,
    ):
        array_name, index_name, rhs = match.groups()
        if "compute_dft_power" in rhs or re.fullmatch(r"\s*[A-Za-z_]\w*\s*", rhs):
            assignments.append((array_name, index_name))
    assert assignments, \
        "Each worker must store its local DFT power in an indexed result slot."

    after_join = source[join_match.end():]
    ordered = False
    for array_name, _ in assignments:
        arr = re.escape(array_name)

        # Accept a conventional increasing index loop from 0 through all segments.
        loop_pattern = re.compile(
            r"for\s*\(\s*(?:int|unsigned|size_t|std::size_t|auto)\s+([A-Za-z_]\w*)"
            r"\s*=\s*0\s*;\s*\1\s*<\s*(?:num_segments|4)\s*;"
            r"\s*(?:\+\+\s*\1|\1\s*\+\+)\s*\)\s*\{([^{}]*)\}",
            re.S,
        )
        for loop in loop_pattern.finditer(after_join):
            index_name, body = loop.groups()
            if re.search(
                r"\btotal_power\s*\+=\s*" + arr + r"\s*\[\s*" +
                re.escape(index_name) + r"\s*\]\s*;",
                body,
            ):
                ordered = True

        # A range-for over the indexed vector also traverses slots in order.
        range_pattern = re.compile(
            r"for\s*\(\s*(?:const\s+)?(?:double|auto)(?:\s*&)?\s+([A-Za-z_]\w*)"
            r"\s*:\s*" + arr + r"\s*\)\s*\{([^{}]*)\}",
            re.S,
        )
        for loop in range_pattern.finditer(after_join):
            value_name, body = loop.groups()
            if re.search(
                r"\btotal_power\s*\+=\s*" + re.escape(value_name) + r"\s*;",
                body,
            ):
                ordered = True

        # Also permit four explicit additions in the required order.
        explicit = (
            r"\btotal_power\s*\+=\s*" + arr + r"\s*\[\s*0\s*\]\s*;.*?"
            r"\btotal_power\s*\+=\s*" + arr + r"\s*\[\s*1\s*\]\s*;.*?"
            r"\btotal_power\s*\+=\s*" + arr + r"\s*\[\s*2\s*\]\s*;.*?"
            r"\btotal_power\s*\+=\s*" + arr + r"\s*\[\s*3\s*\]\s*;"
        )
        if re.search(explicit, after_join, re.S):
            ordered = True

    assert ordered, \
        "After joining the threads, total_power must be accumulated sequentially from segment 0 to segment 3."


def test_artifacts_and_result():
    assert os.path.isfile(RESULT), f"File {RESULT} does not exist. Did you save the final value?"
    with open(RESULT, "r", encoding="utf-8") as f:
        result_contents = f.read()
    assert re.fullmatch(r"[+-]?\d+\.\d{6}\n?", result_contents), \
        "result.txt must contain only one floating-point number rounded to 6 decimal places."
    user_val_str = result_contents.strip()

    assert os.path.isfile(BINARY), f"Missing compiled executable {BINARY}"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable"

    truth_cpp_code = r'''
#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <iomanip>
using namespace std;
double compute_dft_power(const vector<double>& sig, int start, int len) {
    double real_part = 0.0;
    double imag_part = 0.0;
    double freq = 0.05;
    for (int i = 0; i < len; ++i) {
        double angle = 2.0 * M_PI * freq * i;
        real_part += sig[start + i] * cos(angle);
        imag_part -= sig[start + i] * sin(angle);
    }
    return (real_part * real_part + imag_part * imag_part) / len;
}
int main() {
    vector<double> signal;
    ifstream infile("signal.txt");
    double val;
    while (infile >> val) signal.push_back(val);
    int num_segments = 4;
    int seg_len = 250;
    double total_power = 0.0;
    for (int i = 0; i < num_segments; ++i)
        total_power += compute_dft_power(signal, i * seg_len, seg_len);
    double k = 0.5;
    double learning_rate = 0.001;
    double target_concentration = 150.0;
    for (int step = 0; step < 1000; ++step) {
        double y = 0.0;
        double dt = 0.1;
        double t_end = 10.0;
        double y_grad = 0.0;
        for (double t = 0; t < t_end; t += dt) {
            y += (total_power - k * y) * dt;
            y_grad += (-y - k * y_grad) * dt;
        }
        double error = y - target_concentration;
        double loss_grad = 2.0 * error * y_grad;
        double k_new = k - learning_rate * loss_grad;
        if (abs(k_new - k) < 1e-6) {
            k = k_new;
            break;
        }
        k = k_new;
    }
    cout << fixed << setprecision(6) << k << endl;
    return 0;
}
'''

    with tempfile.TemporaryDirectory() as td:
        truth_source = os.path.join(td, "truth.cpp")
        truth_binary = os.path.join(td, "truth")
        rebuilt_binary = os.path.join(td, "submitted")
        with open(truth_source, "w", encoding="utf-8") as f:
            f.write(truth_cpp_code)

        subprocess.run(
            ["g++", "-O3", truth_source, "-o", truth_binary],
            check=True, capture_output=True, text=True, timeout=30,
        )
        subprocess.run(
            ["g++", "-O3", "-pthread", SOURCE, "-o", rebuilt_binary],
            check=True, capture_output=True, text=True, timeout=30,
        )

        truth_val_str = run_program(truth_binary)
        rebuilt_outputs = [run_program(rebuilt_binary) for _ in range(4)]
        submitted_outputs = [run_program(BINARY) for _ in range(4)]

    assert user_val_str == truth_val_str, \
        f"Expected deterministic value {truth_val_str}, but got {user_val_str}."
    assert all(value == truth_val_str for value in rebuilt_outputs), \
        "The submitted source does not consistently produce the deterministic result."
    assert all(value == truth_val_str for value in submitted_outputs), \
        "The submitted executable does not consistently produce the deterministic result."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
