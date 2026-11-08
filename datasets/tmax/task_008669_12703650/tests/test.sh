#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess


def test_pipeline_script():
    script_path = '/home/user/pipeline.sh'
    assert os.path.exists(script_path), f"{script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a regular file."
    with open(script_path, 'r') as f:
        content = f.read().lower()
    assert 'python' not in content, "Python usage is forbidden in pipeline.sh"
    assert 'perl' not in content, "Perl usage is forbidden in pipeline.sh"
    assert 'rscript' not in content, "R usage is forbidden in pipeline.sh"
    assert 'awk' in content, "Expected awk usage in pipeline.sh"

    # Remove any pre-existing result and execute the submitted artifact.
    result_file = '/home/user/result.txt'
    if os.path.exists(result_file):
        os.remove(result_file)
    try:
        proc = subprocess.run(
            ['/bin/bash', script_path],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        assert False, "pipeline.sh did not finish within 180 seconds"
    assert proc.returncode == 0, (
        f"pipeline.sh exited with status {proc.returncode}. stderr: {proc.stderr}"
    )


def test_result_file():
    result_file = '/home/user/result.txt'
    assert os.path.exists(result_file), f"{result_file} does not exist."

    # Compute exact trapezoidal distances from the generated files.
    distances = []
    for i in range(1, 51):
        file_path = f'/home/user/sim_data/sim_{i}.csv'
        assert os.path.exists(file_path), f"{file_path} missing."
        with open(file_path, 'r') as f:
            lines = f.readlines()[1:]
            t = []
            v = []
            for line in lines:
                parts = line.strip().split(',')
                if len(parts) == 2:
                    t.append(float(parts[0]))
                    v.append(float(parts[1]))

        dist = 0.0
        for j in range(1, len(t)):
            dist += (t[j] - t[j-1]) * (v[j] + v[j-1]) / 2.0
        distances.append(dist)

    original_mean = sum(distances) / len(distances)

    with open(result_file, 'r') as f:
        content = f.read()

    mean_match = re.search(r"Mean:\s*([0-9\.\-]+)", content)
    ci_match = re.search(r"95%\s*CI:\s*\[([0-9\.\-]+),\s*([0-9\.\-]+)\]", content)

    assert mean_match is not None, "Mean format not found in result.txt. Expected 'Mean: <value>'"
    assert ci_match is not None, "95% CI format not found in result.txt. Expected '95% CI: [<lower>, <upper>]'"

    agent_mean = float(mean_match.group(1))
    agent_lower = float(ci_match.group(1))
    agent_upper = float(ci_match.group(2))

    assert abs(agent_mean - original_mean) < 0.01, (
        f"Expected mean ~{original_mean:.3f}, got {agent_mean}"
    )

    # Independently reproduce the required 10,000-sample bootstrap with gawk's
    # RNG seeded to 12345. The order is sim_1 through sim_50, matching the input.
    awk_program = r'''
        { d[NR] = $1 }
        END {
            srand(12345)
            for (b = 1; b <= 10000; b++) {
                total = 0
                for (j = 1; j <= NR; j++)
                    total += d[int(rand() * NR) + 1]
                printf "%.15g\n", total / NR
            }
        }
    '''
    bootstrap = subprocess.run(
        ['gawk', awk_program],
        input=''.join(f'{d:.17g}\n' for d in distances),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    means = sorted(float(x) for x in bootstrap.stdout.splitlines())
    assert len(means) == 10000, "Reference bootstrap did not produce 10,000 means"

    # Nearest-rank percentiles: sorted observations 250 and 9750 (1-based).
    expected_lower = means[249]
    expected_upper = means[9749]

    # Allow small differences from common percentile-index conventions and
    # intermediate awk formatting while still requiring the seeded bootstrap CI.
    assert abs(agent_lower - expected_lower) < 0.01, (
        f"Expected seeded-bootstrap lower bound ~{expected_lower:.3f}, got {agent_lower}"
    )
    assert abs(agent_upper - expected_upper) < 0.01, (
        f"Expected seeded-bootstrap upper bound ~{expected_upper:.3f}, got {agent_upper}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
