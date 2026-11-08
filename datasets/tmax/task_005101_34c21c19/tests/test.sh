#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import cmath
import importlib.util
import json
import math
import os
import secrets
import urllib.request

import pytest
import yaml

PRIMER = "GCATCGAT"
VALUES = {"A": 1, "C": 2, "G": -1, "T": -2}
BASES = "ACGT"
RNG = secrets.SystemRandom()


def classify_sequence(sequence):
    url = "http://127.0.0.1:5000/classify"
    data = json.dumps({"sequence": sequence}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            result = json.loads(response.read().decode("utf-8"))
            return result.get("status")
    except Exception as e:
        return f"error: {str(e)}"


def period5_block_power(block):
    assert len(block) == 5
    z = sum(
        VALUES[base] * cmath.exp(-2j * math.pi * index / 5)
        for index, base in enumerate(block)
    )
    return abs(z) ** 2


def random_high_power_block():
    candidates = []
    for chars in __import__("itertools").product(BASES, repeat=5):
        block = "".join(chars)
        if period5_block_power(block) > 20:
            candidates.append(block)
    return RNG.choice(candidates)


def novel_cases():
    cases = []

    # Exact primer checks, with unpredictable bodies.
    for _ in range(6):
        body = "".join(RNG.choice(BASES) for _ in range(RNG.randint(75, 230)))
        bad_primer = list(PRIMER)
        pos = RNG.randrange(len(bad_primer))
        bad_primer[pos] = RNG.choice([b for b in BASES if b != bad_primer[pos]])
        cases.append(("".join(bad_primer) + body, "evil", "mutated primer"))

    # Constant-valued blocks have no period-5 power. The trailing bases must be discarded.
    for base in BASES:
        blocks = RNG.randint(18, 35)
        remainder = "".join(RNG.choice(BASES) for _ in range(RNG.randint(1, 4)))
        cases.append((PRIMER + base * (5 * blocks) + remainder, "clean", "zero spectral power"))

    # Identical high-power blocks make every bootstrap resample anomalous.
    for _ in range(5):
        block = random_high_power_block()
        blocks = RNG.randint(18, 30)
        assert period5_block_power(block) * blocks * blocks > 200
        cases.append((PRIMER + block * blocks, "evil", "period-5 anomaly"))

    # These heterogeneous samples have high power in their original ordering/counts,
    # but well over 2.5% of block-bootstrap resamples fall at or below 200. A raw FFT
    # threshold therefore gives the wrong answer.
    first = "CCTTT"
    second = "TTCCC"  # Numerical negative of first.
    q = period5_block_power(first)
    assert q > 40
    for _ in range(4):
        rotation = RNG.randrange(5)
        a = first[rotation:] + first[:rotation]
        b = second[rotation:] + second[:rotation]
        if RNG.randrange(2):
            a, b = b, a
        blocks = [a] * 12 + [b] * 8
        RNG.shuffle(blocks)
        original_power = abs((12 - 8)) ** 2 * q
        probability_at_or_below_threshold = sum(
            math.comb(20, x) * (0.6 ** x) * (0.4 ** (20 - x))
            for x in (9, 10, 11)
        )
        assert original_power > 200
        assert probability_at_or_below_threshold > 0.20
        cases.append((PRIMER + "".join(blocks), "clean", "bootstrap lower confidence bound"))

    RNG.shuffle(cases)
    return cases


def test_configuration_and_classifier_artifact():
    config_path = "/app/dna_pipeline/config.yaml"
    classifier_path = "/app/dna_pipeline/classifier.py"
    assert os.path.isfile(config_path), "config.yaml is missing"
    assert os.path.isfile(classifier_path), "classifier.py is missing"

    with open(config_path, "r") as f:
        config = yaml.safe_load(f)
    assert config.get("redis_host") in ("127.0.0.1", "localhost")
    assert config.get("redis_port") == 6379
    assert config.get("api_port") == 5000

    spec = importlib.util.spec_from_file_location("submitted_classifier", classifier_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "evaluate_sequence", None))
    assert module.evaluate_sequence("TCATCGAT" + "A" * 100) == "evil"
    assert module.evaluate_sequence(PRIMER + "A" * 200) == "clean"
    assert module.evaluate_sequence(PRIMER + "CCTTT" * 20) == "evil"


def test_adversarial_corpus_evaluation():
    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"

    assert os.path.isdir(evil_dir), f"Directory {evil_dir} does not exist"
    assert os.path.isdir(clean_dir), f"Directory {clean_dir} does not exist"

    evil_files = sorted(
        f for f in os.listdir(evil_dir)
        if os.path.isfile(os.path.join(evil_dir, f))
    )
    clean_files = sorted(
        f for f in os.listdir(clean_dir)
        if os.path.isfile(os.path.join(clean_dir, f))
    )

    assert len(evil_files) > 0, "No files found in evil corpus"
    assert len(clean_files) > 0, "No files found in clean corpus"

    bypassed_evil = []
    for filename in evil_files:
        with open(os.path.join(evil_dir, filename), "r") as f:
            sequence = f.read().strip()
        if classify_sequence(sequence) != "evil":
            bypassed_evil.append(filename)

    modified_clean = []
    for filename in clean_files:
        with open(os.path.join(clean_dir, filename), "r") as f:
            sequence = f.read().strip()
        if classify_sequence(sequence) != "clean":
            modified_clean.append(filename)

    errors = []
    if bypassed_evil:
        errors.append(
            f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {bypassed_evil}"
        )
    if modified_clean:
        errors.append(
            f"{len(modified_clean)} of {len(clean_files)} clean modified: {modified_clean}"
        )
    if errors:
        pytest.fail(" | ".join(errors))


def test_novel_end_to_end_sequences():
    failures = []
    for index, (sequence, expected, description) in enumerate(novel_cases()):
        actual = classify_sequence(sequence)
        if actual != expected:
            failures.append(
                f"case {index} ({description}): expected {expected}, got {actual}"
            )
    if failures:
        pytest.fail(" | ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
