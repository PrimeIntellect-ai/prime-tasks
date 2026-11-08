#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
import secrets
import string
import uuid
import pytest

SCRIPT_PATH = "/home/user/log_sanitizer.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_OUT_DIR = "/tmp/clean_out"
EVIL_OUT_DIR = "/tmp/evil_out"

CODENAME_PATTERN = re.compile(r'(?i)operation crimson hawk')
TLS_CN_PATTERN = re.compile(re.escape(r'badguy.exfil.net'))
TOKEN_PATTERN = re.compile(r'X-Auth-Token: [A-Za-z0-9]{32}')

HIDDEN_INPUT_DIR = None
HIDDEN_OUTPUT_DIR = None
HIDDEN_EXPECTED = {}

def apply_sanitization(text: str) -> str:
    text = CODENAME_PATTERN.sub('[REDACTED_CODENAME]', text)
    text = TLS_CN_PATTERN.sub('[REDACTED_TLS_CN]', text)
    text = TOKEN_PATTERN.sub('[REDACTED_TOKEN]', text)
    return text

def random_text(length=24):
    return ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(length))

def random_case(text):
    return ''.join(
        ch.upper() if ch.isalpha() and secrets.randbelow(2) else ch.lower() if ch.isalpha() else ch
        for ch in text
    )

@pytest.fixture(scope="session", autouse=True)
def run_sanitizer():
    global HIDDEN_INPUT_DIR, HIDDEN_OUTPUT_DIR, HIDDEN_EXPECTED

    assert os.path.isfile(SCRIPT_PATH), f"Sanitizer script not found at {SCRIPT_PATH}"

    for d in [CLEAN_OUT_DIR, EVIL_OUT_DIR]:
        if os.path.exists(d):
            shutil.rmtree(d)
        os.makedirs(d)

    clean_proc = subprocess.run(
        ["python3", SCRIPT_PATH, CLEAN_CORPUS_DIR, CLEAN_OUT_DIR],
        capture_output=True, text=True
    )
    assert clean_proc.returncode == 0, f"Script failed on clean corpus:\n{clean_proc.stderr}"

    evil_proc = subprocess.run(
        ["python3", SCRIPT_PATH, EVIL_CORPUS_DIR, EVIL_OUT_DIR],
        capture_output=True, text=True
    )
    assert evil_proc.returncode == 0, f"Script failed on evil corpus:\n{evil_proc.stderr}"

    hidden_root = tempfile.mkdtemp(prefix="sanitizer_validation_")
    HIDDEN_INPUT_DIR = os.path.join(hidden_root, "incoming_" + secrets.token_hex(8))
    HIDDEN_OUTPUT_DIR = os.path.join(hidden_root, "processed_" + secrets.token_hex(8))
    os.makedirs(HIDDEN_INPUT_DIR)
    os.makedirs(HIDDEN_OUTPUT_DIR)

    token1 = random_text(32)
    token2 = random_text(32)
    codename1 = random_case("Operation Crimson Hawk")
    codename2 = random_case("Operation Crimson Hawk")
    nonce1 = random_text()
    nonce2 = random_text()

    generated_cases = [
        f"{nonce1}: connection to badguy.exfil.net accepted.\n",
        f"request={nonce2} X-Auth-Token: {token1} status=forwarded\n",
        f"briefing says {codename1}; unrelated value={random_text()}\n",
        f"badguy.exfil.net | X-Auth-Token: {token2} | {codename2}\n",
        f"Repeated {codename1}, then {codename2}; hosts badguy.exfil.net and badguy.exfil.net.\n",
        f"Clean event {random_text()}: Operation Blue Falcon; X-Auth-Token-Legacy: false; legitimate.net\n",
        f"Near misses: operation crimson hawks, badguyXexfilXnet, X-Auth-Token: {random_text(31)}\n",
    ]

    for content in generated_cases:
        filename = f"capture_{uuid.uuid4().hex}.log"
        with open(os.path.join(HIDDEN_INPUT_DIR, filename), "w", encoding="utf-8") as f:
            f.write(content)
        HIDDEN_EXPECTED[filename] = apply_sanitization(content)

    hidden_proc = subprocess.run(
        ["python3", SCRIPT_PATH, HIDDEN_INPUT_DIR, HIDDEN_OUTPUT_DIR],
        capture_output=True, text=True
    )
    assert hidden_proc.returncode == 0, f"Script failed on generated hidden corpus:\n{hidden_proc.stderr}"

def test_clean_corpus_preserved():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert len(clean_files) > 0, f"No files found in clean corpus {CLEAN_CORPUS_DIR}"

    modified_files = []
    missing_files = []

    for filename in clean_files:
        orig_path = os.path.join(CLEAN_CORPUS_DIR, filename)
        out_path = os.path.join(CLEAN_OUT_DIR, filename)

        if not os.path.exists(out_path):
            missing_files.append(filename)
            continue

        with open(orig_path, 'r', encoding='utf-8') as f:
            orig_content = f.read()
        with open(out_path, 'r', encoding='utf-8') as f:
            out_content = f.read()

        if orig_content != out_content:
            modified_files.append(filename)

    errors = []
    if missing_files:
        errors.append(f"{len(missing_files)} clean files missing in output: {', '.join(missing_files)}")
    if modified_files:
        errors.append(f"{len(modified_files)} of {len(clean_files)} clean files modified: {', '.join(modified_files)}")

    assert not errors, "Clean corpus validation failed:\n" + "\n".join(errors)

def test_evil_corpus_sanitized():
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert len(evil_files) > 0, f"No files found in evil corpus {EVIL_CORPUS_DIR}"

    bypassed_files = []
    missing_files = []

    for filename in evil_files:
        orig_path = os.path.join(EVIL_CORPUS_DIR, filename)
        out_path = os.path.join(EVIL_OUT_DIR, filename)

        if not os.path.exists(out_path):
            missing_files.append(filename)
            continue

        with open(orig_path, 'r', encoding='utf-8') as f:
            orig_content = f.read()

        expected_content = apply_sanitization(orig_content)

        with open(out_path, 'r', encoding='utf-8') as f:
            out_content = f.read()

        if expected_content != out_content:
            bypassed_files.append(filename)

    errors = []
    if missing_files:
        errors.append(f"{len(missing_files)} evil files missing in output: {', '.join(missing_files)}")
    if bypassed_files:
        errors.append(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed (incorrectly sanitized): {', '.join(bypassed_files)}")

    assert not errors, "Evil corpus validation failed:\n" + "\n".join(errors)

def test_generated_hidden_corpus_sanitized():
    assert HIDDEN_EXPECTED, "Generated hidden corpus was not created"

    missing_files = []
    incorrect_files = []
    for filename, expected_content in HIDDEN_EXPECTED.items():
        out_path = os.path.join(HIDDEN_OUTPUT_DIR, filename)
        if not os.path.isfile(out_path):
            missing_files.append(filename)
            continue
        with open(out_path, 'r', encoding='utf-8') as f:
            out_content = f.read()
        if out_content != expected_content:
            incorrect_files.append(filename)

    errors = []
    if missing_files:
        errors.append(f"{len(missing_files)} generated files missing in output: {', '.join(missing_files)}")
    if incorrect_files:
        errors.append(f"{len(incorrect_files)} generated files incorrectly processed: {', '.join(incorrect_files)}")
    assert not errors, "Generated hidden corpus validation failed:\n" + "\n".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
