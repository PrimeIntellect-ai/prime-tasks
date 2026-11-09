#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import hashlib
import subprocess
import shutil
import time
import tarfile
import secrets
import signal
import pytest


def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))


def create_fuzz_staging_dir(base_dir, num_records):
    os.makedirs(base_dir, exist_ok=True)
    manifest_lines = []

    for i in range(num_records):
        filename = f"{generate_random_string(random.randint(5, 15))}.ext"
        category = generate_random_string(random.randint(3, 10))

        # Decide if this record will be valid, corrupted hash, or missing file
        status = random.choices(['valid', 'corrupt', 'missing'], weights=[80, 10, 10])[0]

        file_content = os.urandom(random.randint(10, 100))
        actual_hash = hashlib.sha256(file_content).hexdigest()

        if status == 'corrupt':
            expected_hash = hashlib.sha256(os.urandom(10)).hexdigest()
        else:
            expected_hash = actual_hash

        manifest_lines.append(f"Filename: {filename}")
        manifest_lines.append(f"Category: {category}")
        manifest_lines.append(f"SHA256: {expected_hash}")
        manifest_lines.append("---")

        if status != 'missing':
            # Create file at random depth
            depth = random.randint(1, 5)
            current_dir = base_dir
            for _ in range(depth):
                subdir = generate_random_string(5)
                current_dir = os.path.join(current_dir, subdir)
                os.makedirs(current_dir, exist_ok=True)

            file_path = os.path.join(current_dir, filename)
            with open(file_path, 'wb') as f:
                f.write(file_content)

    manifest_path = os.path.join(base_dir, 'manifest.txt')
    with open(manifest_path, 'w') as f:
        f.write('\n'.join(manifest_lines) + '\n')


def stop_pipeline_processes():
    subprocess.run(['/usr/bin/redis-cli', '-p', '6379', 'shutdown', 'nosave'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    patterns = (
        '/app/ingestion/worker.py',
        '/app/ingestion/app.py',
        'flask run --port=5000',
        'nginx: master process',
        'nginx: worker process',
        'redis-server',
    )
    victims = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                cmdline = f.read().replace(b'\0', b' ').decode(errors='ignore')
            if any(pattern in cmdline for pattern in patterns):
                os.kill(int(entry), signal.SIGTERM)
                victims.append(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass

    time.sleep(1)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    for pidfile in ('/run/nginx.pid', '/var/run/nginx.pid', '/var/run/redis/redis-server.pid'):
        try:
            os.unlink(pidfile)
        except FileNotFoundError:
            pass


def test_pipeline_configs_fixed():
    nginx_conf = "/app/ingestion/nginx.conf"
    worker_env = "/app/ingestion/worker.env"

    assert os.path.exists(nginx_conf), f"Missing {nginx_conf}"
    with open(nginx_conf, 'r') as f:
        content = f.read()
    assert "127.0.0.1:5000" in content, "nginx.conf not updated to proxy_pass 127.0.0.1:5000"

    assert os.path.exists(worker_env), f"Missing {worker_env}"
    with open(worker_env, 'r') as f:
        content = f.read()
    assert "REDIS_PORT=6379" in content, "worker.env not updated to REDIS_PORT=6379"


def test_pipeline_end_to_end_upload_and_extraction():
    start_script = '/app/ingestion/start_services.sh'
    assert os.path.isfile(start_script), f"Missing {start_script}"
    assert os.access(start_script, os.X_OK), f"{start_script} is not executable"

    stop_pipeline_processes()

    started = subprocess.run([start_script], capture_output=True, text=True, timeout=15)
    assert started.returncode == 0, (
        f"start_services.sh failed with code {started.returncode}: "
        f"{started.stdout}\n{started.stderr}"
    )

    # Wait for Redis, then clear any stale jobs before submitting this probe.
    redis_ready = False
    for _ in range(30):
        ping = subprocess.run(['/usr/bin/redis-cli', '-p', '6379', 'ping'],
                              capture_output=True, text=True)
        if ping.returncode == 0 and ping.stdout.strip() == 'PONG':
            redis_ready = True
            break
        time.sleep(0.25)
    assert redis_ready, 'Redis did not start on port 6379'
    subprocess.run(['/usr/bin/redis-cli', '-p', '6379', 'flushall'], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    token = secrets.token_hex(16)
    probe_root = f'/tmp/pipeline_probe_{token}'
    archive_path = f'{probe_root}.tar.gz'
    nested_dir = os.path.join(probe_root, f'probe_{token}', 'nested')
    os.makedirs(nested_dir)
    filename = f'payload_{token}.bin'
    payload = os.urandom(257)
    source_file = os.path.join(nested_dir, filename)
    with open(source_file, 'wb') as f:
        f.write(payload)

    with tarfile.open(archive_path, 'w:gz') as tar:
        tar.add(os.path.join(probe_root, f'probe_{token}'), arcname=f'probe_{token}')

    response = None
    last_error = ''
    for _ in range(40):
        response = subprocess.run(
            ['/usr/bin/curl', '-sS', '-f', '--max-time', '3',
             '-F', f'file=@{archive_path}', 'http://127.0.0.1:8080/upload'],
            capture_output=True, text=True
        )
        if response.returncode == 0:
            break
        last_error = response.stderr
        time.sleep(0.25)

    assert response is not None and response.returncode == 0, (
        f'Upload through nginx on port 8080 failed: {last_error}'
    )
    assert response.stdout == 'OK\n', f'Unexpected upload response: {response.stdout!r}'

    extracted = None
    deadline = time.time() + 20
    while time.time() < deadline:
        for root, _, files in os.walk('/home/user/staging'):
            if filename in files and os.path.basename(os.path.dirname(root)) == f'probe_{token}':
                candidate = os.path.join(root, filename)
                try:
                    with open(candidate, 'rb') as f:
                        if f.read() == payload:
                            extracted = candidate
                            break
                except FileNotFoundError:
                    pass
        if extracted:
            break
        time.sleep(0.25)

    assert extracted is not None, (
        'The uploaded archive was not extracted by the worker under /home/user/staging/<job_id>/'
    )
    relative = os.path.relpath(extracted, '/home/user/staging').split(os.sep)
    assert len(relative) >= 4, f'Extracted file is not beneath a staging job directory: {extracted}'

    shutil.rmtree(probe_root, ignore_errors=True)
    try:
        os.unlink(archive_path)
    except FileNotFoundError:
        pass


def test_dataset_linker_fuzz_equivalence():
    agent_script = "/home/user/dataset_linker.sh"
    oracle_bin = "/app/oracle_linker"

    assert os.path.exists(agent_script), f"Missing {agent_script}"
    assert os.access(agent_script, os.X_OK), f"{agent_script} is not executable"
    with open(agent_script, 'rb') as f:
        agent_bytes = f.read()
    with open(oracle_bin, 'rb') as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "dataset_linker.sh must not be a byte-identical copy of the oracle"

    random.seed(42)

    for i in range(100):
        fuzz_base = f"/tmp/fuzz_test_{i}"
        staging_dir = os.path.join(fuzz_base, "staging")
        agent_out = os.path.join(fuzz_base, "agent_out")
        oracle_out = os.path.join(fuzz_base, "oracle_out")

        if os.path.exists(fuzz_base):
            shutil.rmtree(fuzz_base)

        os.makedirs(agent_out)
        os.makedirs(oracle_out)

        num_records = random.randint(0, 50)
        create_fuzz_staging_dir(staging_dir, num_records)

        # Run oracle
        oracle_res = subprocess.run([oracle_bin, staging_dir, oracle_out], capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on iteration {i}"

        # Run agent
        agent_res = subprocess.run([agent_script, staging_dir, agent_out], capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on iteration {i}. Stderr: {agent_res.stderr}"

        # Compare directories
        diff_res = subprocess.run(["diff", "-r", oracle_out, agent_out], capture_output=True, text=True)
        assert diff_res.returncode == 0, f"Output mismatch on iteration {i}:\n{diff_res.stdout}"

        # Check hardlinks
        for root, _, files in os.walk(agent_out):
            for file in files:
                agent_file = os.path.join(root, file)
                # Find the source file in staging
                source_found = False
                for src_root, _, src_files in os.walk(staging_dir):
                    if file in src_files:
                        src_file = os.path.join(src_root, file)
                        if os.stat(agent_file).st_ino == os.stat(src_file).st_ino:
                            source_found = True
                            break
                assert source_found, f"File {agent_file} is not a hardlink to the source file in staging"

        shutil.rmtree(fuzz_base)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
