#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess
import tempfile

import pytest

DETECTOR = "/home/user/detector.sh"
THRESHOLD = "/home/user/threshold.txt"
MC_SCRIPT = "/home/user/mc_sim.sh"
HISTOGRAM = "/home/user/histogram.txt"


def read_threshold(path=THRESHOLD):
    with open(path, "r") as f:
        content = f.read().strip()
    assert content.isdigit(), f"Threshold file must contain a single integer, found: {content}"
    return int(content)


def theoretical_threshold():
    # Exact distribution for max(X0,X1,X2)-min(X0,X1,X2), where each
    # Xi is an independent Binomial(100, 1/2) GC count.
    probs = [math.comb(100, k) / (2 ** 100) for k in range(101)]
    dist = [0.0] * 101
    for x, px in enumerate(probs):
        for y, py in enumerate(probs):
            pxy = px * py
            for z, pz in enumerate(probs):
                dist[max(x, y, z) - min(x, y, z)] += pxy * pz
    cumulative = 0.0
    for metric, probability in enumerate(dist):
        cumulative += probability
        if cumulative >= 0.99:
            return metric
    raise AssertionError("Could not derive null-model threshold")


def test_detector_script_exists_and_executable():
    detector_path = "/home/user/detector.sh"
    assert os.path.exists(detector_path), f"Detector script {detector_path} does not exist."
    assert os.access(detector_path, os.X_OK), f"Detector script {detector_path} is not executable."


def test_threshold_file():
    threshold_path = "/home/user/threshold.txt"
    assert os.path.exists(threshold_path), f"Threshold file {threshold_path} does not exist."
    value = read_threshold(threshold_path)
    expected = theoretical_threshold()
    # A 1000-sample empirical 99th percentile can vary slightly around the
    # exact null-model percentile, but should not be arbitrary.
    assert abs(value - expected) <= 3, (
        f"Threshold {value} is inconsistent with the null model; "
        f"the exact 99th percentile is {expected}"
    )


def test_mc_script_and_histogram():
    assert os.path.isfile(MC_SCRIPT), f"Monte Carlo script {MC_SCRIPT} does not exist."
    assert os.access(MC_SCRIPT, os.X_OK), f"Monte Carlo script {MC_SCRIPT} is not executable."
    assert os.path.isfile(HISTOGRAM), f"Histogram {HISTOGRAM} does not exist."
    assert os.path.getsize(HISTOGRAM) > 0, "Histogram is empty."

    with open(MC_SCRIPT, "r", errors="replace") as f:
        script = f.read()
    first_line = script.splitlines()[0] if script.splitlines() else ""
    assert re.match(r"^#!.*\bbash\b", first_line), "mc_sim.sh must be a Bash script."
    assert not re.search(r"(^|[;&|]\s*|\b)(python[0-9]*|perl|ruby|node|gcc|cc)\b", script), (
        "mc_sim.sh must be implemented entirely in Bash and standard shell utilities."
    )
    assert "1000" in script, "mc_sim.sh does not appear to implement the required N=1000 simulation."
    uses_xargs_parallel = re.search(r"\bxargs\b[^\n]*(?:-P\s*[1-9]|--max-procs(?:=|\s+)[1-9])", script)
    uses_background_jobs = re.search(r"&\s*(?:$|\n|;)", script) and re.search(r"\bwait\b", script)
    assert uses_xargs_parallel or uses_background_jobs or re.search(r"\bcoproc\b", script), (
        "mc_sim.sh must use Bash parallelization."
    )

    # Execute the submitted simulation while preserving the agent's original
    # outputs for the detector tests below.
    with tempfile.TemporaryDirectory(prefix="mc_verify_") as td:
        saved_threshold = os.path.join(td, "threshold.txt")
        saved_histogram = os.path.join(td, "histogram.txt")
        os.replace(THRESHOLD, saved_threshold)
        os.replace(HISTOGRAM, saved_histogram)
        try:
            result = subprocess.run(
                [MC_SCRIPT], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                text=True, timeout=180
            )
            assert result.returncode == 0, f"mc_sim.sh failed: {result.stderr[-1000:]}"
            assert os.path.isfile(THRESHOLD), "mc_sim.sh did not recreate threshold.txt."
            generated = read_threshold()
            expected = theoretical_threshold()
            assert abs(generated - expected) <= 3, (
                f"mc_sim.sh generated implausible threshold {generated}; expected near {expected}"
            )
            assert os.path.isfile(HISTOGRAM), "mc_sim.sh did not recreate histogram.txt."
            with open(HISTOGRAM, "r", errors="replace") as f:
                histogram = f.read()
            nonempty_lines = [line for line in histogram.splitlines() if line.strip()]
            assert len(nonempty_lines) >= 2, "Generated histogram does not contain multiple bins."
            assert any(ch.isdigit() for ch in histogram), "Generated histogram contains no numeric labels or counts."
        finally:
            if os.path.exists(THRESHOLD):
                os.unlink(THRESHOLD)
            if os.path.exists(HISTOGRAM):
                os.unlink(HISTOGRAM)
            os.replace(saved_threshold, THRESHOLD)
            os.replace(saved_histogram, HISTOGRAM)


def make_sequence(counts, rng):
    phase_bases = []
    for gc_count in counts:
        values = [rng.choice("GC") for _ in range(gc_count)]
        values += [rng.choice("AT") for _ in range(100 - gc_count)]
        rng.shuffle(values)
        phase_bases.append(values)
    sequence = []
    for i in range(100):
        sequence.extend([phase_bases[0][i], phase_bases[1][i], phase_bases[2][i]])
    return "".join(sequence)


def test_detector_on_hidden_metric_cases():
    threshold = read_threshold()
    assert 0 <= threshold <= 100
    rng = random.SystemRandom()

    metrics = {0, 1, 5, 10, 20, 40, 70, 100}
    for delta in range(-3, 4):
        metrics.add(max(0, min(100, threshold + delta)))

    cases = []
    for metric in sorted(metrics):
        if metric <= 50:
            counts = [50, 50, 50 + metric]
        else:
            counts = [0, 0, metric]
        rng.shuffle(counts)
        cases.append(tuple(counts))
    for _ in range(25):
        cases.append(tuple(rng.randrange(101) for _ in range(3)))

    with tempfile.TemporaryDirectory(prefix="unlabeled_sequences_") as td:
        for index, counts in enumerate(cases):
            path = os.path.join(td, f"sample_{rng.randrange(1 << 60):x}_{index}.dat")
            with open(path, "w") as f:
                f.write(make_sequence(counts, rng) + "\n")
            metric = max(counts) - min(counts)
            expected_status = 1 if metric >= threshold else 0
            result = subprocess.run(
                [DETECTOR, path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=10
            )
            assert result.returncode == expected_status, (
                f"Detector returned {result.returncode} for hidden sequence with phase GC "
                f"counts {counts} (metric {metric}, threshold {threshold}); "
                f"expected {expected_status}"
            )


def test_adversarial_corpus():
    detector_path = "/home/user/detector.sh"
    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_rejected = 0
    evil_bypassed = []
    for fpath in evil_files:
        result = subprocess.run([detector_path, fpath], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode == 1:
            evil_rejected += 1
        else:
            evil_bypassed.append(os.path.basename(fpath))

    clean_preserved = 0
    clean_modified = []
    for fpath in clean_files:
        result = subprocess.run([detector_path, fpath], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            clean_preserved += 1
        else:
            clean_modified.append(os.path.basename(fpath))

    evil_success_rate = evil_rejected / len(evil_files) if evil_files else 0
    clean_success_rate = clean_preserved / len(clean_files) if clean_files else 0

    errors = []
    if evil_success_rate < 0.95:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed (expected <= 5%). Examples: {evil_bypassed[:5]}")
    if clean_success_rate < 0.95:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected (expected <= 5%). Examples: {clean_modified[:5]}")

    assert not errors, "\n".join(errors)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
