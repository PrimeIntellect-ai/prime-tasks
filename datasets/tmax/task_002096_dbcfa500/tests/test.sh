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
import json
import os
import signal
import subprocess
import time
import uuid

import pytest
import requests

JO = '/app/jo-1.9/jo'
SCRIPT = '/home/user/start_server.sh'
RESULT_A = '/app/test_results_A.txt'
RESULT_B = '/app/test_results_B.txt'
URL = 'http://127.0.0.1:8080/api/status'


def assert_status_response(response, expected):
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}."
    content_type = response.headers.get('Content-Type', '')
    assert 'application/json' in content_type, \
        f"Expected Content-Type 'application/json', got '{content_type}'."
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON: {response.text}")
    assert data == expected, f"Expected JSON payload {expected}, got {data}."
    assert list(data.keys()) == sorted(expected), \
        f"JSON keys are not alphabetically sorted: {list(data.keys())}"


def request_with_retry(timeout=8):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            return requests.get(URL, timeout=2)
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.15)
    pytest.fail(f"Failed to connect to the server at {URL}. Error: {last_error}")


def stop_existing_server():
    subprocess.run(['pkill', '-TERM', '-f', '/home/user/start_server.sh'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    subprocess.run(['pkill', '-TERM', '-x', 'nc'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.25)

    # Kill any remaining process that owns a socket bound to port 8080.
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as handle:
                next(handle, None)
                for line in handle:
                    fields = line.split()
                    if len(fields) > 9 and int(fields[1].rsplit(':', 1)[1], 16) == 8080:
                        inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for entry in os.listdir('/proc'):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    victims.add(int(entry))
                    break
        except OSError:
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def test_makefile_typo_fixed():
    makefile_path = '/app/jo-1.9/Makefile.in'
    assert os.path.isfile(makefile_path), f"The file {makefile_path} is missing."

    with open(makefile_path, 'r') as f:
        content = f.read()

    assert "LDFALGS = @LDFLAGS@" not in content, \
        f"The typo 'LDFALGS = @LDFLAGS@' was not fixed in {makefile_path}."
    assert "LDFLAGS = @LDFLAGS@" in content, \
        f"The expected 'LDFLAGS = @LDFLAGS@' was not found in {makefile_path}."


def test_jo_binary_compiled():
    assert os.path.isfile(JO), f"The compiled binary {JO} is missing."
    assert os.access(JO, os.X_OK), f"The file {JO} is not executable."

    with open(JO, 'rb') as handle:
        assert handle.read(4) == b'\x7fELF', f"{JO} is not a compiled ELF binary."

    version = subprocess.run([JO, '-V'], text=True, capture_output=True, timeout=5)
    assert version.returncode == 0, f"The jo binary failed to run: {version.stderr}"
    assert '1.9' in version.stdout + version.stderr, \
        f"Expected jo version 1.9, got: {version.stdout}{version.stderr}"

    probe = subprocess.run(
        [JO, 'zeta=probe_z', 'alpha=probe_a'],
        text=True, capture_output=True, timeout=5
    )
    assert probe.returncode == 0, f"The jo binary failed its functional check: {probe.stderr}"
    try:
        probe_data = json.loads(probe.stdout)
    except ValueError:
        pytest.fail(f"The jo binary did not produce valid JSON: {probe.stdout}")
    assert probe_data == {'zeta': 'probe_z', 'alpha': 'probe_a'}, \
        f"The jo binary produced incorrect output: {probe_data}"


def test_server_response():
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}. Error: {e}")

    expected_data = {
        'build': 'pass',
        'deploy': 'fail',
        'integration': 'pass',
        'lint': 'pass',
        'unit': 'pass'
    }
    assert_status_response(response, expected_data)


def test_submitted_script_reads_both_files_and_uses_jo_per_request():
    assert os.path.isfile(SCRIPT), f"The server script {SCRIPT} is missing."

    with open(RESULT_A, 'rb') as handle:
        original_a = handle.read()
    with open(RESULT_B, 'rb') as handle:
        original_b = handle.read()

    real_jo = JO + '.verifier-real'
    log_path = f"/tmp/jo-called-{uuid.uuid4().hex}"
    server = None

    token1 = uuid.uuid4().hex
    token2 = uuid.uuid4().hex
    phase1_a = {'zulu_' + token1[:8]: 'v_' + token1, 'alpha_' + token1[:8]: 'v_a_' + token1}
    phase1_b = {'middle_' + token1[:8]: 'v_m_' + token1}
    phase2_a = {'theta_' + token2[:8]: 'v_t_' + token2, 'beta_' + token2[:8]: 'v_b_' + token2}
    phase2_b = {'omega_' + token2[:8]: 'v_o_' + token2, 'delta_' + token2[:8]: 'v_d_' + token2}

    def write_results(path, values):
        with open(path, 'w') as handle:
            for key, value in values.items():
                handle.write(f'{key}={value}\n')

    try:
        stop_existing_server()
        write_results(RESULT_A, phase1_a)
        write_results(RESULT_B, phase1_b)

        os.replace(JO, real_jo)
        with open(JO, 'w') as handle:
            handle.write('#!/bin/sh\n')
            handle.write(f"printf 'called\\n' >> {log_path!r}\n")
            handle.write(f'exec {real_jo} "$@"\n')
        os.chmod(JO, 0o755)

        server = subprocess.Popen(
            ['/bin/bash', SCRIPT],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            preexec_fn=os.setsid
        )

        first = request_with_retry()
        expected1 = dict(phase1_a)
        expected1.update(phase1_b)
        assert_status_response(first, expected1)

        # Change both inputs while the same server is running. The next response
        # must be recomputed from the new files rather than cached or hardcoded.
        if os.path.exists(log_path):
            os.unlink(log_path)
        write_results(RESULT_A, phase2_a)
        write_results(RESULT_B, phase2_b)

        second = request_with_retry()
        expected2 = dict(phase2_a)
        expected2.update(phase2_b)
        assert_status_response(second, expected2)
        assert os.path.isfile(log_path) and os.path.getsize(log_path) > 0, \
            'The server did not invoke the compiled /app/jo-1.9/jo binary for the request.'
    finally:
        with open(RESULT_A, 'wb') as handle:
            handle.write(original_a)
        with open(RESULT_B, 'wb') as handle:
            handle.write(original_b)

        if os.path.exists(real_jo):
            try:
                os.unlink(JO)
            except FileNotFoundError:
                pass
            os.replace(real_jo, JO)
        try:
            os.unlink(log_path)
        except FileNotFoundError:
            pass

        if server is not None:
            try:
                os.killpg(server.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        stop_existing_server()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
