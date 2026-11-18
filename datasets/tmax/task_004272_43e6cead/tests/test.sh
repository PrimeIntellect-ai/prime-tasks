#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import json
import math
import wave
import struct
import sqlite3
import shutil
import glob
import subprocess
import importlib
import importlib.machinery
from collections import Counter

APP = '/app'


def rms(values):
    return math.sqrt(sum(x * x for x in values) / len(values))


def read_samples(path='/app/data.wav'):
    with wave.open(path, 'r') as wav:
        frames = wav.readframes(wav.getnframes())
        return struct.unpack(f"{len(frames)//2}h", frames)


def read_events(connect):
    conn = connect('/app/events.db')
    try:
        return conn.execute(
            'SELECT event_id, start_sample, end_sample FROM events ORDER BY event_id'
        ).fetchall()
    finally:
        conn.close()


def assert_output_matches(events, samples):
    output_path = '/app/output.json'
    assert os.path.exists(output_path), f"Output file {output_path} is missing."

    with open(output_path, 'r') as f:
        try:
            output = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Failed to parse {output_path} as JSON."

    assert len(events) > 0, 'No events found in the database.'

    truth = {}
    for eid, start, end in events:
        chunk = samples[start:end]
        assert len(chunk) > 0, f"Event {eid} has an empty sample chunk."
        truth[str(eid)] = rms(chunk)

    mse = 0.0
    for eid, true_val in truth.items():
        assert eid in output, f"Event ID {eid} is missing from {output_path}."
        try:
            pred_val = float(output[eid])
        except (ValueError, TypeError):
            assert False, f"Value for event {eid} in {output_path} is not a valid float."
        assert math.isfinite(pred_val), f"Value for event {eid} is not finite."
        mse += (pred_val - true_val) ** 2

    mse /= len(truth)
    threshold = 0.001
    assert mse < threshold, f"MSE too high: {mse} >= {threshold}. The calculated RMS values are incorrect."


def write_hidden_inputs():
    samples = [((i * 7919 + 1234) % 50001) - 25000 for i in range(47)]
    events = [(101, 0, 7), (202, 7, 8), (303, 8, 29), (404, 29, 47)]

    with wave.open('/app/data.wav', 'w') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(11025)
        wav.writeframes(struct.pack(f'{len(samples)}h', *samples))

    conn = sqlite3.connect('/app/events.db')
    try:
        conn.execute('CREATE TABLE events (event_id INTEGER PRIMARY KEY, start_sample INTEGER, end_sample INTEGER)')
        conn.execute('CREATE TABLE metadata (event_id INTEGER, description TEXT)')
        conn.executemany('INSERT INTO events VALUES (?, ?, ?)', events)
        for eid, _, _ in events:
            for n in range(3):
                conn.execute('INSERT INTO metadata VALUES (?, ?)', (eid, f'meta{n}'))
        conn.commit()
    finally:
        conn.close()
    return events, tuple(samples)


def test_extension_query_and_pipeline():
    assert os.path.isfile('/app/setup.py'), '/app/setup.py is missing.'
    assert os.path.isfile('/app/c_src/filter.c'), '/app/c_src/filter.c is missing.'

    shutil.rmtree('/app/build', ignore_errors=True)
    for path in glob.glob('/app/fast_audio*.so'):
        os.remove(path)

    build = subprocess.run(
        [sys.executable, 'setup.py', 'build_ext', '--inplace'],
        cwd=APP,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    assert build.returncode == 0, 'C extension failed to compile/link:\n' + build.stdout

    importlib.invalidate_caches()
    sys.path.insert(0, APP)
    sys.modules.pop('fast_audio', None)
    fast_audio = importlib.import_module('fast_audio')
    origin = os.path.realpath(getattr(fast_audio, '__file__', ''))
    assert origin.startswith('/app/') and any(origin.endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES), \
        f'fast_audio was not loaded as an in-place compiled extension: {origin}'

    cases = [
        [3.0, 4.0],
        [-9.0],
        [0.0, 1.0, -2.0, 3.0, -4.0, 11.5],
        [float(((i * 37) % 101) - 50) / 7.0 for i in range(257)],
    ]
    for values in cases:
        got = fast_audio.calculate_power(values)
        expected = rms(values)
        assert isinstance(got, float), 'calculate_power must return a float.'
        assert math.isclose(got, expected, rel_tol=1e-12, abs_tol=1e-9), \
            f'calculate_power returned {got}, expected {expected}'

    calls = []
    real_calculate_power = fast_audio.calculate_power

    def monitored_calculate_power(values):
        copied = list(values)
        calls.append(copied)
        return real_calculate_power(values)

    fast_audio.calculate_power = monitored_calculate_power
    sys.modules.pop('processor', None)
    processor = importlib.import_module('processor')
    assert callable(getattr(processor, 'run', None)), 'processor.py must provide run().'

    real_connect = sqlite3.connect
    recorded_queries = []

    class CursorProxy:
        def __init__(self, cursor):
            self._cursor = cursor

        def execute(self, sql, parameters=()):
            if isinstance(sql, str) and sql.lstrip().lower().startswith('select') and 'events' in sql.lower():
                recorded_queries.append((sql, parameters))
            self._cursor.execute(sql, parameters)
            return self

        def __iter__(self):
            return iter(self._cursor)

        def __getattr__(self, name):
            return getattr(self._cursor, name)

    class ConnectionProxy:
        def __init__(self, connection):
            self._connection = connection

        def cursor(self, *args, **kwargs):
            return CursorProxy(self._connection.cursor(*args, **kwargs))

        def execute(self, sql, parameters=()):
            cursor = self.cursor()
            return cursor.execute(sql, parameters)

        def __enter__(self):
            self._connection.__enter__()
            return self

        def __exit__(self, *args):
            return self._connection.__exit__(*args)

        def __getattr__(self, name):
            return getattr(self._connection, name)

    def tracked_connect(*args, **kwargs):
        return ConnectionProxy(real_connect(*args, **kwargs))

    # processor.sqlite3 is the normal sqlite3 module; replace connect only while running it.
    sqlite3.connect = tracked_connect

    original_wav = open('/app/data.wav', 'rb').read()
    original_db = open('/app/events.db', 'rb').read()

    def check_query(events):
        expected = sorted(tuple(row) for row in events)
        assert recorded_queries, 'processor.py did not execute a SELECT query against events.'
        valid = False
        for sql, parameters in recorded_queries:
            conn = real_connect('/app/events.db')
            try:
                rows = conn.execute(sql, parameters).fetchall()
            finally:
                conn.close()
            triples = [tuple(row[:3]) for row in rows if len(row) >= 3]
            if len(triples) == len(set(triples)) and sorted(triples) == expected:
                valid = True
                break
        assert valid, 'The events query did not return exactly one unique (event_id, start_sample, end_sample) row per event.'

    def check_calls(events, samples):
        expected_chunks = Counter(tuple(float(x) for x in samples[start:end]) for _, start, end in events)
        actual_chunks = Counter(tuple(values) for values in calls)
        assert actual_chunks == expected_chunks, \
            'processor.py must invoke the compiled RMS function exactly once for each unique event interval.'

    try:
        os.remove('/app/events.db')
        hidden_events, hidden_samples = write_hidden_inputs()
        if os.path.exists('/app/output.json'):
            os.remove('/app/output.json')
        calls.clear()
        recorded_queries.clear()
        processor.run()
        check_query(hidden_events)
        check_calls(hidden_events, hidden_samples)
        assert_output_matches(hidden_events, hidden_samples)
    finally:
        sqlite3.connect = real_connect
        with open('/app/data.wav', 'wb') as f:
            f.write(original_wav)
        if os.path.exists('/app/events.db'):
            os.remove('/app/events.db')
        with open('/app/events.db', 'wb') as f:
            f.write(original_db)

    # Regenerate the required final output from the original task inputs.
    sqlite3.connect = tracked_connect
    try:
        original_events = read_events(real_connect)
        original_samples = read_samples()
        calls.clear()
        recorded_queries.clear()
        if os.path.exists('/app/output.json'):
            os.remove('/app/output.json')
        processor.run()
        check_query(original_events)
        check_calls(original_events, original_samples)
    finally:
        sqlite3.connect = real_connect

    # Preserve the original final-output MSE assertion.
    assert_output_matches(original_events, original_samples)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
