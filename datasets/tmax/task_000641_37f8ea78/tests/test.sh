#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import subprocess
import tempfile
import uuid

SCRIPT_PATH = "/home/user/filter_fasta.sh"
EVIL_CORPUS_DIR = "/app/evil"
CLEAN_CORPUS_DIR = "/app/clean"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_adversarial_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.fasta"))
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.fasta"))

    assert len(evil_files) > 0, f"No files found in evil corpus {EVIL_CORPUS_DIR}"
    assert len(clean_files) > 0, f"No files found in clean corpus {CLEAN_CORPUS_DIR}"

    evil_bypassed = []
    clean_rejected = []

    for evil_file in evil_files:
        result = subprocess.run([SCRIPT_PATH, evil_file], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "REJECT":
            evil_bypassed.append(os.path.basename(evil_file))

    for clean_file in clean_files:
        result = subprocess.run([SCRIPT_PATH, clean_file], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "ACCEPT":
            clean_rejected.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        errors.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_rejected)}")

    assert not errors, " | ".join(errors)


def solve_threshold():
    lo, hi = 0.0, 1.0
    for _ in range(200):
        mid = (lo + hi) / 2.0
        if 8.0 * mid ** 3 - 1.0 < 0.0:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def expected_result(path):
    counts = {base: 0 for base in "ACGT"}
    with open(path, "r", encoding="utf-8") as fasta:
        for line in fasta:
            if line.startswith(">"):
                continue
            for char in line.upper():
                if char in counts:
                    counts[char] += 1

    total = sum(counts.values())
    assert total > 0
    threshold = solve_threshold()
    return "REJECT" if any(count / total > threshold for count in counts.values()) else "ACCEPT"


def write_randomized_fasta(path, counts, rng):
    symbols = []
    for base, count in zip("ACGT", counts):
        symbols.extend(base for _ in range(count))
    rng.shuffle(symbols)

    rendered = []
    for symbol in symbols:
        rendered.append(symbol.lower() if rng.randrange(2) else symbol)
        if rng.randrange(9) == 0:
            rendered.append(rng.choice(["N", "-", ".", "7"]))

    split = max(1, len(rendered) // 2)
    records = [rendered[:split], rendered[split:]]
    with open(path, "w", encoding="utf-8") as fasta:
        for index, record in enumerate(records):
            if not record:
                continue
            fasta.write(f">header_{index}_AAAA_CCCC_GGGG_TTTT_{uuid.uuid4().hex}\n")
            position = 0
            while position < len(record):
                width = rng.randint(1, 19)
                fasta.write("".join(record[position:position + width]) + "\n")
                position += width


def test_generated_inputs_enforce_frequency_rule():
    rng = secrets.SystemRandom()

    # Includes exact-threshold cases and violations dominated by every base.
    profiles = [
        (8, 3, 3, 2),
        (1, 1, 1, 1),
        (10, 10, 0, 0),
        (11, 4, 3, 2),
        (4, 11, 3, 2),
        (4, 3, 11, 2),
        (4, 3, 2, 11),
    ]

    for _ in range(12):
        while True:
            total = rng.randint(12, 160)
            sequence = [rng.choice("ACGT") for _ in range(total)]
            counts = tuple(sequence.count(base) for base in "ACGT")
            if max(counts) * 2 <= total:
                profiles.append(counts)
                break

    for _ in range(12):
        total = rng.randint(12, 160)
        dominant = rng.randrange(4)
        dominant_count = rng.randint(total // 2 + 1, total)
        counts = [0, 0, 0, 0]
        counts[dominant] = dominant_count
        for _ in range(total - dominant_count):
            choices = [index for index in range(4) if index != dominant]
            counts[rng.choice(choices)] += 1
        profiles.append(tuple(counts))

    rng.shuffle(profiles)
    input_dir = tempfile.mkdtemp(prefix="fasta_inputs_")
    outcomes = set()

    for counts in profiles:
        path = os.path.join(input_dir, uuid.uuid4().hex + ".fasta")
        write_randomized_fasta(path, counts, rng)
        expected = expected_result(path)
        outcomes.add(expected)
        result = subprocess.run([SCRIPT_PATH, path], capture_output=True, text=True)
        assert result.stdout.strip() == expected, (
            f"Incorrect result for generated FASTA with recomputed counts: "
            f"expected {expected}, got {result.stdout!r}"
        )

    assert outcomes == {"ACCEPT", "REJECT"}
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
