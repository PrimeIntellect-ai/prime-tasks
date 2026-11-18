#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import csv
import glob
import io
import json
import os
import re
import subprocess
import xml.etree.ElementTree as ET

HOME = '/home/user'
JSONL = os.path.join(HOME, 'translations.jsonl')
TM = os.path.join(HOME, 'tm.csv')
XML = os.path.join(HOME, 'updated_translations.xml')
UNICODE_ESCAPE = re.compile(r'\\u([0-9a-fA-F]{4})')


def clean_unicode(value):
    if not isinstance(value, str):
        return value
    previous = None
    while value != previous:
        previous = value
        value = UNICODE_ESCAPE.sub(lambda m: chr(int(m.group(1), 16)), value)
    return value


def levenshtein(a, b):
    if len(a) < len(b):
        a, b = b, a
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def derive_expected(jsonl_bytes, tm_bytes):
    tm_rows = list(csv.DictReader(io.StringIO(tm_bytes.decode('utf-8'))))
    tm_sources = [clean_unicode(row['source']) for row in tm_rows]
    assert tm_sources, 'Translation memory must contain at least one source.'

    deduplicated = {}
    for raw_line in jsonl_bytes.decode('utf-8').splitlines():
        if not raw_line.strip():
            continue
        item = json.loads(raw_line)
        item = {key: clean_unicode(value) for key, value in item.items()}
        deduplicated[int(item['id'])] = item

    expected = []
    for item_id in sorted(deduplicated):
        item = deduplicated[item_id]
        source = item['source']
        confidence = item.get('confidence')
        if confidence is None:
            similarities = []
            for tm_source in tm_sources:
                distance = levenshtein(source, tm_source)
                denominator = max(len(source), len(tm_source))
                similarity = 1.0 if denominator == 0 else 1.0 - distance / denominator
                similarities.append(similarity)
            confidence = round(max(similarities), 3)
        expected.append({
            'id': str(item_id),
            'confidence': f'{float(confidence):.3f}',
            'source': source,
            'target': item['target'],
        })
    return expected


def validate_xml(expected):
    assert os.path.isfile(XML), f'{XML} was not generated.'
    tree = ET.parse(XML)
    root = tree.getroot()
    assert root.tag == 'translations', 'Root element must be <translations>.'
    assert root.attrib == {}, 'The <translations> root must not have attributes.'

    translations = list(root)
    assert all(node.tag == 'translation' for node in translations), 'Unexpected root child element.'
    assert len(translations) == len(expected), (
        f'Expected {len(expected)} <translation> elements, found {len(translations)}.'
    )

    ids = [int(node.get('id')) for node in translations]
    expected_ids = [int(row['id']) for row in expected]
    assert ids == expected_ids, f'Translations must be sorted by integer id: {ids}.'

    for node, wanted in zip(translations, expected):
        assert node.attrib == {
            'id': wanted['id'],
            'confidence': wanted['confidence'],
        }, f'Incorrect attributes for id {wanted["id"]}: {node.attrib}'
        children = list(node)
        assert [child.tag for child in children] == ['source', 'target'], (
            f'ID {wanted["id"]} must contain exactly <source> then <target>.'
        )
        assert not list(children[0]) and not list(children[1]), 'Source and target must contain only text.'
        assert (children[0].text or '') == wanted['source'], (
            f'Incorrect source for id {wanted["id"]}.'
        )
        assert (children[1].text or '') == wanted['target'], (
            f'Incorrect target for id {wanted["id"]}.'
        )


def run_case(script, jsonl_bytes, tm_bytes):
    with open(JSONL, 'wb') as f:
        f.write(jsonl_bytes)
    with open(TM, 'wb') as f:
        f.write(tm_bytes)
    expected = derive_expected(jsonl_bytes, tm_bytes)
    try:
        os.unlink(XML)
    except FileNotFoundError:
        pass
    result = subprocess.run(
        ['python3', script], cwd=HOME, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=20, check=False,
    )
    assert result.returncode == 0, (
        f'{script} exited with {result.returncode}: '
        f'{result.stderr.decode("utf-8", "replace")[-2000:]}'
    )
    validate_xml(expected)


with open(JSONL, 'rb') as f:
    original_jsonl = f.read()
with open(TM, 'rb') as f:
    original_tm = f.read()

hidden_rows = [
    {'id': 10, 'source': 'obsolete', 'target': 'old', 'confidence': 0.1},
    {'id': -2, 'source': 'Caf\\u00e9 menu', 'target': 'Menu café'},
    {'id': 7, 'source': 'Gear \\u2699 settings', 'target': 'Use & <gear>', 'confidence': 0.375},
    {'id': 10, 'source': 'Alpha beta!', 'target': '<Final & done>', 'confidence': None},
]
hidden_jsonl = ('\n'.join(json.dumps(row, ensure_ascii=False) for row in hidden_rows) + '\n').encode('utf-8')
hidden_tm = (
    'source,target\n'
    'Alpha beta,Alpha cible\n'
    'Café menu,Menu café\n'
    'Gear settings,Réglages\n'
).encode('utf-8')

candidates = []
for path in glob.glob(os.path.join(HOME, '**', '*.py'), recursive=True):
    rel_parts = os.path.relpath(path, HOME).split(os.sep)
    if any(part.startswith('.') or part in {'venv', '.venv', 'site-packages', '__pycache__'} for part in rel_parts):
        continue
    if os.path.isfile(path):
        candidates.append(path)
assert candidates, 'No Python pipeline script was written under /home/user.'
candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)

errors = []
passed_script = None
try:
    for script in candidates:
        try:
            run_case(script, original_jsonl, original_tm)
            run_case(script, hidden_jsonl, hidden_tm)
            run_case(script, original_jsonl, original_tm)
            passed_script = script
            break
        except Exception as exc:
            errors.append(f'{script}: {exc}')
    assert passed_script is not None, 'No submitted Python script implemented the pipeline.\n' + '\n'.join(errors)

    # Preserve the original verifier's concrete assertions as additional checks.
    tree = ET.parse(XML)
    root = tree.getroot()
    translations = root.findall('translation')
    assert len(translations) == 4
    assert [int(t.get('id')) for t in translations] == [1, 2, 3, 4]
    by_id = {t.get('id'): t for t in translations}
    assert 'é' in (by_id['2'].find('source').text or '')
    assert '⚙' in (by_id['4'].find('source').text or '')
    for item_id, confidence in {'1': 0.995, '2': 0.857, '3': 1.000, '4': 0.850}.items():
        assert abs(float(by_id[item_id].get('confidence')) - confidence) <= 0.001
finally:
    with open(JSONL, 'wb') as f:
        f.write(original_jsonl)
    with open(TM, 'wb') as f:
        f.write(original_tm)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
