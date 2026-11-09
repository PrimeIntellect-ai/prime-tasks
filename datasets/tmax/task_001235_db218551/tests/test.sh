#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/validate_manifest.sh"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
EVIL_CORPUS_DIR = "/app/corpus/evil/"


def run_validator(path, *extra_args):
    try:
        return subprocess.run(
            ["bash", SCRIPT_PATH, path, *extra_args],
            capture_output=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Validator timed out on {path}")


def test_script_exists():
    """Test that the validation script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"Validation script missing at {SCRIPT_PATH}"


def test_adversarial_corpus():
    """Retain the original checks against the shipped clean and evil corpora."""
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus missing at {CLEAN_CORPUS_DIR}"
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus missing at {EVIL_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]

    assert len(clean_files) > 0, "Clean corpus is empty"
    assert len(evil_files) > 0, "Evil corpus is empty"

    failed_clean = []
    failed_evil = []

    for clean_file in clean_files:
        if run_validator(clean_file).returncode != 0:
            failed_clean.append(os.path.basename(clean_file))

    for evil_file in evil_files:
        if run_validator(evil_file).returncode == 0:
            failed_evil.append(os.path.basename(evil_file))

    error_messages = []
    if failed_clean:
        error_messages.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        error_messages.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def oracle(edges):
    """Derive validity directly from the memo's three graph rules."""
    nodes = set()
    parent = {}
    for child, ancestor in edges:
        nodes.add(child)
        nodes.add(ancestor)
        parent[child] = ancestor

    if "CORRUPT" in nodes:
        return False

    for start in nodes:
        if start == "MASTER":
            continue
        seen = set()
        current = start
        while current != "MASTER":
            if current in seen:
                return False
            seen.add(current)
            if current not in parent:
                return False
            current = parent[current]
    return True


def random_node(prefix):
    return f"{prefix}_{secrets.token_hex(8)}"


def make_cases():
    cases = []

    # Random valid rooted trees of varying depth and branching.
    for size in (1, 2, 4, 7, 11, 15):
        nodes = [random_node("backup") for _ in range(size)]
        edges = []
        available_parents = ["MASTER"]
        for node in nodes:
            edges.append((node, secrets.choice(available_parents)))
            available_parents.append(node)
        secrets.SystemRandom().shuffle(edges)
        cases.append(edges)

    # Random disconnected cycles, including self-cycles and longer cycles.
    for cycle_size in (1, 2, 3, 5):
        rooted = random_node("rooted")
        cyc = [random_node("cycle") for _ in range(cycle_size)]
        edges = [(rooted, "MASTER")]
        edges.extend((cyc[i], cyc[(i + 1) % cycle_size]) for i in range(cycle_size))
        secrets.SystemRandom().shuffle(edges)
        cases.append(edges)

    # Random chains ending at a non-MASTER root.
    for size in (1, 3, 8, 13):
        nodes = [random_node("orphan") for _ in range(size)]
        other_root = random_node("otherroot")
        edges = [(nodes[0], other_root)]
        edges.extend((nodes[i], nodes[i - 1]) for i in range(1, size))
        secrets.SystemRandom().shuffle(edges)
        cases.append(edges)

    # CORRUPT appearing as either a child or a parent in otherwise rooted data.
    for _ in range(3):
        good = random_node("good")
        cases.append([(good, "MASTER"), ("CORRUPT", good)])
        cases.append([(good, "CORRUPT")])

    return cases


def test_runtime_generated_hidden_manifests():
    """Exercise unpredictable paths and contents, with expected results derived here."""
    cases = make_cases()
    assert any(oracle(case) for case in cases)
    assert any(not oracle(case) for case in cases)

    with tempfile.TemporaryDirectory(prefix="manifest_checks_") as directory:
        for index, edges in enumerate(cases):
            path = os.path.join(directory, f"{secrets.token_hex(10)}_{index}.manifest")
            with open(path, "w", encoding="utf-8") as handle:
                for child, parent in edges:
                    handle.write(f"{child} {parent}\n")

            expected_valid = oracle(edges)
            result = run_validator(path)
            assert (result.returncode == 0) == expected_valid, (
                f"Incorrect result for generated manifest {index}; "
                f"expected {'valid' if expected_valid else 'invalid'}, "
                f"got exit code {result.returncode}"
            )


def test_requires_exactly_one_argument():
    with tempfile.TemporaryDirectory(prefix="argument_checks_") as directory:
        path = os.path.join(directory, f"{secrets.token_hex(10)}.manifest")
        node = random_node("arg")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(f"{node} MASTER\n")

        no_arg = subprocess.run(["bash", SCRIPT_PATH], capture_output=True, timeout=5)
        two_args = subprocess.run(["bash", SCRIPT_PATH, path, path], capture_output=True, timeout=5)
        assert no_arg.returncode != 0, "Validator accepted zero arguments"
        assert two_args.returncode != 0, "Validator accepted more than one argument"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
