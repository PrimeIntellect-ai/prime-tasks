#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import uuid
from pathlib import Path

import pytest

APP_DIR = Path('/home/user/ticket_app')
PAYLOAD_PATH = Path('/home/user/bad_payload.json')
SESSION_PATH = Path('/home/user/session.txt')


def run_cargo(*args, timeout=180):
    result = subprocess.run(
        ['cargo', *args],
        cwd=APP_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, f"Cargo command failed: cargo {' '.join(args)}\n{result.stdout}"
    return result


def test_bad_payload_extracted():
    payload_path = '/home/user/bad_payload.json'
    assert os.path.isfile(payload_path), f'File not found: {payload_path}'

    with open(payload_path, 'rb') as f:
        content = f.read()

    expected_bytes = b'{"session":"req_8f7b2","user_id":42,"data":"bad\xffdata"}'
    assert content == expected_bytes, f'Content of {payload_path} does not match the exact expected byte sequence.'


def test_cargo_toml_fixed():
    cargo_path = '/home/user/ticket_app/Cargo.toml'
    assert os.path.isfile(cargo_path), f'File not found: {cargo_path}'

    with open(cargo_path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert 'serde' in content, 'serde dependency is missing in Cargo.toml.'
    assert 'derive' in content, "The 'derive' feature for serde is missing in Cargo.toml."


def test_session_extracted():
    session_path = '/home/user/session.txt'
    assert os.path.isfile(session_path), f'File not found: {session_path}. Did you run the Rust application?'

    with open(session_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    assert content == 'req_8f7b2', f"Content of {session_path} is incorrect. Expected 'req_8f7b2', got '{content}'."


def test_main_rs_modified():
    main_path = '/home/user/ticket_app/src/main.rs'
    assert os.path.isfile(main_path), f'File not found: {main_path}'

    with open(main_path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert 'Hello, world!' not in content or len(content.splitlines()) > 5, 'main.rs does not appear to have been implemented.'


def test_serde_derives_compile():
    bin_dir = APP_DIR / 'src' / 'bin'
    bin_dir.mkdir(parents=True, exist_ok=True)
    bin_name = 'verifier_derive_' + uuid.uuid4().hex
    probe = bin_dir / f'{bin_name}.rs'
    probe.write_text(
        '#[derive(serde::Serialize, serde::Deserialize)]\n'
        'struct Probe { value: String }\n'
        'fn main() {\n'
        '    let p = Probe { value: String::from("ok") };\n'
        '    let encoded = serde_json::to_string(&p).unwrap();\n'
        '    let _: Probe = serde_json::from_str(&encoded).unwrap();\n'
        '}\n',
        encoding='utf-8',
    )
    try:
        run_cargo('check', '--quiet', '--bin', bin_name)
    finally:
        probe.unlink(missing_ok=True)


def test_application_builds_and_processes_runtime_inputs():
    original_payload = PAYLOAD_PATH.read_bytes()
    token = uuid.uuid4().hex
    cases = [
        (
            {'data': 'bad-marker', 'user_id': 42, 'session': f'runtime_{token}'},
            f'runtime_{token}',
        ),
        (
            {'user_id': 42, 'session': f'escaped_{token}_\u2603', 'data': 'bad-marker'},
            f'escaped_{token}_\u2603',
        ),
    ]

    try:
        for obj, expected_session in cases:
            encoded = json.dumps(obj, ensure_ascii=True, separators=(',', ':')).encode('ascii')
            encoded = encoded.replace(b'bad-marker', b'bad\xffmarker', 1)
            PAYLOAD_PATH.write_bytes(encoded)
            SESSION_PATH.unlink(missing_ok=True)

            run_cargo('run', '--quiet')

            assert SESSION_PATH.is_file(), 'The Rust application did not create /home/user/session.txt.'
            actual = SESSION_PATH.read_text(encoding='utf-8').strip()
            assert actual == expected_session, (
                'The Rust application did not derive the session from the runtime payload. '
                f'Expected {expected_session!r}, got {actual!r}.'
            )
    finally:
        PAYLOAD_PATH.write_bytes(original_payload)
        SESSION_PATH.unlink(missing_ok=True)

    run_cargo('run', '--quiet')
    assert SESSION_PATH.is_file(), 'The Rust application did not recreate session.txt for the extracted payload.'
    assert SESSION_PATH.read_text(encoding='utf-8').strip() == 'req_8f7b2'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
