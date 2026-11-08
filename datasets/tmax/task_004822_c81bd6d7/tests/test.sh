#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import shutil
import string
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont

SCRIPT_PATH = "/home/user/audit_filter.py"
CLEAN_DIR = "/app/clean"
EVIL_DIR = "/app/evil"
MEMO_PATH = "/app/policy_memo.png"
SALT = "COMPLIANCE_v7_8923"


def process_file(input_file, output_file):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, input_file, output_file],
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result.returncode == 0


def compute_expected_evil(data, salt=SALT):
    out = json.loads(json.dumps(data))

    # Rule 1: Sensitive Data Redaction
    if "payload" in out and isinstance(out["payload"], dict) and "password" in out["payload"]:
        pwd = out["payload"]["password"]
        if isinstance(pwd, str):
            is_hash = len(pwd) == 64 and all(c in "0123456789abcdef" for c in pwd)
            if not is_hash:
                out["payload"]["password"] = f"[REDACTED: {salt}]"

    # Rule 2: Exploit Delivery Detection
    for section in ["payload", "headers"]:
        if section in out and isinstance(out[section], dict):
            for k, v in out[section].items():
                if isinstance(v, str):
                    v_lower = v.lower()
                    if "<script>" in v_lower or "${jndi:" in v_lower:
                        out[section][k] = "[EXPLOIT_BLOCKED]"

    # Rule 3: CSP Enforcement
    has_csp = False
    if "headers" in out and isinstance(out["headers"], dict) and "Content-Security-Policy" in out["headers"]:
        csp = out["headers"]["Content-Security-Policy"]
        if isinstance(csp, str) and "default-src 'self'" in csp:
            has_csp = True

    if not has_csp:
        out["COMPLIANCE_WARNING"] = "MISSING_CSP"

    return out


def run_generated_case(data, salt=SALT):
    with tempfile.TemporaryDirectory() as tmpdir:
        nonce = secrets.token_hex(12)
        input_file = os.path.join(tmpdir, f"request-{nonce}.json")
        output_file = os.path.join(tmpdir, f"result-{secrets.token_hex(12)}.json")
        with open(input_file, "w", encoding="utf-8") as f:
            json.dump(data, f)

        assert process_file(input_file, output_file), "Sanitizer exited unsuccessfully"
        assert os.path.isfile(output_file), "Sanitizer did not create its output file"
        with open(output_file, "r", encoding="utf-8") as f:
            out_data = json.load(f)

        assert out_data == compute_expected_evil(data, salt)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.json"))
    assert len(clean_files) > 0, "No clean files found."

    modified_files = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for input_file in clean_files:
            basename = os.path.basename(input_file)
            output_file = os.path.join(tmpdir, basename)

            success = process_file(input_file, output_file)
            if not success or not os.path.exists(output_file):
                modified_files.append(basename)
                continue

            with open(input_file, "r") as f:
                in_data = json.load(f)
            with open(output_file, "r") as f:
                try:
                    out_data = json.load(f)
                except json.JSONDecodeError:
                    modified_files.append(basename)
                    continue

            if in_data != out_data:
                modified_files.append(basename)

    assert not modified_files, f"{len(modified_files)} of {len(clean_files)} clean files modified or failed: {', '.join(modified_files)}"


def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.json"))
    assert len(evil_files) > 0, "No evil files found."

    bypassed_files = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for input_file in evil_files:
            basename = os.path.basename(input_file)
            output_file = os.path.join(tmpdir, basename)

            success = process_file(input_file, output_file)
            if not success or not os.path.exists(output_file):
                bypassed_files.append(basename)
                continue

            with open(input_file, "r") as f:
                in_data = json.load(f)
            with open(output_file, "r") as f:
                try:
                    out_data = json.load(f)
                except json.JSONDecodeError:
                    bypassed_files.append(basename)
                    continue

            expected_data = compute_expected_evil(in_data)

            if out_data != expected_data:
                bypassed_files.append(basename)

    assert not bypassed_files, f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed or failed: {', '.join(bypassed_files)}"


def test_randomized_inputs_and_rule_combinations():
    token = secrets.token_hex(10)
    random_key = "field_" + secrets.token_hex(6)
    valid_csp = "default-src 'self'; object-src 'none'; report-to " + token
    lower_hash = secrets.token_hex(32)
    upper_hash = lower_hash.upper()

    cases = [
        {
            "endpoint": "/clean/" + token,
            "method": "POST",
            "headers": {"Content-Security-Policy": valid_csp, random_key: token},
            "payload": {"username": token, "password": lower_hash},
            "request_id": secrets.token_hex(8),
        },
        {
            "endpoint": "/plaintext/" + token,
            "headers": {"Content-Security-Policy": valid_csp},
            "payload": {"username": token, "password": "plain-" + secrets.token_hex(9)},
        },
        {
            "headers": {"Content-Security-Policy": valid_csp},
            "payload": {"password": upper_hash, random_key: token},
        },
        {
            "headers": {"Content-Security-Policy": valid_csp},
            "payload": {"password": 73491, random_key: token},
        },
        {
            "headers": {
                "Content-Security-Policy": valid_csp,
                random_key: "prefix<ScRiPt>suffix-" + token,
            },
            "payload": {"password": lower_hash, "note": "safe-" + token},
        },
        {
            "headers": {"Content-Security-Policy": valid_csp},
            "payload": {
                "password": lower_hash,
                random_key: "prefix${JnDi:ldap://" + token + "}suffix",
            },
        },
        {
            "headers": {random_key: token},
            "payload": {"password": lower_hash},
        },
        {
            "headers": {"Content-Security-Policy": "default-src https://" + token},
            "payload": {"password": lower_hash},
        },
        {
            "headers": {"Content-Security-Policy": valid_csp},
            "payload": {"password": "before<SCRIPT>after-" + token},
        },
        {
            "headers": {"Content-Security-Policy": valid_csp},
            "payload": {"password": lower_hash},
            random_key: "<script>top-level-is-outside-scanned-sections</script>",
        },
    ]

    for case in cases:
        run_generated_case(case)


def test_salt_is_read_from_policy_memo_with_ocr():
    assert os.path.isfile(MEMO_PATH), "Policy memo is missing"
    backup = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
    backup.close()
    shutil.copyfile(MEMO_PATH, backup.name)

    dynamic_salt = "AUDIT_v8_" + "".join(secrets.choice(string.digits) for _ in range(10))
    replacement = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
    replacement.close()

    try:
        img = Image.new("RGB", (1000, 200), color="white")
        draw = ImageDraw.Draw(img)
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 30
        )
        draw.text(
            (10, 50),
            "MANDATORY REDACTION SALT: " + dynamic_salt,
            font=font,
            fill="black",
        )
        img.save(replacement.name)
        os.replace(replacement.name, MEMO_PATH)

        data = {
            "endpoint": "/ocr-check/" + secrets.token_hex(8),
            "headers": {"Content-Security-Policy": "default-src 'self'"},
            "payload": {
                "username": secrets.token_hex(7),
                "password": "plaintext-" + secrets.token_hex(8),
            },
        }
        run_generated_case(data, dynamic_salt)
    finally:
        shutil.copyfile(backup.name, MEMO_PATH)
        os.unlink(backup.name)
        if os.path.exists(replacement.name):
            os.unlink(replacement.name)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
