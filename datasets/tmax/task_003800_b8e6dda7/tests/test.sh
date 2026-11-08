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
import random
import secrets
import shutil
import signal
import string
import subprocess
import time
from pathlib import Path

import pytest
import requests

PORTS = (8000, 8080, 9000)
PROCESSES = []
INGEST_FILE = Path('/home/user/app/ingest/data.json')
ORIGINAL_RAW = 'Hello, World! Data Science 123.'


def expected_tokens(text):
    return ''.join(ch for ch in text.lower() if ch.isalnum() or ch.isspace()).split()


def rust_string(value):
    return json.dumps(value)


def make_random_text():
    punctuation = '!@#$%^&*()_+-=[]{};:\\|,.<>/?~`'
    pieces = []
    for _ in range(random.SystemRandom().randint(3, 9)):
        word = ''.join(secrets.choice(string.ascii_letters + string.digits)
                       for _ in range(random.SystemRandom().randint(2, 12)))
        if len(word) > 2:
            pos = random.SystemRandom().randint(1, len(word) - 1)
            word = word[:pos] + secrets.choice(punctuation) + word[pos:]
        pieces.append(secrets.choice(punctuation) + word + secrets.choice(punctuation))
    separators = [' ', '  ', '\t', '\n', ' \t ']
    return ''.join(piece + (secrets.choice(separators) if i + 1 < len(pieces) else '')
                   for i, piece in enumerate(pieces))


def kill_port_listeners(ports):
    wanted_inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != '0A':
                continue
            try:
                port = int(fields[1].rsplit(':', 1)[1], 16)
            except (ValueError, IndexError):
                continue
            if port in ports:
                wanted_inodes.add(fields[9])

    victims = set()
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        fd_dir = proc / 'fd'
        try:
            fds = list(fd_dir.iterdir())
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in wanted_inodes:
                victims.add(int(proc.name))
                break

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.5)


def run_checked(command, cwd, timeout=300):
    result = subprocess.run(
        command, cwd=cwd, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=timeout
    )
    assert result.returncode == 0, (
        f"Command {' '.join(command)} failed in {cwd}:\n{result.stdout}"
    )


def wait_for_json(url, process, timeout=20):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f'Process for {url} exited with status {process.returncode}')
        try:
            response = requests.get(url, timeout=1)
            if response.status_code == 200:
                response.json()
                return
        except (requests.RequestException, ValueError) as exc:
            last_error = exc
        time.sleep(0.2)
    pytest.fail(f'Service at {url} did not become ready: {last_error}')


@pytest.fixture(scope='session', autouse=True)
def rebuild_and_start_requested_artifacts():
    cleaner = Path('/home/user/app/cleaner')
    serving = Path('/home/user/app/serving')
    cleaner_source = cleaner / 'src/main.rs'
    assert cleaner_source.is_file(), f'Missing requested source file {cleaner_source}'

    # Exercise clean_and_tokenize directly from a fresh copy of the submitted Rust
    # project using verifier-generated inputs, in addition to testing the service.
    test_project = Path('/tmp/verifier_cleaner_project')
    shutil.rmtree(test_project, ignore_errors=True)
    shutil.copytree(cleaner, test_project, ignore=shutil.ignore_patterns('target'))
    direct_cases = [
        'MIXED case, punctuation... and 0099!',
        'joined-word SHOULD_remain\tSeparate\nLines',
    ] + [make_random_text() for _ in range(6)]
    module_name = 'verifier_' + secrets.token_hex(8)
    assertions = []
    for raw in direct_cases:
        expected = expected_tokens(raw)
        expected_expr = ', '.join(f'String::from({rust_string(token)})' for token in expected)
        assertions.append(
            f'assert_eq!(super::clean_and_tokenize({rust_string(raw)}), vec![{expected_expr}]);'
        )
    with open(test_project / 'src/main.rs', 'a') as source:
        source.write(
            f'\n#[cfg(test)]\nmod {module_name} {{\n'
            '    #[test]\n    fn verifier_generated_cleaning_cases() {\n        '
            + '\n        '.join(assertions)
            + '\n    }\n}\n'
        )
    run_checked(['cargo', 'test', '--release', '--bin', 'cleaner', '--', '--nocapture'],
                str(test_project))

    # Build the actual requested binaries from the submitted projects. The verifier
    # then launches these exact artifacts, so pre-existing substitute servers cannot pass.
    run_checked(['cargo', 'build', '--release', '--bin', 'cleaner'], str(cleaner))
    run_checked(['cargo', 'build', '--release', '--bin', 'serving'], str(serving))

    kill_port_listeners(PORTS)
    INGEST_FILE.write_text(json.dumps({'raw': ORIGINAL_RAW}))

    PROCESSES.extend([
        subprocess.Popen(
            ['python3', '-m', 'http.server', '8000'],
            cwd='/home/user/app/ingest', stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True
        ),
        subprocess.Popen(
            ['/home/user/app/cleaner/target/release/cleaner'],
            cwd='/home/user/app/cleaner', stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True
        ),
        subprocess.Popen(
            ['/home/user/app/serving/target/release/serving'],
            cwd='/home/user/app/serving', stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True
        ),
    ])

    wait_for_json('http://localhost:8000/data.json', PROCESSES[0])
    wait_for_json('http://localhost:8080/data', PROCESSES[1])
    wait_for_json('http://localhost:9000/predict', PROCESSES[2])
    yield


def test_pipeline_status_log():
    log_file = "/home/user/pipeline_status.log"
    assert os.path.isfile(log_file), f"Log file {log_file} is missing."
    with open(log_file, "r") as f:
        content = f.read().strip()
    assert "READY" in content, f"Log file {log_file} does not contain the word 'READY'. Found: '{content}'"


def test_env_configuration():
    env_file = "/home/user/app/serving/.env"
    assert os.path.isfile(env_file), f"Environment file {env_file} is missing."
    with open(env_file, "r") as f:
        content = f.read()
    assert "CLEANER_URL=http://localhost:8080/data" in content, (
        f"Environment file {env_file} does not contain the correct CLEANER_URL. "
        f"Contents: {content}"
    )


def test_data_ingest_service():
    url = "http://localhost:8000/data.json"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to data_ingest service at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 from {url}, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {url} is not valid JSON: {response.text}")

    assert "raw" in data, f"Expected key 'raw' in response from {url}, got {data}"
    assert data["raw"] == "Hello, World! Data Science 123.", (
        f"Unexpected raw data from {url}: {data['raw']}"
    )


def test_cleaning_worker_service():
    url = "http://localhost:8080/data"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to cleaning_worker service at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 from {url}, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {url} is not valid JSON: {response.text}")

    expected = ["hello", "world", "data", "science", "123"]
    assert isinstance(data, list), f"Expected JSON array from {url}, got {type(data)}"
    assert data == expected, f"Expected tokens {expected} from {url}, got {data}"


def test_model_serving_service():
    url = "http://localhost:9000/predict"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to model_serving service at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 from {url}, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {url} is not valid JSON: {response.text}")

    assert "status" in data, f"Expected key 'status' in response from {url}, got {data}"
    assert data["status"] == "success", f"Expected status 'success' from {url}, got {data['status']}"
    assert "score" in data, f"Expected key 'score' in response from {url}, got {data}"

    expected_score = 42.0
    assert abs(data["score"] - expected_score) < 0.01, (
        f"Expected score close to {expected_score} from {url}, got {data['score']}"
    )


def test_pipeline_on_verifier_generated_inputs():
    cases = [make_random_text() for _ in range(5)]
    try:
        for raw in cases:
            expected = expected_tokens(raw)
            temp = INGEST_FILE.with_suffix('.json.tmp')
            temp.write_text(json.dumps({'raw': raw}))
            os.replace(temp, INGEST_FILE)

            cleaner_response = requests.get('http://localhost:8080/data', timeout=5)
            assert cleaner_response.status_code == 200
            assert cleaner_response.json() == expected, (
                f'Cleaner returned {cleaner_response.text} for verifier-generated input {raw!r}; '
                f'expected {expected!r}'
            )

            serving_response = requests.get('http://localhost:9000/predict', timeout=5)
            assert serving_response.status_code == 200
            prediction = serving_response.json()
            assert prediction.get('status') == 'success'
            assert isinstance(prediction.get('score'), (int, float))
            assert abs(prediction['score'] - len(expected) * 8.4) < 0.01
    finally:
        INGEST_FILE.write_text(json.dumps({'raw': ORIGINAL_RAW}))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
