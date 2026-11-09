#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import shutil
import subprocess
import tempfile
import uuid

import numpy as np

SCRIPT_PATH = "/home/user/protein_classifier.py"


def run_classifier(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        timeout=30,
    ).returncode


def write_pdb(path, coords):
    with open(path, "w") as f:
        for i, (x, y, z) in enumerate(coords, 1):
            f.write(
                f"ATOM  {i:5d}  CA  ALA A{i:4d}    "
                f"{x:8.3f}{y:8.3f}{z:8.3f}  1.00 20.00           C  \n"
            )


def transformed_copy(source, destination, rng):
    lines = open(source).readlines()
    permutation = list(range(3))
    rng.shuffle(permutation)
    signs = np.array([rng.choice((-1.0, 1.0)) for _ in range(3)])
    translation = np.array([rng.randint(-100, 100) for _ in range(3)], dtype=float)

    output = []
    for line in lines:
        if line.startswith(("ATOM  ", "HETATM")) and line[12:16].strip() == "CA":
            xyz = np.array([
                float(line[30:38]),
                float(line[38:46]),
                float(line[46:54]),
            ])
            xyz = xyz[permutation] * signs + translation
            line = line[:30] + f"{xyz[0]:8.3f}{xyz[1]:8.3f}{xyz[2]:8.3f}" + line[54:]
        output.append(line)

    with open(destination, "w") as f:
        f.writelines(output)


def test_protein_classifier_exists():
    assert os.path.isfile(SCRIPT_PATH), (
        f"Script {SCRIPT_PATH} does not exist. The agent failed to create the required file."
    )


def test_clean_corpus_accepted():
    clean_dir = "/app/corpus/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.pdb"))
    if not clean_files:
        clean_files = [
            os.path.join(clean_dir, f)
            for f in os.listdir(clean_dir)
            if os.path.isfile(os.path.join(clean_dir, f))
        ]

    assert len(clean_files) > 0, f"No files found in {clean_dir}"
    failed_files = []
    for filepath in clean_files:
        if run_classifier(filepath) != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        assert False, (
            f"{len(failed_files)} of {len(clean_files)} clean modified/rejected "
            f"(expected exit code 0). Offending files: {', '.join(failed_files)}"
        )


def test_evil_corpus_rejected():
    evil_dir = "/app/corpus/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.pdb"))
    if not evil_files:
        evil_files = [
            os.path.join(evil_dir, f)
            for f in os.listdir(evil_dir)
            if os.path.isfile(os.path.join(evil_dir, f))
        ]

    assert len(evil_files) > 0, f"No files found in {evil_dir}"
    failed_files = []
    for filepath in evil_files:
        if run_classifier(filepath) != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        assert False, (
            f"{len(failed_files)} of {len(evil_files)} evil bypassed "
            f"(expected exit code 1). Offending files: {', '.join(failed_files)}"
        )


def test_neutral_hidden_cases():
    # All cases share a randomly named neutral directory and randomly named files,
    # so their expected result cannot be inferred from the input path.
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    np_rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    workdir = tempfile.mkdtemp(prefix="pdb_" + uuid.uuid4().hex + "_", dir="/tmp")
    cases = []

    try:
        # Preserve the original corpus assertions under randomized paths and exact
        # distance-preserving coordinate transformations.
        for expected, source_dir in ((0, "/app/corpus/clean"), (1, "/app/corpus/evil")):
            for source in glob.glob(os.path.join(source_dir, "*.pdb")):
                destination = os.path.join(workdir, uuid.uuid4().hex + ".pdb")
                transformed_copy(source, destination, rng)
                cases.append((destination, expected))

        # Fresh held-out structures generated independently on every verifier run.
        # These follow the same two structural distributions used by the task.
        for _ in range(4):
            coords = np_rng.random((100, 3)) * 50.0
            destination = os.path.join(workdir, uuid.uuid4().hex + ".pdb")
            write_pdb(destination, coords)
            cases.append((destination, 0))

        for _ in range(4):
            t = np.linspace(0.0, 50.0, 100)
            coords = np.column_stack((t, t, t)) + np_rng.random((100, 3)) * 0.1
            destination = os.path.join(workdir, uuid.uuid4().hex + ".pdb")
            write_pdb(destination, coords)
            cases.append((destination, 1))

        rng.shuffle(cases)
        failures = []
        for path, expected in cases:
            actual = run_classifier(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))

        assert not failures, "Randomized neutral-path cases failed: " + repr(failures)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def test_bad_inputs_return_two():
    workdir = tempfile.mkdtemp(prefix="pdb_" + uuid.uuid4().hex + "_", dir="/tmp")
    try:
        missing = os.path.join(workdir, uuid.uuid4().hex + ".pdb")

        malformed = os.path.join(workdir, uuid.uuid4().hex + ".pdb")
        with open(malformed, "w") as f:
            f.write("this is not a PDB file\n")

        insufficient = os.path.join(workdir, uuid.uuid4().hex + ".pdb")
        write_pdb(insufficient, np.random.default_rng().random((49, 3)) * 20.0)

        for path in (missing, malformed, insufficient):
            assert run_classifier(path) == 2, f"Expected exit code 2 for unusable input {path}"
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
