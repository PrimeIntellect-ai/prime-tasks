#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import re
import secrets
import subprocess
import tempfile
import pytest

DETECTOR_SCRIPT = "/home/user/detector.sh"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
BATS_EXEC = "/app/bats-core/bin/bats"


def test_detector_script_exists_and_executable():
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector script not found at {DETECTOR_SCRIPT}"
    assert os.access(DETECTOR_SCRIPT, os.X_OK), f"Detector script {DETECTOR_SCRIPT} is not executable"


def test_bats_core_fixed():
    assert os.path.isfile(BATS_EXEC), f"Bats executable {BATS_EXEC} is missing."

    with open(BATS_EXEC, "r") as f:
        first_line = f.readline().strip()

    assert first_line != "#!/bin/broken-bash", "The shebang in bats-core is still broken."

    # Check if it runs successfully
    try:
        result = subprocess.run([BATS_EXEC, "-v"], capture_output=True, text=True, check=True)
        assert "Bats 1.9.0" in result.stdout, f"Expected 'Bats 1.9.0' in output, got: {result.stdout}"
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to execute bats-core: {e.stderr}")
    except OSError as e:
        pytest.fail(f"Failed to execute bats-core (OS error): {e}")


def test_clean_corpus_accepted():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, "No files found in clean corpus directory."

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        result = subprocess.run([DETECTOR_SCRIPT, filepath], capture_output=True)
        if result.returncode != 0:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files rejected (should be accepted): {', '.join(failed_files)}")


def test_evil_corpus_rejected():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, "No files found in evil corpus directory."

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        result = subprocess.run([DETECTOR_SCRIPT, filepath], capture_output=True)
        if result.returncode != 1:
            failed_files.append(filename)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (should be rejected): {', '.join(failed_files)}")


def reference_rejects(content):
    patterns = (
        r"-----BEGIN .* PRIVATE KEY-----",
        r"AKIA[A-Z0-9]{16}",
        r"(?:Bearer |Bearer%20)[A-Za-z0-9._-]{20,}",
    )
    return any(re.search(pattern, content) for pattern in patterns)


def random_chars(alphabet, length):
    return "".join(secrets.choice(alphabet) for _ in range(length))


def test_generated_log_contents_match_required_patterns():
    upper_alnum = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    token_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
    nonce = secrets.token_hex(12)
    aws16 = random_chars(upper_alnum, 16)
    token20 = random_chars(token_chars, 20)
    token37 = random_chars(token_chars, 37)

    cases = [
        f"{nonce} ordinary authentication event completed\n",
        f"prefix-{nonce} AKIA{aws16} suffix-{secrets.token_hex(5)}\n",
        f"Authorization: Bearer {token20}\n",
        f"request token=Bearer%20{token37} status=failed\n",
        f"audit: -----BEGIN {secrets.token_hex(8)} PRIVATE KEY----- trailing text\n",
        "audit: -----BEGIN  PRIVATE KEY-----\n",
        f"AKIA{random_chars(upper_alnum, 15)}\n",
        f"AKIB{random_chars(upper_alnum, 16)}\n",
        f"Authorization: Bearer {random_chars(token_chars, 19)}\n",
        f"token=Bearer%2F{random_chars(token_chars, 30)}\n",
        f"-----BEGIN {secrets.token_hex(6)} PUBLIC KEY-----\n",
        f"-----BEGIN {secrets.token_hex(6)}\n PRIVATE KEY-----\n",
        f"Bearer\t{random_chars(token_chars, 30)}\n",
        f"akia{random_chars(upper_alnum, 16)}\n",
    ]

    # Add fresh mixed logs whose positions and values cannot be inferred from paths.
    for _ in range(12):
        filler = f"event={secrets.token_hex(10)} user={secrets.token_hex(4)}"
        kind = secrets.randbelow(4)
        if kind == 0:
            content = filler
        elif kind == 1:
            content = filler + " AKIA" + random_chars(upper_alnum, 16)
        elif kind == 2:
            separator = secrets.choice(["Bearer ", "Bearer%20"])
            content = filler + " " + separator + random_chars(token_chars, 20 + secrets.randbelow(25))
        else:
            content = filler + " -----BEGIN " + secrets.token_hex(7) + " PRIVATE KEY-----"
        cases.append(content + "\n")

    random.SystemRandom().shuffle(cases)
    probe_dir = tempfile.mkdtemp(prefix="detector-probes-")
    failures = []

    for content in cases:
        path = os.path.join(probe_dir, secrets.token_hex(12))
        with open(path, "w", encoding="utf-8") as probe:
            probe.write(content)

        expected = 1 if reference_rejects(content) else 0
        try:
            result = subprocess.run(
                [DETECTOR_SCRIPT, path],
                capture_output=True,
                text=True,
                timeout=5,
            )
        except subprocess.TimeoutExpired:
            failures.append(f"{os.path.basename(path)} timed out; expected exit {expected}")
            continue

        if result.returncode != expected:
            failures.append(
                f"{os.path.basename(path)} returned {result.returncode}; expected {expected}"
            )

    if failures:
        pytest.fail("Generated content checks failed: " + "; ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
