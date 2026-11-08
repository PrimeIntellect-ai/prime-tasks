#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from pathlib import Path

import numpy as np
import pytest
import requests

APP = Path('/home/user/app')
AUTHORIZED = {'Authorization': 'Bearer BOOTSTRAP_SECURE_99'}


def listener_owners(port):
    inodes = set()
    wanted = f'{port:04X}'
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(':', 1)[-1].upper() == wanted and fields[3] == '0A':
                inodes.add(fields[9])

    owners = []
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            links = [os.readlink(fd) for fd in (proc / 'fd').iterdir()]
        except (OSError, PermissionError):
            continue
        if any(link.startswith('socket:[') and link[8:-1] in inodes for link in links):
            try:
                exe = os.path.realpath(proc / 'exe')
                cmdline = (proc / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
                owners.append((int(proc.name), exe, cmdline))
            except OSError:
                pass
    return owners


@pytest.fixture(scope='session')
def expected_body(tmp_path_factory):
    work = tmp_path_factory.mktemp('oracle')
    data_path = work / 'data.bin'
    rng = np.random.RandomState(42)
    x = rng.uniform(0, 10, 1000).astype(np.float32)
    y = (np.float32(2.5) * x + rng.normal(0, 2, 1000)).astype(np.float32)
    with open(data_path, 'wb') as f:
        x.tofile(f)
        y.tofile(f)

    source = work / 'oracle.c'
    source.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
#define N 1000
#define THREADS 4
#define ITERS 10000

static float x[N], y[N], slopes[ITERS];
static int cmp(const void *a, const void *b) {
    float fa = *(const float *)a, fb = *(const float *)b;
    return (fa > fb) - (fa < fb);
}
int main(int argc, char **argv) {
    FILE *f = fopen(argv[1], "rb");
    if (!f || fread(x, sizeof(float), N, f) != N || fread(y, sizeof(float), N, f) != N) return 2;
    fclose(f);
    for (int t = 0; t < THREADS; ++t) {
        unsigned int seed = 42 + t;
        int start = t * (ITERS / THREADS);
        int end = (t + 1) * (ITERS / THREADS);
        for (int i = start; i < end; ++i) {
            float sx = 0, sy = 0, sxy = 0, sxx = 0;
            for (int j = 0; j < N; ++j) {
                int idx = rand_r(&seed) % N;
                sx += x[idx];
                sy += y[idx];
                sxy += x[idx] * y[idx];
                sxx += x[idx] * x[idx];
            }
            slopes[i] = (N * sxy - sx * sy) / (N * sxx - sx * sx);
        }
    }
    qsort(slopes, ITERS, sizeof(float), cmp);
    printf("[%.6f, %.6f]", slopes[(int)(ITERS * 0.025)], slopes[(int)(ITERS * 0.975)]);
    return 0;
}
''')
    binary = work / 'oracle'
    subprocess.run(['gcc', '-O0', str(source), '-o', str(binary)], check=True)
    return subprocess.check_output([str(binary), str(data_path)], text=True).strip()


def test_required_artifacts_and_processes():
    engine = APP / 'engine'
    source_path = APP / 'engine.c'
    nginx_conf = APP / 'nginx.conf'

    assert engine.is_file(), 'Compiled /home/user/app/engine is missing'
    assert os.access(engine, os.X_OK), 'Compiled engine is not executable'
    assert engine.read_bytes()[:4] == b'\x7fELF', 'engine must be a compiled ELF executable'
    assert source_path.is_file(), 'engine.c is missing'
    assert nginx_conf.is_file(), 'nginx.conf is missing'
    subprocess.run(['nginx', '-t', '-c', str(nginx_conf)], check=True, capture_output=True, text=True)

    owners_5000 = listener_owners(5000)
    assert owners_5000, 'Nothing is listening on port 5000'
    assert any(exe == str(engine) for _, exe, _ in owners_5000), \
        f'Port 5000 is not owned by the compiled engine: {owners_5000}'

    owners_9000 = listener_owners(9000)
    assert owners_9000, 'Nothing is listening on port 9000'
    assert any('broker.py' in cmd for _, _, cmd in owners_9000), \
        f'Port 9000 is not owned by broker.py: {owners_9000}'

    owners_8080 = listener_owners(8080)
    assert owners_8080, 'Nothing is listening on port 8080'
    assert any(os.path.basename(exe) == 'nginx' for _, exe, _ in owners_8080), \
        f'Port 8080 is not owned by nginx: {owners_8080}'

    nginx_processes = []
    for proc in Path('/proc').iterdir():
        if proc.name.isdigit():
            try:
                cmd = (proc / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
                exe = os.path.realpath(proc / 'exe')
            except OSError:
                continue
            if os.path.basename(exe) == 'nginx':
                nginx_processes.append(cmd)
    assert any('/home/user/app/nginx.conf' in cmd for cmd in nginx_processes), \
        'Running nginx was not started with /home/user/app/nginx.conf'


def test_engine_source_uses_thread_local_reduction():
    source = (APP / 'engine.c').read_text()
    clean = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    start = clean.find('void* bootstrap_worker')
    if start < 0:
        start = clean.find('void *bootstrap_worker')
    end = clean.find('int compare_floats', start)
    assert start >= 0 and end > start, 'Could not locate bootstrap_worker in engine.c'
    worker = clean[start:end]

    assert 'pthread_mutex_lock' not in worker, 'bootstrap_worker still performs mutex-protected shared reduction'
    for name in ('sum_x', 'sum_y', 'sum_xy', 'sum_xx'):
        shared_write = rf'(?<![.>\w]){name}\s*(?:\+=|=)'
        assert not re.search(shared_write, worker), f'bootstrap_worker still writes shared {name}'

    join_pos = clean.find('pthread_join', end)
    assert join_pos >= 0, 'Main thread does not join bootstrap workers'
    reduction = clean[join_pos:]
    for name in ('sum_x', 'sum_y', 'sum_xy', 'sum_xx'):
        aggregate = rf'(?<![.>\w]){name}\s*(?:\+=|=\s*{name}\s*\+)'
        assert re.search(aggregate, reduction), f'Main thread does not sequentially aggregate {name}'


def test_nginx_proxy_unauthorized():
    url = 'http://localhost:8080/api/fit'
    response = requests.get(url, timeout=10)
    assert response.status_code == 401, f'Expected 401 Unauthorized, got {response.status_code}'

    response = requests.get(url, headers={'Authorization': 'Bearer WRONG_TOKEN'}, timeout=10)
    assert response.status_code == 401, f'Expected 401 Unauthorized for wrong token, got {response.status_code}'


def test_nginx_proxy_authorized_deterministic_and_correct(expected_body):
    url = 'http://localhost:8080/api/fit'
    results = []
    for i in range(5):
        try:
            response = requests.get(url, headers=AUTHORIZED, timeout=10)
        except requests.exceptions.RequestException as exc:
            pytest.fail(f'Request {i + 1} failed: {exc}')
        assert response.status_code == 200, \
            f'Expected 200 OK, got {response.status_code}. Response: {response.text}'
        results.append(response.text.strip())

    first_result = results[0]
    for i, result in enumerate(results[1:], start=2):
        assert result == first_result, \
            f"Non-deterministic output: request 1 gave '{first_result}', request {i} gave '{result}'"

    assert first_result.startswith('[') and first_result.endswith(']'), f'Output format incorrect: {first_result}'
    parts = first_result[1:-1].split(',')
    assert len(parts) == 2, f'Expected two values in output, got: {first_result}'
    try:
        lower = float(parts[0].strip())
        upper = float(parts[1].strip())
    except ValueError:
        pytest.fail(f'Could not parse floats from output: {first_result}')
    assert lower < upper, f'Lower bound {lower} is not less than upper bound {upper}'
    assert first_result == expected_body, \
        f'Bootstrap confidence interval is numerically incorrect: expected {expected_body}, got {first_result}'

    direct = requests.get('http://localhost:5000/analyze', timeout=10)
    assert direct.status_code == 200, f'Direct engine request returned {direct.status_code}'
    assert direct.text.strip() == expected_body, \
        f'Direct engine result is incorrect: expected {expected_body}, got {direct.text.strip()}'


def test_success_log_exists_and_matches_response(expected_body):
    log_path = APP / 'success.log'
    assert log_path.is_file(), f'File {log_path} does not exist'
    content = log_path.read_text().strip()
    assert content.startswith('[') and content.endswith(']'), f'success.log content format incorrect: {content}'

    response = requests.get('http://localhost:8080/api/fit', headers=AUTHORIZED, timeout=10)
    assert response.status_code == 200
    assert content == response.text.strip(), 'success.log does not contain the exact successful HTTP response body'
    assert content == expected_body, f'success.log contains an incorrect confidence interval: {content}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
