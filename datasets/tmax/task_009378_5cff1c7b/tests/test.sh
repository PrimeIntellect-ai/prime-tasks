#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess
import tempfile

import pytest

A_PATH = "/home/user/service_A_logs.csv"
B_PATH = "/home/user/service_B_logs.csv"
CPP_PATH = "/home/user/bootstrap.cpp"
OUTPUT_PATH = "/home/user/ci_output.txt"
OUTPUT_RE = re.compile(r"^Lower:\s*([\d\.]+),\s*Upper:\s*([\d\.]+)$")


def pristine_inputs():
    rng = random.Random(123)
    a_lines = ["req_id,latency_ms\n"]
    b_lines = ["req_id,latency_ms\n"]
    joined = []

    for req_id in range(1, 1001):
        in_a = rng.random() < 0.8
        in_b = rng.random() < 0.8
        lat_a = round(rng.uniform(10.0, 50.0), 2)
        lat_b = round(rng.uniform(5.0, 20.0), 2)

        if in_a:
            a_lines.append(f"{req_id},{lat_a}\n")
        if in_b:
            b_lines.append(f"{req_id},{lat_b}\n")
        if in_a and in_b:
            joined.append(lat_a + lat_b)

    return "".join(a_lines), "".join(b_lines), joined


def expected_ci(joined):
    assert joined, "Verifier test case unexpectedly has an empty join"
    cpp_code = r'''
#include <algorithm>
#include <iomanip>
#include <iostream>
#include <random>
#include <vector>

int main() {
    std::vector<double> data = {DATA};
    int N = static_cast<int>(data.size());
    std::mt19937 gen(42);
    std::uniform_int_distribution<> dist(0, N - 1);
    std::vector<double> means(10000);
    for (int i = 0; i < 10000; ++i) {
        double sum = 0.0;
        for (int j = 0; j < N; ++j) {
            sum += data[dist(gen)];
        }
        means[i] = sum / N;
    }
    std::sort(means.begin(), means.end());
    std::cout << std::fixed << std::setprecision(2)
              << "Lower: " << means[250]
              << ", Upper: " << means[9750] << "\n";
}
'''.replace("{DATA}", ",".join(repr(x) for x in joined))

    with tempfile.TemporaryDirectory() as tmpdir:
        src = os.path.join(tmpdir, "golden.cpp")
        binary = os.path.join(tmpdir, "golden")
        with open(src, "w") as f:
            f.write(cpp_code)
        subprocess.run(["g++", "-O2", src, "-o", binary], check=True, timeout=30)
        result = subprocess.run([binary], capture_output=True, text=True,
                                check=True, timeout=30)

    match = OUTPUT_RE.fullmatch(result.stdout.strip())
    assert match
    return float(match.group(1)), float(match.group(2))


def parse_output():
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is missing."
    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()
    match = OUTPUT_RE.fullmatch(content)
    assert match, (f"Output format in {OUTPUT_PATH} is incorrect. Expected "
                   f"'Lower: [val], Upper: [val]', got '{content}'")
    return float(match.group(1)), float(match.group(2))


def run_submission(binary):
    if os.path.lexists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    subprocess.run([binary], cwd="/home/user", check=True, timeout=60)
    return parse_output()


@pytest.fixture(scope="session")
def compiled_submission():
    assert os.path.isfile(CPP_PATH), f"{CPP_PATH} is missing."
    mode = os.stat(CPP_PATH, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), f"{CPP_PATH} must be a regular C++ source file."
    assert os.path.getsize(CPP_PATH) > 0, f"{CPP_PATH} is empty."

    with tempfile.TemporaryDirectory() as tmpdir:
        binary = os.path.join(tmpdir, "bootstrap")
        subprocess.run(["g++", "-O2", "-std=c++17", CPP_PATH, "-o", binary],
                       check=True, timeout=30)
        yield binary


def test_bootstrap_cpp_exists():
    assert os.path.isfile(CPP_PATH), f"{CPP_PATH} is missing."


def test_input_logs_are_original():
    expected_a, expected_b, _ = pristine_inputs()
    with open(A_PATH, "r") as f:
        actual_a = f.read()
    with open(B_PATH, "r") as f:
        actual_b = f.read()
    assert actual_a == expected_a, f"{A_PATH} was modified."
    assert actual_b == expected_b, f"{B_PATH} was modified."


def test_ci_output_format_and_values(compiled_submission):
    _, _, joined = pristine_inputs()
    expected_lower, expected_upper = expected_ci(joined)
    student_lower, student_upper = run_submission(compiled_submission)

    # Preserve the original tolerance for harmless differences in joined-data order.
    assert abs(student_lower - expected_lower) < 0.5, \
        f"Lower bound {student_lower} is too far from expected ~{expected_lower}"
    assert abs(student_upper - expected_upper) < 0.5, \
        f"Upper bound {student_upper} is too far from expected ~{expected_upper}"


def make_hidden_case(rng, common_count):
    ids = list(range(10001, 10001 + common_count))
    a_rows = []
    b_rows = []
    joined_by_id = {}

    for req_id in ids:
        lat_a = round(rng.uniform(10.0, 50.0), 2)
        lat_b = round(rng.uniform(5.0, 20.0), 2)
        a_rows.append((req_id, lat_a))
        b_rows.append((req_id, lat_b))
        joined_by_id[req_id] = lat_a + lat_b

    for offset in range(7):
        a_rows.append((20000 + offset, round(rng.uniform(10.0, 50.0), 2)))
        b_rows.append((30000 + offset, round(rng.uniform(5.0, 20.0), 2)))

    rng.shuffle(a_rows)
    rng.shuffle(b_rows)
    a_text = "req_id,latency_ms\n" + "".join(f"{i},{v}\n" for i, v in a_rows)
    b_text = "req_id,latency_ms\n" + "".join(f"{i},{v}\n" for i, v in b_rows)
    joined = [joined_by_id[i] for i in sorted(joined_by_id)]
    return a_text, b_text, joined


def test_program_processes_unseen_inputs(compiled_submission):
    original_a, original_b, _ = pristine_inputs()
    saved_output = None
    if os.path.isfile(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            saved_output = f.read()

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    try:
        for count in (37, 83):
            a_text, b_text, joined = make_hidden_case(rng, count)
            with open(A_PATH, "w") as f:
                f.write(a_text)
            with open(B_PATH, "w") as f:
                f.write(b_text)

            expected_lower, expected_upper = expected_ci(joined)
            student_lower, student_upper = run_submission(compiled_submission)
            assert abs(student_lower - expected_lower) < 0.5, \
                f"Lower bound {student_lower} is too far from expected ~{expected_lower} on an unseen dataset"
            assert abs(student_upper - expected_upper) < 0.5, \
                f"Upper bound {student_upper} is too far from expected ~{expected_upper} on an unseen dataset"
    finally:
        with open(A_PATH, "w") as f:
            f.write(original_a)
        with open(B_PATH, "w") as f:
            f.write(original_b)
        if saved_output is None:
            if os.path.lexists(OUTPUT_PATH):
                os.unlink(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(saved_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
