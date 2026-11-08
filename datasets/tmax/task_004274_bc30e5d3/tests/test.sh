#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

HOME = Path('/home/user')
USAGE = HOME / 'metrics/usage.json'
EXPECTED = {'alpha': 1048576, 'beta': 2097152}


def get(url, timeout=2):
    req = urllib.request.Request(url, method='GET')
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.status, response.headers, response.read()


def assert_usage(expected):
    assert USAGE.is_file(), f'JSON file {USAGE} does not exist.'
    try:
        data = json.loads(USAGE.read_text())
    except json.JSONDecodeError:
        assert False, f'{USAGE} does not contain valid JSON.'
    assert isinstance(data, dict), f'{USAGE} must contain a JSON object.'
    assert 'alpha' in data, f"'alpha' key missing in {USAGE}."
    assert 'beta' in data, f"'beta' key missing in {USAGE}."
    assert data == expected, f'Incorrect usage values: expected {expected}, got {data}'


def test_symlinks_exist_and_correct():
    alpha_link = '/home/user/symlinks/alpha'
    beta_link = '/home/user/symlinks/beta'

    assert os.path.islink(alpha_link), f'Symlink {alpha_link} does not exist.'
    assert os.path.islink(beta_link), f'Symlink {beta_link} does not exist.'
    assert os.readlink(alpha_link) == '/home/user/raw_data/proj_alpha', f'{alpha_link} points to wrong location.'
    assert os.readlink(beta_link) == '/home/user/raw_data/proj_beta', f'{beta_link} points to wrong location.'
    assert os.path.isdir(alpha_link), f'Target of {alpha_link} does not exist.'
    assert os.path.isdir(beta_link), f'Target of {beta_link} does not exist.'


def test_raw_data_and_scripts_recompute_usage():
    alpha = HOME / 'raw_data/proj_alpha/data.bin'
    beta = HOME / 'raw_data/proj_beta/data.bin'
    gather = HOME / 'gather_stats.sh'
    runner = HOME / 'runner.sh'

    assert alpha.is_file(), f'{alpha} does not exist.'
    assert beta.is_file(), f'{beta} does not exist.'
    assert alpha.stat().st_size == EXPECTED['alpha'], f'{alpha} is not 1 MiB.'
    assert beta.stat().st_size == EXPECTED['beta'], f'{beta} is not 2 MiB.'
    assert gather.is_file(), f'{gather} does not exist.'
    assert runner.is_file(), f'{runner} does not exist.'

    env = os.environ.copy()
    env['STORAGE_ROOT'] = '/tmp/incorrect-storage-root'
    subprocess.run(['bash', str(runner)], check=True, env=env, timeout=20)
    assert_usage(EXPECTED)

    try:
        with open(alpha, 'r+b') as f:
            f.truncate(12345)
        with open(beta, 'r+b') as f:
            f.truncate(23456)
        USAGE.write_text('{"alpha": 0, "beta": 0}')
        subprocess.run(['bash', str(runner)], check=True, env=env, timeout=20)
        assert_usage({'alpha': 12345, 'beta': 23456})
    finally:
        with open(alpha, 'r+b') as f:
            f.truncate(EXPECTED['alpha'])
        with open(beta, 'r+b') as f:
            f.truncate(EXPECTED['beta'])
        subprocess.run(['bash', str(runner)], check=True, env=env, timeout=20)

    assert_usage(EXPECTED)


def test_usage_json_exists_and_format():
    assert_usage(EXPECTED)


def test_rust_server_health_endpoint():
    url = 'http://127.0.0.1:9090/health'
    try:
        status, headers, raw = get(url)
        assert status == 200, f'Expected 200 OK from {url}'
        body = raw.decode('utf-8')
        assert '{"status": "ok"}' in body, f'Unexpected response from {url}: {body}'
        assert headers.get_content_type() == 'text/plain', f'Health endpoint must return text/plain, got {headers.get("Content-Type")}'
    except urllib.error.URLError as e:
        assert False, f'Failed to connect to Rust server at {url}: {e}'


def test_rust_server_metrics_endpoint():
    url = 'http://127.0.0.1:9090/metrics'
    try:
        status, headers, raw = get(url)
        assert status == 200, f'Expected 200 OK from {url}'
        body = raw.decode('utf-8')
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            assert False, f'Response from {url} is not valid JSON.'
        assert 'alpha' in data, "'alpha' key missing in metrics response."
        assert 'beta' in data, "'beta' key missing in metrics response."
        assert data == EXPECTED, f'Incorrect metrics response: {data}'
        assert body == USAGE.read_text(), 'Metrics endpoint did not return the contents of usage.json.'
        assert headers.get_content_type() == 'application/json', f'Metrics endpoint must return application/json, got {headers.get("Content-Type")}'
    except urllib.error.URLError as e:
        assert False, f'Failed to connect to Rust server at {url}: {e}'


def kill_port_9090():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[1].rsplit(':', 1)[-1].upper() == '2382' and fields[3] == '0A':
                inodes.add(fields[9])

    pids = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / 'fd').iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(proc.name))
        except OSError:
            pass

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_release_rust_artifact_and_dynamic_server_behavior():
    project = HOME / 'capacity_server'
    manifest = project / 'Cargo.toml'
    main_rs = project / 'src/main.rs'
    assert project.is_dir(), f'Rust project {project} does not exist.'
    assert manifest.is_file(), f'{manifest} does not exist.'
    assert main_rs.is_file(), f'{main_rs} does not exist.'

    metadata_raw = subprocess.check_output(
        ['cargo', 'metadata', '--no-deps', '--format-version', '1', '--manifest-path', str(manifest)],
        text=True, timeout=60
    )
    metadata = json.loads(metadata_raw)
    bins = [t for p in metadata['packages'] for t in p['targets'] if 'bin' in t['kind']]
    assert bins, 'The Cargo project has no Rust binary target.'
    assert all(Path(t['src_path']).suffix == '.rs' for t in bins), 'Server binary target is not Rust source.'

    subprocess.run(['cargo', 'clean', '--manifest-path', str(manifest)], check=True, timeout=60)
    subprocess.run(['cargo', 'build', '--release', '--manifest-path', str(manifest)], check=True, timeout=300)

    binary = Path(metadata['target_directory']) / 'release' / bins[0]['name']
    assert binary.is_file(), f'Release binary {binary} was not produced.'
    assert os.access(binary, os.X_OK), f'Release binary {binary} is not executable.'
    assert binary.read_bytes()[:4] == b'\x7fELF', f'{binary} is not a compiled executable.'

    kill_port_9090()
    proc = subprocess.Popen([str(binary)], cwd=str(project), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            if proc.poll() is not None:
                raise AssertionError(f'Release server exited with status {proc.returncode}.')
            try:
                status, _, _ = get('http://127.0.0.1:9090/health', timeout=0.3)
                if status == 200:
                    break
            except urllib.error.URLError:
                time.sleep(0.1)
        else:
            raise AssertionError('Compiled release server did not listen on 127.0.0.1:9090.')

        status, headers, raw = get('http://127.0.0.1:9090/health')
        assert status == 200
        assert raw.decode('utf-8') == '{"status": "ok"}'
        assert headers.get_content_type() == 'text/plain'

        original = USAGE.read_text()
        try:
            changed = '{"alpha": 7, "beta": 11}'
            USAGE.write_text(changed)
            status, headers, raw = get('http://127.0.0.1:9090/metrics')
            assert status == 200
            assert headers.get_content_type() == 'application/json'
            assert raw.decode('utf-8') == changed, 'Server is not reading the current usage.json contents.'

            USAGE.unlink()
            try:
                get('http://127.0.0.1:9090/metrics')
                assert False, 'Missing usage.json should produce HTTP 404 or 500.'
            except urllib.error.HTTPError as e:
                assert e.code in (404, 500), f'Expected 404 or 500 for missing usage.json, got {e.code}.'
        finally:
            USAGE.write_text(original)

        status, headers, raw = get('http://127.0.0.1:9090/metrics')
        assert status == 200
        assert headers.get_content_type() == 'application/json'
        assert raw.decode('utf-8') == USAGE.read_text()
        assert json.loads(raw) == EXPECTED
    except Exception:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
        raise
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
