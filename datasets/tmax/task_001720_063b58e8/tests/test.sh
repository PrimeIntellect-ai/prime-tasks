#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import shlex
import stat
import subprocess
import tempfile
import uuid

import numpy as np
import pytest
from scipy.io import wavfile

SCRIPT_PATH = '/home/user/filter.sh'
MARKER = os.path.join('/tmp', '.aubio_invocations_' + uuid.uuid4().hex)
WRAPPED = False


def _aubio_binaries():
    result = subprocess.run(
        ['find', '/app', '/home/user', '/usr/local', '-type', 'f', '-name', 'aubiopitch', '-perm', '/111'],
        capture_output=True, text=True, check=False
    )
    candidates = []
    for path in result.stdout.splitlines():
        try:
            with open(path, 'rb') as f:
                if f.read(4) == b'\x7fELF':
                    candidates.append(path)
        except OSError:
            pass
    return candidates


def _ensure_compiled_aubio_and_wrap():
    global WRAPPED
    if WRAPPED:
        return

    binaries = _aubio_binaries()
    assert binaries, 'No compiled ELF aubiopitch executable was found.'

    aubio_evidence = False
    for path in binaries:
        strings = subprocess.run(['strings', path], capture_output=True, text=True, check=False).stdout.lower()
        ldd = subprocess.run(['ldd', path], capture_output=True, text=True, check=False).stdout.lower()
        if 'aubio_pitch' in strings or 'libaubio' in ldd:
            aubio_evidence = True
    assert aubio_evidence, 'The aubiopitch executable does not appear to be built from aubio.'

    for path in binaries:
        real_path = path + '.verifier-real'
        os.rename(path, real_path)
        wrapper = '#!/bin/bash\nprintf "%s\\n" "$$" >> ' + shlex.quote(MARKER) + '\nexec ' + shlex.quote(real_path) + ' "$@"\n'
        with open(path, 'w') as f:
            f.write(wrapper)
        os.chmod(path, 0o755)

    open(MARKER, 'a').close()
    WRAPPED = True


def _invocation_count():
    try:
        with open(MARKER) as f:
            return sum(1 for _ in f)
    except FileNotFoundError:
        return 0


def test_filter_script_exists():
    assert os.path.isfile('/home/user/filter.sh'), '/home/user/filter.sh does not exist.'


def test_compiled_aubiopitch_exists():
    assert os.path.isfile(SCRIPT_PATH), 'Script /home/user/filter.sh is missing.'
    with open(SCRIPT_PATH, errors='replace') as f:
        script = f.read()
    assert 'aubiopitch' in script, 'filter.sh does not reference aubiopitch.'
    _ensure_compiled_aubio_and_wrap()


def test_adversarial_corpus():
    script_path = '/home/user/filter.sh'
    assert os.path.isfile(script_path), 'Script /home/user/filter.sh is missing.'

    evil_dir = '/app/corpus/evil'
    clean_dir = '/app/corpus/clean'

    evil_files = glob.glob(os.path.join(evil_dir, '*.wav'))
    clean_files = glob.glob(os.path.join(clean_dir, '*.wav'))

    assert len(evil_files) > 0, f'No evil files found in {evil_dir}'
    assert len(clean_files) > 0, f'No clean files found in {clean_dir}'

    evil_bypassed = []
    clean_rejected = []

    for evil_file in evil_files:
        result = subprocess.run(['bash', script_path, evil_file], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(evil_file))

    for clean_file in clean_files:
        result = subprocess.run(['bash', script_path, clean_file], capture_output=True)
        if result.returncode != 0:
            clean_rejected.append(os.path.basename(clean_file))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f'{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {", ".join(evil_bypassed)}')
    if clean_rejected:
        error_messages.append(f'{len(clean_rejected)} of {len(clean_files)} clean modified (rejected): {", ".join(clean_rejected)}')

    if error_messages:
        pytest.fail(' | '.join(error_messages))


def test_unseen_neutral_path_audio_and_aubiopitch_invocation():
    _ensure_compiled_aubio_and_wrap()
    probe_dir = tempfile.mkdtemp(prefix='audio_inputs_')
    rng = np.random.default_rng()
    sample_rate = 44100
    t = np.arange(sample_rate, dtype=np.float64) / sample_rate
    cases = []

    for _ in range(8):
        name = uuid.uuid4().hex + '.wav'
        freq = float(rng.uniform(320.0, 780.0))
        audio = np.sin(2 * np.pi * freq * t) + rng.normal(0, 0.1, sample_rate)
        audio = np.int16(audio / np.max(np.abs(audio)) * 32767)
        path = os.path.join(probe_dir, name)
        wavfile.write(path, sample_rate, audio)
        cases.append((path, 0))

    for _ in range(8):
        name = uuid.uuid4().hex + '.wav'
        audio = rng.normal(0, 1.0, sample_rate)
        audio = np.int16(audio / np.max(np.abs(audio)) * 32767)
        path = os.path.join(probe_dir, name)
        wavfile.write(path, sample_rate, audio)
        cases.append((path, 1))

    random.SystemRandom().shuffle(cases)
    failures = []
    for path, expected in cases:
        before = _invocation_count()
        result = subprocess.run(['bash', SCRIPT_PATH, path], capture_output=True, timeout=20)
        after = _invocation_count()
        if result.returncode != expected:
            failures.append(f'{os.path.basename(path)} expected {expected}, got {result.returncode}')
        if after <= before:
            failures.append(f'{os.path.basename(path)} did not execute compiled aubiopitch')

    assert not failures, ' | '.join(failures)


def test_fixture_analysis_log():
    path = '/home/user/fixture_analysis.log'
    assert os.path.isfile(path), '/home/user/fixture_analysis.log does not exist.'
    text = open(path, errors='replace').read()
    assert text.strip(), 'fixture_analysis.log is empty.'
    lower = text.lower()
    assert 'average' in lower and 'pitch' in lower, 'Fixture log must identify an average pitch.'
    values = [float(x) for x in re.findall(r'(?<![A-Za-z])[-+]?(?:\d+(?:\.\d*)?|\.\d+)', text)]
    assert any(250.0 <= value <= 850.0 for value in values), 'Fixture log has no plausible average pitch frequency.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
