#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import stat
import struct
import subprocess
from pathlib import Path

import pytest

APP = Path('/app')
EXTRACTOR = APP / 'extractor'
REPORT = Path('/home/user/report.json')


def run(cmd, cwd=None, timeout=90, env=None):
    return subprocess.run(
        cmd, cwd=cwd, env=env, timeout=timeout,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )


def write_bmp(path, payload, width=320, height=8):
    row_size = ((width * 24 + 31) // 32) * 4
    encoded = payload.encode('utf-8')
    assert len(encoded) < width
    with open(path, 'wb') as f:
        f.write(b'BM')
        f.write(struct.pack('<IHHI', 54 + row_size * height, 0, 0, 54))
        f.write(struct.pack('<IiiHHIIiiII', 40, width, height, 1, 24, 0,
                            row_size * height, 2835, 2835, 0, 0))
        empty = bytes(row_size)
        for _ in range(height - 1):
            f.write(empty)
        top = bytearray(row_size)
        for i, value in enumerate(encoded):
            top[i * 3 + 2] = value
        f.write(top)


def make_video(path, telemetry):
    frame_dir = Path('/tmp/verifier_frames')
    shutil.rmtree(frame_dir, ignore_errors=True)
    frame_dir.mkdir()
    try:
        for i in range(max(12, len(telemetry) * 3)):
            payload = json.dumps(telemetry[i], separators=(',', ':')) if i < len(telemetry) else ''
            write_bmp(frame_dir / f'frame_{i:03d}.bmp', payload)
        proc = run([
            'ffmpeg', '-y', '-loglevel', 'error', '-framerate', '30',
            '-i', str(frame_dir / 'frame_%03d.bmp'),
            '-c:v', 'libx264rgb', '-crf', '0', str(path)
        ], timeout=120)
        assert proc.returncode == 0, proc.stderr
    finally:
        shutil.rmtree(frame_dir, ignore_errors=True)


def load_report():
    assert REPORT.is_file(), f'Report file {REPORT} is missing.'
    try:
        with REPORT.open() as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'File {REPORT} is not valid JSON: {exc}')


def workflow_candidates():
    candidates = []
    for root in (Path('/app'), Path('/home/user')):
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {'.git', '__pycache__'}]
            for name in files:
                path = Path(directory) / name
                if path == Path('/app/extractor/decoder.c') or path == Path('/app/extractor/Makefile'):
                    continue
                try:
                    if path.stat().st_size > 1_000_000:
                        continue
                    raw = path.read_bytes()
                    text = raw.decode('utf-8')
                except (OSError, UnicodeDecodeError):
                    continue
                lower = text.lower()
                if not all(token in lower for token in ('ffmpeg', 'manifest', 'report.json', 'decoder')):
                    continue
                if path.suffix == '.py' or text.startswith('#!/usr/bin/env python') or text.startswith('#!/usr/bin/python'):
                    command = ['python3', str(path)]
                elif path.suffix in {'.sh', '.bash'} or 'bash' in text[:100] or text.startswith('#!/bin/sh'):
                    command = ['bash', str(path)]
                elif path.stat().st_mode & stat.S_IXUSR:
                    command = [str(path)]
                else:
                    continue
                score = sum(token in lower for token in ('semantic', 'outdated_components', 'deploy_capture.mp4'))
                candidates.append((score, path, command))
    candidates.sort(key=lambda item: (-item[0], str(item[1])))
    return candidates


def test_extractor_builds_and_decodes_cleanly():
    assert (EXTRACTOR / 'Makefile').is_file(), 'Extractor Makefile is missing.'
    assert (EXTRACTOR / 'decoder.c').is_file(), 'decoder.c is missing.'

    build = run(['make', '-B'], cwd=EXTRACTOR)
    assert build.returncode == 0, f'Extractor does not build with make:\n{build.stdout}\n{build.stderr}'

    decoder = EXTRACTOR / 'decoder'
    assert decoder.is_file(), 'make did not create /app/extractor/decoder.'
    assert os.access(decoder, os.X_OK), 'The built decoder is not executable.'
    assert decoder.read_bytes()[:4] == b'\x7fELF', 'decoder is not a compiled executable.'

    payload = '{"component":"verifier-probe","version":"1.2.3-rc.1"}'
    bmp = Path('/tmp/verifier_decoder.bmp')
    write_bmp(bmp, payload, width=96, height=3)
    decoded = run([str(decoder), str(bmp)], cwd=EXTRACTOR)
    assert decoded.returncode == 0, decoded.stderr
    assert decoded.stdout.strip() == payload, f'Decoder returned unexpected data: {decoded.stdout!r}'

    # Rebuild the supplied decoder source with sanitizers and exercise the frame
    # shape that triggers the original one-past-the-end rows[] write.
    sanitized = Path('/tmp/verifier_decoder_san')
    san_build = run([
        'gcc', '-std=c11', '-O0', '-g', '-fsanitize=address,undefined',
        '-fno-omit-frame-pointer', '-o', str(sanitized), str(EXTRACTOR / 'decoder.c')
    ], cwd=EXTRACTOR)
    assert san_build.returncode == 0, f'decoder.c failed sanitizer build:\n{san_build.stderr}'
    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=1:halt_on_error=1'
    clean_run = run([str(sanitized), str(bmp)], cwd=EXTRACTOR, env=env)
    assert clean_run.returncode == 0, f'Decoder has a memory/undefined-behavior error:\n{clean_run.stderr}'
    assert clean_run.stdout.strip() == payload

    source = (EXTRACTOR / 'decoder.c').read_text(errors='replace')
    assert not re.search(r'for\s*\([^;]*;[^;]*<=\s*height\s*;', source), \
        'The original one-past-height loop is still present.'


def test_programmatic_workflow_on_derived_inputs():
    candidates = workflow_candidates()
    assert candidates, ('No programmatic Python/Bash workflow was found that invokes ffmpeg and the decoder, '
                        'reads the manifest, and writes report.json.')

    original_video = Path('/app/deploy_capture.mp4')
    original_manifest = Path('/app/manifest.json')
    video_backup = Path('/tmp/original_deploy_capture.mp4')
    manifest_backup = Path('/tmp/original_manifest.json')
    shutil.copy2(original_video, video_backup)
    shutil.copy2(original_manifest, manifest_backup)

    novel_video = Path('/tmp/novel_deploy_capture.mp4')
    novel_manifest = {
        'probe-prerelease': '1.0.0',
        'probe-build': '2.0.0',
        'probe-numeric': '1.0.0-beta.2',
        'probe-newer': '0.9.0'
    }
    novel_telemetry = [
        {'component': 'probe-prerelease', 'version': '1.0.0-rc.1'},
        {'component': 'probe-build', 'version': '2.0.0+build.99'},
        {'component': 'probe-numeric', 'version': '1.0.0-beta.11'},
        {'component': 'probe-newer', 'version': '1.0.0'}
    ]
    make_video(novel_video, novel_telemetry)

    selected = None
    failures = []
    try:
        for _, path, command in candidates:
            shutil.copy2(novel_video, original_video)
            original_manifest.write_text(json.dumps(novel_manifest))
            REPORT.unlink(missing_ok=True)
            try:
                proc = run(command, cwd=path.parent, timeout=120)
            except subprocess.TimeoutExpired:
                failures.append(f'{path}: timed out')
                continue
            if proc.returncode != 0:
                failures.append(f'{path}: exited {proc.returncode}: {proc.stderr[-500:]}')
                continue
            try:
                data = load_report()
            except BaseException as exc:
                failures.append(f'{path}: did not produce a valid report: {exc}')
                continue
            result = data.get('outdated_components')
            if isinstance(result, list) and set(result) == {'probe-prerelease'}:
                selected = (path, command)
                break
            failures.append(f'{path}: novel-input result was {result!r}')
    finally:
        shutil.copy2(video_backup, original_video)
        shutil.copy2(manifest_backup, original_manifest)

    assert selected is not None, 'No workflow correctly processed derived video/manifest inputs. ' + ' | '.join(failures)

    # Re-run that same workflow on the task inputs so the final report is itself
    # produced by the tested pipeline rather than by the verifier.
    path, command = selected
    REPORT.unlink(missing_ok=True)
    proc = run(command, cwd=path.parent, timeout=120)
    assert proc.returncode == 0, f'Workflow failed on the supplied audit log:\n{proc.stdout}\n{proc.stderr}'
    assert REPORT.is_file(), 'Workflow did not recreate /home/user/report.json.'


def test_report_jaccard_similarity():
    report_path = '/home/user/report.json'
    assert os.path.isfile(report_path), f'Report file {report_path} is missing.'

    try:
        with open(report_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'File {report_path} is not valid JSON.')

    assert 'outdated_components' in data, "Key 'outdated_components' is missing from report.json."

    agent_list = data.get('outdated_components', [])
    assert isinstance(agent_list, list), "'outdated_components' must be a list."

    agent_data = set(agent_list)
    truth_data = {'auth-service', 'frontend'}

    intersection = len(agent_data.intersection(truth_data))
    union = len(agent_data.union(truth_data))
    jaccard = intersection / union if union > 0 else 0.0

    assert jaccard >= 0.95, f'Jaccard similarity {jaccard:.2f} is below threshold 0.95. Agent components: {agent_data}, Expected: {truth_data}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
