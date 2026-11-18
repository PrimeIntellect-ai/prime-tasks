#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import stat
import string
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/check_py3_ready.sh"
EVIL_CORPUS_DIR = "/app/corpora/evil/"
CLEAN_CORPUS_DIR = "/app/corpora/clean/"

def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."

def test_adversarial_corpus():
    # Ensure corpora directories exist
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus directory {EVIL_CORPUS_DIR} missing."
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus directory {CLEAN_CORPUS_DIR} missing."

    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.py')]
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.py')]

    assert len(evil_files) > 0, "No python files found in evil corpus."
    assert len(clean_files) > 0, "No python files found in clean corpus."

    evil_bypassed = []
    clean_rejected = []

    # Test evil corpus
    for evil_file in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, evil_file)
        result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(evil_file)

    # Test clean corpus
    for clean_file in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, clean_file)
        result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            clean_rejected.append(clean_file)

    error_messages = []
    if evil_bypassed:
        error_messages.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}"
        )
    if clean_rejected:
        error_messages.append(
            f"{len(clean_rejected)} of {len(clean_files)} clean rejected: {', '.join(clean_rejected)}"
        )

    if error_messages:
        pytest.fail(" | ".join(error_messages))

def test_generated_files_at_neutral_paths():
    rng = random.SystemRandom()

    def token(prefix):
        return prefix + ''.join(rng.choice(string.ascii_lowercase) for _ in range(12))

    generated = []
    for _ in range(8):
        spaces = ' ' * rng.randint(1, 7)
        indent = ' ' * rng.randint(0, 6)
        name = token('value_')
        text = token('message_')

        # Forbidden Python 2 print statements and urllib2 imports.
        generated.extend([
            (f"{indent}print{spaces}\"{text}\"\n", 1),
            (f"{name} = 3\n{indent}print{spaces}{name}\n", 1),
            (f"import{spaces}urllib2\n", 1),
            (f"from{spaces}urllib2{spaces}import{spaces}urlopen\n", 1),
            (f"import os,{spaces}urllib2\n", 1),
        ])

        # Similar text that is not either forbidden construct.
        generated.extend([
            (f"print{spaces}(\"{text}\")\n", 0),
            (f"# print{spaces}\"{text}\"\nprint(\"ok\")\n", 0),
            (f"{name} = \"import urllib2\"\nprint({name})\n", 0),
            (f"# import{spaces}urllib2\nimport urllib.request\n", 0),
            (f"from urllib import request\nprint( \"{text}\" )\n", 0),
        ])

    rng.shuffle(generated)
    failures = []
    with tempfile.TemporaryDirectory(prefix="pycheck_" + secrets.token_hex(8) + "_") as directory:
        for index, (source, expected) in enumerate(generated):
            filename = secrets.token_hex(16) + ".py"
            filepath = os.path.join(directory, filename)
            with open(filepath, "w", encoding="utf-8") as handle:
                handle.write(source)
            result = subprocess.run([SCRIPT_PATH, filepath], capture_output=True)
            if result.returncode != expected:
                failures.append(
                    f"case {index}: expected {expected}, got {result.returncode}, source={source!r}"
                )

    assert not failures, "Generated cases misclassified: " + " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
