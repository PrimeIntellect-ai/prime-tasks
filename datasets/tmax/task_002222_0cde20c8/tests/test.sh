#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import subprocess
import tempfile

import cv2
import h5py
import numpy as np


def run_detector(executable, model, fasta, expected):
    result = subprocess.run(
        [executable, model, fasta],
        capture_output=True,
        text=True,
        timeout=240,
    )
    expected_code = 0 if expected == "ACCEPT" else 1
    assert result.returncode == expected_code, (
        f"Detector returned {result.returncode} for {fasta} with {model}; "
        f"expected {expected_code}. stdout={result.stdout!r} stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == expected, (
        f"Detector output for {fasta} must be exactly {expected!r}, "
        f"got {result.stdout!r}"
    )


def compile_submission():
    sources = sorted(
        p for p in glob.glob("/home/user/**/*.c", recursive=True)
        if os.path.isfile(p)
    )
    assert sources, "No C source file was found under /home/user"

    executable = "/tmp/submission_detector"
    result = subprocess.run(
        ["h5cc", "-std=c11", "-O2", *sources, "-lm", "-o", executable],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        "The submitted C program could not be compiled independently with HDF5 "
        f"and libm. stdout={result.stdout}\nstderr={result.stderr}"
    )
    assert os.path.isfile(executable) and os.access(executable, os.X_OK)
    return executable


def video_threshold():
    capture = cv2.VideoCapture("/app/calibration_timelapse.mp4")
    frames = []
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        frames.append(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY))
    capture.release()
    assert len(frames) >= 10, "Calibration video has fewer than ten decodable frames"
    threshold = float(np.mean(np.stack(frames[-10:]))) / 255.0
    assert 0.0 < threshold < 1.0
    return threshold


def empirical_matrix(sequence):
    index = {"A": 0, "C": 1, "G": 2, "T": 3}
    counts = np.zeros((4, 4), dtype=np.float64)
    for a, b in zip(sequence, sequence[1:]):
        counts[index[a], index[b]] += 1.0
    totals = counts.sum(axis=1)
    assert np.all(totals > 0)
    return counts / totals[:, None]


def distance(p, q):
    return -math.log(float(np.sqrt(p * q).sum()) / 4.0)


def reference_at_distance(p, target):
    epsilon = 1e-6
    far = np.full((4, 4), epsilon, dtype=np.float64)
    for row in range(4):
        far[row, int(np.argmin(p[row]))] = 1.0 - 3.0 * epsilon

    assert distance(p, far) > target
    lo, hi = 0.0, 1.0
    for _ in range(80):
        mid = (lo + hi) / 2.0
        candidate = (1.0 - mid) * p + mid * far
        if distance(p, candidate) < target:
            lo = mid
        else:
            hi = mid
    return (1.0 - hi) * p + hi * far


def make_hidden_cases(directory, threshold):
    rng = random.Random(791923)
    transition = [
        [0.10, 0.20, 0.30, 0.40],
        [0.40, 0.30, 0.20, 0.10],
        [0.25, 0.25, 0.25, 0.25],
        [0.30, 0.30, 0.20, 0.20],
    ]
    bases = "ACGT"
    sequence = ["A"]
    for _ in range(3999):
        row = transition[bases.index(sequence[-1])]
        value = rng.random()
        cumulative = 0.0
        for base, probability in zip(bases, row):
            cumulative += probability
            if value <= cumulative:
                sequence.append(base)
                break
    sequence = "".join(sequence)

    fasta = os.path.join(directory, "unseen_sample.fasta")
    with open(fasta, "w") as handle:
        # Identical records make every sequence-level bootstrap resample have the
        # same empirical matrix, so the expected confidence bound is exact.
        for i in range(16):
            handle.write(f">hidden_{i}\n{sequence}\n")

    empirical = empirical_matrix(sequence)
    low_reference = reference_at_distance(empirical, threshold * 0.50)
    high_reference = reference_at_distance(empirical, threshold * 1.50)

    low_model = os.path.join(directory, "near_reference.h5")
    high_model = os.path.join(directory, "far_reference.h5")
    with h5py.File(low_model, "w") as model:
        model.create_dataset("/dinucleotide_probs", data=low_reference)
    with h5py.File(high_model, "w") as model:
        model.create_dataset("/dinucleotide_probs", data=high_reference)

    assert distance(empirical, low_reference) < threshold
    assert distance(empirical, high_reference) > threshold
    return fasta, low_model, high_model


def test_run_eval_script_and_check_results():
    script_path = "/home/user/run_eval.sh"
    assert os.path.isfile(script_path), f"Missing evaluation script at {script_path}"

    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"run_eval.sh failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    results_path = "/home/user/eval_results.txt"
    assert os.path.isfile(results_path), f"Missing evaluation results at {results_path}"
    with open(results_path, "r") as handle:
        lines = [line.strip() for line in handle.readlines() if line.strip()]

    results_dict = {}
    for line in lines:
        parts = line.split(" ", 1)
        if len(parts) == 2:
            status, filepath = parts
            results_dict[filepath] = status

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = glob.glob(os.path.join(clean_dir, "*.fasta"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.fasta"))
    assert clean_files, f"No clean files found in {clean_dir}"
    assert evil_files, f"No evil files found in {evil_dir}"

    clean_modified = [f for f in clean_files if results_dict.get(f) != "ACCEPT"]
    evil_bypassed = [f for f in evil_files if results_dict.get(f) != "REJECT"]
    error_msgs = []
    if evil_bypassed:
        error_msgs.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
            + ", ".join(os.path.basename(f) for f in evil_bypassed)
        )
    if clean_modified:
        error_msgs.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified: "
            + ", ".join(os.path.basename(f) for f in clean_modified)
        )
    assert not error_msgs, " | ".join(error_msgs)

    # Compile and invoke the C implementation ourselves instead of trusting the
    # statuses reported by run_eval.sh.
    executable = compile_submission()
    for fasta in clean_files:
        run_detector(executable, "/app/reference_model.h5", fasta, "ACCEPT")
    for fasta in evil_files:
        run_detector(executable, "/app/reference_model.h5", fasta, "REJECT")

    # Exercise an unseen FASTA against two unseen HDF5 models. The expected
    # answers are derived from the decoded calibration video and computed
    # Bhattacharyya distances, ensuring that argv[1], argv[2], and T are used.
    threshold = video_threshold()
    with tempfile.TemporaryDirectory(prefix="detector_hidden_") as directory:
        fasta, near_model, far_model = make_hidden_cases(directory, threshold)
        run_detector(executable, near_model, fasta, "ACCEPT")
        run_detector(executable, far_model, fasta, "REJECT")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
