#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import stat
import subprocess
import tempfile

HOME = "/home/user"
DATA = os.path.join(HOME, "data.csv")
SOURCE = os.path.join(HOME, "prepare_data.cpp")
BINARY = os.path.join(HOME, "prepare_data")
TRAIN = os.path.join(HOME, "train_features.txt")
TEST = os.path.join(HOME, "test_features.txt")

CANONICAL_CSV = """id,text,feature
1,apple banana,10.0
2,apple orange,12.0
3,banana grape,8.0
4,grape orange,11.0
5,apple kiwi,10.5
6,kiwi mango,9.0
7,mango apple,10.0
8,banana mango,11.5
9,papaya orange,20.0
10,papaya kiwi,22.0
"""

EXPECTED_TRAIN = [
    "1,1 2,-0.25",
    "2,1 3,1.75",
    "3,2 4,-2.25",
    "4,4 3,0.75",
    "5,1 5,0.25",
    "6,5 6,-1.25",
    "7,6 1,-0.25",
    "8,2 6,1.25",
]

EXPECTED_TEST = [
    "9,0 3,9.75",
    "10,0 5,11.75",
]


def write_data(contents):
    with open(DATA, "w", newline="") as f:
        f.write(contents)


def remove_outputs():
    for path in (TRAIN, TEST):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def run_program(path):
    remove_outputs()
    result = subprocess.run(
        [path], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{path} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(TRAIN), f"File {TRAIN} is missing. Did you run the compiled script?"
    assert os.path.isfile(TEST), f"File {TEST} is missing. Did you run the compiled script?"


def read_nonempty(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def assert_canonical_outputs():
    lines = read_nonempty(TRAIN)
    assert len(lines) == 8, f"Expected 8 lines in {TRAIN}, but got {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, EXPECTED_TRAIN)):
        assert actual == expected, (
            f"Line {i+1} in {TRAIN} is incorrect.\nExpected: {expected}\nGot: {actual}"
        )

    lines = read_nonempty(TEST)
    assert len(lines) == 2, f"Expected 2 lines in {TEST}, but got {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, EXPECTED_TEST)):
        assert actual == expected, (
            f"Line {i+1} in {TEST} is incorrect.\nExpected: {expected}\nGot: {actual}"
        )


def make_challenge():
    rng = random.Random(secrets.randbits(128))
    words = ["w" + secrets.token_hex(6) for _ in range(6)]
    oov1 = "oov" + secrets.token_hex(7)
    oov2 = "oov" + secrets.token_hex(7)
    pairs = [
        (words[0], words[1]),
        (words[2], words[0]),
        (words[3], words[2]),
        (words[1], words[4]),
        (words[5], words[3]),
        (words[4], words[0]),
        (words[2], words[5]),
        (words[1], words[3]),
        (oov1, words[4]),
        (words[5], oov2),
    ]
    mean = rng.randint(30, 300)
    deltas = [-7, -4, -2, 0, 0, 2, 4, 7]
    rng.shuffle(deltas)
    features = [mean + d for d in deltas] + [mean + 13, mean - 11]
    ids = [rng.randint(1000, 9000) + i * 10000 for i in range(10)]

    rows = [(ids[i], list(pairs[i]), features[i]) for i in range(10)]
    csv_text = "id,text,feature\n" + "".join(
        f"{rid},{' '.join(tokens)},{feature}.0\n"
        for rid, tokens, feature in rows
    )

    vocab = {}
    next_id = 1
    for _, tokens, _ in rows[:8]:
        for token in tokens:
            if token not in vocab:
                vocab[token] = next_id
                next_id += 1
    train_mean = sum(feature for _, _, feature in rows[:8]) / 8.0

    expected = []
    for rid, tokens, feature in rows:
        token_ids = " ".join(str(vocab.get(token, 0)) for token in tokens)
        expected.append(f"{rid},{token_ids},{feature - train_mean:.2f}")
    return csv_text, expected[:8], expected[8:]


def assert_outputs(expected_train, expected_test):
    actual_train = read_nonempty(TRAIN)
    actual_test = read_nonempty(TEST)
    assert actual_train == expected_train, (
        f"Training output from executed program is incorrect.\n"
        f"Expected: {expected_train}\nGot: {actual_train}"
    )
    assert actual_test == expected_test, (
        f"Test output from executed program is incorrect.\n"
        f"Expected: {expected_test}\nGot: {actual_test}"
    )


def test_implementation_and_outputs():
    # Preserve the original binary existence and executability assertions.
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing. Did you recompile the script?"
    assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable."
    assert stat.S_ISREG(os.stat(BINARY).st_mode), f"{BINARY} must be a regular file."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."

    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    assert stat.S_ISREG(os.stat(SOURCE).st_mode), f"{SOURCE} must be a regular file."

    fd, rebuilt = tempfile.mkstemp(prefix="prepare_data_rebuilt_", dir="/tmp")
    os.close(fd)
    os.unlink(rebuilt)
    try:
        compile_result = subprocess.run(
            ["g++", "-O3", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert compile_result.returncode == 0, (
            f"prepare_data.cpp does not compile with g++ -O3.\n{compile_result.stderr}"
        )

        # Execute the submitted binary on the original dataset and retain all
        # exact output assertions from the original verifier.
        write_data(CANONICAL_CSV)
        run_program(BINARY)
        assert_canonical_outputs()

        # Exercise both the submitted binary and a fresh build of the submitted
        # source on an unpredictable dataset, deriving answers independently.
        challenge_csv, expected_train, expected_test = make_challenge()
        write_data(challenge_csv)
        run_program(BINARY)
        assert_outputs(expected_train, expected_test)

        write_data(challenge_csv)
        run_program(rebuilt)
        assert_outputs(expected_train, expected_test)

        # Restore the required final dataset and outputs, and ensure the binary
        # still produces the original exact results.
        write_data(CANONICAL_CSV)
        run_program(BINARY)
        assert_canonical_outputs()
    finally:
        write_data(CANONICAL_CSV)
        try:
            os.unlink(rebuilt)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
