#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
import uuid
from pathlib import Path

import pytest

HOME = Path('/home/user')
REPORT = HOME / 'audit_report.json'
DATA = HOME / 'audit_data'


def prepare_rust_runner():
    manifests = sorted(
        (p for p in HOME.rglob('Cargo.toml') if 'target' not in p.parts and '.cargo' not in p.parts),
        key=lambda p: (len(p.parts), str(p)),
    )

    for manifest in manifests:
        metadata = subprocess.run(
            ['cargo', 'metadata', '--no-deps', '--format-version', '1', '--manifest-path', str(manifest)],
            cwd=str(manifest.parent), capture_output=True, text=True, timeout=60,
        )
        if metadata.returncode != 0:
            continue
        try:
            info = json.loads(metadata.stdout)
        except json.JSONDecodeError:
            continue

        packages = info.get('packages', [])
        direct = [p for p in packages if Path(p['manifest_path']).resolve() == manifest.resolve()]
        considered = direct or packages
        bins = []
        for package in considered:
            for target in package.get('targets', []):
                if 'bin' in target.get('kind', []):
                    src = Path(target['src_path'])
                    try:
                        src.resolve().relative_to(HOME.resolve())
                    except ValueError:
                        continue
                    bins.append((package['name'], target['name'], src))
        if bins:
            package, binary, source = bins[0]
            assert source.is_file(), f'Rust binary source {source} is missing'
            return {
                'command': [
                    'cargo', 'run', '--quiet', '--manifest-path', str(manifest),
                    '--package', package, '--bin', binary,
                ],
                'cwd': manifest.parent,
            }

    main_files = sorted(
        (p for p in HOME.rglob('main.rs') if 'target' not in p.parts and '.cargo' not in p.parts),
        key=lambda p: (len(p.parts), str(p)),
    )
    assert main_files, 'No Rust Cargo binary or standalone main.rs was found under /home/user'
    source = main_files[0]
    binary = Path('/tmp/submitted_audit_program')
    compile_result = subprocess.run(
        ['rustc', str(source), '-o', str(binary)],
        cwd=str(source.parent), capture_output=True, text=True, timeout=120,
    )
    assert compile_result.returncode == 0, (
        'Failed to compile the submitted Rust program:\n'
        + compile_result.stdout + compile_result.stderr
    )
    return {'command': [str(binary)], 'cwd': source.parent}


def run_program(runner):
    if REPORT.exists():
        REPORT.unlink()
    result = subprocess.run(
        runner['command'], cwd=str(runner['cwd']), capture_output=True,
        text=True, timeout=120,
    )
    assert result.returncode == 0, (
        'The submitted Rust program failed:\n' + result.stdout + result.stderr
    )
    assert REPORT.is_file(), 'The Rust program did not generate /home/user/audit_report.json'


def get_expected_state():
    headers_path = "/home/user/audit_data/headers.txt"
    log_path = "/home/user/audit_data/service.log"
    nmap_path = "/home/user/audit_data/scan.nmap"

    # 1. Extract leaked token
    leaked_token = None
    with open(headers_path, "r") as f:
        for line in f:
            if line.lower().startswith("x-old-cred-token:"):
                leaked_token = line.split(":", 1)[1].strip()
                break

    assert leaked_token is not None, "Could not find X-Old-Cred-Token in headers.txt"

    # 2. Extract compromised IPs
    compromised_ips = set()
    with open(log_path, "r") as f:
        for line in f:
            parts = line.split()
            if len(parts) < 10:
                continue
            ip = parts[0]
            # Standard combined log format: IP - - [date] "request" status bytes "-" "user-agent" "token"
            # We can use regex to parse it more reliably
            match = re.search(r'^(\S+).*" (\d{3}) \d+ ".*" ".*" "([^"]+)"\s*$', line)
            if match:
                log_ip, status, token = match.groups()
                if status == "200" and token == leaked_token:
                    compromised_ips.add(log_ip)

    # 3. Extract unauthorized ports
    unauthorized_ports = set()
    authorized = {22, 80, 443}
    with open(nmap_path, "r") as f:
        for line in f:
            match = re.match(r'^(\d+)/tcp\s+open\s+', line)
            if match:
                port = int(match.group(1))
                if port not in authorized:
                    unauthorized_ports.add(port)

    return {
        "leaked_token": leaked_token,
        "compromised_ips": sorted(list(compromised_ips)),
        "unauthorized_ports": sorted(list(unauthorized_ports))
    }


def test_00_rust_program_runs_and_handles_changed_inputs():
    runner = prepare_rust_runner()
    files = [DATA / 'headers.txt', DATA / 'service.log', DATA / 'scan.nmap']
    originals = {path: path.read_bytes() for path in files}

    # First prove the submitted Rust artifact can generate the report at all.
    run_program(runner)

    token = 'verification-' + uuid.uuid4().hex
    ip_a = f'203.0.113.{random.randint(10, 99)}'
    ip_b = f'198.51.100.{random.randint(100, 199)}'
    port_a = random.randint(10000, 20000)
    port_b = random.randint(40000, 50000)

    headers = (
        'HTTP/1.1 200 OK\n'
        'Server: verifier\n'
        f'X-Old-Cred-Token: {token}\n'
        'Connection: close\n'
    )
    logs = (
        f'{ip_a} - - [11/Sep/2026:01:00:00 +0000] "GET /one HTTP/1.1" 200 10 "-" "agent-a" "{token}"\n'
        f'{ip_b} - - [11/Sep/2026:01:01:00 +0000] "POST /two HTTP/1.1" 200 20 "-" "agent-b" "{token}"\n'
        f'{ip_a} - - [11/Sep/2026:01:02:00 +0000] "GET /again HTTP/1.1" 200 30 "-" "agent-c" "{token}"\n'
        f'192.0.2.25 - - [11/Sep/2026:01:03:00 +0000] "GET /denied HTTP/1.1" 403 40 "-" "agent-d" "{token}"\n'
        f'192.0.2.26 - - [11/Sep/2026:01:04:00 +0000] "GET /wrong HTTP/1.1" 200 50 "-" "agent-e" "wrong-{token}"\n'
    )
    scan = (
        'PORT      STATE  SERVICE\n'
        '22/tcp    open   ssh\n'
        '80/tcp    open   http\n'
        '443/tcp   open   https\n'
        f'{port_b}/tcp open   dynamic-b\n'
        f'{port_a}/tcp open   dynamic-a\n'
        '9999/tcp  closed ignored\n'
        '5353/udp  open   mdns\n'
    )

    try:
        (DATA / 'headers.txt').write_text(headers)
        (DATA / 'service.log').write_text(logs)
        (DATA / 'scan.nmap').write_text(scan)
        expected = get_expected_state()
        run_program(runner)
        try:
            report = json.loads(REPORT.read_text())
        except json.JSONDecodeError as exc:
            pytest.fail(f'The Rust program generated invalid JSON for changed inputs: {exc}')

        assert report.get('leaked_token') == expected['leaked_token']
        assert report.get('compromised_ips') == expected['compromised_ips']
        assert report.get('unauthorized_ports') == expected['unauthorized_ports']
    finally:
        for path, contents in originals.items():
            path.write_bytes(contents)
        # Leave the required final report generated by the Rust program from the original fixtures.
        run_program(runner)


def test_audit_report_exists_and_valid():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"Output file {report_path} is missing. The Rust program must generate this file."

    with open(report_path, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    expected_data = get_expected_state()

    assert "leaked_token" in report_data, "Key 'leaked_token' missing from JSON output."
    assert report_data["leaked_token"] == expected_data["leaked_token"], \
        f"Expected leaked_token '{expected_data['leaked_token']}', got '{report_data['leaked_token']}'"

    assert "compromised_ips" in report_data, "Key 'compromised_ips' missing from JSON output."
    assert isinstance(report_data["compromised_ips"], list), "'compromised_ips' must be a list."
    assert report_data["compromised_ips"] == expected_data["compromised_ips"], \
        f"Expected compromised_ips {expected_data['compromised_ips']}, got {report_data['compromised_ips']}"

    assert "unauthorized_ports" in report_data, "Key 'unauthorized_ports' missing from JSON output."
    assert isinstance(report_data["unauthorized_ports"], list), "'unauthorized_ports' must be a list."
    assert report_data["unauthorized_ports"] == expected_data["unauthorized_ports"], \
        f"Expected unauthorized_ports {expected_data['unauthorized_ports']}, got {report_data['unauthorized_ports']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
