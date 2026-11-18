#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from pathlib import Path

HOME = Path('/home/user')
BIN_DIR = HOME / 'binaries'
SCANNER = HOME / 'audit_scanner.sh'
LOG = HOME / 'audit_trail.log'
BLOCK = HOME / 'block_ips.sh'


def run_scanner():
    for output in (LOG, BLOCK):
        if output.exists():
            output.unlink()
    subprocess.run(['bash', str(SCANNER)], cwd=str(HOME), check=True, timeout=30)


def check_artifacts(expected_pairs):
    assert LOG.is_file(), f'The log file {LOG} does not exist.'
    lines = [line.strip() for line in LOG.read_text().splitlines() if line.strip()]
    expected_lines = [
        f'VULNERABLE_BINARY:{name},BLOCKED_IP:{ip}'
        for name, ip in expected_pairs
    ]
    assert len(lines) == len(expected_lines), (
        f'Expected {len(expected_lines)} lines in {LOG}, found {len(lines)}.'
    )
    for expected, actual in zip(expected_lines, lines):
        assert actual == expected, f"Expected line '{expected}', but got '{actual}' in {LOG}."

    assert BLOCK.is_file(), f'The script {BLOCK} does not exist.'
    block_lines = [line.strip() for line in BLOCK.read_text().splitlines() if line.strip()]
    assert len(block_lines) >= 1, f'The script {BLOCK} is empty.'
    assert block_lines[0] == '#!/bin/bash', f"The first line of {BLOCK} must be '#!/bin/bash'."

    expected_iptables = [
        f'iptables -A OUTPUT -d {ip} -j DROP'
        for _, ip in expected_pairs
    ]
    actual_iptables = [line for line in block_lines[1:] if line.startswith('iptables')]
    assert len(actual_iptables) == len(expected_iptables), (
        f'Expected {len(expected_iptables)} iptables commands, found {len(actual_iptables)}.'
    )
    for expected, actual in zip(expected_iptables, actual_iptables):
        assert ' '.join(actual.split()) == ' '.join(expected.split()), (
            f"Expected command '{expected}', but got '{actual}' in {BLOCK}."
        )


def expected_from_binaries():
    ipv4_pattern = re.compile(rb'(?<![0-9.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9.])')
    result = []
    for path in sorted(BIN_DIR.iterdir(), key=lambda p: p.name):
        if not path.is_file() or path.read_bytes()[:4] != b'\x7fELF':
            continue
        headers = subprocess.run(
            ['readelf', '-W', '-l', str(path)],
            check=True, capture_output=True, text=True
        ).stdout
        stack_lines = [line for line in headers.splitlines() if 'GNU_STACK' in line]
        assert stack_lines, f'{path} has no GNU_STACK program header'
        flags = stack_lines[0].split()[-2]
        if 'E' not in flags:
            continue
        candidates = []
        for raw in ipv4_pattern.findall(path.read_bytes()):
            value = raw.decode('ascii')
            if all(0 <= int(part) <= 255 for part in value.split('.')):
                candidates.append(value)
        candidates = list(dict.fromkeys(candidates))
        assert len(candidates) == 1, f'Expected exactly one IPv4 string in vulnerable ELF {path}'
        result.append((path.name, candidates[0]))
    return result


def test_scanner_and_generated_artifacts():
    assert SCANNER.is_file(), f'The script {SCANNER} does not exist.'

    # Execute the submitted scanner and retain all original exact-content checks.
    run_scanner()
    check_artifacts([
        ('app2', '192.168.50.5'),
        ('app3', '172.16.0.25'),
    ])

    # Add unpredictable ELF inputs, then rerun to ensure the scanner performs
    # ELF-header analysis and IPv4 extraction rather than hardcoding artifacts.
    suffix = secrets.token_hex(6)
    vulnerable_name = f'probe_vulnerable_{suffix}'
    safe_name = f'probe_safe_{suffix}'
    vulnerable_ip = f'198.51.100.{secrets.randbelow(200) + 20}'
    safe_ip = f'192.0.2.{secrets.randbelow(200) + 20}'
    source_dir = Path('/tmp') / f'audit_probe_{suffix}'
    source_dir.mkdir()
    vulnerable_source = source_dir / 'vulnerable.c'
    safe_source = source_dir / 'safe.c'
    vulnerable_source.write_text(
        f'const char *volatile indicator = "{vulnerable_ip}"; int main(void) {{ return indicator[0] == 0; }}\n'
    )
    safe_source.write_text(
        f'const char *volatile indicator = "{safe_ip}"; int main(void) {{ return indicator[0] == 0; }}\n'
    )
    subprocess.run(
        ['gcc', str(vulnerable_source), '-o', str(BIN_DIR / vulnerable_name), '-z', 'execstack'],
        check=True
    )
    subprocess.run(
        ['gcc', str(safe_source), '-o', str(BIN_DIR / safe_name), '-z', 'noexecstack'],
        check=True
    )

    run_scanner()
    check_artifacts(expected_from_binaries())


if __name__ == '__main__':
    test_scanner_and_generated_artifacts()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
