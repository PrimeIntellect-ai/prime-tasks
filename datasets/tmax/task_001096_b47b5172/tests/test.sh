#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess
from pathlib import Path

HOME = Path('/home/user')
RAW = HOME / 'raw_data.csv'
CLEANED = HOME / 'cleaned_data.csv'
TOP = HOME / 'top_pairs.csv'


def expected_cleaned(raw_text):
    lines = raw_text.splitlines()
    assert lines and lines[0] == 'id,text'
    result = ['id,text']
    for line in lines[1:]:
        doc_id, text = line.split(',', 1)
        text = text.lower()
        text = re.sub(r'[^a-z0-9 ]', '', text)
        text = re.sub(r' +', ' ', text).strip()
        result.append(f'{doc_id},{text}')
    return result


def read_cleaned(path):
    assert path.exists(), 'cleaned_data.csv is missing'
    with path.open('r', encoding='utf-8', newline='') as f:
        rows = list(csv.reader(f))
    assert rows and rows[0] == ['id', 'text'], f'Incorrect cleaned_data.csv header: {rows[:1]}'
    assert all(len(row) == 2 for row in rows), f'cleaned_data.csv must have exactly two columns: {rows}'
    return rows


def expected_similarities(clean_rows):
    docs = []
    for doc_id, text in clean_rows[1:]:
        docs.append((int(doc_id), text.split(' ') if text else []))

    similarities = {}
    for i in range(len(docs)):
        id_a, tokens_a = docs[i]
        counts_a = {word: tokens_a.count(word) for word in set(tokens_a)}
        for j in range(i + 1, len(docs)):
            id_b, tokens_b = docs[j]
            counts_b = {word: tokens_b.count(word) for word in set(tokens_b)}
            dot = sum(counts_a.get(word, 0) * count for word, count in counts_b.items())
            norm_a = math.sqrt(sum(count * count for count in counts_a.values()))
            norm_b = math.sqrt(sum(count * count for count in counts_b.values()))
            sim = dot / (norm_a * norm_b) if norm_a and norm_b else 0.0
            pair = tuple(sorted((id_a, id_b)))
            similarities[pair] = sim
    return similarities


def validate_top(path, clean_rows):
    assert path.exists(), 'top_pairs.csv is missing'
    with path.open('r', encoding='utf-8', newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            assert False, 'top_pairs.csv is empty'
        rows = list(reader)

    assert header == ['id1', 'id2', 'similarity'], f'Incorrect columns in top_pairs.csv: {header}'
    assert len(rows) == 3, f'Should contain exactly 3 pairs, found {len(rows)}'

    expected = expected_similarities(clean_rows)
    parsed = []
    seen = set()
    for row in rows:
        assert len(row) == 3, f'Row does not have exactly 3 columns: {row}'
        assert re.fullmatch(r'[0-9]+\.[0-9]{4}', row[2]), f'Similarity must have exactly four decimal places: {row[2]!r}'
        try:
            id1, id2 = int(row[0]), int(row[1])
            sim = float(row[2])
        except ValueError as exc:
            assert False, f'Error parsing row values {row}: {exc}'
        assert id1 < id2, f'Pair must satisfy id1 < id2: {(id1, id2)}'
        pair = (id1, id2)
        assert pair not in seen, f'Duplicate pair: {pair}'
        assert pair in expected, f'Unknown document pair: {pair}'
        assert row[2] == f'{expected[pair]:.4f}', f'Incorrect similarity for {pair}: {row[2]}'
        seen.add(pair)
        parsed.append((id1, id2, sim))

    scores = [row[2] for row in parsed]
    assert scores == sorted(scores, reverse=True), 'Rows are not sorted in descending similarity order'

    chosen_raw = [expected[(id1, id2)] for id1, id2, _ in parsed]
    cutoff = sorted(expected.values(), reverse=True)[2]
    assert all(score + 1e-12 >= cutoff for score in chosen_raw), 'A reported pair is not among the top three similarities'
    assert all(pair in seen for pair, score in expected.items() if score > cutoff + 1e-12), 'A strictly higher-scoring pair was omitted'
    return parsed


def candidate_scripts():
    shell = []
    python = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in {'__pycache__', 'site-packages'}]
        if Path(root).relative_to(HOME).parts and len(Path(root).relative_to(HOME).parts) >= 3:
            dirs[:] = []
        for name in files:
            path = Path(root) / name
            if path in {RAW, CLEANED, TOP} or path.is_symlink():
                continue
            try:
                if path.stat().st_size > 1_000_000:
                    continue
                source = path.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError):
                continue
            first = source.splitlines()[0] if source.splitlines() else ''
            if (path.suffix == '.sh' or re.search(r'^#!.*\b(?:ba|z|k)?sh\b', first)) and 'raw_data.csv' in source and 'cleaned_data.csv' in source:
                shell.append(path)
            if (path.suffix == '.py' or re.search(r'^#!.*python', first)) and 'cleaned_data.csv' in source and 'top_pairs.csv' in source:
                if re.search(r'(^|\n)\s*(?:import\s+numpy|from\s+numpy\s+import)\b', source):
                    python.append(path)
    return shell, python


def test_original_outputs_and_assertions():
    raw_text = RAW.read_text(encoding='utf-8')
    expected_lines = expected_cleaned(raw_text)
    clean_rows = read_cleaned(CLEANED)
    actual_lines = [','.join(row) for row in clean_rows]
    assert actual_lines == expected_lines, f'cleaned_data.csv does not implement the required cleaning rules: {actual_lines}'

    parsed_rows = validate_top(TOP, clean_rows)

    # Preserve the original verifier's score and pair assertions.
    actual_scores = [r[2] for r in parsed_rows]
    expected_top_scores = [0.9129, 0.9129, 0.7500]
    for exp, act in zip(expected_top_scores, actual_scores):
        assert abs(exp - act) < 0.0002, f'Expected similarity close to {exp}, got {act}'
    top_pairs_set = {(r[0], r[1]) for r in parsed_rows}
    assert (4, 5) in top_pairs_set, 'Pair (4, 5) is missing from the top pairs.'
    assert (8, 9) in top_pairs_set, 'Pair (8, 9) is missing from the top pairs.'
    assert (1, 2) in top_pairs_set or (1, 10) in top_pairs_set, 'A 0.7500 pair (either 1,2 or 1,10) is missing.'


def test_pipeline_scripts_execute_on_new_input():
    shell_scripts, python_scripts = candidate_scripts()
    assert shell_scripts, 'No Bash/Shell cleaning pipeline script was found'
    assert python_scripts, 'No numpy-based Python similarity script was found'

    dynamic_raw = '''id,text
11,  Alpha!!!   beta beta...  
2,ALPHA beta beta gamma
7,CAT   dog??
20,cat dog mouse
5,Sun moon star
9,SUN moon cloud
'''
    expected_lines = expected_cleaned(dynamic_raw)
    original_raw = RAW.read_bytes()
    original_cleaned = CLEANED.read_bytes() if CLEANED.exists() else None
    original_top = TOP.read_bytes() if TOP.exists() else None

    try:
        working_cleaned = None
        for script in shell_scripts:
            RAW.write_text(dynamic_raw, encoding='utf-8')
            CLEANED.unlink(missing_ok=True)
            TOP.unlink(missing_ok=True)
            try:
                proc = subprocess.run(['bash', str(script)], cwd=HOME, timeout=20, capture_output=True, text=True)
            except subprocess.TimeoutExpired:
                continue
            if proc.returncode != 0 or not CLEANED.exists():
                continue
            try:
                rows = read_cleaned(CLEANED)
            except AssertionError:
                continue
            if [','.join(row) for row in rows] == expected_lines:
                working_cleaned = CLEANED.read_bytes()
                break
        assert working_cleaned is not None, 'No shell script correctly cleaned a new raw_data.csv input'

        python_succeeded = False
        for script in python_scripts:
            RAW.write_text(dynamic_raw, encoding='utf-8')
            CLEANED.write_bytes(working_cleaned)
            TOP.unlink(missing_ok=True)
            try:
                proc = subprocess.run(['python3', str(script)], cwd=HOME, timeout=20, capture_output=True, text=True)
            except subprocess.TimeoutExpired:
                continue
            if proc.returncode != 0:
                continue
            try:
                rows = read_cleaned(CLEANED)
                assert [','.join(row) for row in rows] == expected_lines
                validate_top(TOP, rows)
            except AssertionError:
                continue
            python_succeeded = True
            break
        assert python_succeeded, 'No numpy-based Python script computed the correct top pairs for a new cleaned dataset'
    finally:
        RAW.write_bytes(original_raw)
        if original_cleaned is None:
            CLEANED.unlink(missing_ok=True)
        else:
            CLEANED.write_bytes(original_cleaned)
        if original_top is None:
            TOP.unlink(missing_ok=True)
        else:
            TOP.write_bytes(original_top)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
