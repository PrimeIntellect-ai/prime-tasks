#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import pwd
import random
import re
import shutil
import subprocess
import tempfile
import uuid
import xml.etree.ElementTree as ET
from collections import defaultdict

PIPELINE = '/home/user/pipeline.py'
OUTPUT = '/home/user/cleaned_sample.json'
WORKER = '/app/etl_worker'
LINE_RE = re.compile(r'^(\d+)\|(\d+)\|(JSON|CSV|XML)\|(.*)$')


def parse_worker_output(text):
    first_by_id = {}
    for line in text.splitlines():
        match = LINE_RE.fullmatch(line)
        assert match, f'Worker emitted an unparsable line: {line[:200]!r}'
        header_id, timestamp, fmt, payload = match.groups()
        header_id = int(header_id)
        timestamp = int(timestamp)

        if fmt == 'JSON':
            item = json.loads(payload)
            record_id = item['id']
            category = item['category']
            value = item['value']
        elif fmt == 'CSV':
            fields = next(csv.reader([payload]))
            assert len(fields) == 3
            record_id, category, value = int(fields[0]), fields[1], float(fields[2])
        else:
            root = ET.fromstring(payload)
            record_id = int(root.findtext('id'))
            category = root.findtext('category')
            value = float(root.findtext('value'))

        assert record_id == header_id
        assert category in {'A', 'B', 'C'}
        record = {
            'id': int(record_id),
            'category': category,
            'value': float(value),
            '_timestamp': timestamp,
        }
        old = first_by_id.get(record_id)
        if old is None or timestamp < old['_timestamp']:
            first_by_id[record_id] = record

    return sorted(first_by_id.values(), key=lambda r: r['_timestamp'])


def build_expected(real_worker):
    proc = subprocess.run(
        [real_worker, '50000'], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=60, check=False
    )
    assert proc.returncode == 0, f'etl_worker failed while building oracle: {proc.stderr}'
    records = parse_worker_output(proc.stdout)

    # The generated stream's global calibration jump begins after record 35000.
    clean = [r for r in records if r['id'] <= 35000]
    assert len(clean) == 35000
    assert any(r['value'] > 1000 for r in records if r['id'] > 35000)
    assert all(r['value'] < 100 for r in clean)

    groups = defaultdict(list)
    for record in clean:
        groups[record['category']].append(record)

    rng = random.Random(42)
    expected = []
    for category_records in groups.values():
        expected.extend(rng.sample(category_records, int(len(category_records) * 0.20)))

    return [
        {'id': r['id'], 'category': r['category'], 'value': r['value']}
        for r in expected
    ]


def load_and_validate_output():
    assert os.path.exists(OUTPUT), f'Expected output file {OUTPUT} does not exist.'
    try:
        with open(OUTPUT, 'r') as f:
            data = json.load(f)
    except Exception as exc:
        assert False, f'Failed to parse {OUTPUT} as JSON: {exc}'

    assert isinstance(data, list), 'Output JSON must be an array of objects.'
    for item in data:
        assert isinstance(item, dict), 'Every output record must be an object.'
        assert {'id', 'category', 'value'} <= set(item), 'Record is missing a required field.'
        assert type(item['id']) is int, 'Record id must be an integer.'
        assert item['category'] in {'A', 'B', 'C'}, 'Invalid category.'
        assert type(item['value']) in (int, float), 'Record value must be numeric.'
    return data


def run_as_user():
    account = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    env = os.environ.copy()
    env['HOME'] = '/home/user'
    return subprocess.run(
        [PIPELINE], cwd='/home/user', env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90,
        preexec_fn=demote, check=False
    )


def test_cleaned_sample_metric():
    assert os.path.exists(PIPELINE), 'Expected script /home/user/pipeline.py does not exist.'
    assert os.path.isfile(PIPELINE), 'pipeline.py must be a regular file.'
    assert os.access(PIPELINE, os.X_OK), 'pipeline.py must be executable.'
    assert os.path.isfile(WORKER) and os.access(WORKER, os.X_OK)

    token = uuid.uuid4().hex
    real_worker = f'/app/.etl_worker_{token}'
    call_log = f'/tmp/.etl_calls_{token}'
    wrapper_bin = f'/tmp/.etl_wrapper_{token}'
    wrapper_src = f'/tmp/.etl_wrapper_{token}.c'

    # A setuid logging shim proves that the submitted pipeline itself invokes the
    # required worker with argument 50000. It drops privilege before executing it.
    source = f'''#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
int main(int argc, char **argv) {{
    uid_t u = getuid(); gid_t g = getgid();
    int fd = open("{call_log}", O_WRONLY|O_APPEND);
    if (fd < 0) return 111;
    dprintf(fd, "%d %s\\n", argc, argc > 1 ? argv[1] : "");
    close(fd);
    if (setgid(g) || setuid(u)) return 112;
    execv("{real_worker}", argv);
    return 113;
}}
'''

    with open(wrapper_src, 'w') as f:
        f.write(source)
    subprocess.run(['gcc', '-O2', wrapper_src, '-o', wrapper_bin], check=True)
    with open(call_log, 'w'):
        pass
    os.chmod(call_log, 0o600)

    os.replace(WORKER, real_worker)
    try:
        expected = build_expected(real_worker)
        expected_map = {r['id']: (r['category'], float(r['value'])) for r in expected}
        assert len(expected_map) == len(expected)

        shutil.copy2(wrapper_bin, WORKER)
        os.chown(WORKER, 0, 0)
        os.chmod(WORKER, 0o4755)

        runs = []
        for _ in range(2):
            if os.path.lexists(OUTPUT):
                os.unlink(OUTPUT)
            proc = run_as_user()
            assert proc.returncode == 0, (
                f'pipeline.py failed with exit code {proc.returncode}. '
                f'stderr: {proc.stderr[-2000:]}'
            )
            runs.append(load_and_validate_output())

        assert runs[0] == runs[1], 'Seed 42 must make repeated pipeline runs reproducible.'
        data = runs[0]

        with open(call_log) as f:
            calls = [line.strip() for line in f if line.strip()]
        assert calls == ['2 50000', '2 50000'], (
            'Each pipeline run must execute /app/etl_worker with exactly the argument 50000.'
        )

        actual_map = {r['id']: (r['category'], float(r['value'])) for r in data}
        assert len(actual_map) == len(data), 'Duplicate ids remain in the sampled output.'
        assert actual_map == expected_map, (
            'Output does not match the clean, first-occurrence, pre-changepoint, '
            'seed-42 stratified sample derived from the worker stream.'
        )

        # Preserve the original metric assertions.
        selected_ids = [d.get('id') for d in data if 'id' in d]
        assert len(selected_ids) > 0, "No valid records with 'id' found in cleaned_sample.json."
        valid = sum(1 for x in selected_ids if x <= 35000)
        invalid = sum(1 for x in selected_ids if x > 35000)
        duplicates = len(selected_ids) - len(set(selected_ids))
        expected_count = 7000
        score = 1.0
        if invalid > 0:
            score -= invalid / len(selected_ids)
        if duplicates > 0:
            score -= duplicates / len(selected_ids)
        count_diff = abs(len(selected_ids) - expected_count)
        if count_diff > 500:
            score -= 0.5
        elif count_diff > 100:
            score -= 0.2
        score = max(0.0, score)
        assert score >= 0.95, (
            f'Metric threshold failed: score {score:.3f} < 0.95. '
            f'Total records: {len(selected_ids)}, Invalid (>35000): {invalid}, '
            f'Duplicates: {duplicates}, Expected count: {expected_count}.'
        )
    finally:
        if os.path.lexists(WORKER):
            os.unlink(WORKER)
        if os.path.exists(real_worker):
            os.replace(real_worker, WORKER)
        for path in (call_log, wrapper_bin, wrapper_src):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
