#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess

PIPELINE_CPP = "/home/user/pipeline.cpp"
PIPELINE_BIN = "/home/user/pipeline"
FEATURES = "/home/user/features.csv"
EMBEDDINGS = "/home/user/embeddings.csv"
OUTPUT = "/home/user/sampled_data.csv"


def mt19937_indices(size, count=50):
    helper_src = "/tmp/expected_indices.cpp"
    helper_bin = "/tmp/expected_indices"
    with open(helper_src, "w") as f:
        f.write(r'''#include <cstdlib>
#include <iostream>
#include <random>
int main(int argc, char **argv) {
    size_t size = static_cast<size_t>(std::strtoull(argv[1], 0, 10));
    std::mt19937 gen(42);
    for (int i = 0; i < 50; ++i) std::cout << (gen() % size) << "\n";
    return 0;
}
''')
    subprocess.run(
        ["g++", "-O2", "-std=c++11", helper_src, "-o", helper_bin],
        check=True,
    )
    result = subprocess.run(
        [helper_bin, str(size)], check=True, text=True, capture_output=True
    )
    return [int(x) for x in result.stdout.splitlines()]


def joined_rows_from_files():
    features_map = {}
    with open(FEATURES, "r") as f:
        next(f)
        for line in f:
            line = line.rstrip("\r\n")
            if not line:
                continue
            ident, rest = line.split(",", 1)
            features_map[ident] = rest

    joined = []
    with open(EMBEDDINGS, "r") as f:
        next(f)
        for line in f:
            line = line.rstrip("\r\n")
            if not line:
                continue
            ident, rest = line.split(",", 1)
            if ident in features_map:
                joined.append(f"{ident},{features_map[ident]},{rest}")
    return joined


def expected_sample_rows():
    joined = joined_rows_from_files()
    assert joined, "The test input has an empty inner join."
    return [joined[i] for i in mt19937_indices(len(joined))]


def run_pipeline():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    subprocess.run([PIPELINE_BIN], check=True, timeout=10)
    assert os.path.isfile(OUTPUT), f"Missing file: {OUTPUT}. Did you run the compiled pipeline?"
    with open(OUTPUT, "r") as f:
        return [line.rstrip("\r\n") for line in f]


def assert_output(lines, expected_rows):
    assert len(lines) == 51, f"Expected 51 lines in {OUTPUT} (header + 50 rows), but got {len(lines)}."
    assert "id" in lines[0].lower(), "Header does not contain 'id'."

    for i in range(1, 51):
        assert lines[i].count(',') >= 2, (
            f"Row {i} does not appear to be properly comma-separated: {lines[i]}"
        )

    expected_indices = [42, 67, 76, 81, 22]
    expected_ids = [str(idx + 1) for idx in expected_indices]
    actual_ids = [lines[i].split(',')[0] for i in range(1, 6)]
    assert actual_ids == expected_ids, (
        "The sampled IDs do not match the expected deterministic sequence. "
        f"Expected first 5 IDs: {expected_ids}, got: {actual_ids}. "
        "Did you use 'gen() % joined_data.size()' with seed 42?"
    )

    assert lines[1:] == expected_rows, (
        "All 50 sampled rows must match the joined data and the complete deterministic "
        "mt19937(42) modulo sequence."
    )


def test_pipeline_source_binary_and_behavior():
    assert os.path.isfile(PIPELINE_CPP), f"Missing file: {PIPELINE_CPP}"

    with open(PIPELINE_CPP, "r") as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert "std::random_device" not in content or "std::random_device rd;" not in content, "The code still uses std::random_device."
    assert "std::mt19937 gen(42);" in content or "gen(42)" in content, "The code does not initialize mt19937 with seed 42."
    assert "%" in content and "joined_data.size()" in content, "The code does not use modulo joined_data.size() for sampling."
    assert "std::uniform_int_distribution" not in content, "The code still uses std::uniform_int_distribution."
    assert "std::getline(ss, id, ',');" in content and "std::getline(ss, id, ' ');" not in content, "The delimiter for embeddings.csv was not fixed to a comma."

    # The instruction requires the agent to have compiled the program.
    assert os.path.isfile(PIPELINE_BIN), f"Missing compiled pipeline: {PIPELINE_BIN}"
    mode = os.stat(PIPELINE_BIN).st_mode
    assert stat.S_ISREG(mode) and os.access(PIPELINE_BIN, os.X_OK), "The pipeline is not an executable regular file."
    with open(PIPELINE_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The compiled pipeline is not an ELF executable."

    # Rebuild from the submitted source using the required command, then execute it.
    subprocess.run(
        ["g++", "-O3", "-std=c++11", PIPELINE_CPP, "-o", PIPELINE_BIN],
        check=True,
        timeout=30,
    )

    canonical_expected = expected_sample_rows()
    canonical_lines = run_pipeline()
    assert_output(canonical_lines, canonical_expected)

    # Exercise the submitted program on a fresh join whose values and ordering are
    # generated at verification time, rather than trusting a pre-created CSV.
    with open(FEATURES, "rb") as f:
        original_features = f.read()
    with open(EMBEDDINGS, "rb") as f:
        original_embeddings = f.read()

    rng = random.SystemRandom()
    nonce = rng.randrange(10**8, 10**9)
    ids = [str(nonce + i * 17) for i in range(18)]
    embedding_order = ids[:]
    rng.shuffle(embedding_order)

    try:
        with open(FEATURES, "w") as f:
            f.write("id,feature_a,feature_b\n")
            for i, ident in enumerate(ids):
                f.write(f"{ident},F{nonce}_{i},{1000 + i}\n")

        with open(EMBEDDINGS, "w") as f:
            f.write("id,emb_a,emb_b\n")
            for i, ident in enumerate(embedding_order):
                f.write(f"{ident},E{nonce}_{i},{-2000 - i}\n")
            f.write(f"unmatched_{nonce},unused,unused\n")

        challenge_expected = expected_sample_rows()
        challenge_lines = run_pipeline()
        assert len(challenge_lines) == 51, "Challenge run did not produce exactly 50 samples plus a header."
        assert "id" in challenge_lines[0].lower(), "Challenge output header does not contain 'id'."
        for i in range(1, 51):
            assert challenge_lines[i].count(',') >= 2, f"Challenge row {i} is not comma-separated."
        assert challenge_lines[1:] == challenge_expected, (
            "The pipeline did not correctly join and deterministically sample the verification-time inputs."
        )
    finally:
        with open(FEATURES, "wb") as f:
            f.write(original_features)
        with open(EMBEDDINGS, "wb") as f:
            f.write(original_embeddings)
        # Leave the requested artifact generated from the original input files.
        subprocess.run([PIPELINE_BIN], check=False, timeout=10)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
