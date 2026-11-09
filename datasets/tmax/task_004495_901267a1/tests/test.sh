#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import re
import stat
import subprocess
import time
import uuid
from pathlib import Path

HOME = Path('/home/user')
NORMALIZE = HOME / 'normalize.py'
AGGREGATE = HOME / 'aggregate.py'
PIPELINE = HOME / 'pipeline.sh'
RAW = HOME / 'raw_translations.jsonl'
FINAL = HOME / 'final_translations.csv'


def run(cmd, *, input_text=None, timeout=15):
    return subprocess.run(
        cmd,
        input=input_text,
        text=True,
        capture_output=True,
        cwd=str(HOME),
        timeout=timeout,
        check=True,
    )


def read_csv_text(text):
    return list(csv.reader(io.StringIO(text)))


def expected_for(records):
    quote_map = str.maketrans({
        '“': '"', '”': '"', '«': '"', '»': '"',
        '‘': "'", '’': "'",
    })
    best = {}
    for record in records:
        normalized = re.sub(r'\s+', ' ', record['raw_text'].strip()).translate(quote_map)
        key = (record['lang'], record['id'])
        candidate = (record['contributor_score'], record['timestamp'], normalized)
        if key not in best or candidate[:2] > best[key][:2]:
            best[key] = candidate
    rows = [['lang', 'id', 'normalized_text']]
    for lang, message_id in sorted(best):
        rows.append([lang, message_id, best[(lang, message_id)][2]])
    return rows


def test_scripts_exist():
    assert os.path.isfile(NORMALIZE), 'normalize.py is missing'
    assert os.path.isfile(AGGREGATE), 'aggregate.py is missing'
    assert os.path.isfile(PIPELINE), 'pipeline.sh is missing'


def test_pipeline_executable_and_set_e():
    st = os.stat(PIPELINE)
    assert bool(st.st_mode & stat.S_IXUSR), 'pipeline.sh is not executable'
    content = PIPELINE.read_text()
    assert 'set -e' in content, "pipeline.sh must use 'set -e'"


def test_final_csv_exists_and_content_after_execution():
    # Execute the submitted artifact rather than trusting a pre-created CSV.
    run([str(PIPELINE)])
    assert os.path.isfile(FINAL), 'final_translations.csv was not generated'

    expected_csv = [
        ['lang', 'id', 'normalized_text'],
        ['es-ES', 'btn_save', 'Guardar'],
        ['es-ES', 'err_404', 'No encontrado'],
        ['es-ES', 'msg_welcome', '"Bienvenidos" a la aplicación'],
        ['fr-FR', 'btn_save', 'Enregistrer'],
        ['fr-FR', 'err_404', "La page n'existe pas"],
    ]
    with FINAL.open('r', encoding='utf-8', newline='') as f:
        actual = list(csv.reader(f))
    assert actual == expected_csv, f'CSV content mismatch.\nExpected: {expected_csv}\nGot: {actual}'


def test_normalize_script_behavior():
    token = uuid.uuid4().hex
    records = [
        {
            'id': 'id-' + token,
            'lang': 'zz-ZZ',
            'raw_text': '\t  «Alpha»\n  beta\u2003and ‘gamma’  ',
            'timestamp': 731,
            'contributor_score': -4,
            'extra': {'must': ['remain', 7]},
        },
        {
            'id': 'second-' + token,
            'lang': 'aa-AA',
            'raw_text': '  “x”\t»y«  ',
            'timestamp': 0,
            'contributor_score': 12,
        },
    ]
    source = ''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in records)
    result = run(['python3', str(NORMALIZE)], input_text=source)
    output = [json.loads(line) for line in result.stdout.splitlines()]

    expected = [dict(r) for r in records]
    expected[0]['raw_text'] = '"Alpha" beta and \'gamma\''
    expected[1]['raw_text'] = '"x" "y"'
    assert output == expected


def test_aggregate_script_behavior():
    token = uuid.uuid4().hex
    records = [
        {'id': 'b-' + token, 'lang': 'zz-ZZ', 'raw_text': 'low', 'timestamp': 999, 'contributor_score': 2},
        {'id': 'b-' + token, 'lang': 'zz-ZZ', 'raw_text': 'high-old', 'timestamp': 10, 'contributor_score': 8},
        {'id': 'b-' + token, 'lang': 'zz-ZZ', 'raw_text': 'winner, "quoted"', 'timestamp': 11, 'contributor_score': 8},
        {'id': 'a-' + token, 'lang': 'zz-ZZ', 'raw_text': 'z-row', 'timestamp': 1, 'contributor_score': 1},
        {'id': 'c-' + token, 'lang': 'aa-AA', 'raw_text': 'a-row', 'timestamp': 3, 'contributor_score': 4},
    ]
    source = ''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in records)
    result = run(['python3', str(AGGREGATE)], input_text=source)
    assert read_csv_text(result.stdout) == [
        ['lang', 'id', 'normalized_text'],
        ['aa-AA', 'c-' + token, 'a-row'],
        ['zz-ZZ', 'a-' + token, 'z-row'],
        ['zz-ZZ', 'b-' + token, 'winner, "quoted"'],
    ]


def test_pipeline_on_unseen_data_and_direct_chain():
    saved_raw = RAW.read_bytes()
    saved_final = FINAL.read_bytes() if FINAL.exists() else None
    saved_normalize = NORMALIZE.read_bytes()
    saved_aggregate = AGGREGATE.read_bytes()
    normalize_mode = NORMALIZE.stat().st_mode
    aggregate_mode = AGGREGATE.stat().st_mode

    try:
        token = uuid.uuid4().hex
        records = [
            {'id': 'two-' + token, 'lang': 'qz-QZ', 'raw_text': ' inferior ', 'timestamp': 500, 'contributor_score': 1},
            {'id': 'two-' + token, 'lang': 'qz-QZ', 'raw_text': '\t“new”  value\n', 'timestamp': 41, 'contributor_score': 9},
            {'id': 'two-' + token, 'lang': 'qz-QZ', 'raw_text': '«old» value', 'timestamp': 40, 'contributor_score': 9},
            {'id': 'one-' + token, 'lang': 'aa-XA', 'raw_text': '  comma, and ’quote’  ', 'timestamp': 4, 'contributor_score': 3},
        ]
        RAW.write_text(''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in records), encoding='utf-8')
        run([str(PIPELINE)])
        with FINAL.open('r', encoding='utf-8', newline='') as f:
            actual = list(csv.reader(f))
        assert actual == expected_for(records)

        # Replace the two components temporarily with cooperating probes. The
        # normalizer waits until the aggregator consumes its first output line,
        # proving that pipeline.sh starts both stages as a streaming pipe and
        # sends the aggregate stage's stdout to the required final file.
        signal = Path('/tmp/pipeline-probe-' + token)
        probe_input = json.dumps({
            'id': 'probe-' + token,
            'lang': 'pp-PP',
            'raw_text': 'probe',
            'timestamp': 1,
            'contributor_score': 1,
        }) + '\n'
        RAW.write_text(probe_input, encoding='utf-8')

        NORMALIZE.write_text(f'''#!/usr/bin/env python3
import pathlib, sys, time
expected = {probe_input!r}
if sys.stdin.read() != expected:
    raise SystemExit(21)
print({json.dumps({'stage': 'first', 'token': token})!r}, flush=True)
signal = pathlib.Path({str(signal)!r})
for _ in range(100):
    if signal.exists():
        break
    time.sleep(0.05)
else:
    raise SystemExit(22)
print({json.dumps({'stage': 'second', 'token': token})!r}, flush=True)
''', encoding='utf-8')
        AGGREGATE.write_text(f'''#!/usr/bin/env python3
import pathlib, sys
first = sys.stdin.readline().rstrip('\\n')
if first != {json.dumps({'stage': 'first', 'token': token})!r}:
    raise SystemExit(31)
pathlib.Path({str(signal)!r}).write_text('seen')
second = sys.stdin.readline().rstrip('\\n')
if second != {json.dumps({'stage': 'second', 'token': token})!r}:
    raise SystemExit(32)
print('lang,id,normalized_text')
print('probe,stream,{token}')
''', encoding='utf-8')
        os.chmod(NORMALIZE, 0o755)
        os.chmod(AGGREGATE, 0o755)
        run([str(PIPELINE)], timeout=10)
        with FINAL.open('r', encoding='utf-8', newline='') as f:
            assert list(csv.reader(f)) == [
                ['lang', 'id', 'normalized_text'],
                ['probe', 'stream', token],
            ]
    finally:
        RAW.write_bytes(saved_raw)
        NORMALIZE.write_bytes(saved_normalize)
        AGGREGATE.write_bytes(saved_aggregate)
        os.chmod(NORMALIZE, stat.S_IMODE(normalize_mode))
        os.chmod(AGGREGATE, stat.S_IMODE(aggregate_mode))
        if saved_final is None:
            FINAL.unlink(missing_ok=True)
        else:
            FINAL.write_bytes(saved_final)
        for path in Path('/tmp').glob('pipeline-probe-*'):
            path.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
