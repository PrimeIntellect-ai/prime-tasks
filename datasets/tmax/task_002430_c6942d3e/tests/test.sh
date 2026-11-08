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

VALIDATOR_SCRIPT = "/home/user/build_validator.py"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"


def run_validator(filepath):
    return subprocess.run(
        ["python3", VALIDATOR_SCRIPT, filepath],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_validator_script_exists():
    """Ensure the student created the build_validator.py script."""
    assert os.path.isfile(VALIDATOR_SCRIPT), f"Validator script not found at {VALIDATOR_SCRIPT}"


def test_clean_corpus():
    """Assert that every original clean corpus file is accepted."""
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*"))
    assert len(clean_files) > 0, f"No files found in clean corpus directory {CLEAN_DIR}"

    failures = []
    for filepath in clean_files:
        result = run_validator(filepath)
        if result.returncode != 0 or "VALID" not in result.stdout.strip().upper():
            failures.append(os.path.basename(filepath))

    if failures:
        pytest.fail(f"{len(failures)} of {len(clean_files)} clean modified/rejected: {', '.join(failures)}")


def test_evil_corpus():
    """Assert that every original evil corpus file is rejected."""
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*"))
    assert len(evil_files) > 0, f"No files found in evil corpus directory {EVIL_DIR}"

    failures = []
    for filepath in evil_files:
        result = run_validator(filepath)
        if result.returncode != 1 or "INVALID" not in result.stdout.strip().upper():
            failures.append(os.path.basename(filepath))

    if failures:
        pytest.fail(f"{len(failures)} of {len(evil_files)} evil bypassed: {', '.join(failures)}")


def test_generated_manifests_on_neutral_random_paths():
    """Exercise architecture and command checks without clean/evil path labels."""
    allowed = {
        "Frontend": ("APIGateway",),
        "APIGateway": ("AuthService", "UserDatabase"),
        "AuthService": ("AuthDatabase",),
    }
    services = {
        "Frontend", "APIGateway", "AuthService", "UserDatabase", "AuthDatabase"
    }
    nonce = secrets.token_hex(8)
    safe_command = f"printf '%s\\n' build-{nonce}"

    cases = []

    # Valid manifests use exactly the dependencies shown by the architecture.
    for target, dependencies in allowed.items():
        cases.append((
            f"Target: {target}\n"
            f"Depends-On: {', '.join(dependencies)}\n"
            f"Cmd: {safe_command}\n",
            True,
        ))

    # Derive invalid edges as the complement of the architecture's allowed edges.
    allowed_edges = {
        (target, dependency)
        for target, dependencies in allowed.items()
        for dependency in dependencies
    }
    for target in allowed:
        for dependency in services:
            if (target, dependency) not in allowed_edges:
                cases.append((
                    f"Target: {target}\n"
                    f"Depends-On: {dependency}\n"
                    f"Cmd: {safe_command}\n",
                    False,
                ))

    # Unknown services cannot satisfy the extracted architecture.
    unknown = f"UnknownService{nonce}"
    cases.append((
        f"Target: Frontend\nDepends-On: {unknown}\nCmd: {safe_command}\n",
        False,
    ))

    # Keep dependencies valid so these cases specifically exercise command parsing.
    dangerous_commands = [
        f"echo $(printf {nonce})",
        f"echo `printf {nonce}`",
        f"echo $(echo $(printf {nonce}))",
        "bash -i >& /dev/tcp/127.0.0.1/4444 0>&1",
        "0<&196; exec 196<>/dev/tcp/127.0.0.1/5555; sh <&196 >&196 2>&196",
        # A shell line continuation turns this into command substitution.
        f"echo $\\\n(printf {nonce})",
    ]
    for command in dangerous_commands:
        cases.append((
            "Target: Frontend\n"
            "Depends-On: APIGateway\n"
            f"Cmd: {command}\n",
            False,
        ))

    random.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix=f"validator-{nonce}-") as directory:
        failures = []
        for index, (manifest, should_accept) in enumerate(cases):
            filepath = os.path.join(directory, f"case-{secrets.token_hex(6)}-{index}.manifest")
            with open(filepath, "w", encoding="utf-8") as handle:
                handle.write(manifest)

            result = run_validator(filepath)
            expected_code = 0 if should_accept else 1
            expected_output = "VALID" if should_accept else "INVALID"
            if result.returncode != expected_code or result.stdout.strip().upper() != expected_output:
                failures.append(
                    f"case {index}: expected {expected_output}/{expected_code}, "
                    f"got {result.stdout.strip()!r}/{result.returncode}"
                )

        if failures:
            pytest.fail("Generated manifest failures:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
