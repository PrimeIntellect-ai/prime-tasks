#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

HOME = "/home/user"
SOURCE = os.path.join(HOME, "match_samples.c")
EXECUTABLE = os.path.join(HOME, "match_samples")
MATCHES = os.path.join(HOME, "matches.csv")


def test_matches_csv_exists_and_correct():
    file_path = MATCHES
    assert os.path.isfile(file_path), f"Error: {file_path} is missing. Did you run your program?"

    expected_content = "2,102\n5,105\n3,103"

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Error: Content of {file_path} does not match expected output.\nExpected:\n{expected_content}\nGot:\n{content}"


def test_c_source_file_exists():
    file_path = SOURCE
    assert os.path.isfile(file_path), f"Error: {file_path} is missing. You must save your C code here."


def test_executable_exists():
    file_path = EXECUTABLE
    assert os.path.isfile(file_path), f"Error: {file_path} is missing. Did you compile your code?"
    assert os.access(file_path, os.X_OK), f"Error: {file_path} is not executable."
    with open(file_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Error: {file_path} is not a compiled executable."


def make_fixture(rng):
    anchor_ids = rng.sample(range(1000, 9000), 5)
    candidate_ids = rng.sample(range(10000, 90000), 10)
    offset = rng.randrange(-500, 500)

    anchors = []
    candidates = []
    for i, anchor_id in enumerate(anchor_ids):
        x = offset + i * 10000
        y = rng.randrange(-100, 101)
        z = rng.randrange(-100, 101)
        anchors.append((anchor_id, x, y, z))

        # Two equidistant nearest candidates exercise the smaller-ID tie rule.
        id1 = candidate_ids[2 * i]
        id2 = candidate_ids[2 * i + 1]
        candidates.append((id1, x - 1, y, z))
        candidates.append((id2, x + 1, y, z))

    rng.shuffle(anchors)
    rng.shuffle(candidates)
    sample_ids = anchor_ids[:]
    rng.shuffle(sample_ids)
    return anchors, candidates, sample_ids


def write_fixture(fixture):
    anchors, candidates, sample_ids = fixture
    with open(os.path.join(HOME, "anchors.csv"), "w") as f:
        for row in anchors:
            f.write(",".join(map(str, row)) + "\n")
    with open(os.path.join(HOME, "candidates.csv"), "w") as f:
        for row in candidates:
            f.write(",".join(map(str, row)) + "\n")
    with open(os.path.join(HOME, "sample_ids.txt"), "w") as f:
        for anchor_id in sample_ids:
            f.write(f"{anchor_id}\n")


def derive_expected():
    anchors = {}
    with open(os.path.join(HOME, "anchors.csv")) as f:
        for line in f:
            fields = line.strip().split(",")
            anchors[int(fields[0])] = tuple(float(v) for v in fields[1:])

    candidates = []
    with open(os.path.join(HOME, "candidates.csv")) as f:
        for line in f:
            fields = line.strip().split(",")
            candidates.append((int(fields[0]), tuple(float(v) for v in fields[1:])))

    with open(os.path.join(HOME, "sample_ids.txt")) as f:
        sample_ids = [int(line.strip()) for line in f if line.strip()]

    result = []
    for anchor_id in sample_ids:
        vector = anchors[anchor_id]
        closest_id, _ = min(
            candidates,
            key=lambda item: (
                sum((a - b) ** 2 for a, b in zip(vector, item[1])),
                item[0],
            ),
        )
        result.append(f"{anchor_id},{closest_id}")
    return "\n".join(result)


def run_and_check(program):
    if os.path.exists(MATCHES):
        os.unlink(MATCHES)
    completed = subprocess.run(
        [program], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert completed.returncode == 0, (
        f"{program} exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(MATCHES), f"{program} did not create {MATCHES}."
    with open(MATCHES) as f:
        actual = f.read().strip()
    expected = derive_expected()
    assert actual == expected, (
        f"Incorrect output from {program}.\nExpected:\n{expected}\nGot:\n{actual}"
    )


def test_program_and_source_on_unseen_inputs():
    paths = [
        os.path.join(HOME, "anchors.csv"),
        os.path.join(HOME, "candidates.csv"),
        os.path.join(HOME, "sample_ids.txt"),
        MATCHES,
    ]
    originals = {}
    for path in paths:
        with open(path, "rb") as f:
            originals[path] = f.read()

    rebuilt = "/tmp/verifier_match_samples"
    rng = random.SystemRandom()
    try:
        write_fixture(make_fixture(rng))
        run_and_check(EXECUTABLE)

        compiled = subprocess.run(
            ["gcc", "-O2", SOURCE, "-o", rebuilt, "-lm"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
        )
        assert compiled.returncode == 0, (
            "match_samples.c could not be compiled with gcc.\n"
            f"stdout:\n{compiled.stdout}\nstderr:\n{compiled.stderr}"
        )

        write_fixture(make_fixture(rng))
        run_and_check(rebuilt)
    finally:
        for path, data in originals.items():
            with open(path, "wb") as f:
                f.write(data)
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
