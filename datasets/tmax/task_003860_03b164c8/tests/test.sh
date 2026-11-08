#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_submission.py
import csv
import ctypes
import json
import math
import os
from pathlib import Path
import random
import shutil
import struct
import subprocess
import wave


def locate_rust_program():
    preferred = Path('/home/user/restore_tool/Cargo.toml')
    manifests = []
    if preferred.is_file():
        manifests.append(preferred)

    for root in (Path('/home/user'), Path('/app')):
        if not root.exists():
            continue
        for path in root.rglob('Cargo.toml'):
            if 'target' in path.parts or path == preferred:
                continue
            manifests.append(path)

    for manifest in manifests:
        rust_sources = [p for p in manifest.parent.rglob('*.rs') if 'target' not in p.parts]
        if rust_sources:
            return ['cargo', 'run', '--quiet', '--offline', '--manifest-path', str(manifest)], manifest.parent

    standalone = []
    for root in (Path('/home/user'), Path('/app')):
        if not root.exists():
            continue
        for path in root.rglob('*.rs'):
            if 'target' not in path.parts and path.is_file():
                standalone.append(path)

    for source in sorted(standalone, key=lambda p: (p.name != 'main.rs', len(p.parts))):
        try:
            if 'fn main' in source.read_text(errors='ignore'):
                binary = '/tmp/submitted_restore_tool'
                subprocess.run(
                    ['rustc', str(source), '-o', binary],
                    check=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=120,
                )
                return [binary], source.parent
        except (OSError, subprocess.SubprocessError):
            continue

    raise AssertionError('No executable Rust program was found.')


def prepare_dynamic_fixture():
    restored = Path('/app/restored')
    blobs = Path('/app/blobs')
    shutil.rmtree(restored, ignore_errors=True)
    shutil.rmtree(blobs, ignore_errors=True)
    restored.mkdir(parents=True)
    blobs.mkdir(parents=True)

    seed = int.from_bytes(os.urandom(16), 'big')
    rng = random.Random(seed)
    suffix = f'{seed:x}'
    sample_rate = rng.choice([8000, 11025, 16000, 22050, 44100])
    window_size = int(sample_rate * 0.1)
    sample_count = window_size * 4 + rng.randrange(1, window_size)
    samples = [rng.randint(-32768, 32767) for _ in range(sample_count)]

    entries = [
        (f'audio_{suffix}', f'logs/{suffix}/operator.wav', 'audio'),
        (f'config_{suffix}', f'etc/{suffix}/sysconfig.txt', 'text'),
        (f'db_{suffix}', f'db/{suffix}/users.sql', 'text'),
    ]

    with wave.open(str(blobs / entries[0][0]), 'wb') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(struct.pack('<' + 'h' * len(samples), *samples))

    (blobs / entries[1][0]).write_text(f'config-{rng.getrandbits(128):032x}\n')
    (blobs / entries[2][0]).write_text(f'database-{rng.getrandbits(128):032x}\n')

    with open('/app/backup_manifest.csv', 'w', newline='') as manifest:
        writer = csv.writer(manifest)
        writer.writerow(['blob_id', 'original_path', 'file_type'])
        writer.writerows(entries)

    expected_rms = []
    normalized = [sample / 32768.0 for sample in samples]
    for start in range(0, len(normalized), window_size):
        window = normalized[start:start + window_size]
        if len(window) < window_size:
            window += [0.0] * (window_size - len(window))
        expected_rms.append(math.sqrt(sum(x * x for x in window) / window_size))

    return entries, expected_rms


def start_atomicity_watch():
    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, f'inotify_init1 failed: errno {ctypes.get_errno()}'

    mask = 0x00000002 | 0x00000008 | 0x00000040 | 0x00000080 | 0x00000100
    wd = libc.inotify_add_watch(fd, b'/app/restored', mask)
    assert wd >= 0, f'inotify_add_watch failed: errno {ctypes.get_errno()}'
    return fd


def read_events(fd):
    events = []
    try:
        while True:
            try:
                data = os.read(fd, 65536)
            except BlockingIOError:
                break
            if not data:
                break
            offset = 0
            while offset < len(data):
                wd, mask, cookie, name_len = struct.unpack_from('iIII', data, offset)
                offset += 16
                raw_name = data[offset:offset + name_len]
                offset += name_len
                name = raw_name.split(b'\0', 1)[0].decode(errors='replace')
                events.append((mask, cookie, name))
    finally:
        os.close(fd)
    return events


def test_rust_restoration_and_atomic_rms():
    command, cwd = locate_rust_program()
    entries, true_rms = prepare_dynamic_fixture()
    watch_fd = start_atomicity_watch()

    env = os.environ.copy()
    env['CARGO_NET_OFFLINE'] = 'true'
    try:
        result = subprocess.run(
            command,
            cwd=str(cwd),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired as exc:
        read_events(watch_fd)
        raise AssertionError('The Rust program timed out.') from exc

    events = read_events(watch_fd)
    assert result.returncode == 0, (
        f'Rust program exited with {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )

    # Preserve the original hard-link assertions, now on an unpredictable manifest.
    for blob_id, original_path, _ in entries:
        blob_path = Path('/app/blobs') / blob_id
        restored_path = Path('/app/restored') / original_path
        assert restored_path.exists(), f'Restored file {restored_path} is missing.'
        blob_stat = blob_path.stat()
        restored_stat = restored_path.stat()
        assert (blob_stat.st_dev, blob_stat.st_ino) == (restored_stat.st_dev, restored_stat.st_ino), (
            f'File {restored_path} is not a hard link to {blob_path}.'
        )

    output_path = Path('/app/restored/rms_output.json')
    assert output_path.is_file(), f'Output file {output_path} is missing.'
    try:
        agent_rms = json.loads(output_path.read_text())
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {output_path} is not valid JSON.') from exc

    assert isinstance(agent_rms, list), 'Output JSON must be an array.'
    assert len(agent_rms) == len(true_rms), (
        f'Length mismatch: agent output has {len(agent_rms)} values, expected {len(true_rms)}.'
    )
    assert all(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
               for value in agent_rms), 'RMS output must contain only finite numeric values.'

    mse = sum((actual - expected) ** 2 for actual, expected in zip(agent_rms, true_rms)) / len(true_rms)
    assert mse < 1e-5, f'MSE {mse} exceeds threshold of 1e-5.'

    IN_MODIFY = 0x00000002
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100

    final_events = [(mask, cookie) for mask, cookie, name in events if name == 'rms_output.json']
    assert any(mask & IN_MOVED_TO for mask, _ in final_events), (
        'rms_output.json was not installed by a rename from a temporary file.'
    )
    assert not any(mask & (IN_CREATE | IN_MODIFY | IN_CLOSE_WRITE) for mask, _ in final_events), (
        'rms_output.json was written directly instead of being written to a temporary file and renamed.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_submission.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
