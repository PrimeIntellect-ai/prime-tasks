#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import shlex
import shutil
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/classifier.sh"
EMBEDDER_PATH = "/app/artifact_embedder"
CLEAN_CORPUS_DIR = "/app/test_clean"
EVIL_CORPUS_DIR = "/app/test_evil"
TRAIN_CLEAN_DIR = "/home/user/data/train_clean"
TRAIN_EVIL_DIR = "/home/user/data/train_evil"


def run_classifier(path_args, cwd=None):
    return subprocess.run(
        ["bash", SCRIPT_PATH, *path_args],
        cwd=cwd,
        capture_output=True,
        timeout=15,
    )


def read_embedding(executable, path):
    result = subprocess.run(
        [executable, path], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"artifact_embedder failed for {path}"
    fields = result.stdout.strip().split()
    assert len(fields) == 5, f"Expected a 5-dimensional embedding for {path}"
    values = [float(value) for value in fields]
    assert all(math.isfinite(value) for value in values)
    return values


def centroid(vectors):
    return [sum(row[i] for row in vectors) / len(vectors) for i in range(5)]


def squared_distance(left, right):
    return sum((a - b) ** 2 for a, b in zip(left, right))


@pytest.fixture(scope="session")
def instrumented_embedder():
    assert os.path.isfile(EMBEDDER_PATH), "Missing /app/artifact_embedder"
    assert os.access(EMBEDDER_PATH, os.X_OK), "/app/artifact_embedder is not executable"
    with open(EMBEDDER_PATH, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "/app/artifact_embedder is not the supplied binary"

    work_dir = tempfile.mkdtemp(prefix="artifact-verifier-")
    real_embedder = os.path.join(work_dir, "real_embedder")
    mapping_path = os.path.join(work_dir, "embedding_map.tsv")
    log_path = os.path.join(work_dir, "embedder_calls.tsv")
    generated_dir = os.path.join(work_dir, "artifacts")
    os.mkdir(generated_dir)
    shutil.copy2(EMBEDDER_PATH, real_embedder)

    clean_training = [
        read_embedding(real_embedder, os.path.join(TRAIN_CLEAN_DIR, name))
        for name in sorted(os.listdir(TRAIN_CLEAN_DIR))
        if os.path.isfile(os.path.join(TRAIN_CLEAN_DIR, name))
    ]
    evil_training = [
        read_embedding(real_embedder, os.path.join(TRAIN_EVIL_DIR, name))
        for name in sorted(os.listdir(TRAIN_EVIL_DIR))
        if os.path.isfile(os.path.join(TRAIN_EVIL_DIR, name))
    ]
    assert clean_training and evil_training

    clean_center = centroid(clean_training)
    evil_center = centroid(evil_training)
    rng = random.SystemRandom()
    candidates = []
    for _ in range(12):
        candidates.append(rng.choice(clean_training))
        candidates.append(rng.choice(evil_training))
    rng.shuffle(candidates)

    cases = []
    with open(mapping_path, "w", encoding="utf-8") as mapping:
        for vector in candidates:
            name = "artifact_" + os.urandom(10).hex() + ".dat"
            path = os.path.join(generated_dir, name)
            # Contents and directory are identical across both classes, so only the
            # embedding returned by the required tool distinguishes each case.
            with open(path, "wb") as artifact:
                artifact.write(b"opaque artifact payload\n")
            clean_distance = squared_distance(vector, clean_center)
            evil_distance = squared_distance(vector, evil_center)
            assert clean_distance != evil_distance
            expected = 0 if clean_distance < evil_distance else 1
            mapping.write(path + "\t" + " ".join(str(v) for v in vector) + "\n")
            cases.append((path, expected))

    assert {expected for _, expected in cases} == {0, 1}

    wrapper = (
        "#!/bin/bash\n"
        "printf '%s\\t%s\\n' \"${1-}\" \"$#\" >> " + shlex.quote(log_path) + "\n"
        "if [ \"$#\" -eq 1 ]; then\n"
        "  mapped=$(awk -F '\\t' -v p=\"$1\" '$1 == p { print $2; exit }' " + shlex.quote(mapping_path) + ")\n"
        "  if [ -n \"$mapped\" ]; then\n"
        "    printf '%s\\n' \"$mapped\"\n"
        "    exit 0\n"
        "  fi\n"
        "fi\n"
        "exec " + shlex.quote(real_embedder) + " \"$@\"\n"
    )

    try:
        with open(EMBEDDER_PATH, "w", encoding="utf-8") as handle:
            handle.write(wrapper)
        os.chmod(EMBEDDER_PATH, 0o755)
        yield {
            "cases": cases,
            "log": log_path,
            "generated_dir": generated_dir,
        }
    finally:
        if os.path.exists(real_embedder):
            os.replace(real_embedder, EMBEDDER_PATH)
        shutil.rmtree(work_dir, ignore_errors=True)


def test_classifier_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Classifier script missing at {SCRIPT_PATH}"


def test_clean_corpus_accepted(instrumented_embedder):
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus directory."

    failed_files = []
    for filepath in clean_files:
        result = run_classifier([filepath])
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files rejected (should be accepted/exit 0). Offending files: {', '.join(failed_files)}")


def test_evil_corpus_rejected(instrumented_embedder):
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil corpus directory."

    failed_files = []
    for filepath in evil_files:
        result = run_classifier([filepath])
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (should be rejected/exit 1). Offending files: {', '.join(failed_files)}")


def test_randomized_artifacts_use_embedder_and_are_classified(instrumented_embedder):
    log_path = instrumented_embedder["log"]
    for filepath, expected in instrumented_embedder["cases"]:
        with open(log_path, "w", encoding="utf-8"):
            pass
        result = run_classifier([filepath])
        assert result.returncode == expected, (
            f"Incorrect classification for randomized artifact {os.path.basename(filepath)}: "
            f"expected exit {expected}, got {result.returncode}"
        )
        with open(log_path, encoding="utf-8") as calls_file:
            calls = [line.rstrip("\n").split("\t", 1) for line in calls_file]
        assert any(call[0] == filepath and call[1] == "1" for call in calls), (
            f"Classifier did not execute /app/artifact_embedder on {filepath}"
        )


def test_requires_exactly_one_absolute_argument(instrumented_embedder):
    clean_path = next(path for path, expected in instrumented_embedder["cases"] if expected == 0)
    evil_path = next(path for path, expected in instrumented_embedder["cases"] if expected == 1)

    assert run_classifier([]).returncode != 0, "Classifier accepted a missing argument"
    assert run_classifier([clean_path, evil_path]).returncode != 0, "Classifier accepted two arguments"

    relative_name = os.path.basename(clean_path)
    result = run_classifier([relative_name], cwd=instrumented_embedder["generated_dir"])
    assert result.returncode != 0, "Classifier accepted a relative artifact path"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
