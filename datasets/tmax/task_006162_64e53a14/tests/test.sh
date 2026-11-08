#!/bin/bash
set -e
mkdir -p /logs/verifier

cp /home/user/sequences.txt /tmp/original_sequences.txt
trap 'cp /tmp/original_sequences.txt /home/user/sequences.txt' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import subprocess

HOME = "/home/user"
CPP = f"{HOME}/analyze_mutations.cpp"
PIPELINE = f"{HOME}/pipeline.sh"
SAMPLES = f"{HOME}/mcmc_samples.csv"
RESULTS = f"{HOME}/results.txt"
ANALYZE = f"{HOME}/analyze"
SEQUENCES = f"{HOME}/sequences.txt"
ORIGINAL_SEQUENCES = "/tmp/original_sequences.txt"


def clean_outputs():
    for path in (SAMPLES, RESULTS, ANALYZE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_as_user(command):
    proc = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", "-lc", command],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert proc.returncode == 0, (
        f"Command failed with status {proc.returncode}: {command}\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    return proc.stdout


def expected_mle(seq1, seq2):
    assert len(seq1) == len(seq2) and len(seq1) > 0
    k = sum(a != b for a, b in zip(seq1, seq2))
    p = k / len(seq1)
    return -0.75 * math.log(1.0 - (4.0 * p / 3.0)), k


def parse_mle(stdout):
    matches = re.findall(r"(?:^|\n)MLE_d:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?)", stdout)
    assert matches, f"Program output did not contain 'MLE_d: <value>':\n{stdout}"
    value = float(matches[-1])
    assert math.isfinite(value)
    return value


def read_samples():
    assert os.path.isfile(SAMPLES), f"Output file {SAMPLES} is missing."
    with open(SAMPLES, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == 10000, f"Expected exactly 10000 lines in {SAMPLES}, but found {len(lines)}."
    values = []
    for i, line in enumerate(lines):
        try:
            value = float(line.strip())
        except ValueError:
            raise AssertionError(f"Line {i+1} in {SAMPLES} is not a valid float: '{line}'")
        assert math.isfinite(value), f"Line {i+1} in {SAMPLES} is not finite."
        assert value > 0.0, f"MCMC distance on line {i+1} must be positive."
        values.append(value)
    return lines, values


def read_result():
    assert os.path.isfile(RESULTS), f"Results file {RESULTS} is missing."
    with open(RESULTS, "r") as f:
        content = f.read()
    matches = re.findall(r"Mean_Posterior:\s*([0-9]*\.?[0-9]+)", content)
    assert matches, f"Could not find 'Mean_Posterior: <value>' in {RESULTS}. File content:\n{content}"
    return float(matches[-1]), content


def posterior_numeric_mean(n, k):
    # Deterministically derive the posterior expectation from the specified
    # likelihood and exponential prior; no submitted output is trusted.
    step = 0.00002
    count = int(2.0 / step)
    logs = []
    ds = []
    max_log = -math.inf
    for i in range(1, count + 1):
        d = i * step
        p = 0.75 * (1.0 - math.exp(-4.0 * d / 3.0))
        lp = k * math.log(p) + (n - k) * math.log1p(-p) - 10.0 * d
        ds.append(d)
        logs.append(lp)
        max_log = max(max_log, lp)
    weights = [math.exp(x - max_log) for x in logs]
    return sum(d * w for d, w in zip(ds, weights)) / sum(weights)


def validate_chain(stdout, seq1, seq2, require_original_bound=False):
    mle_expected, k = expected_mle(seq1, seq2)
    mle_reported = parse_mle(stdout)
    assert abs(mle_reported - mle_expected) < 2e-6, (
        f"MLE {mle_reported} does not solve the Jukes-Cantor equation; expected {mle_expected}."
    )

    lines, values = read_samples()
    assert abs(values[0] - mle_expected) < 2e-6, (
        f"Iteration 0 must be initialized at the MLE {mle_expected}, got {values[0]}."
    )
    changed = sum(values[i] != values[i-1] for i in range(1, len(values)))
    assert 100 < changed < 9900, "The output does not behave like a Metropolis-Hastings chain."

    reported_mean, content = read_result()
    calculated_mean = sum(values[-5000:]) / 5000.0
    assert abs(reported_mean - calculated_mean) <= 5e-6, (
        f"Mean_Posterior {reported_mean} is not the arithmetic mean of the last 5000 samples "
        f"({calculated_mean}). File content:\n{content}"
    )
    if require_original_bound:
        assert 0.08 < reported_mean < 0.15, (
            f"Mean posterior value {reported_mean} is out of the expected bounds (0.08, 0.15)."
        )
    return lines, values, reported_mean, k


def test_complete_pipeline_and_program_behavior():
    # Preserve the original existence and executable assertions.
    assert os.path.isfile(CPP), f"C++ program {CPP} is missing."
    assert os.path.isfile(PIPELINE), f"Bash script {PIPELINE} is missing."
    st = os.stat(PIPELINE)
    assert bool(st.st_mode & stat.S_IXUSR), f"Bash script {PIPELINE} is not executable."

    with open(ORIGINAL_SEQUENCES) as f:
        seq1, seq2 = [line.strip() for line in f.read().splitlines()]

    # Execute the submitted pipeline as the unprivileged user from a clean state.
    clean_outputs()
    out1 = run_as_user("cd /home/user && ./pipeline.sh")
    assert os.path.isfile(ANALYZE), "pipeline.sh did not create /home/user/analyze."
    mode = os.stat(ANALYZE).st_mode
    assert stat.S_ISREG(mode) and bool(mode & stat.S_IXUSR), "analyze is not an executable file."
    with open(ANALYZE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "pipeline.sh did not produce a compiled executable named analyze."
    lines1, _, mean1, _ = validate_chain(out1, seq1, seq2, require_original_bound=True)

    # The fixed mt19937 seed must make a clean second run reproducible.
    clean_outputs()
    out2 = run_as_user("cd /home/user && ./pipeline.sh")
    lines2, _, mean2, _ = validate_chain(out2, seq1, seq2, require_original_bound=True)
    assert lines2 == lines1, "MCMC samples are not reproducible across clean runs with the fixed seed."
    assert mean2 == mean1, "Mean posterior is not reproducible across clean runs."

    # Exercise the implementation on an additional input and derive all expected
    # quantities independently. This prevents hard-coded files/results from passing.
    dyn1 = "A" * 400
    dyn2 = "C" * 80 + "A" * 320
    with open(SEQUENCES, "w") as f:
        f.write(dyn1 + "\n" + dyn2 + "\n")
    os.chmod(SEQUENCES, 0o666)

    clean_outputs()
    dyn_out = run_as_user("cd /home/user && ./pipeline.sh")
    dyn_lines, dyn_values, _, dyn_k = validate_chain(dyn_out, dyn1, dyn2)
    expected_post_mean = posterior_numeric_mean(len(dyn1), dyn_k)
    sampled_mean = sum(dyn_values[-5000:]) / 5000.0
    assert abs(sampled_mean - expected_post_mean) < 0.02, (
        f"MCMC stationary mean {sampled_mean} is inconsistent with the specified posterior "
        f"(numerical expectation {expected_post_mean})."
    )

    # Independently compile and execute the submitted C++ source. Its deterministic
    # chain must agree with the one produced when the pipeline compiled and ran it.
    direct_exe = "/tmp/submitted_analyze"
    subprocess.run(["g++", "-O3", CPP, "-o", direct_exe], check=True, timeout=120)
    try:
        os.remove(SAMPLES)
    except FileNotFoundError:
        pass
    direct_out = run_as_user("cd /home/user && /tmp/submitted_analyze")
    parse_mle(direct_out)
    direct_lines, _ = read_samples()
    assert direct_lines == dyn_lines, (
        "The C++ source compiled independently does not produce the samples generated by pipeline.sh."
    )

    # Restore the required original input before verification finishes.
    with open(ORIGINAL_SEQUENCES) as src, open(SEQUENCES, "w") as dst:
        dst.write(src.read())
    os.chmod(SEQUENCES, 0o666)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
