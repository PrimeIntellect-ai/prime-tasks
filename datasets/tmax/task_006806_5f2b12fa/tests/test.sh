#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.util
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile
import unittest

import pytest

PROJECT = Path('/home/user/project')
SCRIPT = PROJECT / 'process_events.py'
LIBRARY = PROJECT / 'bin/libstate.so'
EVENTS = PROJECT / 'archive/events.txt'
RESULTS = PROJECT / 'results.json'
PROBE_LOG = Path('/tmp/state_probe.log')


def test_files_moved_correctly():
    """Verify that libstate.so and events.txt were moved to their new locations."""
    assert os.path.isfile('/home/user/project/bin/libstate.so'), "Shared library libstate.so was not moved to /home/user/project/bin/"
    assert not os.path.exists('/home/user/project/lib/libstate.so'), "Shared library libstate.so still exists in the old location"

    assert os.path.isfile('/home/user/project/archive/events.txt'), "Data file events.txt was not moved to /home/user/project/archive/"
    assert not os.path.exists('/home/user/project/data/events.txt'), "Data file events.txt still exists in the old location"


def test_python_script_contents():
    """Verify that process_events.py exists and contains the required elements."""
    script_path = '/home/user/project/process_events.py'
    assert os.path.isfile(script_path), f"Python script {script_path} is missing"

    with open(script_path, 'r') as f:
        code = f.read()

    assert "unittest.TestCase" in code, "unittest.TestCase is missing from the Python script"
    assert "TestFFIWrapper" in code, "TestFFIWrapper class is missing from the Python script"
    assert "c_char_p" in code, "ctypes.c_char_p is missing from the Python script"
    assert "c_int" in code, "ctypes.c_int is missing from the Python script"
    assert "process_event" in code, "process_event function reference is missing from the Python script"


def load_json(path):
    assert path.is_file(), f"{path} is missing"
    try:
        with path.open() as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{path} is not a valid JSON file")


def expected_with_library(events_path, library_path):
    lib = ctypes.CDLL(str(library_path))
    fn = lib.process_event
    fn.argtypes = [ctypes.c_char_p]
    fn.restype = ctypes.c_int
    expected = {}
    for raw_line in events_path.read_text().splitlines():
        if not raw_line.strip():
            continue
        event_id, sequence = raw_line.split(':', 1)
        expected[event_id.strip()] = fn(sequence.strip().encode())
    return expected


def test_results_json():
    """Execute the submitted program and verify its output using the moved library."""
    RESULTS.unlink(missing_ok=True)
    completed = subprocess.run(
        [sys.executable, str(SCRIPT)],
        cwd=str(PROJECT), text=True, capture_output=True, timeout=20
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr
    results = load_json(RESULTS)
    expected = expected_with_library(EVENTS, LIBRARY)
    assert results == expected, f"Expected {expected}, got {results}"


def probe_value(sequence):
    value = 17
    for byte in sequence.encode():
        value = ((value * 131) + byte) & 0xffffffff
    value = (value + len(sequence) * 1009) & 0xffffffff
    return value & 0x7fffffff


def test_script_uses_ffi_and_unit_test_calls_it_directly():
    """Exercise processing on unpredictable data through an instrumented shared library."""
    original_library = LIBRARY.read_bytes()
    original_events = EVENTS.read_bytes()
    original_results = RESULTS.read_bytes() if RESULTS.exists() else None

    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / 'probe.c'
            probe = Path(temp_dir) / 'libstate.so'
            source.write_text(r'''
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int process_event(const char *event_seq) {
    FILE *f = fopen("/tmp/state_probe.log", "a");
    if (f) {
        fprintf(f, "%s\n", event_seq);
        fclose(f);
    }
    uint32_t value = 17;
    const unsigned char *p = (const unsigned char *)event_seq;
    while (*p) {
        value = value * 131u + *p;
        p++;
    }
    value += (uint32_t)strlen(event_seq) * 1009u;
    return (int)(value & 0x7fffffffu);
}
''')
            subprocess.run(
                ['gcc', '-shared', '-fPIC', '-o', str(probe), str(source)],
                check=True, capture_output=True, text=True
            )
            shutil.copyfile(probe, LIBRARY)

        token = secrets.token_hex(8)
        alphabet = 'ABCXYZ'
        cases = {}
        while len(cases) < 7:
            sequence = ''.join(secrets.choice(alphabet) for _ in range(4 + secrets.randbelow(13)))
            if sequence != 'AAB':
                cases[f'case_{token}_{len(cases)}'] = sequence

        EVENTS.write_text(''.join(f'{event_id}: {sequence}\n' for event_id, sequence in cases.items()))
        RESULTS.unlink(missing_ok=True)
        PROBE_LOG.unlink(missing_ok=True)

        completed = subprocess.run(
            [sys.executable, str(SCRIPT)],
            cwd=str(PROJECT), text=True, capture_output=True, timeout=20
        )
        assert completed.returncode == 0, completed.stdout + completed.stderr
        expected = {event_id: probe_value(sequence) for event_id, sequence in cases.items()}
        assert load_json(RESULTS) == expected

        calls = PROBE_LOG.read_text().splitlines() if PROBE_LOG.exists() else []
        for sequence in cases.values():
            assert sequence in calls, f"process_event was not called for {sequence!r}"

        helper = r'''
import importlib.util
import pathlib
import sys
import unittest

script = pathlib.Path('/home/user/project/process_events.py')
spec = importlib.util.spec_from_file_location('submitted_process_events', script)
module = importlib.util.module_from_spec(spec)
sys.argv = [str(script)]
spec.loader.exec_module(module)
cls = getattr(module, 'TestFFIWrapper', None)
if not isinstance(cls, type) or not issubclass(cls, unittest.TestCase):
    raise SystemExit('TestFFIWrapper is not a unittest.TestCase subclass')
pathlib.Path('/tmp/state_probe.log').write_text('')
suite = unittest.defaultTestLoader.loadTestsFromTestCase(cls)
if suite.countTestCases() < 1:
    raise SystemExit('TestFFIWrapper contains no test methods')
result = unittest.TextTestRunner(verbosity=2).run(suite)
if not result.wasSuccessful():
    raise SystemExit(1)
'''
        unit_run = subprocess.run(
            [sys.executable, '-c', helper], text=True, capture_output=True, timeout=20
        )
        assert unit_run.returncode == 0, unit_run.stdout + unit_run.stderr
        unit_calls = PROBE_LOG.read_text().splitlines() if PROBE_LOG.exists() else []
        assert 'AAB' in unit_calls, "TestFFIWrapper did not directly call the FFI function with 'AAB'"
    finally:
        LIBRARY.write_bytes(original_library)
        EVENTS.write_bytes(original_events)
        if original_results is None:
            RESULTS.unlink(missing_ok=True)
        else:
            RESULTS.write_bytes(original_results)
        PROBE_LOG.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
