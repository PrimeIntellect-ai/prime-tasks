#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

SCRIPT = "/home/user/bootstrap.sh"
MEANS = "/home/user/means.txt"
CI = "/home/user/ci.txt"


def get_expected_means():
    cmd = r"""awk -F, 'NR>1 {print $4}' /home/user/data.csv | awk '
BEGIN { srand(42) }
{ val[NR] = $1 }
END {
  N = NR
  for (iter=1; iter<=1000; iter++) {
    sum = 0
    for (i=1; i<=N; i++) {
        idx = int(rand() * N) + 1
        sum += val[idx]
    }
    printf "%.6f\n", sum / N
  }
}' | sort -n"""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=True)
    return result.stdout.strip().split('\n')


def test_bootstrap_script_exists_uses_required_awk_and_runs():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist or is not a regular file."

    with open(SCRIPT, "r") as f:
        source = f.read()

    compact = re.sub(r"\s+", "", source)
    assert re.search(r"\bawk\b", source), "bootstrap.sh must use awk."
    assert len(re.findall(r"\bsrand\s*\(", source)) == 1, \
        "awk srand must be initialized exactly once."
    assert re.search(r"BEGIN\{[^}]*srand\(42\)[^}]*\}", compact), \
        "bootstrap.sh must call srand(42) in an awk BEGIN block."
    assert "int(rand()*N)+1" in compact, \
        "bootstrap.sh must select indices with int(rand() * N) + 1."

    for path in (MEANS, CI):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["bash", SCRIPT],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, \
        f"bootstrap.sh failed with exit code {result.returncode}:\n{result.stderr}"
    assert os.path.isfile(MEANS), f"Running {SCRIPT} did not generate {MEANS}."
    assert os.path.isfile(CI), f"Running {SCRIPT} did not generate {CI}."


def test_means_txt():
    """Test that means.txt contains the correct reproducible output."""
    assert os.path.exists(MEANS), f"{MEANS} does not exist."

    with open(MEANS, "r") as f:
        actual_means = f.read().strip().split('\n')

    expected_means = get_expected_means()

    assert len(actual_means) == 1000, f"{MEANS} should contain exactly 1000 lines."
    assert actual_means == expected_means, \
        f"The contents of {MEANS} do not match the expected reproducible output from awk."


def test_ci_txt():
    """Test that ci.txt contains the correctly formatted 95% confidence interval."""
    assert os.path.exists(CI), f"{CI} does not exist."

    with open(CI, "r") as f:
        actual_ci = f.read().strip()

    expected_means = get_expected_means()
    lower = float(expected_means[24])
    upper = float(expected_means[974])
    expected_ci = f"{lower:.4f},{upper:.4f}"

    assert actual_ci == expected_ci, \
        f"The contents of {CI} do not match the expected output. Expected '{expected_ci}', got '{actual_ci}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
