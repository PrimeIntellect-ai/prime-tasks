#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=120, **kwargs)


def test_phase1_error_frame_and_repaired_analyzer():
    error_frame_path = Path('/home/user/error_frame.txt')
    assert error_frame_path.is_file(), f'File missing: {error_frame_path}'
    content = error_frame_path.read_text().strip()
    assert content in ['14', '15'], f"Expected frame 14 or 15 in {error_frame_path}, but got: '{content}'"

    source = Path('/home/user/tools/analyzer/main.cpp')
    assert source.is_file(), f'Analyzer source missing: {source}'
    source_text = source.read_text(errors='replace')
    assert not re.search(r'for\s*\([^;]*;[^;]*<=\s*size\b', source_text), \
        'The analyzer still contains the unsafe inclusive buffer bound'

    analyzer_dir = source.parent
    executables = []
    for path in analyzer_dir.iterdir():
        if path.is_file() and os.access(path, os.X_OK):
            try:
                if path.read_bytes()[:4] == b'\x7fELF':
                    executables.append(path)
            except OSError:
                pass
    assert executables, 'No compiled analyzer executable was found in /home/user/tools/analyzer'

    build_dir = Path(tempfile.mkdtemp(prefix='verify-analyzer-'))
    checked_binary = build_dir / 'analyzer_checked'
    compile_result = run([
        'g++', '-std=c++17', '-O1', '-g', '-fsanitize=address,undefined',
        '-fno-omit-frame-pointer', str(source), '-o', str(checked_binary)
    ])
    assert compile_result.returncode == 0, \
        f'Fixed analyzer source did not compile:\n{compile_result.stdout}\n{compile_result.stderr}'

    no_marker = build_dir / 'normal.bin'
    marker = build_dir / 'error.bin'
    data = bytearray(secrets.token_bytes(8192))
    data = bytearray(b if b != ord('R') else ord('Q') for b in data)
    no_marker.write_bytes(data)
    insert_at = secrets.randbelow(len(data))
    data[insert_at] = ord('R')
    marker.write_bytes(data)

    def check_analyzer(binary):
        env = os.environ.copy()
        env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'
        normal = subprocess.run([str(binary), str(no_marker)], capture_output=True, text=True,
                                timeout=20, env=env)
        error = subprocess.run([str(binary), str(marker)], capture_output=True, text=True,
                               timeout=20, env=env)
        return (normal.returncode == 0 and normal.stdout.strip() == 'STATE=OK' and
                error.returncode == 0 and error.stdout.strip() == 'STATE=UI_ERROR_MODAL')

    assert check_analyzer(checked_binary), 'The repaired analyzer failed behavioral or sanitizer checks'
    assert any(check_analyzer(binary) for binary in executables), \
        'No compiled analyzer artifact implements the repaired source behavior'

    frames_dir = build_dir / 'frames'
    frames_dir.mkdir()
    extraction = run([
        'ffmpeg', '-v', 'error', '-i', '/app/test_run.mp4', '-vf', 'fps=1',
        str(frames_dir / 'frame_%03d.bmp')
    ])
    assert extraction.returncode == 0, f'Could not extract recording frames: {extraction.stderr}'
    frames = sorted(frames_dir.glob('frame_*.bmp'))
    assert len(frames) >= 15, 'Recording did not produce the expected frames'
    for frame in frames:
        result = subprocess.run([str(checked_binary), str(frame)], capture_output=True, text=True,
                                timeout=20, env={**os.environ, 'ASAN_OPTIONS': 'detect_leaks=0:halt_on_error=1'})
        assert result.returncode == 0, f'Analyzer crashed on extracted frame {frame.name}'
        assert result.stdout.strip() in {'STATE=OK', 'STATE=UI_ERROR_MODAL'}, \
            f'Unexpected analyzer output on {frame.name}: {result.stdout!r}'

    pixels = subprocess.run([
        'ffmpeg', '-v', 'error', '-i', '/app/test_run.mp4', '-vf', 'fps=1,scale=1:1',
        '-pix_fmt', 'rgb24', '-f', 'rawvideo', '-'
    ], capture_output=True, timeout=120)
    assert pixels.returncode == 0 and len(pixels.stdout) >= 45, 'Could not analyze recording colors'
    rgb = [pixels.stdout[i:i+3] for i in range(0, len(pixels.stdout) - 2, 3)]
    red_index = max(range(len(rgb)), key=lambda i: rgb[i][0] - max(rgb[i][1], rgb[i][2])) + 1
    assert int(content) in {red_index, red_index - 1}, \
        f'error_frame.txt does not identify the independently detected red error frame {red_index}'


def test_phase2_go_race_with_immutable_stress_test():
    dispatcher_dir = Path('/home/user/dispatcher')
    assert dispatcher_dir.is_dir(), f'Directory missing: {dispatcher_dir}'

    original = run(['go', 'test', '-race'], cwd=dispatcher_dir)
    assert original.returncode == 0, \
        f'Go test failed or race condition detected:\nSTDOUT:\n{original.stdout}\nSTDERR:\n{original.stderr}'

    injected = dispatcher_dir / ('verifier_' + secrets.token_hex(8) + '_test.go')
    injected.write_text(r'''package main

import (
    "fmt"
    "sort"
    "testing"
)

func TestVerifierConcurrentCompleteness(t *testing.T) {
    for round := 0; round < 8; round++ {
        jobs := make([]string, 200)
        expected := make([]string, 200)
        for i := range jobs {
            jobs[i] = fmt.Sprintf("hidden-%d-%d-%d", round, i, (i*7919+round*104729)%1000003)
            expected[i] = jobs[i] + "_done"
        }
        d := &Dispatcher{}
        d.RunJobs(jobs)
        if len(d.Results) != len(expected) {
            t.Fatalf("round %d: expected %d results, got %d", round, len(expected), len(d.Results))
        }
        sort.Strings(d.Results)
        sort.Strings(expected)
        for i := range expected {
            if d.Results[i] != expected[i] {
                t.Fatalf("round %d result %d: expected %q, got %q", round, i, expected[i], d.Results[i])
            }
        }
    }
}
''')
    try:
        stressed = run(['go', 'test', '-race', '-count=1'], cwd=dispatcher_dir)
        assert stressed.returncode == 0, \
            f'Go dispatcher failed the verifier stress/race test:\nSTDOUT:\n{stressed.stdout}\nSTDERR:\n{stressed.stderr}'
    finally:
        injected.unlink(missing_ok=True)


def test_phase3_manifest_validator_hidden_generated_corpus():
    package_dir = Path('/home/user/manifest_validator')
    binary_path = package_dir / 'target/release/manifest_validator'
    assert binary_path.is_file(), f'Rust binary missing at {binary_path}. Did you compile with --release?'
    assert os.access(binary_path, os.X_OK), f'Rust binary is not executable at {binary_path}'

    evil_corpus = Path('/app/corpora/evil')
    clean_corpus = Path('/app/corpora/clean')
    evil_files = [p for p in evil_corpus.iterdir() if p.is_file()]
    clean_files = [p for p in clean_corpus.iterdir() if p.is_file()]
    assert evil_files, 'No files found in evil corpus.'
    assert clean_files, 'No files found in clean corpus.'

    bypassed_evil = [p.name for p in evil_files if run([str(binary_path), str(p)]).returncode == 0]
    rejected_clean = [p.name for p in clean_files if run([str(binary_path), str(p)]).returncode != 0]
    errors = []
    if bypassed_evil:
        errors.append(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")
    if rejected_clean:
        errors.append(f"{len(rejected_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(rejected_clean)}")
    assert not errors, 'Manifest validator failed:\n' + '\n'.join(errors)

    assert (package_dir / 'Cargo.toml').is_file(), 'Cargo.toml is missing'
    assert (package_dir / 'src/main.rs').is_file(), 'Rust source src/main.rs is missing'
    target_dir = Path(tempfile.mkdtemp(prefix='verify-rust-target-'))
    built = subprocess.run(
        ['cargo', 'build', '--release', '--offline'], cwd=package_dir,
        env={**os.environ, 'CARGO_TARGET_DIR': str(target_dir)},
        capture_output=True, text=True, timeout=180
    )
    assert built.returncode == 0, f'Rust package could not be rebuilt:\n{built.stdout}\n{built.stderr}'
    rebuilt_binary = target_dir / 'release/manifest_validator'
    assert rebuilt_binary.is_file() and os.access(rebuilt_binary, os.X_OK), 'Rebuilt CLI is missing'

    corpus_dir = Path(tempfile.mkdtemp(prefix='manifest-hidden-'))
    token = secrets.token_hex(10)
    safe = f'assets/{token}/icon-{random.randrange(100000, 999999)}.png'
    cases = [
        (True, {'schema': 'v1', 'asset_path': safe}),
        (True, {'asset_path': f'./local/{token}.jpg', 'schema': 'v2'}),
        (True, {'schema': 'v2', 'asset_path': f'content/{token}/../safe.png'.replace(f'{token}/../', '')}),
        (False, {'schema': 'v1', 'asset_path': f'assets/{token}/../../secret'}),
        (False, {'schema': 'v2', 'asset_path': f'../{token}/payload'}),
        (False, {'schema': 'v1', 'asset_path': f'/etc/{token}'}),
        (False, {'schema': 'v2', 'asset_path': f'/var/tmp/{token}'}),
        (False, {'schema': 'v1', 'asset_path': safe, 'assets': {'icon': safe}}),
        (False, {'schema': 'v2', 'asset_path': safe, 'assets': [safe]}),
        (False, {'schema': 'v3', 'asset_path': safe}),
        (False, {'schema': ['v1'], 'asset_path': safe}),
        (False, {'schema': 'v1', 'asset_path': 42}),
    ]

    for index, (should_accept, value) in enumerate(cases):
        path = corpus_dir / f'{secrets.token_hex(7)}-{index}.json'
        path.write_text(json.dumps(value, ensure_ascii=False, indent=(index % 4) + 1))
        result = run([str(rebuilt_binary), str(path)])
        if should_accept:
            assert result.returncode == 0, f'Valid hidden manifest was rejected: {value}\n{result.stderr}'
        else:
            assert result.returncode != 0, f'Invalid hidden manifest was accepted: {value}'

    malformed = corpus_dir / f'{secrets.token_hex(8)}.json'
    malformed.write_text('{"schema":"v1","asset_path":')
    assert run([str(rebuilt_binary), str(malformed)]).returncode != 0, 'Malformed JSON was accepted'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
