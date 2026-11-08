#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/query_validator.py"


def run_validator(path):
    return subprocess.run(
        ["python3", SCRIPT_PATH, path],
        capture_output=True,
        text=True,
        timeout=5,
    )


def test_query_validator_exists():
    """Ensure the user created the query validator script."""
    assert os.path.exists(SCRIPT_PATH), f"Missing script: {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Not a file: {SCRIPT_PATH}"


def test_adversarial_corpus():
    """Retain the original checks against the clean and evil corpora."""
    clean_dir = "/app/clean/"
    evil_dir = "/app/evil/"

    clean_files = glob.glob(os.path.join(clean_dir, "*.cypher"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.cypher"))

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    clean_failures = []
    for cf in clean_files:
        result = run_validator(cf)
        if result.returncode != 0 or result.stdout.strip() != "VALID":
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        result = run_validator(ef)
        if result.returncode != 1 or result.stdout.strip() != "INVALID":
            evil_failures.append(os.path.basename(ef))

    error_messages = []
    if clean_failures:
        error_messages.append(
            f"{len(clean_failures)} of {len(clean_files)} clean files rejected/failed: "
            + ", ".join(clean_failures)
        )
    if evil_failures:
        error_messages.append(
            f"{len(evil_failures)} of {len(evil_files)} evil files bypassed: "
            + ", ".join(evil_failures)
        )

    if error_messages:
        assert False, " | ".join(error_messages)


def test_generated_queries_at_same_hidden_path():
    """Exercise generated valid and invalid queries without revealing status in the path."""
    rng = random.SystemRandom()

    # (path form, maximum depth or None for unbounded, has ORDER BY, LIMIT value)
    specs = [
        ("upper", rng.randint(1, 4), True, rng.randint(1, 50)),
        ("range", rng.randint(1, 4), True, rng.randint(1, 50)),
        ("exact", rng.randint(1, 4), True, rng.randint(1, 50)),
        ("upper", rng.randint(5, 12), True, rng.randint(1, 50)),
        ("range", rng.randint(5, 12), True, rng.randint(1, 50)),
        ("exact", rng.randint(5, 12), True, rng.randint(1, 50)),
        ("unbounded", None, True, rng.randint(1, 50)),
        ("range", rng.randint(1, 4), False, rng.randint(1, 50)),
        ("upper", rng.randint(1, 4), True, None),
        ("exact", rng.randint(1, 4), True, rng.randint(51, 500)),
        ("unbounded", None, False, None),
    ]

    # Add independently generated combinations; expectations are computed from
    # their rule attributes rather than from filenames or fixed labels.
    for _ in range(20):
        form = rng.choice(["upper", "range", "exact", "unbounded"])
        maximum = None if form == "unbounded" else rng.randint(1, 10)
        has_order = rng.choice([True, False])
        limit = rng.choice([None, rng.randint(1, 50), rng.randint(51, 300)])
        specs.append((form, maximum, has_order, limit))

    rng.shuffle(specs)

    def keyword(word):
        return rng.choice([word.lower(), word.upper(), word.title()])

    failures = []
    with tempfile.TemporaryDirectory(prefix="cypher_validator_") as temp_dir:
        # Every case reuses this exact path, so validity cannot be inferred from it.
        query_path = os.path.join(temp_dir, "query.cypher")

        for index, (form, maximum, has_order, limit) in enumerate(specs):
            if form == "unbounded":
                relationship = "[:REL*]"
            elif form == "upper":
                relationship = f"[:REL*..{maximum}]"
            elif form == "range":
                lower = rng.randint(1, maximum)
                relationship = f"[:REL*{lower}..{maximum}]"
            else:
                relationship = f"[:REL*{maximum}]"

            clauses = [
                f"{keyword('MATCH')} (a)-{relationship}->(b)",
                f"{keyword('RETURN')} b",
            ]
            if has_order:
                clauses.append(
                    f"{keyword('ORDER')}{' ' * rng.randint(1, 5)}{keyword('BY')} b.id"
                )
            if limit is not None:
                clauses.append(f"{keyword('LIMIT')}{' ' * rng.randint(1, 5)}{limit}")

            separator = rng.choice([" ", "\n", "  \n  "])
            query = separator.join(clauses) + "\n"
            with open(query_path, "w", encoding="utf-8") as query_file:
                query_file.write(query)

            complies = (
                maximum is not None
                and maximum <= 4
                and has_order
                and limit is not None
                and limit <= 50
            )
            expected_stdout = "VALID" if complies else "INVALID"
            expected_code = 0 if complies else 1

            result = run_validator(query_path)
            if result.returncode != expected_code or result.stdout.strip() != expected_stdout:
                failures.append(
                    f"case {index}: expected ({expected_code}, {expected_stdout}), "
                    f"got ({result.returncode}, {result.stdout.strip()!r}) for {query!r}"
                )

    assert not failures, "Generated-query failures: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
