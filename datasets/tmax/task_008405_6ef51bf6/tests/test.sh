#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

PIPELINE = "/home/user/pipeline"
SOURCE = os.path.join(PIPELINE, "mc_det.cpp")
CI_FILE = os.path.join(PIPELINE, "ci.txt")

REF_CPP = r'''#include <iostream>
#include <cstdlib>
#include <iomanip>
#include <string>
using namespace std;

int main(int argc, char** argv) {
    if (argc != 10) return 1;
    double m[9];
    for (int i = 0; i < 9; ++i) m[i] = stod(argv[i + 1]);

    srand(42);
    for (int iter = 0; iter < 1000; ++iter) {
        double m_pert[9];
        for (int i = 0; i < 9; ++i) {
            double noise = (rand() % 2001 - 1000) * 1e-9;
            m_pert[i] = m[i] + noise;
        }
        double det = m_pert[0] * (m_pert[4] * m_pert[8] - m_pert[5] * m_pert[7])
                   - m_pert[1] * (m_pert[3] * m_pert[8] - m_pert[5] * m_pert[6])
                   + m_pert[2] * (m_pert[3] * m_pert[7] - m_pert[4] * m_pert[6]);
        cout << fixed << setprecision(10) << det << "\n";
    }
    return 0;
}
'''

@pytest.fixture(scope="session")
def programs():
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing"

    ref_src = "/tmp/ref_solve.cpp"
    ref_exe = "/tmp/ref_solve"
    submitted_exe = "/tmp/submitted_mc_det"
    with open(ref_src, "w") as f:
        f.write(REF_CPP)

    ref_compile = subprocess.run(
        ["g++", "-std=c++17", "-O2", ref_src, "-o", ref_exe],
        capture_output=True, text=True
    )
    assert ref_compile.returncode == 0, f"Failed to compile reference code:\n{ref_compile.stderr}"

    submitted_compile = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", submitted_exe],
        capture_output=True, text=True
    )
    assert submitted_compile.returncode == 0, f"mc_det.cpp does not compile:\n{submitted_compile.stderr}"
    return ref_exe, submitted_exe

@pytest.fixture(scope="session")
def cases():
    rng = random.SystemRandom()
    result = [["1.0", "2.0", "3.0", "4.0", "5.0", "6.0", "7.0", "8.0", "9.000001"]]

    for _ in range(3):
        row1 = [rng.uniform(-8.0, 8.0) for _ in range(3)]
        row2 = [rng.uniform(-8.0, 8.0) for _ in range(3)]
        row3 = [row1[i] + row2[i] for i in range(3)]
        row3[rng.randrange(3)] += rng.uniform(2e-7, 2e-6)
        result.append([format(x, ".17g") for x in row1 + row2 + row3])
    return result

def run_program(path, args):
    return subprocess.run([path] + args, capture_output=True, text=True, timeout=10)

def assert_matches_reference(candidate, reference, cases):
    for args in cases:
        expected = run_program(reference, args)
        actual = run_program(candidate, args)
        assert expected.returncode == 0
        assert actual.returncode == 0, f"{candidate} failed for valid matrix arguments: {actual.stderr}"
        assert len(actual.stdout.splitlines()) == 1000, f"{candidate} did not print exactly 1000 determinant values"
        assert actual.stdout == expected.stdout, f"{candidate} does not implement the required double-precision simulation"

    assert run_program(candidate, []).returncode != 0, f"{candidate} must reject calls without exactly 9 matrix elements"
    assert run_program(candidate, ["1"] * 10).returncode != 0, f"{candidate} must reject calls with more than 9 matrix elements"

def test_ci_txt_exists():
    assert os.path.isfile(CI_FILE), f"{CI_FILE} is missing"

def test_mc_det_cpp_fixed(programs, cases):
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "double" in content, "mc_det.cpp does not seem to be updated to use double precision."

    reference, submitted_exe = programs
    assert_matches_reference(submitted_exe, reference, cases)

def test_compiled_program_exists_and_works(programs, cases):
    reference, _ = programs
    candidates = []
    for root, _, files in os.walk(PIPELINE):
        for name in files:
            path = os.path.join(root, name)
            try:
                if not os.path.isfile(path) or not os.access(path, os.X_OK):
                    continue
                with open(path, "rb") as f:
                    if f.read(4) == b"\x7fELF":
                        candidates.append(path)
            except OSError:
                pass

    assert candidates, "No compiled ELF executable was left in /home/user/pipeline"
    failures = []
    for candidate in candidates:
        try:
            assert_matches_reference(candidate, reference, cases)
            return
        except (AssertionError, subprocess.SubprocessError, OSError) as exc:
            failures.append(f"{candidate}: {exc}")
    pytest.fail("No compiled executable implements mc_det.cpp correctly:\n" + "\n".join(failures))

def test_ci_txt_content(programs):
    reference, _ = programs
    args = [reference, "1.0", "2.0", "3.0", "4.0", "5.0", "6.0", "7.0", "8.0", "9.000001"]
    run_proc = subprocess.run(args, capture_output=True, text=True, timeout=10)
    assert run_proc.returncode == 0, f"Failed to run reference C++ code:\n{run_proc.stderr}"

    outputs = run_proc.stdout.strip().split("\n")
    assert len(outputs) == 1000, "Reference program did not output exactly 1000 lines."
    outputs.sort(key=float)
    expected_ci = f"{outputs[24]},{outputs[974]}"

    with open(CI_FILE, "r") as f:
        actual_ci = f.read().strip()
    assert actual_ci == expected_ci, f"The contents of ci.txt ({actual_ci}) do not match the expected confidence interval ({expected_ci}). Check the percentiles and sorting."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
