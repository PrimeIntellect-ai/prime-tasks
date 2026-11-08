#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import re
import secrets
import subprocess
import tempfile
import pytest


def _lex_nginx(content):
    tokens = []
    i = 0
    while i < len(content):
        c = content[i]
        if c.isspace():
            i += 1
            continue
        if c == '#':
            while i < len(content) and content[i] != '\n':
                i += 1
            continue
        if c in '{};':
            tokens.append(c)
            i += 1
            continue
        if c in "'\"":
            quote = c
            i += 1
            value = []
            while i < len(content) and content[i] != quote:
                if content[i] == '\\' and i + 1 < len(content):
                    i += 1
                value.append(content[i])
                i += 1
            assert i < len(content), 'Nginx configuration contains an unterminated quote.'
            i += 1
            tokens.append(''.join(value))
            continue

        start = i
        while i < len(content) and not content[i].isspace() and content[i] not in '{};#':
            i += 1
        assert i > start, 'Nginx configuration contains invalid syntax.'
        tokens.append(content[start:i])
    return tokens


def _parse_nginx(tokens):
    def parse_sequence(pos, nested):
        nodes = []
        while pos < len(tokens):
            if tokens[pos] == '}':
                assert nested, 'Unexpected closing brace in Nginx configuration.'
                return nodes, pos + 1

            args = []
            while pos < len(tokens) and tokens[pos] not in ('{', '}', ';'):
                args.append(tokens[pos])
                pos += 1
            assert args, 'Empty or malformed Nginx directive.'
            assert pos < len(tokens), 'Nginx directive is missing a semicolon or block.'

            if tokens[pos] == ';':
                nodes.append((args, None))
                pos += 1
            elif tokens[pos] == '{':
                children, pos = parse_sequence(pos + 1, True)
                nodes.append((args, children))
            else:
                raise AssertionError('Nginx directive is missing a semicolon or block.')

        assert not nested, 'Nginx configuration contains an unclosed block.'
        return nodes, pos

    parsed, end = parse_sequence(0, False)
    assert end == len(tokens), 'Nginx configuration contains trailing invalid syntax.'
    return parsed


def test_nginx_config():
    conf_path = '/home/user/nginx.conf'
    assert os.path.isfile(conf_path), f'Nginx config missing at {conf_path}'

    with open(conf_path, 'r') as f:
        content = f.read()

    # Preserve the original textual assertions.
    assert re.search(r'listen\s+80\s*;', content), "Nginx config does not correctly specify 'listen 80;'."
    assert re.search(r'proxy_pass\s+http://127\.0\.0\.1:8080\s*;', content), "Nginx config does not correctly specify 'proxy_pass http://127.0.0.1:8080;'."

    # Parse directives so comments, unrelated blocks, and malformed files cannot satisfy the checks.
    root = _parse_nginx(_lex_nginx(content))
    assert any(args == ['events'] and children is not None for args, children in root), \
        'Nginx configuration must contain an events block.'

    http_blocks = [children for args, children in root if args == ['http'] and children is not None]
    assert http_blocks, 'Nginx configuration must contain an http block.'

    valid_server = False
    for http in http_blocks:
        for server_args, server in http:
            if server_args != ['server'] or server is None:
                continue
            listens = any(args[0] == 'listen' and len(args) >= 2 and args[1] == '80' and children is None
                          for args, children in server)
            locations = [children for args, children in server
                         if len(args) == 2 and args == ['location', '/'] and children is not None]
            proxies_root = any(
                any(args == ['proxy_pass', 'http://127.0.0.1:8080'] and children is None
                    for args, children in location)
                for location in locations
            )
            if listens and proxies_root:
                valid_server = True
    assert valid_server, 'No server block listens on 80 and proxies location / to 127.0.0.1:8080.'


def _run_sanitiser(cargo_dir, path):
    return subprocess.run(
        ['cargo', 'run', '--quiet', '--', path],
        cwd=cargo_dir,
        capture_output=True,
        timeout=20,
    )


def _random_id(rng):
    return 's_' + secrets.token_hex(8) + str(rng.randrange(1000000))


def test_sanitiser_corpus():
    clean_dir = '/app/corpus/clean'
    evil_dir = '/app/corpus/evil'

    clean_files = glob.glob(os.path.join(clean_dir, '*.json'))
    evil_files = glob.glob(os.path.join(evil_dir, '*.json'))

    assert len(clean_files) > 0, f'No clean corpus files found in {clean_dir}'
    assert len(evil_files) > 0, f'No evil corpus files found in {evil_dir}'

    cargo_dir = '/home/user/sanitiser'
    assert os.path.isdir(cargo_dir), f'Rust project directory missing at {cargo_dir}'

    build_res = subprocess.run(['cargo', 'build'], cwd=cargo_dir, capture_output=True, timeout=120)
    assert build_res.returncode == 0, f'Failed to build Rust project in {cargo_dir}:\n{build_res.stderr.decode()}'

    clean_failed = []
    evil_bypassed = []

    # Preserve the original corpus assertions.
    for cf in clean_files:
        res = _run_sanitiser(cargo_dir, cf)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    for ef in evil_files:
        res = _run_sanitiser(cargo_dir, ef)
        if res.returncode == 0:
            evil_bypassed.append(os.path.basename(ef))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed (accepted): {', '.join(evil_bypassed)}")
    if errors:
        pytest.fail(' | '.join(errors))

    # Exercise fresh payloads at unpredictable paths and derive expected results from their construction.
    rng = random.SystemRandom()
    cases = []

    for _ in range(7):
        count = rng.randint(2, 9)
        ids = [_random_id(rng) for _ in range(count)]
        pipeline = []
        for i, step_id in enumerate(ids):
            dependencies = [ids[j] for j in range(i) if rng.random() < 0.45]
            pipeline.append({
                'step_id': step_id,
                'plugin_path': '/var/lib/plugins/lib_' + secrets.token_hex(10) + '.so',
                'depends_on': dependencies,
            })
        rng.shuffle(pipeline)
        cases.append(({'pipeline': pipeline}, 0))

    for _ in range(5):
        count = rng.randint(2, 8)
        ids = [_random_id(rng) for _ in range(count)]
        pipeline = []
        for i, step_id in enumerate(ids):
            pipeline.append({
                'step_id': step_id,
                'plugin_path': '/var/lib/plugins/lib_' + secrets.token_hex(10) + '.so',
                'depends_on': [ids[(i + 1) % count]],
            })
        rng.shuffle(pipeline)
        cases.append(({'pipeline': pipeline}, 1))

    for _ in range(5):
        count = rng.randint(1, 7)
        ids = [_random_id(rng) for _ in range(count)]
        bad_index = rng.randrange(count)
        pipeline = []
        for i, step_id in enumerate(ids):
            path = '/var/lib/plugins/lib_' + secrets.token_hex(10) + '.so'
            if i == bad_index:
                path = rng.choice([
                    '/etc/' + secrets.token_hex(8) + '.so',
                    '/var/lib/plugins_' + secrets.token_hex(8) + '.so',
                    'var/lib/plugins/' + secrets.token_hex(8) + '.so',
                ])
            pipeline.append({
                'step_id': step_id,
                'plugin_path': path,
                'depends_on': ids[:i][-1:] if i else [],
            })
        rng.shuffle(pipeline)
        cases.append(({'pipeline': pipeline}, 1))

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix='payloads_' + secrets.token_hex(8) + '_') as temp_dir:
        failures = []
        for payload, expected in cases:
            path = os.path.join(temp_dir, secrets.token_hex(16) + '.json')
            with open(path, 'w') as f:
                json.dump(payload, f, separators=(',', ':'))
            result = _run_sanitiser(cargo_dir, path)
            if result.returncode != expected:
                failures.append(f'{os.path.basename(path)} expected exit {expected}, got {result.returncode}')
        assert not failures, 'Generated payload validation failures: ' + ' | '.join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
