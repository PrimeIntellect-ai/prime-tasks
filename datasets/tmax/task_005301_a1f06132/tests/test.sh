#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import tempfile
import uuid

import pytest


def run_script(args, **kwargs):
    return subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        **kwargs,
    )


def test_jsonlines_fix():
    """The vendored source itself must be repaired and that source installed."""
    vendored = Path('/app/vendored/jsonlines-3.1.0/jsonlines/jsonlines.py')
    assert vendored.is_file(), 'Vendored jsonlines source is missing'
    source = vendored.read_text(encoding='utf-8')
    assert 'Illegal unicode escape' not in source, 'The injected vendored parser perturbation remains'

    try:
        import jsonlines
        from jsonlines import jsonlines as installed_impl
    except ImportError:
        pytest.fail('jsonlines package is not installed.')

    installed_source = Path(installed_impl.__file__).resolve()
    if installed_source.suffix == '.pyc':
        installed_source = Path(str(installed_source)[:-1])
    assert installed_source.is_file(), 'Cannot locate installed jsonlines source'
    assert installed_source.read_bytes() == vendored.read_bytes(), (
        'Installed jsonlines does not come from the repaired vendored source'
    )

    examples = [
        ('{"key": "value\\u0041"}', {'key': 'valueA'}),
        ('{"key": "\\u03a9", "other": "x\\u263ay"}', {'key': 'Ω', 'other': 'x☺y'}),
    ]
    for test_data, expected in examples:
        try:
            result = next(jsonlines.Reader([test_data]))
            assert result == expected
        except ValueError as exc:
            pytest.fail(f'jsonlines failed to parse unicode escape: {exc}')

    # Exercise the vendored tree directly, independently of the installed import.
    code = (
        'import jsonlines; '
        'r=next(jsonlines.Reader([\'{"v":"\\\\u0041\\\\u03a9"}\'])); '
        'assert r == {"v":"AΩ"}'
    )
    env = os.environ.copy()
    env['PYTHONPATH'] = '/app/vendored/jsonlines-3.1.0'
    proc = run_script([sys.executable, '-c', code], env=env)
    assert proc.returncode == 0, proc.stderr


def test_adversarial_corpus_filter():
    """Retain the original clean/evil corpus assertions."""
    script_path = '/home/user/filter_configs.py'
    assert os.path.isfile(script_path), f'Script not found at {script_path}'
    assert os.access(script_path, os.X_OK), 'filter_configs.py is not executable'

    clean_dir = '/app/corpora/clean/'
    evil_dir = '/app/corpora/evil/'
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.jsonl')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.jsonl')]

    evil_bypassed = []
    clean_modified = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for evil_file in evil_files:
            out_file = os.path.join(tmpdir, 'evil_out_' + os.path.basename(evil_file))
            subprocess.run([sys.executable, script_path, evil_file, out_file], check=False)
            if os.path.exists(out_file) and Path(out_file).read_text():
                evil_bypassed.append(os.path.basename(evil_file))

        for clean_file in clean_files:
            out_file = os.path.join(tmpdir, 'clean_out_' + os.path.basename(clean_file))
            subprocess.run([sys.executable, script_path, clean_file, out_file], check=False)
            if not os.path.exists(out_file) or Path(clean_file).read_bytes() != Path(out_file).read_bytes():
                clean_modified.append(os.path.basename(clean_file))

    errors = []
    if evil_bypassed:
        errors.append(f'{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {", ".join(evil_bypassed)}')
    if clean_modified:
        errors.append(f'{len(clean_modified)} of {len(clean_files)} clean modified: {", ".join(clean_modified)}')
    if errors:
        pytest.fail('; '.join(errors))


def make_nested(depth):
    value = 'leaf'
    for i in range(depth):
        value = {f'level_{i}': value}
    return value


def test_filter_on_generated_mixed_input():
    """Use runtime-generated records and check exact byte preservation and all rejection rules."""
    script = '/home/user/filter_configs.py'
    token = uuid.uuid4().hex
    valid = [
        json.dumps({'config_state': {'token': token, 'text': 'unicode Ω'}}) + '\n',
        '  ' + json.dumps({'config_state': make_nested(5), 'padding': token}) + '  \n',
        json.dumps({'config_state': {'items': ['plain', {'more': token}]}}) + '\n',
    ]
    rejected = [
        json.dumps({'config_state': make_nested(6), 'marker': token}) + '\n',
        json.dumps({'config_state': {'nested': [{'value': 'safe'}, {'value': 'bad|' + token}]}}) + '\n',
        json.dumps({'config_state': {'value': 'x&' + token}}) + '\n',
        '{"config_state":{"broken":"' + token + '"}\n',
        '{"config_state":{"number":NaN},"marker":"' + token + '"}\n',
        '{"config_state":{"number":Infinity},"marker":"' + token + '"}\n',
    ]
    order = valid + rejected
    random.SystemRandom().shuffle(order)
    expected = ''.join(line for line in order if line in valid).encode()

    with tempfile.TemporaryDirectory() as td:
        inp = Path(td, 'mixed.jsonl')
        out = Path(td, 'filtered.jsonl')
        inp.write_bytes(''.join(order).encode())
        proc = run_script([sys.executable, script, str(inp), str(out)])
        assert proc.returncode == 0, proc.stderr
        assert out.is_file(), 'Filter did not create its output file'
        assert out.read_bytes() == expected, 'Filter did not reject/preserve generated lines correctly'


def compute_expected_metrics(telemetry_file):
    events_per_server = {}
    with open(telemetry_file, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            event = json.loads(line)
            events_per_server.setdefault(event['server_id'], []).append(event)

    expected_summary = {}
    for server_id, events in events_per_server.items():
        deduped = []
        last_hash = None
        for event in events:
            serialized = json.dumps(event.get('config_state', {}), sort_keys=True)
            current_hash = hashlib.sha256(serialized.encode('utf-8')).hexdigest()
            if current_hash != last_hash:
                deduped.append(event)
                last_hash = current_hash
        if deduped:
            expected_summary[server_id] = {
                'total_deduplicated_events': len(deduped),
                'max_memory_allocated': max(e.get('memory_allocated', 0) for e in deduped),
            }
    return expected_summary


def read_summary(path):
    result = {}
    with open(path, newline='') as f:
        for row in csv.DictReader(f):
            server_id = row.get('server_id')
            if server_id:
                result[server_id] = {
                    'total_deduplicated_events': int(row['total_deduplicated_events']),
                    'max_memory_allocated': int(row['max_memory_allocated']),
                }
    return result


def test_process_metrics_fixed_corpus():
    """Retain the original fixed evaluation assertions."""
    script = '/home/user/process_metrics.py'
    assert os.path.isfile(script), f'Script not found at {script}'
    assert os.access(script, os.X_OK), 'process_metrics.py is not executable'
    telemetry = '/app/eval_data/telemetry.jsonl'
    subprocess.run([sys.executable, script, telemetry], check=False)
    summary = '/home/user/metrics_summary.csv'
    assert os.path.isfile(summary), f'Summary file not found at {summary}'
    actual = read_summary(summary)
    expected = compute_expected_metrics(telemetry)
    for server_id, values in expected.items():
        assert server_id in actual, f'Missing server_id {server_id} in summary'
        assert actual[server_id] == values, f'Incorrect fixed-corpus metrics for {server_id}'


def file_snapshot(root):
    result = {}
    root = Path(root)
    if not root.exists():
        return result
    for path in root.rglob('*'):
        if path.is_file():
            try:
                data = path.read_bytes()
            except OSError:
                continue
            if len(data) <= 2_000_000:
                result[str(path)] = hashlib.sha256(data).hexdigest()
    return result


def records_from_text(text):
    collections = []
    stripped = text.strip()
    if not stripped:
        return collections

    try:
        obj = json.loads(stripped)
        if isinstance(obj, list) and all(isinstance(x, dict) for x in obj):
            collections.append(obj)
        elif isinstance(obj, dict):
            collections.append([obj])
            for value in obj.values():
                if isinstance(value, list) and all(isinstance(x, dict) for x in value):
                    collections.append(value)
    except Exception:
        pass

    line_records = []
    for line in text.splitlines():
        try:
            value = json.loads(line)
        except Exception:
            line_records = []
            break
        if isinstance(value, dict):
            line_records.append(value)
        else:
            line_records = []
            break
    if line_records:
        collections.append(line_records)

    try:
        reader = csv.DictReader(io.StringIO(text))
        rows = list(reader)
        if reader.fieldnames and rows and len(reader.fieldnames) >= 2:
            collections.append(rows)
    except Exception:
        pass
    return collections


def numeric(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def generated_expectations(events):
    by_server = {}
    for event in events:
        by_server.setdefault(event['server_id'], []).append(event)

    deduped = {}
    rolling = {}
    sample = {}
    summary = {}
    for server, server_events in by_server.items():
        kept = []
        previous = None
        for event in server_events:
            digest = hashlib.sha256(
                json.dumps(event['config_state'], sort_keys=True).encode('utf-8')
            ).hexdigest()
            if digest != previous:
                kept.append(event)
                previous = digest
        deduped[server] = kept
        for index, event in enumerate(kept):
            window = kept[max(0, index - 2):index + 1]
            rolling[(server, event['timestamp'])] = sum(x['memory_allocated'] for x in window) / len(window)
        winner = max(kept, key=lambda x: x['memory_allocated'])
        sample[server] = winner
        summary[server] = {
            'total_deduplicated_events': len(kept),
            'max_memory_allocated': winner['memory_allocated'],
        }
    return summary, rolling, sample


def record_server(record):
    return record.get('server_id', record.get('server'))


def record_timestamp(record):
    value = record.get('timestamp')
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def find_rolling_value(record):
    for key, value in record.items():
        name = str(key).lower()
        if 'rolling' in name and ('avg' in name or 'average' in name or 'mean' in name):
            return numeric(value)
    return None


def test_process_metrics_generated_behavior_and_outputs():
    script = '/home/user/process_metrics.py'
    nonce = uuid.uuid4().hex
    base = random.SystemRandom().randint(1000, 100000)
    a = 'srv-a-' + nonce
    b = 'srv-b-' + nonce
    events = [
        {'timestamp': base, 'server_id': a, 'config_state': {'x': nonce, 'n': 1}, 'memory_allocated': 11},
        {'timestamp': base + 1, 'server_id': b, 'config_state': {'kind': 'q', 'id': nonce}, 'memory_allocated': 40},
        {'timestamp': base + 2, 'server_id': a, 'config_state': {'n': 1, 'x': nonce}, 'memory_allocated': 999},
        {'timestamp': base + 3, 'server_id': a, 'config_state': {'x': nonce, 'n': 2}, 'memory_allocated': 29},
        {'timestamp': base + 4, 'server_id': b, 'config_state': {'kind': 'q', 'id': nonce}, 'memory_allocated': 900},
        {'timestamp': base + 5, 'server_id': a, 'config_state': {'x': nonce, 'n': 1}, 'memory_allocated': 47},
        {'timestamp': base + 6, 'server_id': b, 'config_state': {'kind': 'r', 'id': nonce}, 'memory_allocated': 64},
        {'timestamp': base + 7, 'server_id': a, 'config_state': {'x': nonce, 'n': 3}, 'memory_allocated': 83},
        {'timestamp': base + 8, 'server_id': b, 'config_state': {'kind': 's', 'id': nonce}, 'memory_allocated': 52},
        {'timestamp': base + 9, 'server_id': b, 'config_state': {'kind': 't', 'id': nonce}, 'memory_allocated': 101},
    ]
    expected_summary, expected_rolling, expected_sample = generated_expectations(events)

    before_home = file_snapshot('/home/user')
    with tempfile.TemporaryDirectory() as td:
        inp = Path(td, 'generated.jsonl')
        inp.write_text(''.join(json.dumps(e, ensure_ascii=False) + '\n' for e in events), encoding='utf-8')
        before_tmp = file_snapshot(td)
        proc = run_script([sys.executable, script, str(inp)], cwd=td)
        assert proc.returncode == 0, proc.stderr

        summary_path = Path('/home/user/metrics_summary.csv')
        assert summary_path.is_file(), 'Generated run did not create metrics_summary.csv'
        actual_summary = read_summary(summary_path)
        assert actual_summary == expected_summary, 'Summary is incorrect for runtime-generated telemetry'

        after_home = file_snapshot('/home/user')
        after_tmp = file_snapshot(td)
        changed = []
        for path, digest in {**after_home, **after_tmp}.items():
            old = before_home.get(path, before_tmp.get(path))
            if digest != old and path != str(inp):
                changed.append(Path(path))

        collections = records_from_text(proc.stdout)
        for path in changed:
            try:
                collections.extend(records_from_text(path.read_text(encoding='utf-8')))
            except (OSError, UnicodeError):
                pass

    rolling_ok = False
    for records in collections:
        matched = set()
        for record in records:
            key = (record_server(record), record_timestamp(record))
            if key in expected_rolling:
                value = find_rolling_value(record)
                if value is not None and abs(value - expected_rolling[key]) < 1e-8:
                    matched.add(key)
        if matched == set(expected_rolling):
            rolling_ok = True
            break
    assert rolling_ok, 'No produced output contains the correct rolling 3-event averages'

    sample_ok = False
    expected_servers = set(expected_sample)
    for records in collections:
        relevant = [r for r in records if record_server(r) in expected_servers]
        if len(relevant) != len(expected_servers):
            continue
        seen = set()
        good = True
        for record in relevant:
            server = record_server(record)
            wanted = expected_sample[server]
            if server in seen or record_timestamp(record) != wanted['timestamp']:
                good = False
                break
            if numeric(record.get('memory_allocated')) != float(wanted['memory_allocated']):
                good = False
                break
            seen.add(server)
        if good and seen == expected_servers:
            sample_ok = True
            break
    assert sample_ok, 'No produced output is the required one-highest-event-per-server stratified sample'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
