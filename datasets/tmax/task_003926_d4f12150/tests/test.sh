#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import string
import subprocess
import tempfile

BINARY_PATH = "/home/user/bot_detector/target/release/bot_detector"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
W = 12
D = 18.5


def run_detector(filepath):
    return subprocess.run(
        [BINARY_PATH, filepath],
        capture_output=True,
        timeout=10,
    ).returncode


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def contains_cyrillic(text):
    return any(
        0x0400 <= ord(ch) <= 0x04FF
        or 0x0500 <= ord(ch) <= 0x052F
        or 0x2DE0 <= ord(ch) <= 0x2DFF
        or 0xA640 <= ord(ch) <= 0xA69F
        or 0x1C80 <= ord(ch) <= 0x1C8F
        for ch in text
    )


def expected_exit(records):
    window = []
    for record in records:
        text = record["text"]
        if len(window) == W:
            mean = sum(levenshtein(text, old) for old in window) / W
            if mean < D and contains_cyrillic(text):
                return 1
        window.append(text)
        if len(window) > W:
            window.pop(0)
    return 0


def records_for(texts):
    start = secrets.randbelow(1000000)
    return [
        {"text": text, "timestamp": start + i}
        for i, text in enumerate(texts)
    ]


def random_latin(length):
    alphabet = string.ascii_letters + string.digits + " _-"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def write_case(directory, records):
    path = os.path.join(directory, secrets.token_hex(16) + ".jsonl")
    with open(path, "w", encoding="utf-8") as handle:
        for i, record in enumerate(records):
            # Vary JSON member order and Unicode escaping to require real JSON parsing.
            if i % 2:
                obj = {"text": record["text"], "timestamp": record["timestamp"]}
            else:
                obj = {"timestamp": record["timestamp"], "text": record["text"]}
            handle.write(json.dumps(obj, ensure_ascii=(i % 3 == 0)) + "\n")
    return path


def test_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"
    with open(BINARY_PATH, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "Compiled detector must be a native executable"


def test_clean_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory missing: {CLEAN_CORPUS_DIR}"
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith(".jsonl")]
    assert len(clean_files) > 0, "No clean files found"

    failed_files = []
    for filepath in clean_files:
        result = subprocess.run([BINARY_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files failed (expected exit code 0): {failed_files}"


def test_evil_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory missing: {EVIL_CORPUS_DIR}"
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith(".jsonl")]
    assert len(evil_files) > 0, "No evil files found"

    failed_files = []
    for filepath in evil_files:
        result = subprocess.run([BINARY_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil files bypassed (expected exit code 1): {failed_files}"


def test_generated_inputs_at_unlabeled_random_paths():
    cases = []

    base = random_latin(24)
    target = "Ж" + base

    # Fewer than W prior messages must not trigger comparison.
    cases.append(records_for([target] * W))

    # The thirteenth identical Cyrillic message must trigger.
    cases.append(records_for([target] * (W + 1)))

    # Similar Latin-only messages must remain clean because the script test fails.
    latin = random_latin(30)
    cases.append(records_for([latin] * (W + 4)))

    # Exercise the strict D=18.5 boundary. Distances sum to 221 and 222.
    distances_221 = [19] * 5 + [18] * 7
    distances_222 = [19] * 6 + [18] * 6
    cases.append(records_for([target + ("x" * n) for n in distances_221] + [target]))
    cases.append(records_for([target + ("x" * n) for n in distances_222] + [target]))

    # Exercise rolling-window eviction: the old dissimilar entry must be discarded.
    rolling_base = random_latin(28)
    rolling_target = rolling_base + "Я"
    cases.append(records_for(
        [random_latin(80)] + [rolling_base] * 11 + [rolling_base, rolling_target]
    ))

    # Runtime-randomized mixtures make path- and fixed-content dispatch insufficient.
    for i in range(24):
        anchor = secrets.choice(["Б", "Д", "Ж", "Я"]) + random_latin(secrets.randbelow(16) + 12)
        mode = i % 3
        if mode == 0:
            prior = [anchor + (secrets.choice("qz") * secrets.randbelow(28)) for _ in range(W)]
            texts = prior + [anchor]
        elif mode == 1:
            no_script = random_latin(secrets.randbelow(20) + 15)
            texts = [no_script] * (W + 1 + secrets.randbelow(4))
        else:
            alphabet = string.ascii_letters + string.digits + " БДЖЯ"
            texts = [
                "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(25) + 35))
                for _ in range(W + 3 + secrets.randbelow(10))
            ]
        cases.append(records_for(texts))

    expected_values = [expected_exit(records) for records in cases]
    assert 0 in expected_values and 1 in expected_values

    with tempfile.TemporaryDirectory() as directory:
        failures = []
        for records, expected in zip(cases, expected_values):
            filepath = write_case(directory, records)
            actual = run_detector(filepath)
            if actual != expected:
                failures.append((os.path.basename(filepath), expected, actual))
        assert not failures, f"Generated behavioral cases failed: {failures}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
