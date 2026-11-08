#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import signal
import socket
import subprocess
import time

import numpy as np
import scipy.io.wavfile as wav
import pandas as pd
import pytest

HOME = '/home/user'
PLAN = f'{HOME}/scaling_plan.txt'
WAV_PATH = '/app/sonar_data.wav'
CHUNK_SIZE = 4410


def expected_values():
    assert os.path.exists(WAV_PATH), f"Ground truth audio {WAV_PATH} is missing."
    rate, data = wav.read(WAV_PATH)
    assert rate == 44100
    assert data.ndim == 1
    count = len(data) // CHUNK_SIZE
    rms_values = []
    replicas = []
    for i in range(count):
        chunk = data[i * CHUNK_SIZE:(i + 1) * CHUNK_SIZE].astype(np.float64)
        rms = np.sqrt(np.mean(chunk ** 2))
        rms_values.append(rms)
        replicas.append(max(1, int(rms / 500)))
    return rms_values, replicas


def validate_plan(path=PLAN):
    expected_rms, expected_replicas = expected_values()
    assert os.path.exists(path), f"Output file {path} does not exist."
    try:
        agent_df = pd.read_csv(path, header=None, names=['Chunk', 'RMS', 'Replicas'])
    except Exception as e:
        pytest.fail(f"Could not read {path} as CSV: {e}")

    count = len(expected_rms)
    assert len(agent_df) >= count, f"Expected at least {count} rows in {path}, got {len(agent_df)}"
    rows = agent_df.iloc[:count]
    assert np.array_equal(rows['Chunk'].to_numpy(), np.arange(count)), "Chunk IDs are not sequential from zero."

    agent_rms = pd.to_numeric(rows['RMS'], errors='raise').to_numpy(dtype=np.float64)
    assert np.all(np.isfinite(agent_rms)), "RMS values must be finite numbers."
    mse = np.mean((np.asarray(expected_rms) - agent_rms) ** 2)
    assert mse <= 0.1, f"MSE of RMS values is {mse}, which exceeds the threshold of 0.1."

    agent_replicas = pd.to_numeric(rows['Replicas'], errors='raise').to_numpy()
    assert np.array_equal(agent_replicas, expected_replicas), \
        "Replica counts do not match the expected formula Replicas = max(1, integer_part(RMS / 500))."
    return count


def listening_inodes(port):
    result = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == '0A' and int(local.rsplit(':', 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def pids_for_inodes(inodes):
    pids = set()
    if not inodes:
        return pids
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        fd_dir = f'/proc/{entry}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def kill_port(port):
    pids = pids_for_inodes(listening_inodes(port))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listening_inodes(port):
        time.sleep(0.05)
    for pid in pids_for_inodes(listening_inodes(port)):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listening_inodes(port):
        time.sleep(0.05)
    assert not listening_inodes(port), f"Could not free TCP port {port}"


def wait_for_port(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail(f"TCP port {port} did not become available")


def assert_ssh_tunnel_process():
    found = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            raw = open(f'/proc/{entry}/cmdline', 'rb').read()
            argv = [part.decode(errors='replace') for part in raw.split(b'\0') if part]
        except (FileNotFoundError, PermissionError):
            continue
        if not argv:
            continue
        executable = os.path.basename(argv[0])
        command = ' '.join(argv)
        if executable == 'ssh' and '9090' in command and '8080' in command:
            found.append(command)
    assert found, "No running SSH client establishing the required 9090-to-8080 tunnel was found."


def test_required_scripts_exist():
    """Check if the required bash scripts and C++ source exist."""
    assert os.path.exists('/home/user/start_api.sh'), 'Missing /home/user/start_api.sh'
    assert os.path.exists('/home/user/operator.cpp'), 'Missing /home/user/operator.cpp'
    assert os.path.exists('/home/user/deploy.sh'), 'Missing /home/user/deploy.sh'
    assert os.path.exists('/home/user/operator_bin'), 'Missing compiled binary /home/user/operator_bin'
    for path in ('/home/user/start_api.sh', '/home/user/operator.cpp', '/home/user/deploy.sh', '/home/user/operator_bin'):
        assert os.path.isfile(path), f'{path} must be a regular file'


def test_cpp_source_and_operator_binary_execute():
    binary = '/home/user/operator_bin'
    with open(binary, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'operator_bin is not a compiled ELF binary.'
    assert os.access(binary, os.X_OK), 'operator_bin is not executable.'

    rebuilt = '/tmp/operator_rebuilt'
    subprocess.run(
        ['g++', '-std=c++17', '-O2', '/home/user/operator.cpp', '-o', rebuilt],
        check=True, timeout=30
    )

    for executable in (rebuilt, binary):
        try:
            os.remove(PLAN)
        except FileNotFoundError:
            pass
        subprocess.run([executable], cwd=HOME, check=True, timeout=20)
        validate_plan()


def test_start_api_script_starts_background_python_http_server():
    kill_port(8080)
    proc = subprocess.Popen(
        ['setsid', 'bash', '/home/user/start_api.sh'],
        cwd=HOME, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        proc.wait(timeout=4)
        assert proc.returncode == 0, 'start_api.sh exited unsuccessfully.'
        wait_for_port(8080, timeout=5)
        response = subprocess.run(
            ['curl', '-fsS', '--max-time', '3', 'http://127.0.0.1:8080/'],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True
        )
        assert response.returncode == 0, f'start_api.sh did not provide an HTTP server: {response.stderr}'

        owners = pids_for_inodes(listening_inodes(8080))
        assert owners, 'No process owns the HTTP listener on port 8080.'
        python_owner = False
        for pid in owners:
            try:
                exe = os.path.basename(os.readlink(f'/proc/{pid}/exe')).lower()
                cmd = open(f'/proc/{pid}/cmdline', 'rb').read().lower()
                if 'python' in exe or b'python' in cmd:
                    python_owner = True
            except (FileNotFoundError, PermissionError):
                pass
        assert python_owner, 'The API server on port 8080 was not a Python HTTP server.'
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        kill_port(8080)


def test_deploy_uses_operator_and_posts_json_through_ssh_tunnel():
    assert_ssh_tunnel_process()
    kill_port(8080)
    log_path = '/tmp/captured_posts.jsonl'
    try:
        os.remove(log_path)
    except FileNotFoundError:
        pass

    server_code = r'''
import http.server, json
LOG = '/tmp/captured_posts.jsonl'
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'ok')
    def do_POST(self):
        n = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(n)
        with open(LOG, 'ab', buffering=0) as f:
            f.write(body + b'\n')
        self.send_response(200); self.end_headers(); self.wfile.write(b'ok')
    def log_message(self, *args):
        pass
http.server.ThreadingHTTPServer(('127.0.0.1', 8080), Handler).serve_forever()
'''
    server = subprocess.Popen(['python3', '-c', server_code])
    original = '/home/user/operator_bin'
    saved = '/tmp/operator_bin.saved'
    marker = '/tmp/operator_was_invoked'
    try:
        wait_for_port(8080)
        probe = subprocess.run(
            ['curl', '-fsS', '--max-time', '4', '-X', 'POST', '-H', 'Content-Type: application/json',
             '--data', '{"probe":true}', 'http://localhost:9090/probe'],
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True
        )
        assert probe.returncode == 0, f'The SSH tunnel did not forward 9090 to 8080: {probe.stderr}'
        open(log_path, 'w').close()

        os.replace(original, saved)
        with open(original, 'w') as f:
            f.write('#!/bin/bash\necho invoked > /tmp/operator_was_invoked\nexec /tmp/operator_bin.saved "$@"\n')
        os.chmod(original, 0o755)
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass
        try:
            os.remove(PLAN)
        except FileNotFoundError:
            pass

        result = subprocess.run(
            ['bash', '/home/user/deploy.sh'], cwd=HOME, timeout=30,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert result.returncode == 0, f'deploy.sh failed: {result.stderr}'
        assert os.path.exists(marker), 'deploy.sh did not execute /home/user/operator_bin.'
        count = validate_plan()
        time.sleep(0.5)

        with open(log_path) as f:
            payloads = [json.loads(line) for line in f if line.strip()]
        _, replicas = expected_values()
        expected = [{'chunk': i, 'replicas': replicas[i]} for i in range(count)]
        assert payloads == expected, f'deploy.sh sent incorrect JSON POST payloads: {payloads}'
    finally:
        if os.path.exists(saved):
            try:
                os.remove(original)
            except FileNotFoundError:
                pass
            os.replace(saved, original)
        server.terminate()
        try:
            server.wait(timeout=3)
        except subprocess.TimeoutExpired:
            server.kill()
        kill_port(8080)


def test_scaling_plan_mse():
    """Check the MSE of the RMS calculation and verify Replica counts."""
    output_file = '/home/user/scaling_plan.txt'
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."

    # Read ground truth audio
    wav_path = '/app/sonar_data.wav'
    assert os.path.exists(wav_path), f"Ground truth audio {wav_path} is missing."

    rate, data = wav.read(wav_path)
    chunk_size = 4410
    num_chunks = len(data) // chunk_size

    expected_rms = []
    expected_replicas = []
    for i in range(num_chunks):
        chunk = data[i*chunk_size : (i+1)*chunk_size].astype(np.float64)
        rms = np.sqrt(np.mean(chunk**2))
        expected_rms.append(rms)
        expected_replicas.append(max(1, int(rms / 500)))

    # Read agent's output
    try:
        agent_df = pd.read_csv(output_file, header=None, names=['Chunk', 'RMS', 'Replicas'])
    except Exception as e:
        pytest.fail(f"Could not read {output_file} as CSV: {e}")

    assert len(agent_df) >= num_chunks, f"Expected at least {num_chunks} rows in {output_file}, got {len(agent_df)}"

    agent_rms = agent_df['RMS'].values[:num_chunks]

    # Calculate MSE
    mse = np.mean((np.array(expected_rms) - agent_rms)**2)
    assert mse <= 0.1, f"MSE of RMS values is {mse}, which exceeds the threshold of 0.1."

    # Verify Replicas
    agent_replicas = agent_df['Replicas'].values[:num_chunks]
    replicas_match = np.array_equal(agent_replicas, expected_replicas)
    assert replicas_match, "Replica counts do not match the expected formula Replicas = max(1, integer_part(RMS / 500))."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
