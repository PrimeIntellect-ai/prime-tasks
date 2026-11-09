#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import statistics
import subprocess
import tempfile

SIM_DIR = '/home/user/sim'
SOURCE = os.path.join(SIM_DIR, 'equilibrium_sim.cpp')
RESULT = os.path.join(SIM_DIR, 'converged_result.txt')
EXPECTED = '10.976077'


def test_fixed_simulation_end_to_end():
    # Preserve the original result-file assertion.
    assert os.path.isfile(RESULT), f"The file {RESULT} does not exist."
    with open(RESULT, 'r') as f:
        result_content = f.read().strip()
    assert result_content == EXPECTED, (
        f"Expected converged result to be '{EXPECTED}', but got '{result_content}'."
    )
    assert re.fullmatch(r'-?\d+\.\d{6}', result_content), (
        'converged_result.txt must contain exactly one value with 6 decimal places.'
    )

    # Preserve the original source checks.
    assert os.path.isfile(SOURCE), f"The file {SOURCE} does not exist."
    with open(SOURCE, 'r') as f:
        source = f.read()
    assert 'std::execution::par' not in source, (
        "The source file still contains 'std::execution::par', which causes non-deterministic reduction."
    )
    assert 'std::execution::par_unseq' not in source, (
        "The source file contains 'std::execution::par_unseq', which causes non-deterministic reduction."
    )

    # Ensure the original model and Newton-Raphson update are still present.
    compact = re.sub(r'\s+', '', source)
    assert 'intN=5000000;' in compact
    assert 'w[i]=1.0+(i%100)/100.0;' in compact
    assert 't[i]=0.01+(i%50)/500.0;' in compact
    assert 'doublex=1.0;' in compact
    assert 'doubleC=2500000.0;' in compact
    assert 'for(intiter=0;iter<15;++iter)' in compact
    assert 'wi*std::exp(-x*ti)' in compact
    assert '-wi*ti*std::exp(-x*ti)' in compact
    assert 'x=x-f_val/f_prime;' in compact
    assert re.search(r'f_val\s*=.*?-\s*C\s*;', source, re.DOTALL)
    assert re.search(r'std::cout\s*<<\s*std::fixed\s*<<\s*std::setprecision\s*\(\s*10\s*\)\s*<<\s*x', source)
    assert EXPECTED not in source, 'The expected answer must not be hardcoded in the C++ source.'

    # Compile the submitted source rather than trusting a prebuilt executable.
    with tempfile.TemporaryDirectory(prefix='equilibrium_verify_') as td:
        executable = os.path.join(td, 'equilibrium_sim')
        compile_result = subprocess.run(
            ['g++', '-std=c++17', '-O2', '-pthread', SOURCE, '-o', executable, '-ltbb'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
        assert compile_result.returncode == 0, (
            'The fixed C++ source did not compile:\n' + compile_result.stderr
        )
        assert os.path.isfile(executable) and os.access(executable, os.X_OK)

        outputs = []
        values = []
        for run_number in range(50):
            completed = subprocess.run(
                [executable],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=120,
            )
            assert completed.returncode == 0, (
                f'Simulation run {run_number + 1} failed:\n{completed.stderr}'
            )
            output = completed.stdout.strip()
            assert re.fullmatch(r'-?\d+\.\d{10}', output), (
                f'Run {run_number + 1} did not emit exactly one fixed-point value '
                f'with 10 decimal places: {output!r}'
            )
            value = float(output)
            assert math.isfinite(value)
            outputs.append(output)
            values.append(value)

    assert len(set(outputs)) == 1, 'The 50 simulation outputs are not exactly reproducible.'
    assert statistics.pvariance(values) == 0.0, 'The variance of the 50 runs is not exactly 0.0.'
    assert format(values[0], '.6f') == result_content, (
        'converged_result.txt does not match the reproducible value produced by the simulation.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
