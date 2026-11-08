#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
from pathlib import Path

import pytest

REPO = Path('/home/user/signal_decoder')
AGENT = REPO / 'signal_decoder'
SOURCE = REPO / 'decoder.cpp'
MAKEFILE = REPO / 'Makefile'
ORACLE = Path('/app/oracle_decoder')
SOURCE_BUILD = Path('/tmp/signal_decoder_from_source')


def run_decoder(path, fuzz_input, timeout=10):
    return subprocess.run(
        [str(path)],
        input=fuzz_input.encode('ascii'),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def expected_output(hex_input):
    return bytes.fromhex(hex_input) + b'\n'


@pytest.fixture(scope='session', autouse=True)
def rebuild_project():
    assert REPO.is_dir(), f'Repository {REPO} is missing.'
    assert SOURCE.is_file(), f'Repaired source {SOURCE} is missing.'
    assert MAKEFILE.is_file(), f'{MAKEFILE} is missing.'

    # The requested fixes must be present in the actual source/build files, not
    # replaced by a copied oracle or a wrapper around it.
    source = SOURCE.read_text(errors='replace')
    makefile = MAKEFILE.read_text(errors='replace')
    checked_text = source + '\n' + makefile
    assert '/app/oracle_decoder' not in checked_text, 'Source or Makefile invokes the oracle.'
    assert 'oracle_decoder' not in checked_text, 'Source or Makefile wraps/copies the oracle.'
    assert '-pthread' in makefile, 'Makefile does not enable pthread support.'

    # Ignore comments when checking the two concrete regressions in this codebase.
    code = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
    code = re.sub(r'//.*', '', code)
    assert re.search(r'chunk_size\s*=\s*16\s*;', code), 'The chunk-size regression was not fixed.'
    has_raii_lock = re.search(r'(lock_guard|scoped_lock|unique_lock)\s*<', code)
    has_manual_lock = re.search(r'\bmtx\s*\.\s*lock\s*\(\s*\)', code) and re.search(r'\bmtx\s*\.\s*unlock\s*\(\s*\)', code)
    assert has_raii_lock or has_manual_lock, 'The result-vector synchronization was not restored.'

    if AGENT.exists() or AGENT.is_symlink():
        AGENT.unlink()
    built = subprocess.run(
        ['make', '-B'], cwd=REPO, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=60
    )
    assert built.returncode == 0, (
        'make failed.\nstdout:\n' + built.stdout.decode(errors='replace') +
        '\nstderr:\n' + built.stderr.decode(errors='replace')
    )

    # Independently compile the repaired source so a Makefile that merely copies
    # or launches the reference binary cannot satisfy the behavioral checks.
    compiled = subprocess.run(
        ['g++', '-O3', '-pthread', str(SOURCE), '-o', str(SOURCE_BUILD)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert compiled.returncode == 0, (
        'decoder.cpp does not compile independently.\nstdout:\n' +
        compiled.stdout.decode(errors='replace') + '\nstderr:\n' +
        compiled.stderr.decode(errors='replace')
    )


def test_executable_exists():
    assert os.path.isfile(AGENT), f'Agent executable {AGENT} does not exist. Did you compile the code?'
    assert os.access(AGENT, os.X_OK), f'Agent executable {AGENT} is not executable.'
    assert not AGENT.is_symlink(), 'Agent executable must not be a symlink.'
    assert os.path.isfile(SOURCE_BUILD) and os.access(SOURCE_BUILD, os.X_OK)


def test_not_copied_oracle():
    assert ORACLE.is_file(), f'Oracle {ORACLE} missing.'
    assert AGENT.read_bytes() != ORACLE.read_bytes(), 'Agent executable is a byte-for-byte copy of the oracle.'


def test_video_payload_and_concurrency_fix():
    video = Path('/app/signal.mp4')
    assert video.is_file(), f'Video {video} is missing.'
    frames = subprocess.run(
        ['ffmpeg', '-v', 'error', '-i', str(video), '-vf', 'scale=1:1,format=gray',
         '-fps_mode', 'passthrough', '-f', 'rawvideo', '-'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60, check=True
    ).stdout
    assert len(frames) == 240, f'Expected exactly 240 video frames, got {len(frames)}.'
    bits = ''.join('1' if value >= 128 else '0' for value in frames)
    payload = ''.join(f'{int(bits[i:i+8], 2):02x}' for i in range(0, 240, 8))
    assert len(payload) == 60
    expected = expected_output(payload)

    oracle_proc = run_decoder(ORACLE, payload)
    assert oracle_proc.returncode == 0
    assert oracle_proc.stdout == expected

    # Repetition makes the formerly racy vector update exercise multiple times.
    for binary in (AGENT, SOURCE_BUILD):
        for _ in range(100):
            proc = run_decoder(binary, payload)
            assert proc.returncode == 0, f'{binary} crashed on the extracted video payload.'
            assert proc.stdout == expected, f'{binary} produced incorrect output for the video payload.'


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE), f'Oracle {ORACLE} missing.'
    assert os.path.isfile(AGENT), f'Agent {AGENT} missing.'

    random.seed(42)
    hex_chars = '0123456789abcdef'

    N = 1000
    for _ in range(N):
        length = random.randint(8, 512) * 2
        fuzz_input = ''.join(random.choice(hex_chars) for _ in range(length))
        expected = expected_output(fuzz_input)

        oracle_proc = run_decoder(ORACLE, fuzz_input)
        agent_proc = run_decoder(AGENT, fuzz_input)
        source_proc = run_decoder(SOURCE_BUILD, fuzz_input)

        assert agent_proc.returncode == oracle_proc.returncode, (
            f'Return code mismatch on input {fuzz_input[:32]}...\n'
            f'Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}'
        )
        assert agent_proc.stdout == oracle_proc.stdout, (
            f'Output mismatch on input {fuzz_input[:32]}...\n'
            f'Oracle output: {oracle_proc.stdout!r}\nAgent output: {agent_proc.stdout!r}'
        )
        assert oracle_proc.returncode == 0 and oracle_proc.stdout == expected, (
            'Oracle no longer has the required valid-hex behavior.'
        )
        assert source_proc.returncode == 0 and source_proc.stdout == expected, (
            f'Independently compiled source failed on input {fuzz_input[:32]}...'
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
