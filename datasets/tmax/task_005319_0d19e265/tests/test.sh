#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import uuid

import pytest


def is_malicious(line):
    if re.search(r'<[^>]+>', line):
        return True
    if 'javascript:' in line.lower():
        return True
    if line.count('{') != line.count('}'):
        return True
    return False


def processes_running_script(script_path):
    matches = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        proc_dir = os.path.join('/proc', entry)
        try:
            with open(os.path.join(proc_dir, 'cmdline'), 'rb') as f:
                args = [a.decode(errors='replace') for a in f.read().split(b'\0') if a]
            with open(os.path.join(proc_dir, 'stat'), 'r') as f:
                state = f.read().split()[2]
            cwd = os.readlink(os.path.join(proc_dir, 'cwd'))
        except (FileNotFoundError, PermissionError, ProcessLookupError, IndexError):
            continue

        if state == 'Z':
            continue

        found = False
        for arg in args:
            if arg == script_path:
                found = True
                break
            if os.path.basename(arg) == os.path.basename(script_path):
                candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
                if os.path.realpath(candidate) == os.path.realpath(script_path):
                    found = True
                    break
        if found:
            matches.append((entry, args))
    return matches


def process_environment(pid):
    with open(f'/proc/{pid}/environ', 'rb') as f:
        entries = f.read().split(b'\0')
    env = {}
    for entry in entries:
        if b'=' in entry:
            key, value = entry.split(b'=', 1)
            env[key.decode(errors='replace')] = value.decode(errors='replace')
    return env


def run_filter(filepath):
    assert os.path.isfile('/home/user/filter.sh'), '/home/user/filter.sh is missing'
    result = subprocess.run(
        ['bash', '/home/user/filter.sh', filepath],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.splitlines()


def test_worker_conf_exists_and_correct():
    conf_path = '/home/user/services/worker.conf'
    assert os.path.exists(conf_path), f'{conf_path} does not exist'

    with open(conf_path, 'r') as f:
        content = f.read()

    # Preserve the original assertions.
    assert 'REDIS_PORT=6379' in content, 'REDIS_PORT=6379 not found in worker.conf'
    assert 'API_ENDPOINT=http://localhost:5000' in content, 'API_ENDPOINT=http://localhost:5000 not found in worker.conf'

    # Require real, unambiguous shell assignments rather than comments or substrings.
    redis_assignments = re.findall(r'^\s*REDIS_PORT=6379\s*(?:#.*)?$', content, re.MULTILINE)
    api_assignments = re.findall(r'^\s*API_ENDPOINT=http://localhost:5000\s*(?:#.*)?$', content, re.MULTILINE)
    assert len(redis_assignments) == 1, 'worker.conf must contain exactly one active REDIS_PORT=6379 assignment'
    assert len(api_assignments) == 1, 'worker.conf must contain exactly one active API_ENDPOINT assignment'


def test_services_running():
    redis_result = subprocess.run(
        ['redis-cli', '-h', '127.0.0.1', '-p', '6379', 'PING'],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert redis_result.returncode == 0 and redis_result.stdout.strip() == 'PONG', 'Redis is not running on port 6379'

    api_processes = processes_running_script('/home/user/services/tm_api.py')
    assert api_processes, 'tm_api.py is not running'

    correctly_configured_api = False
    for pid, _ in api_processes:
        try:
            redis_url = process_environment(pid).get('REDIS_URL')
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if not redis_url:
            continue
        parsed = urllib.parse.urlparse(redis_url)
        try:
            port = parsed.port
        except ValueError:
            continue
        if parsed.scheme == 'redis' and parsed.hostname in ('localhost', '127.0.0.1', '::1') and port == 6379:
            correctly_configured_api = True
            break
    assert correctly_configured_api, 'running tm_api.py does not have REDIS_URL pointing to local Redis port 6379'

    try:
        req = urllib.request.Request('http://localhost:5000/health')
        with urllib.request.urlopen(req, timeout=5) as response:
            status = response.getcode()
            assert status == 200, f'Flask health endpoint returned status {status}'
            assert response.read().decode(errors='replace').strip() == 'OK'
    except urllib.error.URLError as e:
        pytest.fail(f'Could not connect to Flask API at localhost:5000: {e}')

    workers = processes_running_script('/home/user/services/tm_worker.sh')
    assert workers, 'tm_worker.sh is not running'


def test_filter_clean_corpus():
    clean_dir = '/home/user/corpora/clean/'
    assert os.path.isdir(clean_dir), 'Clean corpus directory missing'
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.csv')]
    assert clean_files, 'No CSV files found in clean corpus'

    failed_files = []
    for filepath in clean_files:
        with open(filepath, 'r') as f:
            original_lines = f.read().splitlines()
        output_lines = run_filter(filepath)

        # Preserve the original line-count check and additionally require exact preservation.
        if len(output_lines) != len(original_lines) or output_lines != original_lines:
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f'{len(failed_files)} of {len(clean_files)} clean modified. Offending files: {", ".join(failed_files)}')


def test_filter_evil_corpus():
    evil_dir = '/home/user/corpora/evil/'
    assert os.path.isdir(evil_dir), 'Evil corpus directory missing'
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.csv')]
    assert evil_files, 'No CSV files found in evil corpus'

    failed_files = []
    for filepath in evil_files:
        with open(filepath, 'r') as f:
            original_lines = f.read().splitlines()
        output_lines = run_filter(filepath)

        malicious_original = [line for line in original_lines if is_malicious(line)]
        bypassed = [line for line in output_lines if is_malicious(line)]
        expected_safe = [line for line in original_lines if not is_malicious(line)]

        # Preserve the original bypass assertion and also reject invented/replaced output.
        if bypassed or output_lines != expected_safe or (malicious_original and any(x in output_lines for x in malicious_original)):
            failed_files.append(os.path.basename(filepath))

    if failed_files:
        pytest.fail(f'{len(failed_files)} of {len(evil_files)} evil bypassed or produced invented output. Offending files: {", ".join(failed_files)}')


def test_filter_on_generated_mixed_input(tmp_path):
    token = uuid.uuid4().hex
    safe = [
        f'alpha,en-US,Hello {token}!',
        'beta,es-ES,¡Hola {username}!',
        'gamma,fr-FR,Price: 12.50 (tax included).',
        'delta,de-DE,Use [brackets] & punctuation #1.',
    ]
    malicious = [
        f'bad1,en-US,Hello <script>{token}</script>',
        'bad2,en-US,Click JAVASCRIPT:alert(1)',
        'bad3,en-US,Hello {username',
        'bad4,en-US,Hello username}',
        'bad5,en-US,Wrong }{ order',
        'bad6,en-US,Use <img src=x>',
        'malformed-without-columns',
    ]
    mixed = [safe[0], malicious[0], safe[1], malicious[1], malicious[2], safe[2], malicious[3], malicious[4], safe[3], malicious[5], malicious[6]]
    source = tmp_path / f'unseen-{token}.csv'
    source.write_text('\n'.join(mixed) + '\n')
    assert run_filter(str(source)) == safe

    clean_source = tmp_path / f'clean-{token}.csv'
    clean_source.write_text('\n'.join(safe) + '\n')
    assert run_filter(str(clean_source)) == safe


def test_pipeline_executes_etl_and_writes_output(tmp_path):
    pipeline = '/home/user/pipeline.sh'
    output_path = '/home/user/processed_translations.csv'
    assert os.path.isfile(pipeline), f'{pipeline} is missing'

    with open('/home/user/data/master_keys.txt', 'r') as f:
        master_keys = f.read().splitlines()
    assert master_keys == ['welcome_msg', 'login_btn', 'logout_btn'], 'master key list was modified'

    token = uuid.uuid4().hex
    welcome_en = f'Welcome {token}'
    login_en = f'Log In {token}'
    logout_en = f'Log Out {token}'
    shared = f'Shared {token}'
    duplicate = f'Duplicate {token}'

    input_lines = [
        f'welcome_msg,EN_us,{welcome_en}',
        f'login_btn,en-us,{login_en}',
        f'logout_btn,EN-US,{logout_en}',
        f'extra_en,en_US,{shared}',
        f'extra_es,ES-es,{shared}',
        f'welcome_msg,es_ES,Bienvenido {token}',
        f'dup_first,ES_ES,{duplicate}',
        f'dup_second,es-es,{duplicate}',
        f'login_btn,Es_eS,Entrar {token}',
    ]
    expected = [
        f'welcome_msg,en-US,{welcome_en}',
        f'login_btn,en-US,{login_en}',
        f'logout_btn,en-US,{logout_en}',
        f'extra_en,en-US,{shared}',
        f'extra_es,es-ES,{shared}',
        f'welcome_msg,es-ES,Bienvenido {token}',
        f'dup_first,es-ES,{duplicate}',
        f'login_btn,es-ES,Entrar {token}',
        f'logout_btn,es-ES,{logout_en}',
    ]

    source = tmp_path / f'sanitized-{token}.csv'
    source.write_text('\n'.join(input_lines) + '\n')
    try:
        os.remove(output_path)
    except FileNotFoundError:
        pass

    result = subprocess.run(
        ['bash', pipeline, str(source)],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, result.stderr
    assert os.path.isfile(output_path), 'pipeline did not create /home/user/processed_translations.csv'
    with open(output_path, 'r') as f:
        actual = f.read().splitlines()
    assert actual == expected, f'pipeline output was incorrect:\nexpected={expected!r}\nactual={actual!r}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
