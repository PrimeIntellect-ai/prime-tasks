#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import binascii
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

PROJECT_DIR = Path('/home/user/forensic_tool')
REPORT_PATH = Path('/home/user/report.json')
EVIDENCE_DIR = Path('/home/user/evidence')


def get_expected_suid():
    bin_dir = '/home/user/evidence/bin'
    suid_binaries = []
    if not os.path.isdir(bin_dir):
        return suid_binaries

    for f in os.listdir(bin_dir):
        path = os.path.join(bin_dir, f)
        if os.path.isfile(path):
            st = os.stat(path)
            if st.st_mode & stat.S_ISUID:
                suid_binaries.append(f)
    return sorted(suid_binaries)


def get_expected_cn():
    cert_path = '/home/user/evidence/attacker.crt'
    if not os.path.isfile(cert_path):
        return 'c2.evilcorp.local'

    try:
        out = subprocess.check_output(
            ['openssl', 'x509', '-noout', '-subject', '-in', cert_path],
            stderr=subprocess.DEVNULL,
        ).decode('utf-8')
        match = re.search(r'CN\s*=\s*([^,\n]+)', out)
        if match:
            return match.group(1).strip()
    except Exception:
        pass

    return 'c2.evilcorp.local'


def get_expected_payload(cn):
    payload_path = '/home/user/evidence/payload.enc'
    if not os.path.isfile(payload_path):
        return ''

    with open(payload_path, 'r') as f:
        hex_data = f.read().strip()

    try:
        enc_bytes = binascii.unhexlify(hex_data)
        key_bytes = cn.encode('utf-8')
        dec_bytes = bytearray()
        for i in range(len(enc_bytes)):
            dec_bytes.append(enc_bytes[i] ^ key_bytes[i % len(key_bytes)])
        return dec_bytes.decode('utf-8')
    except Exception:
        return ''


def load_report():
    assert REPORT_PATH.is_file(), f'The final report file {REPORT_PATH} was not found.'
    try:
        with REPORT_PATH.open('r') as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'The file {REPORT_PATH} does not contain valid JSON.')


def assert_report(expected_suid, expected_cn, expected_payload):
    report = load_report()
    assert isinstance(report, dict), f'The JSON in {REPORT_PATH} must be an object (dictionary).'

    assert 'suid_binaries' in report, "The key 'suid_binaries' is missing from the JSON report."
    assert isinstance(report['suid_binaries'], list), "'suid_binaries' must be a list."
    assert sorted(report['suid_binaries']) == expected_suid, (
        f"The 'suid_binaries' list is incorrect. Expected {expected_suid}, "
        f"but got {report['suid_binaries']}."
    )
    assert report['suid_binaries'] == expected_suid, (
        f"The 'suid_binaries' list must be sorted alphabetically. "
        f"Expected {expected_suid}, but got {report['suid_binaries']}."
    )

    assert 'cert_common_name' in report, "The key 'cert_common_name' is missing from the JSON report."
    assert report['cert_common_name'] == expected_cn, (
        f"The 'cert_common_name' is incorrect. Expected '{expected_cn}', "
        f"but got '{report['cert_common_name']}'."
    )

    assert 'decoded_payload' in report, "The key 'decoded_payload' is missing from the JSON report."
    assert report['decoded_payload'] == expected_payload, (
        f"The 'decoded_payload' is incorrect. Expected '{expected_payload}', "
        f"but got '{report['decoded_payload']}'."
    )


def build_rust_binary():
    cargo_toml = PROJECT_DIR / 'Cargo.toml'
    assert PROJECT_DIR.is_dir(), f'The Rust project directory {PROJECT_DIR} was not found.'
    assert cargo_toml.is_file() and not cargo_toml.is_symlink(), 'Cargo.toml must be a regular file.'

    rust_sources = [
        p for p in (PROJECT_DIR / 'src').rglob('*.rs')
        if p.is_file() and not p.is_symlink()
    ] if (PROJECT_DIR / 'src').is_dir() else []
    assert rust_sources, 'The project must contain Rust source code under src/.'

    clean = subprocess.run(
        ['cargo', 'clean', '--manifest-path', str(cargo_toml)],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert clean.returncode == 0, f'cargo clean failed:\n{clean.stdout}'

    build = subprocess.run(
        ['cargo', 'build', '--manifest-path', str(cargo_toml), '--message-format=json-render-diagnostics'],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert build.returncode == 0, f'The Rust project failed to compile:\n{build.stdout}'

    executables = []
    for line in build.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get('reason') != 'compiler-artifact' or not message.get('executable'):
            continue
        if 'bin' in message.get('target', {}).get('kind', []):
            executables.append((message['target'].get('name'), Path(message['executable'])))

    assert executables, 'Cargo did not produce a Rust binary target.'

    metadata_result = subprocess.run(
        ['cargo', 'metadata', '--no-deps', '--format-version=1', '--manifest-path', str(cargo_toml)],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert metadata_result.returncode == 0, f'cargo metadata failed:\n{metadata_result.stderr}'
    metadata = json.loads(metadata_result.stdout)
    root_package = next(
        (p for p in metadata.get('packages', []) if Path(p['manifest_path']).resolve() == cargo_toml.resolve()),
        None,
    )
    default_run = root_package.get('default_run') if root_package else None

    if default_run:
        candidates = [path for name, path in executables if name == default_run]
        assert candidates, f"The configured default-run binary '{default_run}' was not built."
        executable = candidates[0]
    else:
        unique_paths = list(dict.fromkeys(path for _, path in executables))
        assert len(unique_paths) == 1, 'Multiple binary targets require package.default-run in Cargo.toml.'
        executable = unique_paths[0]

    assert executable.is_file(), 'The compiled Rust executable was not found.'
    with executable.open('rb') as f:
        assert f.read(4) == b'\x7fELF', 'The Cargo binary target is not a native executable.'
    return executable


def run_binary(executable):
    if REPORT_PATH.exists() or REPORT_PATH.is_symlink():
        REPORT_PATH.unlink()
    result = subprocess.run(
        [str(executable)],
        cwd=PROJECT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f'The compiled Rust program failed:\n{result.stdout}'
    assert REPORT_PATH.is_file(), 'Running the compiled Rust program did not create /home/user/report.json.'


def test_rust_project_is_compiled_run_and_analyzes_evidence():
    executable = build_rust_binary()

    with tempfile.TemporaryDirectory() as temp_dir:
        backup = Path(temp_dir) / 'evidence'
        shutil.copytree(EVIDENCE_DIR, backup, copy_function=shutil.copy2)

        token = uuid.uuid4().hex[:12]
        cn = f'triage-{token}.example'
        plaintext = f'dynamic_payload:{token}:uid=0'
        key_path = Path(temp_dir) / 'test.key'

        try:
            shutil.rmtree(EVIDENCE_DIR)
            bin_dir = EVIDENCE_DIR / 'bin'
            bin_dir.mkdir(parents=True)

            names = [f'zeta_{token}', f'alpha_{token}', f'normal_{token}']
            for name in names:
                path = bin_dir / name
                path.write_bytes(b'')
                os.chmod(path, 0o755)
            os.chmod(bin_dir / names[0], 0o4755)
            os.chmod(bin_dir / names[1], 0o4755)

            cert_result = subprocess.run(
                [
                    'openssl', 'req', '-x509', '-newkey', 'rsa:2048',
                    '-keyout', str(key_path), '-out', str(EVIDENCE_DIR / 'attacker.crt'),
                    '-days', '1', '-nodes', '-subj', f'/C=US/O=Triage/CN={cn}',
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert cert_result.returncode == 0, f'Failed to create test certificate: {cert_result.stderr}'

            key = cn.encode('utf-8')
            encoded = bytes(
                byte ^ key[i % len(key)]
                for i, byte in enumerate(plaintext.encode('utf-8'))
            )
            (EVIDENCE_DIR / 'payload.enc').write_text(binascii.hexlify(encoded).decode('ascii'))

            run_binary(executable)
            assert_report(sorted(names[:2]), cn, plaintext)
        finally:
            if EVIDENCE_DIR.exists():
                shutil.rmtree(EVIDENCE_DIR)
            shutil.copytree(backup, EVIDENCE_DIR, copy_function=shutil.copy2)

    run_binary(executable)


def test_report_json_exists_and_valid():
    report_path = '/home/user/report.json'
    assert os.path.isfile(report_path), f'The final report file {report_path} was not found.'

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {report_path} does not contain valid JSON.')

    assert isinstance(report, dict), f'The JSON in {report_path} must be an object (dictionary).'


def test_report_contents():
    report_path = '/home/user/report.json'
    if not os.path.isfile(report_path):
        pytest.skip('Report file missing, skipping content check.')

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.skip('Report file is not valid JSON, skipping content check.')

    expected_suid = get_expected_suid()
    expected_cn = get_expected_cn()
    expected_payload = get_expected_payload(expected_cn)

    assert 'suid_binaries' in report, "The key 'suid_binaries' is missing from the JSON report."
    assert isinstance(report['suid_binaries'], list), "'suid_binaries' must be a list."
    assert sorted(report['suid_binaries']) == expected_suid, (
        f"The 'suid_binaries' list is incorrect. Expected {expected_suid}, but got {report['suid_binaries']}."
    )
    assert report['suid_binaries'] == expected_suid, (
        f"The 'suid_binaries' list must be sorted alphabetically. Expected {expected_suid}, "
        f"but got {report['suid_binaries']}."
    )

    assert 'cert_common_name' in report, "The key 'cert_common_name' is missing from the JSON report."
    assert report['cert_common_name'] == expected_cn, (
        f"The 'cert_common_name' is incorrect. Expected '{expected_cn}', but got '{report['cert_common_name']}'."
    )

    assert 'decoded_payload' in report, "The key 'decoded_payload' is missing from the JSON report."
    assert report['decoded_payload'] == expected_payload, (
        f"The 'decoded_payload' is incorrect. Expected '{expected_payload}', but got '{report['decoded_payload']}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
