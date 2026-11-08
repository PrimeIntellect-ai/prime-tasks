#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path


def test_pin_file_correct():
    pin_path = '/home/user/pin.txt'
    assert os.path.isfile(pin_path), f"Expected file {pin_path} does not exist. Did you save the PIN?"

    with open(pin_path, 'r') as f:
        pin_content = f.read().strip()

    assert pin_content == "4821", f"The PIN in {pin_path} is incorrect. Expected '4821', got '{pin_content}'."


def test_decrypted_file_exists():
    decrypted_path = '/home/user/decrypted.txt'
    assert os.path.isfile(decrypted_path), f"Expected file {decrypted_path} does not exist. Did you save the decrypted output?"

    with open(decrypted_path, 'r') as f:
        content = f.read()

    assert "C2_SERVER: evil-corp.local" in content, "The decrypted text does not contain expected C2_SERVER data."
    assert "4532111122223333" in content, "The decrypted text does not contain the expected credit card number."


def test_clean_report_correct():
    clean_path = '/home/user/clean_report.txt'
    assert os.path.isfile(clean_path), f"Expected file {clean_path} does not exist. Did you save the redacted output?"

    with open(clean_path, 'r') as f:
        content = f.read()

    expected_content = "C2_SERVER: evil-corp.local\nTARGET_CC: [REDACTED]\nSTATUS: ACTIVE\n"

    assert content.strip() == expected_content.strip(), (
        f"The content of {clean_path} does not match the expected redacted output.\n"
        f"Expected:\n{expected_content}\nGot:\n{content}"
    )

    assert "4532111122223333" not in content, "The 16-digit credit card number was not properly redacted in the clean report."


def test_c_program_bruteforces_and_decrypts_unseen_evidence():
    home = Path('/home/user')
    headers_path = home / 'evidence/headers.txt'
    payload_path = home / 'evidence/payload.bin'
    decrypted_path = home / 'decrypted.txt'
    pin_path = home / 'pin.txt'
    clean_path = home / 'clean_report.txt'

    candidates = sorted(home.rglob('*.c'))
    assert candidates, "No C source program was created or completed."

    managed = [headers_path, payload_path, decrypted_path, pin_path, clean_path]
    saved = {p: p.read_bytes() if p.is_file() else None for p in managed}

    pin = secrets.randbelow(10000)
    while pin == 4821:
        pin = secrets.randbelow(10000)
    session_id = (pin ^ 0x5A5A) + 12345
    marker = secrets.token_hex(24).encode('ascii')
    plaintext = b"DYNAMIC_C_TEST:" + marker + b"\nSECOND_LINE: verifier-generated\n"
    ciphertext = bytes(b ^ (pin % 256) for b in plaintext)
    headers = (
        "POST /api/exfil HTTP/1.1\n"
        "Host: 192.0.2.77\n"
        "User-Agent: verifier\n"
        f"Cookie: SessionID={session_id}; Tracking=DYNAMIC\n"
        "Content-Type: application/octet-stream\n"
        f"Content-Length: {len(ciphertext)}\n"
    ).encode('ascii')

    successes = []
    diagnostics = []
    try:
        for index, source in enumerate(candidates):
            headers_path.write_bytes(headers)
            payload_path.write_bytes(ciphertext)
            for output in (decrypted_path, pin_path, clean_path):
                try:
                    output.unlink()
                except FileNotFoundError:
                    pass

            executable = Path(tempfile.gettempdir()) / f'verifier_candidate_{index}'
            compile_result = subprocess.run(
                ['gcc', '-std=c11', '-O2', str(source), '-o', str(executable)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            if compile_result.returncode != 0:
                diagnostics.append(f"{source}: did not compile")
                continue

            try:
                run_result = subprocess.run(
                    [str(executable)],
                    cwd=str(home),
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )
            except subprocess.TimeoutExpired:
                diagnostics.append(f"{source}: timed out")
                continue

            decrypted_ok = decrypted_path.is_file() and decrypted_path.read_bytes() == plaintext
            pin_text = f'{pin:04d}'
            pin_file_ok = pin_path.is_file() and pin_path.read_text(errors='replace').strip() == pin_text
            stdout_ok = re.search(rf'(?<!\d){re.escape(pin_text)}(?!\d)', run_result.stdout) is not None

            if run_result.returncode == 0 and decrypted_ok and (pin_file_ok or stdout_ok):
                successes.append(str(source))
                break

            diagnostics.append(f"{source}: failed unseen SessionID/PIN/payload test")
    finally:
        for path, data in saved.items():
            if data is None:
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)

    assert successes, (
        "No submitted C program could be compiled and executed to brute-force an unseen "
        "SessionID and decrypt its corresponding payload. " + '; '.join(diagnostics)
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
