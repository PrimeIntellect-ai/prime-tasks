#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess
import urllib.request
import urllib.error
import pytest


def post_file(url, file_path):
    boundary = "----BoundaryTest123456789"
    with open(file_path, "rb") as f:
        file_content = f.read()

    filename = os.path.basename(file_path)
    body = (
        f"--{boundary}\r\n"
        f"Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n"
        f"Content-Type: text/csv\r\n\r\n".encode('utf-8') +
        file_content +
        f"\r\n--{boundary}--\r\n".encode('utf-8')
    )

    req = urllib.request.Request(url, data=body)
    req.add_header('Content-Type', f'multipart/form-data; boundary={boundary}')

    try:
        response = urllib.request.urlopen(req, timeout=5)
        return response.getcode()
    except urllib.error.HTTPError as e:
        return e.code
    except urllib.error.URLError:
        return 0


def test_adversarial_corpus():
    clean_dir = '/app/corpus/clean/'
    evil_dir = '/app/corpus/evil/'
    url = 'http://127.0.0.1:8080/upload'

    assert os.path.isdir(clean_dir), f"{clean_dir} does not exist"
    assert os.path.isdir(evil_dir), f"{evil_dir} does not exist"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, "No clean files found in corpus"
    assert len(evil_files) > 0, "No evil files found in corpus"

    bypassed_evil = []
    modified_clean = []

    for cf in clean_files:
        code = post_file(url, cf)
        if code != 200:
            modified_clean.append(os.path.basename(cf))

    for ef in evil_files:
        code = post_file(url, ef)
        if code != 400:
            bypassed_evil.append(os.path.basename(ef))

    error_msg = []
    if bypassed_evil:
        error_msg.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if modified_clean:
        error_msg.append(f"{len(modified_clean)} of {len(clean_files)} clean modified: {', '.join(modified_clean)}")

    if error_msg:
        pytest.fail(" | ".join(error_msg))


def test_required_artifacts_and_sql_strategy():
    validator = '/home/user/validate.sh'
    assert os.path.isfile(validator), f"{validator} does not exist"
    with open(validator, 'r', encoding='utf-8', errors='replace') as f:
        script = f.read()

    assert re.search(r'\bsqlite3\b', script, re.IGNORECASE), "validator does not use sqlite3"
    assert re.search(r'\bwith\s+recursive\b', script, re.IGNORECASE), "validator does not contain a recursive CTE"
    assert re.search(
        r'\bcreate\s+(?:unique\s+)?index\b.*?\(\s*manager_id\s*\)',
        script,
        re.IGNORECASE | re.DOTALL,
    ), "validator does not create an index on manager_id"

    nginx_conf = '/app/nginx.conf'
    assert os.path.isfile(nginx_conf), f"{nginx_conf} does not exist"
    with open(nginx_conf, 'r', encoding='utf-8', errors='replace') as f:
        nginx_text = f.read()
    assert re.search(
        r'proxy_pass\s+http://127\.0\.0\.1:5000\s*;',
        nginx_text,
        re.IGNORECASE,
    ), "nginx does not proxy to the Flask service on 127.0.0.1:5000"


def has_cycle(rows):
    managers = {employee_id: manager_id for employee_id, _, manager_id in rows}
    done = set()

    for start in managers:
        if start in done:
            continue
        path = set()
        current = start
        while current in managers and current not in done:
            if current in path:
                return True
            path.add(current)
            manager = managers[current]
            if manager is None or manager == '':
                break
            current = manager
        done.update(path)
    return False


def write_case(path, rows):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        for employee_id, name, manager_id in rows:
            manager = '' if manager_id is None else manager_id
            f.write(f"{employee_id},{name},{manager}\n")


def make_random_case(rng, cyclic):
    count = rng.randint(7, 28)
    base = secrets.randbelow(800000000) + 100000000
    step = rng.choice([7, 11, 13, 17, 19])
    ids = [str(base + i * step) for i in range(count)]
    nonce = secrets.token_hex(5)
    rows = []

    for i, employee_id in enumerate(ids):
        if i == 0 or rng.random() < 0.22:
            manager = None
        else:
            manager = ids[rng.randrange(i)]
        rows.append([employee_id, f"employee_{nonce}_{i}", manager])

    if cyclic:
        cycle_size = rng.randint(2, min(6, count))
        cycle_indices = rng.sample(range(count), cycle_size)
        for pos, index in enumerate(cycle_indices):
            rows[index][2] = ids[cycle_indices[(pos + 1) % cycle_size]]

    rng.shuffle(rows)
    return [tuple(row) for row in rows]


def test_hidden_generated_corpus(tmp_path):
    rng = random.SystemRandom()
    nonce = secrets.token_hex(8)
    cases = [
        [('901001', f'root_{nonce}', None), ('901002', f'child_{nonce}', '901001')],
        [('902001', f'self_{nonce}', '902001')],
        [('903001', f'a_{nonce}', '903002'), ('903002', f'b_{nonce}', '903001')],
        [('904001', f'root_{nonce}', None), ('904002', f'leaf_{nonce}', '904001'),
         ('904003', f'x_{nonce}', '904004'), ('904004', f'y_{nonce}', '904005'),
         ('904005', f'z_{nonce}', '904003')],
    ]
    for i in range(8):
        cases.append(make_random_case(rng, cyclic=(i % 2 == 1)))

    rng.shuffle(cases)
    url = 'http://127.0.0.1:8080/upload'

    for index, rows in enumerate(cases):
        path = tmp_path / f"hidden_{nonce}_{index}_{secrets.token_hex(3)}.csv"
        write_case(path, rows)
        evil = has_cycle(rows)
        expected_exit = 1 if evil else 0
        expected_http = 400 if evil else 200

        try:
            result = subprocess.run(
                ['bash', '/home/user/validate.sh', str(path)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"validator timed out on generated case {index}")
        assert result.returncode == expected_exit, (
            f"validator returned {result.returncode} for generated case {index}; "
            f"expected {expected_exit}"
        )

        code = post_file(url, str(path))
        assert code == expected_http, (
            f"upload returned HTTP {code} for generated case {index}; "
            f"expected {expected_http}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
