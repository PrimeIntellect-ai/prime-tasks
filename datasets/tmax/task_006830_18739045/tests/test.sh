#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import itertools
import os
from pathlib import Path
import secrets
import shlex
import string
import subprocess

import pytest

HOME = Path('/home/user')
HASH_PATH = HOME / 'legacy_hash.txt'
TOKEN_PATH = HOME / 'new_token.txt'
CRACKER = HOME / 'cracker'
RULES_PATH = HOME / 'firewall.rules'
ALPHABET = string.ascii_lowercase + string.digits


def recover_expected(hash_text):
    for suffix in itertools.product(ALPHABET, repeat=3):
        candidate = 'sec' + ''.join(suffix)
        if hashlib.sha256(candidate.encode()).hexdigest() == hash_text:
            return candidate
    raise AssertionError('The supplied legacy hash has no password in the documented search space.')


def build_runner():
    assert CRACKER.is_dir(), f'Directory {CRACKER} does not exist.'
    rust_sources = [p for p in CRACKER.rglob('*.rs') if 'target' not in p.parts]
    assert rust_sources, f'No Rust source file exists in {CRACKER}.'

    env = os.environ.copy()
    env['CARGO_NET_OFFLINE'] = 'true'
    if (CRACKER / 'Cargo.toml').is_file():
        build = subprocess.run(
            ['cargo', 'build', '--offline'], cwd=CRACKER, env=env,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=120,
        )
        assert build.returncode == 0, f'Rust cracker did not compile:\n{build.stdout}'
        return ['cargo', 'run', '--quiet', '--offline'], env

    main = CRACKER / 'main.rs'
    if not main.is_file():
        main_candidates = [p for p in rust_sources if p.name == 'main.rs']
        assert main_candidates, 'No Cargo.toml or compilable main.rs Rust entry point was found.'
        main = main_candidates[0]
    executable = Path('/tmp/submitted_cracker')
    build = subprocess.run(
        ['rustc', str(main), '-O', '-o', str(executable)], cwd=CRACKER,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120,
    )
    assert build.returncode == 0, f'Rust cracker did not compile:\n{build.stdout}'
    return [str(executable)], env


def run_cracker_for(password, command, env):
    target_hash = hashlib.sha256(password.encode()).hexdigest()
    HASH_PATH.write_text(target_hash)
    if TOKEN_PATH.exists():
        TOKEN_PATH.unlink()

    result = subprocess.run(
        command, cwd=CRACKER, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90,
    )
    assert result.returncode == 0, f'Rust cracker failed while processing a valid legacy hash:\n{result.stdout}'

    output_recovered = password in result.stdout
    expected_token = base64.b64encode(f'{password}:NEW_AUTH_FLOW'.encode())
    token_recovered = TOKEN_PATH.is_file() and TOKEN_PATH.read_bytes() == expected_token
    assert output_recovered or token_recovered, (
        'Executing the Rust program did not recover the password supplied through legacy_hash.txt. '
        f'Program output was:\n{result.stdout}'
    )


def test_new_token_content():
    assert TOKEN_PATH.is_file(), f'File {TOKEN_PATH} does not exist.'
    content = TOKEN_PATH.read_bytes()
    expected_token = b'c2VjN3g5Ok5FV19BVVRIX0ZMT1c='
    assert content == expected_token, (
        f'Content of {TOKEN_PATH} is incorrect. Expected {expected_token!r}, got {content!r}.'
    )

    original_hash = HASH_PATH.read_text().strip()
    recovered = recover_expected(original_hash)
    derived = base64.b64encode(f'{recovered}:NEW_AUTH_FLOW'.encode())
    assert content == derived, 'Token does not encode the password derived from legacy_hash.txt.'


def test_rust_cracker_executes_and_recovers_credentials():
    original_hash = HASH_PATH.read_bytes()
    original_token = TOKEN_PATH.read_bytes() if TOKEN_PATH.is_file() else None
    command, env = build_runner()
    try:
        original_password = recover_expected(original_hash.decode().strip())
        run_cracker_for(original_password, command, env)

        random_password = None
        while random_password is None or random_password == original_password:
            random_password = 'sec' + ''.join(secrets.choice(ALPHABET) for _ in range(3))
        run_cracker_for(random_password, command, env)
    finally:
        HASH_PATH.write_bytes(original_hash)
        if original_token is None:
            TOKEN_PATH.unlink(missing_ok=True)
        else:
            TOKEN_PATH.write_bytes(original_token)


def test_firewall_rules_content_and_validity():
    assert RULES_PATH.is_file(), f'File {RULES_PATH} does not exist.'
    content = RULES_PATH.read_text()

    validation = subprocess.run(
        ['iptables-restore', '--test'], input=content, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20,
    )
    assert validation.returncode == 0, f'iptables-restore rejected firewall.rules:\n{validation.stdout}'

    raw_lines = [line.strip() for line in content.splitlines()]
    lines = [line for line in raw_lines if line and not line.startswith('#')]
    assert lines.count('*filter') == 1, "The ruleset must contain exactly one '*filter' declaration."

    in_filter = False
    filter_lines = []
    filter_commits = 0
    all_rules = []
    for line in lines:
        if line.startswith('*'):
            in_filter = line == '*filter'
            continue
        if line == 'COMMIT':
            if in_filter:
                filter_commits += 1
            in_filter = False
            continue
        try:
            tokens = shlex.split(line)
        except ValueError as exc:
            pytest.fail(f'Invalid quoting in firewall.rules: {exc}')
        if tokens and tokens[0] in ('-A', '--append'):
            all_rules.append(tokens)
        if in_filter:
            filter_lines.append(tokens)

    assert filter_commits == 1, "The filter table must have exactly one 'COMMIT'."

    policies = {}
    for tokens in filter_lines:
        if tokens and tokens[0].startswith(':'):
            assert len(tokens) in (2, 3), f'Invalid chain declaration: {tokens}'
            chain = tokens[0][1:]
            assert chain not in policies, f'Duplicate declaration for chain {chain}.'
            policies[chain] = tokens[1]

    assert policies.get('INPUT') == 'DROP', "Missing exact default policy ':INPUT DROP'."
    assert policies.get('FORWARD') == 'DROP', "Missing exact default policy ':FORWARD DROP'."
    assert policies.get('OUTPUT') == 'ACCEPT', "Missing exact default policy ':OUTPUT ACCEPT'."

    assert len(all_rules) == 1, f'Expected exactly one firewall rule, found {len(all_rules)}.'
    tokens = all_rules[0]
    assert len(tokens) >= 2 and tokens[1] == 'INPUT', 'The sole rule must be appended to INPUT.'

    values = {}
    modules = []
    i = 2
    paired = {
        '-p': 'protocol', '--protocol': 'protocol',
        '-s': 'source', '--source': 'source',
        '--dport': 'dport', '--destination-port': 'dport',
        '-j': 'jump', '--jump': 'jump',
    }
    while i < len(tokens):
        token = tokens[i]
        assert token != '!', 'Negated firewall matches are not permitted.'
        if token == '-m' or token == '--match':
            assert i + 1 < len(tokens), 'Missing match module name.'
            modules.append(tokens[i + 1])
            i += 2
            continue
        assert token in paired and i + 1 < len(tokens), f'Unexpected or incomplete rule option: {token}'
        key = paired[token]
        assert key not in values, f'Duplicate rule option for {key}.'
        values[key] = tokens[i + 1]
        i += 2

    assert all(module == 'tcp' for module in modules), 'Only the optional tcp match module is allowed.'
    assert values == {
        'protocol': 'tcp',
        'source': values.get('source'),
        'dport': '9999',
        'jump': 'ACCEPT',
    }, 'The sole rule must only accept TCP destination port 9999 from the required source.'
    assert values['source'] in ('10.0.0.45', '10.0.0.45/32'), (
        'The sole rule must exclusively use source address 10.0.0.45.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
