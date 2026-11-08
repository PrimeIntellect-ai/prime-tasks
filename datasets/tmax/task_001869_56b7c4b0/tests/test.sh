#!/bin/bash
set -e
mkdir -p /logs/verifier

REAL_EMBEDDER="/app/seq_embedder.verifier-real"
CALL_LOG="/tmp/seq_embedder_calls.log"

cleanup() {
    if [ -e "$REAL_EMBEDDER" ]; then
        rm -f /app/seq_embedder
        mv "$REAL_EMBEDDER" /app/seq_embedder
    fi
}
trap cleanup EXIT

if [ ! -f /app/seq_embedder ] || [ ! -x /app/seq_embedder ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

mv /app/seq_embedder "$REAL_EMBEDDER"
cat <<'WRAPPER_EOF' > /app/seq_embedder
#!/bin/sh
printf '%s\n' "$@" >> /tmp/seq_embedder_calls.log
exec /app/seq_embedder.verifier-real "$@"
WRAPPER_EOF
chmod 755 /app/seq_embedder
: > "$CALL_LOG"

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import tempfile

import numpy as np
import pytest
from sklearn.mixture import GaussianMixture

SCRIPT = "/home/user/evaluate.py"
TRAIN = "/home/user/data/train.fasta"
HIDDEN = "/home/user/data/hidden_test.fasta"
REAL_EMBEDDER = "/app/seq_embedder.verifier-real"
CALL_LOG = "/tmp/seq_embedder_calls.log"


def test_evaluate_script_exists():
    assert os.path.exists(SCRIPT), f"Evaluation script not found at {SCRIPT}"
    assert os.path.isfile(SCRIPT), f"Path {SCRIPT} is not a file"


def embed(fasta_path):
    fd, output_path = tempfile.mkstemp(suffix=".bin")
    os.close(fd)
    try:
        subprocess.run(
            [REAL_EMBEDDER, fasta_path, output_path],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        values = np.fromfile(output_path, dtype=np.float32)
        assert values.size > 0 and values.size % 64 == 0
        return values.reshape(-1, 64).astype(np.float64)
    finally:
        try:
            os.unlink(output_path)
        except FileNotFoundError:
            pass


def make_fasta(kind):
    fd, path = tempfile.mkstemp(prefix="verifier_unseen_", suffix=".fasta")
    os.close(fd)
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    with open(path, "w") as handle:
        for i in range(48):
            if kind == "mixture":
                weights = (0.1, 0.4, 0.4, 0.1) if i % 2 else (0.4, 0.1, 0.1, 0.4)
                sequence = "".join(rng.choices("ACGT", weights=weights, k=100))
            else:
                weights = (0.015, 0.47, 0.50, 0.015) if i % 3 else (0.48, 0.02, 0.02, 0.48)
                sequence = "".join(rng.choices("ACGT", weights=weights, k=100))
            handle.write(f">unseen_{i}\n{sequence}\n")
    return path


def run_evaluate(fasta_path):
    open(CALL_LOG, "w").close()
    try:
        result = subprocess.run(
            ["python3", SCRIPT, fasta_path],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(
            f"evaluate.py failed with return code {exc.returncode}.\n"
            f"Stdout: {exc.stdout}\nStderr: {exc.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail("evaluate.py timed out after 30 seconds.")

    output = result.stdout.strip()
    assert output, "evaluate.py produced no standard output."
    try:
        value = float(output)
    except ValueError:
        pytest.fail(f"evaluate.py output could not be parsed as a float. Output was: {output!r}")
    assert math.isfinite(value), f"evaluate.py must output a finite float, got {value!r}"

    with open(CALL_LOG) as handle:
        calls = handle.read()
    assert fasta_path in calls, (
        "evaluate.py did not invoke /app/seq_embedder on the supplied FASTA file"
    )
    return value


def build_reference_predictions(train_x, test_sets):
    candidates = []
    for centered in (False, True):
        mean = train_x.mean(axis=0) if centered else np.zeros(train_x.shape[1])
        train_for_svd = train_x - mean
        _, _, vt = np.linalg.svd(train_for_svd, full_matrices=False)
        projection = vt[:3].T
        train_z = (train_x - mean) @ projection

        # GMM covariance structure and initialization seed are not specified by
        # the task, so accept the standard sklearn structures and stable seeds.
        for covariance_type in ("full", "tied", "diag", "spherical"):
            for seed in range(5):
                model = GaussianMixture(
                    n_components=2,
                    covariance_type=covariance_type,
                    random_state=seed,
                ).fit(train_z)
                candidates.append(np.array([
                    model.score((test_x - mean) @ projection)
                    for test_x in test_sets
                ]))
    return candidates


def test_evaluate_script_output_metric():
    assert os.path.exists(SCRIPT), f"Cannot run test: {SCRIPT} does not exist."
    assert os.path.exists(HIDDEN), f"Cannot run test: {HIDDEN} does not exist."
    assert os.path.exists(TRAIN), f"Training FASTA not found at {TRAIN}."

    challenge_a = make_fasta("mixture")
    challenge_b = make_fasta("shifted")
    train_backup = TRAIN + ".verifier-hidden"
    try:
        train_x = embed(TRAIN)
        test_paths = [HIDDEN, challenge_a, challenge_b]
        test_sets = [embed(path) for path in test_paths]
        expected_candidates = build_reference_predictions(train_x, test_sets)

        # The evaluator must use stored training parameters rather than fitting
        # again at evaluation time.
        os.replace(TRAIN, train_backup)
        try:
            observed = np.array([run_evaluate(path) for path in test_paths])
        finally:
            os.replace(train_backup, TRAIN)

        threshold = -12.5
        assert observed[0] >= threshold, (
            "Mean Log-Likelihood (MLL) is too low. "
            f"Expected >= {threshold}, but got {observed[0]}."
        )

        assert any(
            np.allclose(observed, expected, rtol=0.02, atol=0.20)
            for expected in expected_candidates
        ), (
            "evaluate.py scores do not match an SVD projection and fitted "
            "2-component GMM learned from the training embeddings. "
            f"Observed scores: {observed.tolist()}"
        )
    finally:
        if os.path.exists(train_backup) and not os.path.exists(TRAIN):
            os.replace(train_backup, TRAIN)
        for path in (challenge_a, challenge_b):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
