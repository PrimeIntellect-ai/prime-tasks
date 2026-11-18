#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import struct
import subprocess
from pathlib import Path


def test_payload_bin_content():
    payload_bin_path = "/home/user/payload.bin"
    assert os.path.isfile(payload_bin_path), f"File {payload_bin_path} is missing. The payload was not decrypted."

    c2_ip = bytes([192, 168, 137, 42])
    c2_port = struct.pack('!H', 4444)
    expected_plain = (
        b'\x7FELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' +
        b'A' * 50 +
        b'C2_START' +
        c2_ip +
        c2_port +
        b'B' * 20
    )

    with open(payload_bin_path, 'rb') as f:
        actual_plain = f.read()

    assert actual_plain == expected_plain, "The decrypted payload in /home/user/payload.bin does not match the expected plaintext."


def test_firewall_rule_content():
    firewall_rule_path = "/home/user/firewall_rule.txt"
    assert os.path.isfile(firewall_rule_path), f"File {firewall_rule_path} is missing. The firewall rule was not saved."

    expected_rule = "iptables -A OUTPUT -d 192.168.137.42 -p tcp --dport 4444 -j DROP"

    with open(firewall_rule_path, 'r') as f:
        actual_rule = f.read().strip()

    assert actual_rule == expected_rule, f"The firewall rule in {firewall_rule_path} is incorrect. Expected: '{expected_rule}', but got: '{actual_rule}'"


def _looks_like_bruteforce_c(source):
    text = source.lower()
    alphabet_domain = (("'a'" in text and "'z'" in text) or
                       'abcdefghijklmnopqrstuvwxyz' in text)
    loop_count = len(re.findall(r'\b(?:for|while)\s*\(', text))
    full_keyspace = ('456976' in text or
                     re.search(r'26\s*\*\s*26\s*\*\s*26\s*\*\s*26', text) or
                     (re.search(r'%\s*26', text) and re.search(r'/\s*26', text)))
    enumerates_four_positions = loop_count >= 4 or bool(full_keyspace)
    has_xor = '^' in source
    return alphabet_domain and enumerates_four_positions and has_xor


def test_c_bruteforce_implementation_executes():
    home = Path('/home/user')
    evidence = home / 'evidence' / 'payload.enc'
    payload = home / 'payload.bin'
    firewall = home / 'firewall_rule.txt'

    candidates = sorted(home.rglob('*.c'))
    assert candidates, "No C source program was written under /home/user."

    original_enc = evidence.read_bytes()
    original_payload = payload.read_bytes() if payload.exists() else None
    original_rule = firewall.read_bytes() if firewall.exists() else None

    keys = [b'qzmt', b'bnxy']
    configurations = [
        (bytes([10, 23, 45, 67]), 31337, b'Q', b'R'),
        (bytes([172, 19, 201, 8]), 8087, b'M', b'N'),
    ]
    failures = []

    try:
        for index, source_path in enumerate(candidates):
            source = source_path.read_text(errors='replace')
            if not _looks_like_bruteforce_c(source):
                failures.append(f"{source_path}: source does not enumerate the four-letter lowercase keyspace using XOR")
                continue

            executable = Path(f'/tmp/decryptor_candidate_{index}')
            compiled = subprocess.run(
                ['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', str(source_path), '-o', str(executable)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )
            if compiled.returncode != 0:
                failures.append(f"{source_path}: compilation failed: {compiled.stderr[-500:]}")
                continue

            candidate_ok = True
            for key, (ip_bytes, port, fill_a, fill_b) in zip(keys, configurations):
                plain = (
                    b'\x7FELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00' +
                    fill_a * 50 + b'C2_START' + ip_bytes + struct.pack('!H', port) + fill_b * 20
                )
                encrypted = bytes(byte ^ key[i % 4] for i, byte in enumerate(plain))
                evidence.write_bytes(encrypted)
                payload.unlink(missing_ok=True)
                firewall.unlink(missing_ok=True)

                try:
                    run = subprocess.run(
                        [str(executable)], cwd='/home/user',
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        timeout=20
                    )
                except subprocess.TimeoutExpired:
                    failures.append(f"{source_path}: executable timed out")
                    candidate_ok = False
                    break

                expected_rule = (
                    f"iptables -A OUTPUT -d {'.'.join(map(str, ip_bytes))} "
                    f"-p tcp --dport {port} -j DROP"
                )
                if run.returncode != 0:
                    failures.append(f"{source_path}: executable returned {run.returncode}")
                    candidate_ok = False
                    break
                if not payload.is_file() or payload.read_bytes() != plain:
                    failures.append(f"{source_path}: did not decrypt a verifier-generated payload correctly")
                    candidate_ok = False
                    break
                if not firewall.is_file() or firewall.read_text().strip() != expected_rule:
                    failures.append(f"{source_path}: did not extract the verifier-generated C2 endpoint correctly")
                    candidate_ok = False
                    break

            if candidate_ok:
                return

        assert False, "No submitted C brute-force program compiled and worked on generated evidence. " + " | ".join(failures)
    finally:
        evidence.write_bytes(original_enc)
        if original_payload is None:
            payload.unlink(missing_ok=True)
        else:
            payload.write_bytes(original_payload)
        if original_rule is None:
            firewall.unlink(missing_ok=True)
        else:
            firewall.write_bytes(original_rule)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
