#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/audit_query.py"
CLEAN_DIR = "/app/tests/clean/"
EVIL_DIR = "/app/tests/evil/"


def run_auditor(filepath):
    return subprocess.run(
        ["python3", SCRIPT_PATH, filepath],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_script_exists():
    """Verify that the agent created the audit script."""
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"


def test_clean_corpus():
    """Verify that the script accepts all clean queries."""
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.cypher"))
    assert len(clean_files) > 0, f"No clean files found in {CLEAN_DIR}"

    failed_files = []
    for filepath in clean_files:
        result = run_auditor(filepath)
        if result.returncode != 0 or "ACCEPT" not in result.stdout:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean queries rejected/modified incorrectly. Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    """Verify that the script rejects all evil queries."""
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.cypher"))
    assert len(evil_files) > 0, f"No evil files found in {EVIL_DIR}"

    failed_files = []
    for filepath in evil_files:
        result = run_auditor(filepath)
        if result.returncode != 1 or "REJECT" not in result.stdout:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil queries bypassed the filter. Offending files: {', '.join(failed_files)}")


def test_generated_queries_at_unclassified_paths():
    """Exercise newly generated queries whose paths do not reveal their class."""
    labels = ["Person", "Employee", "ShellCompanyArchive", "shellcompany", "ShellCompany"]
    relationships = ["WORKS_FOR", "TRANSFERRED_TO", "KICKBACK_TO_LEGACY", "kickback_to", "KICKBACK_TO"]

    # Include every label and relationship at least once, then add random combinations.
    pairs = [(label, "WORKS_FOR") for label in labels]
    pairs += [("Person", relationship) for relationship in relationships]
    rng = random.SystemRandom()
    pairs += [(rng.choice(labels), rng.choice(relationships)) for _ in range(18)]
    rng.shuffle(pairs)

    failures = []
    with tempfile.TemporaryDirectory(prefix=f"audit-{secrets.token_hex(8)}-") as query_dir:
        for label, relationship in pairs:
            left = f"n{secrets.token_hex(4)}"
            right = f"n{secrets.token_hex(4)}"
            query = (
                f"MATCH ({left}:{label})-[r:{relationship}]->"
                f"({right}:Company) RETURN {left}, {right}\n"
            )
            expected_reject = label == "ShellCompany" or relationship == "KICKBACK_TO"
            expected_status = 1 if expected_reject else 0
            expected_stdout = "REJECT" if expected_reject else "ACCEPT"

            filepath = os.path.join(query_dir, f"{secrets.token_hex(12)}.cypher")
            with open(filepath, "w", encoding="utf-8") as query_file:
                query_file.write(query)

            result = run_auditor(filepath)
            if result.returncode != expected_status or result.stdout.strip() != expected_stdout:
                failures.append(
                    f"label={label!r}, relationship={relationship!r}, "
                    f"status={result.returncode}, stdout={result.stdout!r}"
                )

    if failures:
        pytest.fail("Generated query failures:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
