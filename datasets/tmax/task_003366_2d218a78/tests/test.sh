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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import signal
import socket
import subprocess
import time
from pathlib import Path

import pytest
import requests
from PIL import Image, ImageDraw, ImageFont

APP = Path('/app')
SOURCE = APP / 'server.go'
CONFIG = APP / 'config.png'
BINARY = Path('/tmp/submission-server')
TESSERACT = Path('/usr/bin/tesseract')
REAL_TESSERACT = Path('/usr/bin/tesseract.verifier-real')
TESS_LOG = Path('/tmp/tesseract-calls.log')


def kill_port_8080():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].endswith(':1F90') and fields[3] == '0A':
                inodes.add(fields[9])

    victims = set()
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        fd_dir = entry / 'fd'
        try:
            fds = list(fd_dir.iterdir())
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                victims.add(int(entry.name))
                break

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.25)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def wait_for_server(use_original_get_check=False):
    if use_original_get_check:
        server_up = False
        for _ in range(50):
            try:
                requests.get('http://127.0.0.1:8080/', timeout=0.5)
                server_up = True
                break
            except requests.exceptions.ConnectionError:
                time.sleep(0.1)
        assert server_up, 'Server is not listening on 127.0.0.1:8080'
        return

    for _ in range(50):
        try:
            with socket.create_connection(('127.0.0.1', 8080), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail('Server is not listening on 127.0.0.1:8080')


def assert_exact_bind(pid):
    socket_inodes = set()
    fd_dir = Path(f'/proc/{pid}/fd')
    for fd in fd_dir.iterdir():
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        if target.startswith('socket:['):
            socket_inodes.add(target[8:-1])

    listeners = []
    for line in Path('/proc/net/tcp').read_text().splitlines()[1:]:
        fields = line.split()
        if len(fields) > 9 and fields[9] in socket_inodes and fields[3] == '0A':
            listeners.append(fields[1])
    assert '0100007F:1F90' in listeners, 'Server must listen exactly on 127.0.0.1:8080'


def start_server(original_wait=False):
    kill_port_8080()
    TESS_LOG.write_text('')
    proc = subprocess.Popen(
        [str(BINARY)], cwd='/app', stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, env=os.environ.copy()
    )
    try:
        wait_for_server(original_wait)
        assert proc.poll() is None, 'Compiled Go server exited before testing'
        assert_exact_bind(proc.pid)
        assert TESS_LOG.read_text().strip(), 'The running service did not invoke tesseract'
        return proc
    except Exception:
        proc.terminate()
        raise


def stop_server(proc):
    if proc is not None and proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)
    kill_port_8080()


def ocr_config(tesseract_path):
    output = subprocess.run(
        [str(tesseract_path), str(CONFIG), 'stdout'],
        check=True, text=True, capture_output=True
    ).stdout
    rate_match = re.search(r'(?m)^RATE_LIMIT\s*=\s*(\d+)\s*$', output)
    assert rate_match, f'Could not derive RATE_LIMIT from OCR output: {output!r}'
    lines = [line.strip() for line in output.splitlines()]
    marker = next((i for i, line in enumerate(lines) if line == 'VALID_KEYS:'), None)
    assert marker is not None, f'Could not derive VALID_KEYS from OCR output: {output!r}'
    keys = [line for line in lines[marker + 1:] if line]
    assert keys, 'OCR produced no valid keys'
    return int(rate_match.group(1)), keys


def make_random_config():
    corpus = ['cobalt', 'falcon', 'harbor', 'jupiter', 'maple', 'nectar', 'quartz', 'velvet']
    chosen = random.SystemRandom().sample(corpus, 4)
    rate = random.SystemRandom().randint(6, 9)
    image = Image.new('RGB', (500, 420), color=(255, 255, 255))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(
        '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf', 24
    )
    text = f"RATE_LIMIT={rate}\nVALID_KEYS:\n" + '\n'.join(chosen)
    draw.text((20, 20), text, fill=(0, 0, 0), font=font)
    image.save(CONFIG)
    return rate, chosen, corpus


def test_go_service_and_dynamic_configuration():
    assert SOURCE.is_file() and not SOURCE.is_symlink(), '/app/server.go must be a regular file'
    source = SOURCE.read_text()
    assert re.search(r'(?m)^\s*package\s+main\b', source), 'server.go must be a Go main package'
    assert '"net/http"' in source, 'server.go must use Go standard net/http'
    assert '"encoding/json"' in source, 'server.go must use Go standard encoding/json'
    assert re.search(r'(?i)tesseract', source), 'server.go must invoke tesseract'

    build = subprocess.run(
        ['go', 'build', '-o', str(BINARY), str(SOURCE)],
        cwd='/app', text=True, capture_output=True
    )
    assert build.returncode == 0, f'server.go did not compile:\n{build.stdout}\n{build.stderr}'

    original_config = CONFIG.read_bytes()
    proc = None
    wrapper_installed = False
    try:
        # Independently derive the original card's values before instrumenting tesseract.
        original_rate, original_keys = ocr_config(TESSERACT)
        assert original_rate == 4
        assert set(original_keys) == {'omega', 'theta', 'sigma', 'lambda'}

        os.replace(TESSERACT, REAL_TESSERACT)
        TESSERACT.write_text(
            '#!/bin/sh\n'
            'echo called >> /tmp/tesseract-calls.log\n'
            'exec /usr/bin/tesseract.verifier-real "$@"\n'
        )
        TESSERACT.chmod(0o755)
        wrapper_installed = True

        # Preserve all original behavioral assertions on a freshly compiled server.
        proc = start_server(original_wait=True)
        url = 'http://127.0.0.1:8080/validate'

        resp1 = requests.post(url, json={'keys': ['omega', 'sigma']})
        assert resp1.status_code == 200, f'Request 1 expected 200 OK, got {resp1.status_code}'

        resp2 = requests.post(url, json={'keys': ['lambda']})
        assert resp2.status_code == 200, f'Request 2 expected 200 OK, got {resp2.status_code}'

        resp3 = requests.post(url, json={'keys': ['omega', 'invalid_key']})
        assert resp3.status_code == 400, f'Request 3 expected 400 Bad Request, got {resp3.status_code}'

        resp4 = requests.post(url, json={'keys': ['theta']})
        assert resp4.status_code == 200, f'Request 4 expected 200 OK, got {resp4.status_code}'

        resp5 = requests.post(url, json={'keys': ['sigma']})
        assert resp5.status_code == 429, f'Request 5 expected 429 Too Many Requests, got {resp5.status_code}'

        resp6 = requests.post(url, json={'keys': ['invalid_key']})
        assert resp6.status_code == 429, f'Request 6 expected 429 Too Many Requests, got {resp6.status_code}'
        stop_server(proc)
        proc = None

        # Replace the card with an unpredictable configuration, derive its actual OCR
        # result independently, and exercise randomized valid and invalid combinations.
        intended_rate, intended_keys, corpus = make_random_config()
        observed_rate, observed_keys = ocr_config(REAL_TESSERACT)
        assert observed_rate == intended_rate
        assert set(observed_keys) == set(intended_keys)

        proc = start_server(original_wait=False)
        url = 'http://127.0.0.1:8080/validate'
        rng = random.SystemRandom()

        cases = []
        cases.append(({'keys': [observed_keys[0], observed_keys[0]]}, 200))
        cases.append(({'keys': rng.sample(observed_keys, 2)}, 200))
        excluded = rng.choice([key for key in corpus if key not in observed_keys])
        cases.append(({'keys': [excluded]}, 400))
        cases.append(({'keys': [rng.choice(observed_keys), 'bad-' + secrets.token_hex(12)]}, 400))
        while len(cases) < observed_rate:
            if rng.choice([True, False]):
                size = rng.randint(1, len(observed_keys))
                cases.append(({'keys': rng.sample(observed_keys, size)}, 200))
            else:
                cases.append(({'keys': ['unknown-' + secrets.token_hex(12)]}, 400))
        rng.shuffle(cases)

        for index, (payload, expected) in enumerate(cases, 1):
            response = requests.post(url, json=payload)
            assert response.status_code == expected, (
                f'Dynamic request {index} expected {expected}, got {response.status_code}; '
                f'payload={payload!r}'
            )

        for payload in ({'keys': observed_keys}, {'keys': ['unknown-' + secrets.token_hex(12)]}):
            response = requests.post(url, json=payload)
            assert response.status_code == 429, (
                f'Request after dynamic RATE_LIMIT={observed_rate} expected 429, '
                f'got {response.status_code}'
            )
    finally:
        stop_server(proc)
        CONFIG.write_bytes(original_config)
        if wrapper_installed:
            try:
                TESSERACT.unlink()
            except FileNotFoundError:
                pass
            if REAL_TESSERACT.exists():
                os.replace(REAL_TESSERACT, TESSERACT)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
