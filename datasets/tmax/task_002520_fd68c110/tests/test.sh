#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/verify_pipeline.py
import datetime
import math
import os
import random
import re
import struct
import subprocess
import wave
from pathlib import Path

INPUTS = [Path('/app/sensor_logs.jsonl'), Path('/app/backup_morse.wav'), Path('/app/reference.csv')]
LOG = Path('/home/user/pipeline.log')
RESULT = Path('/home/user/mse_result.txt')
FLOAT_RE = re.compile(r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$')
MORSE = {
    '0': '-----', '1': '.----', '2': '..---', '3': '...--', '4': '....-',
    '5': '.....', '6': '-....', '7': '--...', '8': '---..', '9': '----.',
    '.': '.-.-.-'
}

original = {p: p.read_bytes() for p in INPUTS}


def candidate_scripts():
    found = []
    for root in ('/home/user', '/app', '/root', '/workspace'):
        base = Path(root)
        if not base.exists():
            continue
        for p in base.rglob('*.py'):
            try:
                if not p.is_file() or p.is_symlink() or p.stat().st_size > 2_000_000:
                    continue
                text = p.read_text(errors='ignore')
            except OSError:
                continue
            markers = sum(x in text for x in ('sensor_logs.jsonl', 'backup_morse.wav',
                                               'mse_result.txt', 'pipeline.log', 'reference.csv'))
            if markers >= 2:
                name_score = sum(x in p.name.lower() for x in ('pipeline', 'recover', 'sensor', 'main'))
                found.append((-name_score, -markers, str(p)))
    return [Path(x[2]) for x in sorted(set(found))]


def clear_outputs():
    for p in (LOG, RESULT):
        try:
            p.unlink()
        except FileNotFoundError:
            pass


def execute(script):
    clear_outputs()
    proc = subprocess.run(
        ['python3', str(script)], cwd=str(script.parent),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60
    )
    assert proc.returncode == 0, (
        f'{script} exited with {proc.returncode}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    assert LOG.is_file(), f'Log file missing at {LOG}'
    assert RESULT.is_file(), f'Result file missing at {RESULT}'


def read_and_check_outputs(expected_mse, decoded_text):
    # Preserve and strengthen the original log assertions.
    content = LOG.read_text(errors='replace')
    assert '[INFO]' in content, "Log file does not contain expected '[INFO]' tags."
    assert 'Pipeline completed' in content, 'Log file does not indicate pipeline completion.'
    assert '[INFO] Pipeline completed.' in content, 'Missing required completion log entry.'

    parsed = re.findall(r'\[INFO\]\s*Parsed\s+(\d+)\s+valid records from JSONL', content)
    assert parsed, 'Missing required parsed-record count log entry.'
    assert 5 <= int(parsed[-1]) <= 7, f'Implausible JSONL record count: {parsed[-1]}'
    assert f'[INFO] Decoded audio: {decoded_text}' in content, (
        'The log does not contain the Morse text recovered from the current WAV input.'
    )

    raw = RESULT.read_text().strip()
    assert FLOAT_RE.fullmatch(raw), f'{RESULT} must contain one finite float; got {raw!r}'
    submitted = float(raw)
    assert math.isfinite(submitted), 'Submitted MSE is not finite.'

    # Preserve the original threshold assertion, then require an actual metric match.
    diff = abs(submitted - expected_mse)
    assert diff < 0.5, (
        f'Submitted MSE {submitted} is too far from expected MSE {expected_mse:.12g}.'
    )
    assert diff <= max(1e-7, abs(expected_mse) * 1e-7), (
        f'Submitted MSE {submitted} does not match the independently derived MSE '
        f'{expected_mse:.12g} (difference {diff:.12g}).'
    )


def write_wav(text):
    rate = 8000
    dot = 0.06
    samples = []

    def tone(duration):
        n = int(rate * duration)
        samples.extend(int(32767 * math.sin(2 * math.pi * 1000 * i / rate)) for i in range(n))

    def silence(duration):
        samples.extend([0] * int(rate * duration))

    for word in text.split(' '):
        for char in word:
            for symbol in MORSE[char]:
                tone(dot if symbol == '.' else 3 * dot)
                silence(dot)
            silence(2 * dot)
        silence(4 * dot)

    with wave.open(str(INPUTS[1]), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(b''.join(struct.pack('<h', x) for x in samples))


def write_case(rng):
    # Values in the malformed records equal their interpolation values, so either
    # permitted policy (repairing or gracefully skipping those records) has the
    # same correct reconstructed series.
    allowed = [10.5, 12.5, 15.0, 17.5, 20.0, 22.5, 25.0, 27.5]
    v0, v2, v6, v8, v12 = [rng.choice(allowed) for _ in range(5)]
    v1, v3, v5 = [rng.choice(allowed) for _ in range(3)]
    v4 = (v3 + v5) / 2
    v10 = (v8 + v12) / 2

    lines = [
        f'{{"timestamp": "2023-10-01T12:00:00", "value": {v0}}}',
        f'{{"timestamp": "2023-10-01T12:10:00", "value": {v2}}}',
        f'{{"timestamp": "2023-10-01T12:20:00", "value": {v4}, "note": "bad \\u001"}}',
        f'{{"timestamp": "2023-10-01T12:30:00", "value": {v6}}}',
        f'{{"timestamp": "2023-10-01T12:40:00", "value": {v8}}}',
        f'{{"timestamp": "2023-10-01T12:50:00", "value": {v10}, "note": "bad \\xZZ"}}',
        f'{{"timestamp": "2023-10-01T13:00:00", "value": {v12}}}',
    ]
    INPUTS[0].write_text('\n'.join(lines) + '\n')

    decoded = f'1205 {v1:.1f} 1215 {v3:.1f} 1225 {v5:.1f}'
    write_wav(decoded)

    reconstructed = [
        v0, v1, v2, v3, v4, v5, v6, (v6 + v8) / 2, v8,
        (v8 + v10) / 2, v10, (v10 + v12) / 2, v12
    ]
    reference = [v + rng.randint(-93, 93) / 100 for v in reconstructed]
    with INPUTS[2].open('w') as f:
        f.write('timestamp,value\n')
        dt = datetime.datetime(2023, 10, 1, 12, 0)
        for value in reference:
            f.write(f'{dt:%Y-%m-%d %H:%M:%S},{value:.12g}\n')
            dt += datetime.timedelta(minutes=5)

    mse = sum((a - b) ** 2 for a, b in zip(reconstructed, reference)) / len(reconstructed)
    return decoded, mse


try:
    scripts = candidate_scripts()
    assert scripts, 'No Python pipeline artifact was found.'

    original_expected = [10.0, 12.5, 15.0, 17.5, 20.0, 22.5, 25.0,
                         27.5, 30.0, 32.5, 35.0, 37.5, 40.0]
    original_reference = [10.2, 12.4, 15.1, 17.6, 20.0, 22.3, 25.0,
                          27.8, 30.1, 32.5, 34.9, 37.5, 40.2]
    original_mse = sum((a-b)**2 for a, b in zip(original_expected, original_reference)) / 13

    selected = None
    failures = []
    for script in scripts:
        for p, data in original.items():
            p.write_bytes(data)
        try:
            execute(script)
            read_and_check_outputs(original_mse, '1205 12.5 1215 17.5 1225 22.5')
            selected = script
            break
        except Exception as exc:
            failures.append(f'{script}: {exc}')
    assert selected is not None, 'No submitted pipeline passed its original input: ' + ' | '.join(failures)

    # Fresh unpredictable cases prevent a precomputed MSE or fabricated log from passing.
    rng = random.Random(int.from_bytes(os.urandom(16), 'big'))
    for _ in range(2):
        decoded, expected_mse = write_case(rng)
        execute(selected)
        read_and_check_outputs(expected_mse, decoded)
finally:
    for p, data in original.items():
        p.write_bytes(data)
PY

if python3 /tmp/verify_pipeline.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
