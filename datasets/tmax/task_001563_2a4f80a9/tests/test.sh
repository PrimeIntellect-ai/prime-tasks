#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

import pytest

HOME = Path('/home/user')


def get_trigrams(text):
    return set(text[i:i+3] for i in range(len(text) - 2))


def jaccard(set1, set2):
    if not set1 and not set2:
        return 1.0
    return len(set1 & set2) / len(set1 | set2)


def parse_reference_raw(path):
    extracted = []
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(' | ')
            if len(parts) != 3:
                continue
            id_str = parts[0].replace('ID:', '').strip()
            text_str = parts[1].replace('TEXT:', '').strip()
            meta_str = parts[2].replace('META:', '').strip()
            match = re.search(r'rating:([1-5])|([1-5]) stars|score=([1-5])', meta_str)
            if match:
                rating = int(next(g for g in match.groups() if g is not None))
                extracted.append((int(id_str), rating, text_str))
    return extracted


def sample_reference(extracted):
    sampled = []
    for rating in range(1, 6):
        records = sorted((r for r in extracted if r[1] == rating), key=lambda r: r[0])
        sampled.extend(records[:5])
    return sampled


def pairs_reference(sampled):
    pairs = []
    for i in range(len(sampled)):
        for j in range(i + 1, len(sampled)):
            id1, _, text1 = sampled[i]
            id2, _, text2 = sampled[j]
            if jaccard(get_trigrams(text1), get_trigrams(text2)) >= 0.4:
                pairs.append([min(id1, id2), max(id1, id2)])
    return sorted(pairs, key=lambda p: (p[0], p[1]))


def reference_pipeline():
    raw_path = HOME / 'raw_reviews.txt'
    if not raw_path.exists():
        return []
    return pairs_reference(sample_reference(parse_reference_raw(raw_path)))


def read_csv(path):
    with open(path, newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        rows = list(reader)
    return header, rows


def write_csv(path, records):
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['id', 'rating', 'text'])
        writer.writerows(records)


def run_script(name, env=None):
    path = HOME / name
    assert path.exists(), f'{path} does not exist.'
    result = subprocess.run(
        ['python3', str(path)], cwd=HOME, capture_output=True, text=True,
        env=env, timeout=60
    )
    assert result.returncode == 0, f'{name} failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'


def test_00_each_stage_and_parallel_execution():
    paths = [HOME / n for n in ('raw_reviews.txt', 'extracted.csv', 'sampled.csv', 'similar_pairs.json')]
    backups = {p: p.read_bytes() if p.exists() else None for p in paths}

    try:
        # Exercise extract.py independently on data different from the shipped input.
        extraction_records = []
        raw_lines = []
        for i in range(30, 0, -1):
            rating = ((i - 1) % 5) + 1
            text = f'Case-sensitive review number {i}, group {rating}.'
            if i % 3 == 0:
                meta = f'noise rating:{rating} tail'
            elif i % 3 == 1:
                meta = f'noise {rating} stars tail'
            else:
                meta = f'noise score={rating} tail'
            raw_lines.append(f'ID:{i} | TEXT:{text} | META:{meta}\n')
            extraction_records.append((i, rating, text))
        (HOME / 'raw_reviews.txt').write_text(''.join(raw_lines))
        run_script('extract.py')
        header, rows = read_csv(HOME / 'extracted.csv')
        assert header == ['id', 'rating', 'text']
        assert rows == [[str(i), str(r), text] for i, r, text in extraction_records], \
            'extract.py did not produce the exact records from the controlled raw input.'

        # Exercise sample.py independently, including sorting rather than input order.
        source = []
        for rating in range(1, 6):
            for k in range(7, 0, -1):
                source.append((rating * 100 + k, rating, f'sample text r{rating} item{k}'))
        write_csv(HOME / 'extracted.csv', source)
        run_script('sample.py')
        expected_sample = []
        for rating in range(1, 6):
            expected_sample.extend(sorted(
                (row for row in source if row[1] == rating), key=lambda row: row[0]
            )[:5])
        header, rows = read_csv(HOME / 'sampled.csv')
        assert header == ['id', 'rating', 'text']
        assert rows == [[str(i), str(r), text] for i, r, text in expected_sample], \
            'sample.py did not perform the specified deterministic stratified sampling.'

        # Exercise similarity.py independently and instrument multiprocessing at runtime.
        controlled_sample = []
        for i in range(25):
            group = i % 5
            text = (
                f'Controlled similarity group {group}: repeated phrase repeated phrase '
                f'with case Sensitive marker and item {i:02d}.'
            )
            controlled_sample.append((1000 + i, group + 1, text))
        write_csv(HOME / 'sampled.csv', controlled_sample)

        with tempfile.TemporaryDirectory() as td:
            log_path = os.path.join(td, 'mp.log')
            sitecustomize = r'''
import os
_log_path = os.environ.get('TRACK_MP_LOG')
def _log(value):
    if _log_path:
        with open(_log_path, 'a') as f:
            f.write(value + '\n')
try:
    import multiprocessing.process as _mpp
    _old_start = _mpp.BaseProcess.start
    def _tracked_start(self, *args, **kwargs):
        _log('PROCESS_START')
        return _old_start(self, *args, **kwargs)
    _mpp.BaseProcess.start = _tracked_start

    import multiprocessing.pool as _pool
    for _name in ('map', 'starmap', 'imap', 'imap_unordered', 'apply', 'apply_async', 'map_async', 'starmap_async'):
        if hasattr(_pool.Pool, _name):
            _old = getattr(_pool.Pool, _name)
            def _make_wrapper(old, name):
                def wrapper(self, *args, **kwargs):
                    _log('POOL_WORK:' + name)
                    return old(self, *args, **kwargs)
                return wrapper
            setattr(_pool.Pool, _name, _make_wrapper(_old, _name))
except Exception as exc:
    _log('INSTRUMENTATION_ERROR:' + repr(exc))
'''
            Path(td, 'sitecustomize.py').write_text(sitecustomize)
            env = os.environ.copy()
            env['TRACK_MP_LOG'] = log_path
            env['PYTHONPATH'] = td + os.pathsep + env.get('PYTHONPATH', '')
            run_script('similarity.py', env=env)

            events = Path(log_path).read_text().splitlines() if os.path.exists(log_path) else []
            pool_work = any(e.startswith('POOL_WORK:') for e in events)
            process_starts = sum(e == 'PROCESS_START' for e in events)
            assert pool_work or process_starts >= 2, \
                'similarity.py did not perform work through a multiprocessing pool or multiple processes.'

        with open(HOME / 'similar_pairs.json') as f:
            actual_pairs = json.load(f)
        assert actual_pairs == pairs_reference(controlled_sample), \
            'similarity.py produced incorrect results for the controlled sampled.csv.'
    finally:
        for path, data in backups.items():
            if data is None:
                if path.exists():
                    path.unlink()
            else:
                path.write_bytes(data)


def test_makefile_dag_definition():
    makefile_path = HOME / 'Makefile'
    assert makefile_path.exists(), f'{makefile_path} does not exist.'
    result = subprocess.run(
        ['make', '-C', str(HOME), '-pn', 'all'], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f'Could not inspect Makefile:\n{result.stderr}'

    dependencies = {}
    for line in result.stdout.splitlines():
        if not line or line[0].isspace() or line.startswith('#') or ':' not in line:
            continue
        left, right = line.split(':', 1)
        if '=' in left:
            continue
        for target in left.split():
            name = os.path.basename(target)
            if name in {'all', 'extracted.csv', 'sampled.csv', 'similar_pairs.json'}:
                deps = {os.path.basename(x) for x in right.split('|', 1)[0].split()}
                dependencies.setdefault(name, set()).update(deps)

    assert {'raw_reviews.txt', 'extract.py'} <= dependencies.get('extracted.csv', set())
    assert {'extracted.csv', 'sample.py'} <= dependencies.get('sampled.csv', set())
    assert {'sampled.csv', 'similarity.py'} <= dependencies.get('similar_pairs.json', set())
    assert 'similar_pairs.json' in dependencies.get('all', set())


def test_makefile_execution():
    makefile_path = HOME / 'Makefile'
    assert makefile_path.exists(), f'{makefile_path} does not exist.'

    # Remove every generated artifact so bare make must execute the complete DAG.
    for name in ('extracted.csv', 'sampled.csv', 'similar_pairs.json'):
        path = HOME / name
        if path.exists():
            path.unlink()

    result = subprocess.run(['make', '-C', str(HOME)], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, f'make command failed with error:\n{result.stderr}'
    for name in ('extracted.csv', 'sampled.csv', 'similar_pairs.json'):
        assert (HOME / name).exists(), f'Bare make did not produce {name}.'


def test_extracted_csv():
    extracted_path = HOME / 'extracted.csv'
    assert extracted_path.exists(), f'{extracted_path} does not exist.'
    header, rows = read_csv(extracted_path)
    assert header == ['id', 'rating', 'text'], f'Incorrect header in extracted.csv: {header}'
    assert len(rows) > 0, 'extracted.csv is empty.'

    expected = parse_reference_raw(HOME / 'raw_reviews.txt')
    assert rows == [[str(i), str(r), text] for i, r, text in expected], \
        'extracted.csv does not exactly match extraction from raw_reviews.txt.'


def test_sampled_csv():
    sampled_path = HOME / 'sampled.csv'
    assert sampled_path.exists(), f'{sampled_path} does not exist.'
    header, rows = read_csv(sampled_path)
    assert header == ['id', 'rating', 'text'], f'Incorrect header in sampled.csv: {header}'
    assert len(rows) == 25, f'sampled.csv should have exactly 25 records, found {len(rows)}.'

    expected = sample_reference(parse_reference_raw(HOME / 'raw_reviews.txt'))
    assert rows == [[str(i), str(r), text] for i, r, text in expected], \
        'sampled.csv does not exactly match the specified stratified sample.'


def test_similar_pairs_json():
    json_path = HOME / 'similar_pairs.json'
    assert json_path.exists(), f'{json_path} does not exist.'
    with open(json_path, 'r') as f:
        try:
            student_pairs = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'Could not parse {json_path} as valid JSON.')

    expected_pairs = reference_pipeline()
    assert isinstance(student_pairs, list), 'similar_pairs.json must contain a JSON array.'
    student_pairs = [list(p) for p in student_pairs]
    assert student_pairs == expected_pairs, (
        f'Similar pairs do not match expected output.\nExpected: {expected_pairs}\nFound: {student_pairs}'
    )


def test_multiprocessing_used():
    sim_script = HOME / 'similarity.py'
    assert sim_script.exists(), f'{sim_script} does not exist.'
    content = sim_script.read_text()
    assert 'multiprocessing' in content or 'Pool' in content or 'Process' in content, \
        'The similarity.py script does not appear to use the multiprocessing module.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
