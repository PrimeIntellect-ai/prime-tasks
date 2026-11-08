#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import secrets
import subprocess
from pathlib import Path

import pytest

ROOT = Path('/home/user/incident')


def compile_cpp(source, output, extra_source=None):
    cmd = ['g++', '-std=c++17', '-O2']
    if extra_source is not None:
        cmd.append(str(extra_source))
    else:
        cmd.append(str(source))
    cmd += ['-o', str(output)]
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=30).returncode == 0


def cpp_tool_sources():
    excluded = {(ROOT / 'upload_server.cpp').resolve(),
                (ROOT / 'patched_server.cpp').resolve()}
    return [p for p in ROOT.rglob('*.cpp') if p.resolve() not in excluded]


def run_as_user(command):
    return subprocess.run(['runuser', '-u', 'user', '--'] + command,
                          cwd=str(ROOT), stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=20)


def test_phase1_patched_server():
    filepath = ROOT / 'patched_server.cpp'
    assert filepath.is_file(), f"Phase 1 failed: {filepath} is missing."

    content = filepath.read_text()
    assert 'ERROR: Invalid filename' in content, "Phase 1 failed: The patched server does not contain the exact error message 'ERROR: Invalid filename'."
    assert '..' in content or "'/'" in content or '"/"' in content, "Phase 1 failed: The patched server does not appear to check for '..' or '/'."

    harness = Path('/tmp/phase1_harness.cpp')
    harness.write_text(r'''#include <string>
#define main submitted_upload_main
#include "/home/user/incident/patched_server.cpp"
#undef main
int main() {
    const std::string error = "ERROR: Invalid filename";
    if (handle_upload("../passwd") != error) return 1;
    if (handle_upload("abc..def") != error) return 2;
    if (handle_upload("nested/file.txt") != error) return 3;
    if (handle_upload("/absolute") != error) return 4;
    if (handle_upload("safe.txt") != "Uploading to: /var/www/uploads/safe.txt") return 5;
    if (handle_upload("") != "Uploading to: /var/www/uploads/") return 6;
    return 0;
}
''')
    executable = Path('/tmp/phase1_harness')
    assert compile_cpp(None, executable, harness), 'Phase 1 failed: patched_server.cpp could not be compiled and exercised.'
    result = subprocess.run([str(executable)], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, 'Phase 1 failed: the patched handler does not implement the required filename validation and original valid-filename behavior.'


def test_phase2_attacker_username():
    output = ROOT / 'attacker_username.txt'
    assert output.is_file(), f"Phase 2 failed: {output} is missing."
    content = output.read_text().strip()
    assert content == 'sys_h4x0r', f"Phase 2 failed: Expected 'sys_h4x0r', but got '{content}'."

    sources = cpp_tool_sources()
    assert sources, 'Phase 2 failed: no C++ decoding program was created.'

    token_file = ROOT / 'tokens.txt'
    original_tokens = token_file.read_bytes()
    original_output = output.read_bytes()
    username = 'audit_' + secrets.token_hex(6)

    def encode_token(text):
        return bytes((b ^ 0x5A) for b in text.encode()).hex()

    challenge = '\n'.join([
        encode_token('ordinary_user:user'),
        encode_token(username + ':admin'),
        encode_token('service_account:reader'),
    ]) + '\n'

    worked = False
    try:
        token_file.write_text(challenge)
        for index, source in enumerate(sources):
            executable = Path(f'/tmp/phase2_tool_{index}')
            if not compile_cpp(source, executable):
                continue
            for args in ([], [str(token_file), str(output)]):
                output.unlink(missing_ok=True)
                try:
                    run_as_user([str(executable)] + args)
                except subprocess.TimeoutExpired:
                    continue
                if output.is_file() and output.read_text(errors='replace').strip() == username:
                    worked = True
                    break
            if worked:
                break
    finally:
        token_file.write_bytes(original_tokens)
        output.write_bytes(original_output)

    assert worked, 'Phase 2 failed: no submitted C++ program correctly decoded a verifier-generated Hex/XOR token set and selected its admin username.'


def test_phase3_decoded_payload():
    output = ROOT / 'decoded_payload.txt'
    assert output.is_file(), f"Phase 3 failed: {output} is missing."
    content = output.read_text().strip()
    expected_payload = '#!/bin/bash\nrm -rf /'
    assert content == expected_payload, 'Phase 3 failed: Decoded payload does not match expected output.'

    sources = cpp_tool_sources()
    assert sources, 'Phase 3 failed: no C++ payload-decoding tool was created.'

    payload_file = ROOT / 'payload.b64'
    original_payload = payload_file.read_bytes()
    original_output = output.read_bytes()
    plaintext = ('verification-' + secrets.token_hex(12) + '\nsecond-line').encode()
    encoded = base64.b64encode(bytes((b ^ 0x1F) for b in plaintext)) + b'\n'

    worked = False
    try:
        payload_file.write_bytes(encoded)
        for index, source in enumerate(sources):
            executable = Path(f'/tmp/phase3_tool_{index}')
            if not compile_cpp(source, executable):
                continue
            for args in ([], [str(payload_file), str(output)]):
                output.unlink(missing_ok=True)
                try:
                    run_as_user([str(executable)] + args)
                except subprocess.TimeoutExpired:
                    continue
                if output.is_file() and output.read_bytes().strip() == plaintext:
                    worked = True
                    break
            if worked:
                break
    finally:
        payload_file.write_bytes(original_payload)
        output.write_bytes(original_output)

    assert worked, 'Phase 3 failed: no submitted C++ tool correctly Base64-decoded and XOR-decrypted a verifier-generated payload.'


def test_phase4_compromised_file():
    output = ROOT / 'compromised_file.txt'
    assert output.is_file(), f"Phase 4 failed: {output} is missing."
    content = output.read_text().strip()
    assert content == 'ps', f"Phase 4 failed: Expected 'ps', but got '{content}'."

    expected_hashes = {}
    for line in (ROOT / 'hashes.md5').read_text().splitlines():
        fields = line.split(maxsplit=1)
        assert len(fields) == 2, 'Phase 4 failed: malformed known-good hash file.'
        expected_hashes[Path(fields[1].lstrip('*')).name] = fields[0].lower()

    mismatches = []
    for name, expected in expected_hashes.items():
        binary = ROOT / 'bin' / name
        assert binary.is_file(), f'Phase 4 failed: listed binary {name} is missing.'
        actual = hashlib.md5(binary.read_bytes()).hexdigest()
        if actual != expected:
            mismatches.append(name)

    assert len(mismatches) == 1, f'Phase 4 failed: expected one compromised binary, found {mismatches}.'
    assert content == mismatches[0], 'Phase 4 failed: compromised_file.txt does not identify the binary whose current MD5 differs from the known-good hash.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
