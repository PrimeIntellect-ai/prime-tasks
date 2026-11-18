#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import secrets
import subprocess
import tempfile
import pytest

SANITIZER_SCRIPT = "/home/user/sanitizer.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"


def run_sanitizer(path, *extra):
    return subprocess.run(
        ["python3", SANITIZER_SCRIPT, path, *extra],
        capture_output=True,
        timeout=5,
    )


def test_sanitizer_exists():
    assert os.path.isfile(SANITIZER_SCRIPT), f"The script {SANITIZER_SCRIPT} does not exist."
    assert os.access(SANITIZER_SCRIPT, os.X_OK) or os.access(SANITIZER_SCRIPT, os.R_OK), \
        f"The script {SANITIZER_SCRIPT} must be readable or executable."


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Missing directory: {CLEAN_CORPUS_DIR}"
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    assert len(clean_files) > 0, "No clean JSON files found."

    failed_files = []
    for filepath in clean_files:
        result = run_sanitizer(filepath)
        if result.returncode != 0:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly rejected (exit code != 0). "
                    f"Offending files: {', '.join(failed_files)}")


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Missing directory: {EVIL_CORPUS_DIR}"
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    assert len(evil_files) > 0, "No evil JSON files found."

    failed_files = []
    for filepath in evil_files:
        result = run_sanitizer(filepath)
        if result.returncode != 1:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed the sanitizer (exit code != 1). "
                    f"Offending files: {', '.join(failed_files)}")


def expected_code(value):
    if not isinstance(value, dict) or set(value) != {"var_alpha", "var_beta"}:
        return 1
    a = value["var_alpha"]
    b = value["var_beta"]
    if type(a) not in (int, float) or type(b) not in (int, float):
        return 1
    if not math.isfinite(a) or not math.isfinite(b):
        return 1
    return 0 if a != b else 1


def test_independently_generated_payloads_and_unpredictable_paths():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    cases = [
        {"var_alpha": 4, "var_beta": -3},
        {"var_alpha": -2.5, "var_beta": 7.25},
        {"var_alpha": 0, "var_beta": 1},
        {"var_alpha": 0.0, "var_beta": -0.0},
        {"var_alpha": True, "var_beta": 2},
        {"var_alpha": 2, "var_beta": False},
        {"var_alpha": "2", "var_beta": 1},
        {"var_alpha": 2, "var_beta": None},
        {"var_alpha": 3, "var_beta": 3},
        {"var_alpha": 3.5, "var_beta": 3.5},
        {"var_alpha": 9},
        {"var_beta": 9},
        {"var_alpha": 9, "var_beta": 2, "extra": 0},
        {},
        [10, 5],
        "not an object",
        None,
    ]

    for _ in range(60):
        a = rng.randint(-10**9, 10**9)
        b = rng.randint(-10**9, 10**9)
        if rng.randrange(3) == 0:
            a += rng.random()
        if rng.randrange(3) == 0:
            b += rng.random()
        kind = rng.randrange(6)
        if kind == 0:
            if a == b:
                b += 1
            value = {"var_alpha": a, "var_beta": b}
        elif kind == 1:
            value = {"var_alpha": a, "var_beta": a}
        elif kind == 2:
            value = {"var_alpha": str(a), "var_beta": b}
        elif kind == 3:
            value = {"var_alpha": a, "var_beta": b, secrets.token_hex(5): rng.randint(0, 9)}
        elif kind == 4:
            value = {"var_alpha": a}
        else:
            value = {"var_alpha": rng.choice([None, True, [], {}]), "var_beta": b}
        cases.append(value)

    with tempfile.TemporaryDirectory(prefix="payload-check-" + secrets.token_hex(8) + "-") as root:
        neutral = os.path.join(root, "incoming files " + secrets.token_hex(6))
        os.makedirs(neutral)
        for index, value in enumerate(cases):
            path = os.path.join(neutral, f"request {secrets.token_hex(8)} {index}.json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(value, handle, allow_nan=False)
            result = run_sanitizer(os.path.abspath(path))
            assert result.returncode == expected_code(value), \
                f"Wrong exit code {result.returncode} for generated payload {value!r}"

        # Validity must depend on content, not clean/evil path labels.
        misleading_evil = os.path.join(root, "evil", "valid payload.json")
        misleading_clean = os.path.join(root, "clean", "invalid payload.json")
        os.makedirs(os.path.dirname(misleading_evil))
        os.makedirs(os.path.dirname(misleading_clean))
        with open(misleading_evil, "w", encoding="utf-8") as handle:
            json.dump({"var_alpha": 101, "var_beta": -37}, handle)
        with open(misleading_clean, "w", encoding="utf-8") as handle:
            json.dump({"var_alpha": 8, "var_beta": 8}, handle)
        assert run_sanitizer(misleading_evil).returncode == 0
        assert run_sanitizer(misleading_clean).returncode == 1


def test_malformed_inputs_are_rejected_without_crashing():
    malformed = [
        b"",
        b"{",
        b'{"var_alpha": 1, "var_beta": 2} trailing',
        b'{"var_alpha": NaN, "var_beta": 2}',
        b'{"var_alpha": Infinity, "var_beta": 2}',
        b'{"var_alpha": 1, "var_beta": 2,}',
        b'\xff\xfe\x00',
    ]
    with tempfile.TemporaryDirectory(prefix="malformed-" + secrets.token_hex(8) + "-") as root:
        for index, content in enumerate(malformed):
            path = os.path.join(root, f"input with spaces {index} {secrets.token_hex(5)}.json")
            with open(path, "wb") as handle:
                handle.write(content)
            assert run_sanitizer(os.path.abspath(path)).returncode == 1

        missing = os.path.join(root, "does not exist " + secrets.token_hex(5) + ".json")
        assert run_sanitizer(missing).returncode == 1
        assert run_sanitizer(root).returncode == 1


def test_exactly_one_argument_required():
    no_arg = subprocess.run(["python3", SANITIZER_SCRIPT], capture_output=True, timeout=5)
    assert no_arg.returncode == 1
    with tempfile.NamedTemporaryFile(suffix=".json") as handle:
        handle.write(b'{"var_alpha": 2, "var_beta": 1}')
        handle.flush()
        two_args = subprocess.run(
            ["python3", SANITIZER_SCRIPT, handle.name, handle.name],
            capture_output=True,
            timeout=5,
        )
    assert two_args.returncode == 1
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
