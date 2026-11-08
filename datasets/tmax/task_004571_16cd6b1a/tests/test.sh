#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

SCRIPT = Path('/home/user/run_e2e.sh')
SOURCE = Path('/home/user/src/analyze_frame.c')
RESULT = Path('/home/user/result.txt')
VIDEO = Path('/app/deploy_recording.mp4')
FRAME_SIZE = 1920 * 1080 * 3


def read_result():
    assert RESULT.is_file(), f'Result file missing: {RESULT}'
    content = RESULT.read_text().strip()
    try:
        return int(content)
    except ValueError:
        pytest.fail(f"Result file does not contain a valid integer. Found: '{content}'")


def compile_trace_library(tmpdir):
    src = Path(tmpdir) / 'trace_exec.c'
    lib = Path(tmpdir) / 'trace_exec.so'
    src.write_text(r'''
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

__attribute__((constructor)) static void record_exec(void) {
    char exe[4096];
    ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (n <= 0) return;
    exe[n] = '\0';
    int fd = open("/tmp/verifier-exec-events.log", O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) return;
    dprintf(fd, "%s\n", exe);
    close(fd);
}
''')
    subprocess.run(
        ['gcc', '-shared', '-fPIC', '-O2', str(src), '-o', str(lib)],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    return lib


def run_submission(trace=False, timeout=300):
    event_file = Path('/tmp/verifier-exec-events.log')
    event_file.unlink(missing_ok=True)
    env = os.environ.copy()
    tmp = None
    if trace:
        tmp = tempfile.TemporaryDirectory(prefix='verifier-trace-')
        lib = compile_trace_library(tmp.name)
        env['LD_PRELOAD'] = str(lib)

    RESULT.unlink(missing_ok=True)
    try:
        proc = subprocess.run(
            [str(SCRIPT)], env=env, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=timeout
        )
    finally:
        if tmp is not None:
            tmp.cleanup()

    assert proc.returncode == 0, (
        f'run_e2e.sh failed with exit code {proc.returncode}\n'
        f'stdout:\n{proc.stdout[-4000:]}\nstderr:\n{proc.stderr[-4000:]}'
    )
    assert RESULT.is_file(), 'run_e2e.sh did not create /home/user/result.txt'
    events = event_file.read_text().splitlines() if event_file.exists() else []
    return events


def executable_reports_zero(path):
    try:
        proc = subprocess.run(
            [path], input=b'\0' * FRAME_SIZE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    if proc.returncode != 0:
        return False
    lines = proc.stdout.decode('ascii', errors='ignore').strip().splitlines()
    return bool(lines) and all(line.strip() == '0' for line in lines)


def derive_success_count(video):
    proc = subprocess.Popen(
        ['ffmpeg', '-v', 'error', '-i', str(video), '-f', 'rawvideo',
         '-pix_fmt', 'rgb24', 'pipe:1'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    count = 0
    frames = 0
    try:
        while True:
            data = bytearray()
            while len(data) < FRAME_SIZE:
                chunk = proc.stdout.read(FRAME_SIZE - len(data))
                if not chunk:
                    break
                data.extend(chunk)
            if not data:
                break
            assert len(data) == FRAME_SIZE, 'ffmpeg emitted a partial RGB24 frame'
            frames += 1
            avg_red = sum(data[0::3]) // (1920 * 1080)
            if avg_red > 200:
                count += 1
    finally:
        if proc.stdout:
            proc.stdout.close()
    stderr = proc.stderr.read() if proc.stderr else b''
    rc = proc.wait(timeout=60)
    assert rc == 0, f'Independent ffmpeg decode failed: {stderr.decode(errors="replace")}'
    assert frames > 0, 'Independent decoder found no video frames'
    return count


def make_alternate_video(path):
    red_indices = {0, 3, 6}
    proc = subprocess.Popen(
        ['ffmpeg', '-y', '-v', 'error', '-f', 'rawvideo', '-pixel_format', 'rgb24',
         '-video_size', '1920x1080', '-framerate', '30', '-i', 'pipe:0',
         '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', str(path)],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    red = b'\xff\x00\x00' * (1920 * 1080)
    black = b'\x00\x00\x00' * (1920 * 1080)
    try:
        for i in range(8):
            proc.stdin.write(red if i in red_indices else black)
        proc.stdin.close()
        proc.stdin = None
        stdout, stderr = proc.communicate(timeout=120)
    except Exception:
        proc.kill()
        proc.wait()
        raise
    assert proc.returncode == 0, f'Failed to create alternate video: {stderr.decode(errors="replace")}'


def test_script_exists():
    assert SCRIPT.is_file(), f'Bash script missing: {SCRIPT}'
    assert os.access(SCRIPT, os.X_OK), f'Bash script is not executable: {SCRIPT}'


def test_c_source_exists():
    assert SOURCE.is_file(), f'C source missing: {SOURCE}'


def test_c_compiles_cleanly_and_is_memory_safe(tmp_path):
    normal = tmp_path / 'analyze_frame'
    sanitized = tmp_path / 'analyze_frame_sanitized'

    subprocess.run(
        ['gcc', '-O2', '-Wall', '-Wextra', '-Wpedantic', '-Werror',
         str(SOURCE), '-o', str(normal)],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    subprocess.run(
        ['gcc', '-O2', '-Wall', '-Wextra', '-Wpedantic', '-Werror',
         '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
         str(SOURCE), '-o', str(sanitized)],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )

    cases = [
        (b'\x00\x00\x00' * (1920 * 1080), 0),
        (b'\xff\x00\x00' * (1920 * 1080), 255),
    ]
    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=1:halt_on_error=1'
    env['UBSAN_OPTIONS'] = 'halt_on_error=1:print_stacktrace=1'

    for data, expected in cases:
        proc = subprocess.run(
            [str(sanitized)], input=data, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, env=env, timeout=40
        )
        assert proc.returncode == 0, proc.stderr.decode(errors='replace')
        values = proc.stdout.decode().strip().splitlines()
        assert values and all(int(v) == expected for v in values)

    for _ in range(5):
        data = os.urandom(FRAME_SIZE)
        expected = sum(data[0::3]) // (1920 * 1080)
        proc = subprocess.run(
            [str(sanitized)], input=data, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, env=env, timeout=40
        )
        assert proc.returncode == 0, proc.stderr.decode(errors='replace')
        values = proc.stdout.decode().strip().splitlines()
        assert values and int(values[0]) == expected
        assert b'AddressSanitizer' not in proc.stderr
        assert b'runtime error:' not in proc.stderr


def test_result_count_and_runtime_pipeline():
    text = SCRIPT.read_text(errors='replace')
    assert re.search(r'\bffmpeg\b', text), 'run_e2e.sh does not invoke ffmpeg'
    assert 'rgb24' in text, 'run_e2e.sh does not request rgb24 frame output'
    assert re.search(r'/dev/urandom|os\.urandom|secrets\.|getrandom|openssl\s+rand', text), (
        'run_e2e.sh does not contain a random fuzz-data source'
    )

    events = run_submission(trace=True)
    agent_val = read_result()
    target_value = 14
    error = abs(agent_val - target_value)
    assert error <= 0, (
        f'Metric threshold failed: Expected exactly {target_value} frames, '
        f'but found {agent_val}. Error: {error} > 0'
    )

    ffmpeg_positions = [i for i, p in enumerate(events) if os.path.basename(p).startswith('ffmpeg')]
    assert ffmpeg_positions, 'No ffmpeg process was executed by run_e2e.sh'
    first_ffmpeg = ffmpeg_positions[0]

    counts = {}
    for p in events:
        counts[p] = counts.get(p, 0) + 1

    valid_analyzers = []
    for path, total in counts.items():
        if total < 6 or not os.path.isfile(path) or not os.access(path, os.X_OK):
            continue
        before_video = sum(1 for p in events[:first_ffmpeg] if p == path)
        if before_video >= 5 and executable_reports_zero(path):
            valid_analyzers.append((path, before_video, total))

    assert valid_analyzers, (
        'Could not verify five analyzer fuzz executions before ffmpeg processing '
        'and an additional analyzer execution for the video'
    )


def test_pipeline_on_alternate_recording(tmp_path):
    alternate = tmp_path / 'alternate.mp4'
    make_alternate_video(alternate)
    independently_expected = derive_success_count(alternate)
    assert independently_expected == 3

    backup_video = tmp_path / 'original.mp4'
    shutil.copy2(VIDEO, backup_video)
    old_result = RESULT.read_bytes() if RESULT.exists() else None
    try:
        shutil.copy2(alternate, VIDEO)
        run_submission(trace=False)
        assert read_result() == independently_expected, (
            'run_e2e.sh did not compute the success-frame count for a changed recording'
        )
    finally:
        shutil.copy2(backup_video, VIDEO)
        if old_result is None:
            RESULT.unlink(missing_ok=True)
        else:
            RESULT.write_bytes(old_result)
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
