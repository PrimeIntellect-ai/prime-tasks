#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import csv
import json
import os
import random
import secrets
import signal
import subprocess
import time
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen

HOME = Path('/home/user')
SERVER = HOME / 'server'
SOURCE = HOME / 'graph_server.cpp'
DATASET = HOME / 'dataset.csv'
BUILT = Path('/tmp/server_rebuilt_from_submission')


def assert_elf(path):
    assert path.is_file(), f'Compiled server binary not found at {path}'
    assert os.access(path, os.X_OK), f'Server binary at {path} is not executable'
    with path.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'{path} is not a compiled ELF executable'


def request(name, timeout=5):
    url = 'http://127.0.0.1:8080/coauthors?' + urlencode({'name': name})
    try:
        with urlopen(url, timeout=timeout) as response:
            status = response.status
            body = response.read().decode('utf-8')
    except Exception as e:
        raise AssertionError(f'Failed to query {url}: {e}')
    assert status == 200, f'Expected HTTP 200, got {status}. Response: {body}'
    try:
        data = json.loads(body)
    except Exception:
        raise AssertionError(f'Response is not valid JSON: {body}')
    return data


def assert_response(name, expected, timeout=5):
    data = request(name, timeout)
    assert isinstance(data, dict), f'Expected a JSON object, got {type(data)}'
    assert set(data) == {'author', 'coauthors'}, f'Unexpected JSON schema: {data}'
    assert data['author'] == name, f'Expected author {name!r}, got {data.get("author")!r}'
    assert isinstance(data['coauthors'], list), "Expected 'coauthors' to be a list"
    assert all(isinstance(x, str) for x in data['coauthors']), 'Every coauthor must be a string'
    assert len(data['coauthors']) == len(set(data['coauthors'])), 'Coauthors were not deduplicated'
    assert name not in data['coauthors'], 'Requested author was included as a coauthor'
    assert set(data['coauthors']) == set(expected), \
        f'For {name!r}, expected {sorted(expected)!r}, got {data["coauthors"]!r}'


def listening_inodes():
    result = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[1].split(':')[-1].upper() == '1F90' and fields[3] == '0A':
                result.add(fields[9])
    return result


def stop_port():
    inodes = listening_inodes()
    if inodes:
        for entry in Path('/proc').iterdir():
            if not entry.name.isdigit() or int(entry.name) == os.getpid():
                continue
            try:
                for fd in (entry / 'fd').iterdir():
                    try:
                        target = os.readlink(fd)
                    except OSError:
                        continue
                    if target.startswith('socket:[') and target[8:-1] in inodes:
                        os.kill(int(entry.name), signal.SIGKILL)
                        break
            except (OSError, PermissionError):
                pass
    deadline = time.time() + 5
    while listening_inodes() and time.time() < deadline:
        time.sleep(0.05)
    assert not listening_inodes(), 'Could not stop the process listening on port 8080'


def start_server(executable):
    log = open('/tmp/verified_server.log', 'ab', buffering=0)
    proc = subprocess.Popen([str(executable)], cwd=str(HOME), stdout=log, stderr=log)
    deadline = time.time() + 8
    while time.time() < deadline:
        if proc.poll() is not None:
            log.close()
            raise AssertionError(f'{executable} exited before accepting requests')
        try:
            request('__readiness_probe__', timeout=0.3)
            return proc, log
        except AssertionError:
            time.sleep(0.1)
    proc.kill()
    proc.wait()
    log.close()
    raise AssertionError(f'{executable} did not listen on 127.0.0.1:8080')


def write_hidden_dataset():
    tag = secrets.token_hex(8)
    names = {k: f'{k}_{tag}' for k in ('Target', 'PeerOne', 'PeerTwo', 'OldPeer', 'Other', 'Extra')}
    base = int.from_bytes(os.urandom(3), 'big') + 10000
    eligible = base
    old = base + 1
    solo = base + 2
    unrelated = base + 3
    rows = [
        (11, names['Target'], eligible, 2021),
        (12, names['PeerOne'], eligible, 2021),
        (13, names['PeerTwo'], eligible, 2021),
        (13, names['PeerTwo'], eligible, 2021),
        (11, names['Target'], old, 2020),
        (14, names['OldPeer'], old, 2020),
        (11, names['Target'], solo, 2024),
        (15, names['Other'], unrelated, 2025),
        (16, names['Extra'], eligible, 2021),
    ]
    # Numerous unpredictable unrelated records ensure a cross join cannot
    # accidentally produce the expected result.
    for i in range(300):
        rows.append((1000 + i, f'Decoy_{tag}_{i}', base + 1000 + i, 2022 + i % 4))
    random.SystemRandom().shuffle(rows)
    with DATASET.open('w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['AuthorID', 'AuthorName', 'PaperID', 'PaperYear'])
        writer.writerows(rows)
    expected = {
        names['Target']: {names['PeerOne'], names['PeerTwo'], names['Extra']},
        names['PeerOne']: {names['Target'], names['PeerTwo'], names['Extra']},
        names['PeerTwo']: {names['Target'], names['PeerOne'], names['Extra']},
        names['OldPeer']: set(),
        names['Other']: set(),
        f'Unknown_{tag}': set(),
    }
    return expected


assert_elf(SERVER)
assert SOURCE.is_file(), f'Missing source file: {SOURCE}'

# Preserve the original verifier's assertions against the deployed service.
assert_response('Alice', {'Charlie'})
assert_response('Bob', set())
assert_response('Charlie', {'Alice'})
assert_response('David', set())

# Ensure the submitted source still compiles using the required toolchain.
subprocess.run(
    ['g++', '-O3', '-std=c++17', str(SOURCE), '-o', str(BUILT)],
    cwd=str(HOME), check=True, timeout=60,
)
assert_elf(BUILT)

original_dataset = DATASET.read_bytes()
try:
    # Restart the submitted artifact on a verifier-generated dataset unknown to
    # the agent, then derive and check all answers from that dataset.
    stop_port()
    expected = write_hidden_dataset()
    proc, log = start_server(SERVER)
    try:
        for name, answer in expected.items():
            assert_response(name, answer)
    finally:
        proc.kill()
        proc.wait()
        log.close()
        stop_port()

    # Independently execute a fresh build of the submitted C++ source on a
    # second hidden dataset, preventing a correct source/fake deployed binary split.
    expected = write_hidden_dataset()
    proc, log = start_server(BUILT)
    try:
        for name, answer in expected.items():
            assert_response(name, answer)
    finally:
        proc.kill()
        proc.wait()
        log.close()
        stop_port()
finally:
    DATASET.write_bytes(original_dataset)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
