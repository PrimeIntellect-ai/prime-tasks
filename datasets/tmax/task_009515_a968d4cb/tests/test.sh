#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/root/.cargo/bin:/home/user/.cargo/bin:$PATH"

cat <<'PY_EOF' > /tmp/verify_log_analyzer.py
import csv
import ipaddress
import json
import os
import re
import secrets
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/log_analyzer')
AUTH = Path('/home/user/logs/auth.csv')
APP = Path('/home/user/logs/app.jsonl')
OUTPUT = Path('/home/user/flagged_ips.json')
PIPELINE_LOG = Path('/home/user/pipeline.log')
EXPECTED_LOG = [
    '[INFO] Pipeline started',
    '[INFO] Processing auth.csv',
    '[INFO] Processing app.jsonl',
    '[INFO] Pipeline finished',
]

def get_expected_ips():
    failed_counts = {}
    if AUTH.exists():
        with AUTH.open('r', encoding='utf-8') as f:
            for row in csv.DictReader(f):
                ip_str = row.get('ip_address', '')
                if row.get('status', '') == 'FAILED':
                    try:
                        ipaddress.IPv4Address(ip_str)
                        failed_counts[ip_str] = failed_counts.get(ip_str, 0) + 1
                    except ipaddress.AddressValueError:
                        pass

    auth_suspects = {ip for ip, count in failed_counts.items() if count > 3}
    app_error_ips = set()
    pattern = re.compile(r'\b(?:\d{1,3}\.){3}\d{1,3}\b')
    if APP.exists():
        with APP.open('r', encoding='utf-8') as f:
            for line in f:
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if record.get('level') == 'ERROR':
                    for match in pattern.findall(record.get('msg', '')):
                        try:
                            ipaddress.IPv4Address(match)
                            app_error_ips.add(match)
                        except ipaddress.AddressValueError:
                            pass
    return sorted(auth_suspects & app_error_ips)

def assert_elf(path):
    assert path.is_file(), f'Release executable {path} does not exist.'
    assert os.access(path, os.X_OK), f'Release executable {path} is not executable.'
    with path.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'{path} is not an ELF executable.'

def run_and_check(binary):
    if OUTPUT.exists():
        OUTPUT.unlink()
    PIPELINE_LOG.write_text('', encoding='utf-8')
    subprocess.run([str(binary)], cwd=str(PROJECT), check=True, timeout=30)

    assert OUTPUT.exists(), f'Output file {OUTPUT} does not exist.'
    try:
        flagged = json.loads(OUTPUT.read_text(encoding='utf-8'))
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {OUTPUT} does not contain valid JSON: {exc}')
    assert isinstance(flagged, list), f'Expected a JSON array in {OUTPUT}.'
    assert all(isinstance(ip, str) for ip in flagged), 'Every flagged IP must be a string.'
    expected = get_expected_ips()
    assert sorted(flagged) == expected, f'Flagged IPs do not match expected. Found: {flagged}, Expected: {expected}'
    assert flagged == sorted(flagged), f'Flagged IPs are not alphabetically sorted: {flagged}'

    assert PIPELINE_LOG.exists(), f'Log file {PIPELINE_LOG} does not exist.'
    lines = PIPELINE_LOG.read_text(encoding='utf-8').splitlines()
    for line in EXPECTED_LOG:
        assert line in lines, f"Expected log line '{line}' not found in {PIPELINE_LOG}."
    assert lines == EXPECTED_LOG, f'Pipeline log lines are not the exact required lines in order: {lines}'

def random_ip(used):
    while True:
        ip = f'10.{secrets.randbelow(250) + 1}.{secrets.randbelow(256)}.{secrets.randbelow(254) + 1}'
        if ip not in used:
            used.add(ip)
            return ip

def write_dynamic_inputs():
    used = set()
    correlated1 = random_ip(used)
    below_threshold = random_ip(used)
    wrong_level = random_ip(used)
    correlated2 = random_ip(used)

    rows = ['timestamp,ip_address,status,username']
    n = 0
    def add(ip, status, username='user'):
        nonlocal n
        n += 1
        rows.append(f'2026-01-01T00:00:{n:02d}Z,{ip},{status},{username}')
    for _ in range(4): add(correlated1, 'FAILED')
    for _ in range(3): add(below_threshold, 'FAILED')
    for _ in range(5): add(wrong_level, 'FAILED')
    for _ in range(6): add(correlated2, 'FAILED')
    add(correlated1, 'SUCCESS')
    add(correlated2, 'failed')
    add('999.999.999.999', 'FAILED')
    add('01.2.3.4', 'FAILED')
    AUTH.write_text('\n'.join(rows) + '\n', encoding='utf-8')

    records = [
        {'ts':'x', 'level':'INFO', 'msg':f'ordinary event from {correlated1}'},
        {'ts':'x', 'level':'ERROR', 'msg':f'connection from ({correlated1}) failed'},
        {'ts':'x', 'level':'ERROR', 'msg':f'retry source={below_threshold}'},
        {'ts':'x', 'level':'WARN', 'msg':f'warning source {wrong_level}'},
        {'ts':'x', 'level':'ERROR', 'msg':f'peers 999.2.3.4 and {correlated2} disconnected'},
        {'ts':'x', 'level':'error', 'msg':f'lowercase level {wrong_level}'},
    ]
    APP.write_text('\n'.join(json.dumps(x) for x in records) + '\n{malformed json\n', encoding='utf-8')
    return sorted([correlated1, correlated2])

def main():
    assert PROJECT.is_dir(), f'Rust project directory {PROJECT} does not exist.'
    assert (PROJECT / 'Cargo.toml').is_file(), 'Cargo.toml does not exist.'
    sources = list((PROJECT / 'src').rglob('*.rs'))
    assert sources, 'No Rust source files exist under log_analyzer/src.'
    source_text = '\n'.join(p.read_text(encoding='utf-8', errors='replace') for p in sources)
    assert re.search(r'BufReader|BufRead|csv::Reader|ReaderBuilder|serde_json::Deserializer', source_text), \
        'Rust source does not use a streaming reader.'
    assert not re.search(r'\bread_to_string\b|\bread_to_end\b|std::fs::read\s*\(', source_text), \
        'Rust source appears to load an entire input file instead of streaming it.'

    metadata = json.loads(subprocess.check_output(
        ['cargo', 'metadata', '--format-version', '1', '--no-deps'], cwd=str(PROJECT), text=True
    ))
    bins = [t['name'] for p in metadata['packages'] for t in p['targets'] if 'bin' in t['kind']]
    assert bins, 'Cargo project has no binary target.'
    target_dir = Path(metadata['target_directory']) / 'release'
    existing = [target_dir / name for name in bins if (target_dir / name).is_file()]
    assert existing, 'No previously compiled release executable exists; cargo build --release was not run.'
    for path in existing:
        assert_elf(path)

    for src in sources:
        os.utime(src, None)
    subprocess.run(['cargo', 'build', '--release'], cwd=str(PROJECT), check=True, timeout=180)
    binary = target_dir / bins[0]
    assert_elf(binary)

    paths = [AUTH, APP, OUTPUT, PIPELINE_LOG]
    backups = {p: p.read_bytes() if p.exists() else None for p in paths}
    try:
        original_expected = get_expected_ips()
        run_and_check(binary)
        assert json.loads(OUTPUT.read_text(encoding='utf-8')) == original_expected

        dynamic_expected = write_dynamic_inputs()
        assert get_expected_ips() == dynamic_expected
        run_and_check(binary)
    finally:
        for path, data in backups.items():
            if data is None:
                if path.exists():
                    path.unlink()
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)

if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_log_analyzer.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
