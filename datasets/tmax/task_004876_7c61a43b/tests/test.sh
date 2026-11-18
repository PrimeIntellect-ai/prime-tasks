#!/bin/bash
mkdir -p /logs/verifier

rm -f /tmp/submission_was_oracle_copy /tmp/oracle_was_present
if [ -e /app/spatial_transformer ]; then
    touch /tmp/oracle_was_present
    if [ -e /home/user/spatial_transformer_recreated ] && cmp -s /app/spatial_transformer /home/user/spatial_transformer_recreated; then
        touch /tmp/submission_was_oracle_copy
    fi
fi
# The legacy binary must be available while the agent works, but not while its
# submitted implementation is exercised.
rm -f /app/spatial_transformer

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import subprocess
import tempfile

import pytest

AGENT_EXE = "/home/user/spatial_transformer_recreated"
AGENT_SOURCE = "/home/user/recreated_pipeline.cpp"

REFERENCE_SOURCE = r'''
#include <iostream>
#include <sstream>
#include <string>
#include <cmath>
#include <iomanip>

int main() {
    std::string line;
    while (std::getline(std::cin, line)) {
        if (line.empty()) continue;
        std::stringstream ss(line);
        std::string token;
        int id;
        double x, y, z;

        std::getline(ss, token, ','); id = std::stoi(token);
        std::getline(ss, token, ','); x = std::stod(token);
        std::getline(ss, token, ','); y = std::stod(token);
        std::getline(ss, token, ','); z = std::stod(token);

        double f1 = x*x + y*y + z*z;
        double f2 = std::exp(-f1);
        double f3 = x*y;
        double f4 = y*z;
        double f5 = z*x;
        double f6 = x + y + z;

        std::cout << id << ","
                  << std::fixed << std::setprecision(6)
                  << f1 << "," << f2 << "," << f3 << ","
                  << f4 << "," << f5 << "," << f6 << "\n";
    }
    return 0;
}
'''


def run_checked(command, input_data):
    return subprocess.run(
        command,
        input=input_data,
        text=True,
        capture_output=True,
        check=False,
        timeout=20,
    )


@pytest.fixture(scope="session")
def test_artifacts():
    assert os.path.exists("/tmp/oracle_was_present"), \
        "The legacy oracle was missing before verification began."
    assert not os.path.lexists("/app/spatial_transformer"), \
        "The legacy oracle remained accessible during verification."
    assert not os.path.exists("/tmp/submission_was_oracle_copy"), \
        "The submitted executable is byte-identical to the legacy binary."

    work = tempfile.mkdtemp(prefix="spatial_verifier_")
    reference_cpp = os.path.join(work, "reference.cpp")
    reference_exe = os.path.join(work, "reference")
    rebuilt_exe = os.path.join(work, "rebuilt_static")
    sandbox = os.path.join(work, "sandbox")
    os.mkdir(sandbox)

    with open(reference_cpp, "w", encoding="utf-8") as f:
        f.write(REFERENCE_SOURCE)

    ref_compile = subprocess.run(
        ["g++", "-O3", reference_cpp, "-o", reference_exe],
        text=True,
        capture_output=True,
        check=False,
    )
    assert ref_compile.returncode == 0, ref_compile.stderr

    student_compile = subprocess.run(
        ["g++", "-O3", "-static", AGENT_SOURCE, "-o", rebuilt_exe],
        text=True,
        capture_output=True,
        check=False,
    )
    assert student_compile.returncode == 0, \
        "recreated_pipeline.cpp did not compile as a standalone C++ program:\n" + student_compile.stderr

    sandbox_exe = os.path.join(sandbox, "pipeline")
    shutil.copyfile(rebuilt_exe, sandbox_exe)
    os.chmod(sandbox_exe, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)

    yield reference_exe, sandbox
    shutil.rmtree(work, ignore_errors=True)


def test_student_executable_exists():
    assert os.path.exists(AGENT_EXE), f"The expected executable {AGENT_EXE} does not exist."
    assert os.path.isfile(AGENT_EXE), f"{AGENT_EXE} is not a file."
    assert os.access(AGENT_EXE, os.X_OK), f"{AGENT_EXE} is not executable."


def test_student_source_exists():
    assert os.path.exists(AGENT_SOURCE), f"The required source file {AGENT_SOURCE} does not exist."
    assert os.path.isfile(AGENT_SOURCE), f"{AGENT_SOURCE} is not a file."


def test_fuzz_equivalence(test_artifacts):
    reference_exe, sandbox = test_artifacts

    inputs = [
        "0,0.000000,0.000000,0.000000\n",
        "-7,1.000000,-1.000000,2.000000\n",
        "2147483647,-0.000000,0.500000,-0.500000\n",
        "19,10.000000,-10.000000,10.000000\n",
    ]

    random.seed(42)
    for _ in range(100):
        id_val = random.randint(1, 1000)
        x = random.uniform(-10.0, 10.0)
        y = random.uniform(-10.0, 10.0)
        z = random.uniform(-10.0, 10.0)
        inputs.append(f"{id_val},{x:.6f},{y:.6f},{z:.6f}\n")

    input_data = "".join(inputs)
    expected = run_checked([reference_exe], input_data)
    assert expected.returncode == 0, expected.stderr

    # Preserve the original check against the submitted executable.
    submitted = run_checked([AGENT_EXE], input_data)
    assert submitted.returncode == expected.returncode, \
        f"Submitted executable returned {submitted.returncode}; expected {expected.returncode}."
    assert submitted.stdout == expected.stdout, \
        f"Submitted executable output mismatch.\nExpected:\n{expected.stdout}\nGot:\n{submitted.stdout}"

    # Independently compile the required source and run it in an empty chroot.
    # This prevents source code that merely invokes a saved legacy executable.
    rebuilt = run_checked(["chroot", sandbox, "/pipeline"], input_data)
    assert rebuilt.returncode == expected.returncode, \
        f"Executable rebuilt from source returned {rebuilt.returncode}; expected {expected.returncode}."
    assert rebuilt.stdout == expected.stdout, \
        f"Output from recreated_pipeline.cpp mismatch.\nExpected:\n{expected.stdout}\nGot:\n{rebuilt.stdout}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
