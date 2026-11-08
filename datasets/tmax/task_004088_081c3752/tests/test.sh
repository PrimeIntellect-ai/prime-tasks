#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess
import tempfile


def test_files_exist():
    """Check if all required files were created."""
    assert os.path.exists('/home/user/mc_ruin.cpp'), "/home/user/mc_ruin.cpp does not exist."
    assert os.path.exists('/home/user/run_convergence.sh'), "/home/user/run_convergence.sh does not exist."
    assert os.path.exists('/home/user/convergence_report.md'), "/home/user/convergence_report.md does not exist."


def test_convergence_script_compiles_and_runs_required_cases():
    """Exercise the orchestration script with an instrumented C++ source."""
    source_path = '/home/user/mc_ruin.cpp'
    script_path = '/home/user/run_convergence.sh'
    executable_path = '/home/user/mc_ruin'
    report_path = '/home/user/convergence_report.md'
    probe_log = '/tmp/convergence_probe.log'

    with open(source_path, 'rb') as f:
        original_source = f.read()

    probe_source = r'''#include <fstream>
#include <iostream>
#include <string>

int main(int argc, char** argv) {
    std::ofstream log("/tmp/convergence_probe.log", std::ios::app);
    log << argc;
    for (int i = 1; i < argc; ++i) log << " " << argv[i];
    log << "\n";
    if (argc != 3) return 2;
    std::string n = argv[1];
    if (n == "1000") std::cout << "0.101001";
    else if (n == "10000") std::cout << "0.202002";
    else if (n == "100000") std::cout << "0.303003";
    else std::cout << "0.909009";
    return 0;
}
'''

    probe_result = None
    probe_lines = []
    report_lines = []
    try:
        with open(source_path, 'w') as f:
            f.write(probe_source)
        for path in (probe_log, executable_path, report_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        probe_result = subprocess.run(
            ['/bin/bash', script_path], cwd='/home/user',
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            timeout=60
        )
        if os.path.exists(probe_log):
            with open(probe_log) as f:
                probe_lines = [line.strip() for line in f if line.strip()]
        if os.path.exists(report_path):
            with open(report_path) as f:
                report_lines = [line.strip() for line in f if line.strip()]
    finally:
        with open(source_path, 'wb') as f:
            f.write(original_source)
        try:
            os.remove(probe_log)
        except FileNotFoundError:
            pass
        # Regenerate the required final executable and report from the real source.
        subprocess.run(
            ['/bin/bash', script_path], cwd='/home/user',
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            timeout=120
        )

    assert probe_result is not None and probe_result.returncode == 0, (
        f"run_convergence.sh failed during instrumented execution: "
        f"{probe_result.stderr if probe_result else 'not run'}"
    )
    assert probe_lines == [
        '3 1000 42',
        '3 10000 42',
        '3 100000 42',
    ], f"The script did not execute the compiled simulator with the required arguments: {probe_lines}"
    assert report_lines == [
        'N=1000, P=0.101001',
        'N=10000, P=0.202002',
        'N=100000, P=0.303003',
    ], f"The script did not construct the report from simulator output: {report_lines}"


def test_executable_exists():
    """Check if the C++ program was compiled into the expected executable."""
    assert os.path.exists('/home/user/mc_ruin'), "/home/user/mc_ruin executable does not exist."
    assert os.access('/home/user/mc_ruin', os.X_OK), "/home/user/mc_ruin is not executable."


def test_simulator_behavior_against_derived_reference():
    """Compile and exercise the submitted simulator on independently derived cases."""
    reference_source = r'''#include <cstdint>
#include <iostream>
#include <random>
#include <string>

int main(int argc, char** argv) {
    if (argc != 3) return 2;
    unsigned long long n = std::stoull(argv[1]);
    unsigned int seed = static_cast<unsigned int>(std::stoul(argv[2]));
    std::mt19937 gen(seed);
    unsigned long long ruined = 0;
    for (unsigned long long i = 0; i < n; ++i) {
        int capital = 10;
        for (int step = 0; step < 100 && capital > 0; ++step) {
            if (gen() % 100 < 45) ++capital;
            else --capital;
        }
        if (capital == 0) ++ruined;
    }
    std::cout << static_cast<double>(ruined) / static_cast<double>(n);
    return 0;
}
'''
    number_pattern = re.compile(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$')

    with tempfile.TemporaryDirectory() as td:
        ref_cpp = os.path.join(td, 'reference.cpp')
        ref_bin = os.path.join(td, 'reference')
        submitted_bin = os.path.join(td, 'submitted')
        with open(ref_cpp, 'w') as f:
            f.write(reference_source)

        subprocess.run(['g++', '-O3', ref_cpp, '-o', ref_bin], check=True, timeout=60)
        subprocess.run(
            ['g++', '-O3', '/home/user/mc_ruin.cpp', '-o', submitted_bin],
            check=True, timeout=60
        )

        cases = [(1, 0), (17, 7), (257, 123456), (4096, 98765)]
        for executable in (submitted_bin, '/home/user/mc_ruin'):
            for n, seed in cases:
                expected_run = subprocess.run(
                    [ref_bin, str(n), str(seed)], check=True,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                    timeout=30
                )
                actual_run = subprocess.run(
                    [executable, str(n), str(seed)],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                    timeout=30
                )
                assert actual_run.returncode == 0, (
                    f"Simulator failed for N={n}, seed={seed}: {actual_run.stderr}"
                )
                output = actual_run.stdout.strip()
                assert number_pattern.fullmatch(output), (
                    f"Simulator must print only one floating-point number; got {actual_run.stdout!r}"
                )
                assert actual_run.stderr == '', f"Simulator printed unexpected stderr: {actual_run.stderr!r}"
                actual = float(output)
                expected = float(expected_run.stdout.strip())
                assert math.isfinite(actual)
                assert abs(actual - expected) < 1e-12, (
                    f"Wrong result for N={n}, seed={seed}: expected {expected}, got {actual}"
                )

            for bad_args in ([], ['10', '42', 'extra']):
                bad_run = subprocess.run(
                    [executable] + bad_args,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                    timeout=10
                )
                assert bad_run.returncode != 0, "Simulator must require exactly two command-line arguments."


def test_convergence_report_contents():
    """Check the contents of the convergence report for correct N and probabilities."""
    report_path = '/home/user/convergence_report.md'
    assert os.path.exists(report_path), f"{report_path} does not exist."

    with open(report_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {report_path}, found {len(lines)}."

    expected_results = {
        1000: 0.551,
        10000: 0.5364,
        100000: 0.53587
    }

    parsed_results = {}
    pattern = re.compile(r'^N=(\d+),\s*P=([0-9.]+)$')

    for line in lines:
        match = pattern.match(line)
        assert match, f"Line '{line}' does not match the expected format 'N=<N>, P=<probability>'."
        n_val = int(match.group(1))
        p_val = float(match.group(2))
        parsed_results[n_val] = p_val

    for expected_n, expected_p in expected_results.items():
        assert expected_n in parsed_results, f"Missing result for N={expected_n} in the report."
        actual_p = parsed_results[expected_n]
        assert abs(actual_p - expected_p) < 1e-5, f"For N={expected_n}, expected P approx {expected_p}, got {actual_p}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
