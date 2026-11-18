#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import pytest

BINARY_PATH = "/home/user/waf"
EXPECTED_SEED = "BYPASS_SEED:xyz_hx99_v2"


def run_waf(filename, description):
    input_data = f"{filename}\n{description}\n".encode("utf-8")
    try:
        result = subprocess.run(
            [BINARY_PATH],
            input=input_data,
            capture_output=True,
            timeout=2,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"WAF timed out for filename={filename!r}, description={description!r}")
    except Exception as exc:
        pytest.fail(f"WAF execution failed: {exc}")

    return result.stdout.decode("utf-8", errors="ignore").strip()


def mixed_case(value):
    return "".join(
        ch.upper() if ch.isalpha() and secrets.randbelow(2) else ch.lower()
        if ch.isalpha() else ch
        for ch in value
    )


def test_bypass_seed_recovered():
    """Check if the bypass seed was correctly recovered from the video."""
    seed_file = "/home/user/bypass_seed.txt"
    assert os.path.isfile(seed_file), f"Expected seed file not found at {seed_file}"

    with open(seed_file, "r") as f:
        content = f.read().strip()

    assert content == EXPECTED_SEED, (
        f"Incorrect seed recovered. Expected '{EXPECTED_SEED}', got '{content}'"
    )


def test_waf_binary_exists():
    """Check that both required WAF artifacts exist and the binary is executable."""
    source_path = "/home/user/waf.cpp"
    assert os.path.isfile(source_path), f"WAF source not found at {source_path}."
    assert os.path.isfile(BINARY_PATH), (
        f"WAF binary not found at {BINARY_PATH}. Did you compile your C++ code?"
    )
    assert os.access(BINARY_PATH, os.X_OK), f"WAF binary at {BINARY_PATH} is not executable."


def test_waf_adversarial_corpus():
    """Evaluate the WAF against the provided clean and evil corpora."""
    assert os.path.isfile(BINARY_PATH), "Cannot run WAF tests: binary missing."

    evil_dir = "/app/corpus/evil/"
    clean_dir = "/app/corpus/clean/"

    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    evil_files = sorted(
        f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))
    )
    clean_files = sorted(
        f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))
    )

    bypassed_evil = []
    for evil_file in evil_files:
        file_path = os.path.join(evil_dir, evil_file)
        with open(file_path, "rb") as f:
            input_data = f.read()
        try:
            result = subprocess.run(
                [BINARY_PATH], input=input_data, capture_output=True, timeout=2
            )
            output = result.stdout.decode("utf-8", errors="ignore").strip()
            if output != "REJECT":
                bypassed_evil.append(evil_file)
        except subprocess.TimeoutExpired:
            bypassed_evil.append(f"{evil_file} (Timeout)")
        except Exception as exc:
            bypassed_evil.append(f"{evil_file} (Error: {exc})")

    modified_clean = []
    for clean_file in clean_files:
        file_path = os.path.join(clean_dir, clean_file)
        with open(file_path, "rb") as f:
            input_data = f.read()
        try:
            result = subprocess.run(
                [BINARY_PATH], input=input_data, capture_output=True, timeout=2
            )
            output = result.stdout.decode("utf-8", errors="ignore").strip()
            if output != "ACCEPT":
                modified_clean.append(clean_file)
        except subprocess.TimeoutExpired:
            modified_clean.append(f"{clean_file} (Timeout)")
        except Exception as exc:
            modified_clean.append(f"{clean_file} (Error: {exc})")

    error_messages = []
    if bypassed_evil:
        error_messages.append(
            f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: "
            + ", ".join(bypassed_evil)
        )
    if modified_clean:
        error_messages.append(
            f"{len(modified_clean)} of {len(clean_files)} clean modified: "
            + ", ".join(modified_clean)
        )

    assert not error_messages, " | ".join(error_messages)


def test_waf_generated_hidden_cases():
    """Exercise the stated policy on fresh cases unavailable before verification."""
    cases = []

    traversal_forms = ["../", "%2e%2e%2f", "%2e%2e/", "..%2f"]
    for form in traversal_forms:
        for _ in range(5):
            token = secrets.token_hex(12)
            encoded_form = mixed_case(form) if "%" in form else form
            cases.append((f"uploads/{token}/{encoded_form}{token}.dat", f"Upload {token}", "REJECT"))

    xss_forms = ["<script>", "javascript:", "onerror=", "onload="]
    for form in xss_forms:
        for _ in range(5):
            token = secrets.token_hex(12)
            payload = mixed_case(form)
            cases.append((f"asset_{token}.bin", f"Metadata {token} {payload}alert(1)", "REJECT"))

    for index in range(8):
        token = secrets.token_hex(12)
        if index % 2:
            cases.append((f"{token}_{EXPECTED_SEED}.txt", f"Ordinary metadata {token}", "REJECT"))
        else:
            cases.append((f"ordinary_{token}.txt", f"{token} {EXPECTED_SEED} {token}", "REJECT"))

    extensions = ["pdf", "png", "jpg", "txt", "csv"]
    for _ in range(24):
        token_a = secrets.token_hex(12)
        token_b = secrets.token_hex(12)
        extension = extensions[secrets.randbelow(len(extensions))]
        cases.append((
            f"upload_{token_a}.{extension}",
            f"Normal file metadata {token_b} approved for storage",
            "ACCEPT",
        ))

    random.SystemRandom().shuffle(cases)
    failures = []
    for filename, description, expected in cases:
        actual = run_waf(filename, description)
        if actual != expected:
            failures.append(
                f"expected {expected}, got {actual!r} for filename={filename!r}, "
                f"description={description!r}"
            )

    assert not failures, "Generated corpus failures:\n" + "\n".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
