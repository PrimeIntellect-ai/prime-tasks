#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
from fractions import Fraction
from pathlib import Path

import pytest

HOME = Path('/home/user')
AGENT = HOME / 'build/smoother'
ORACLE = Path('/app/oracle_smoother')
SOURCE = HOME / 'smoother.cpp'
CMAKE = HOME / 'CMakeLists.txt'
BENCHMARK = HOME / 'benchmark.sh'
VIDEO = Path('/app/touch_recording.mp4')
TMP_BUILD = Path('/tmp/verifier_cmake_build')
DIRECT_BINARY = Path('/tmp/verifier_direct_smoother')


def run(cmd, **kwargs):
    kwargs.setdefault('text', True)
    kwargs.setdefault('capture_output', True)
    kwargs.setdefault('timeout', 30)
    return subprocess.run(cmd, **kwargs)


def video_constants():
    proc = run([
        'ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'stream=avg_frame_rate,nb_frames',
        '-of', 'json', str(VIDEO)
    ])
    assert proc.returncode == 0, proc.stderr
    streams = json.loads(proc.stdout)['streams']
    assert streams
    fps = int(Fraction(streams[0]['avg_frame_rate']))
    frames = int(streams[0]['nb_frames'])
    return fps, frames


def expected_output(input_data, fps, max_frames):
    values = []
    tokens = input_data.split()
    for i in range(0, len(tokens) - 1, 2):
        if len(values) >= max_frames:
            break
        values.append((float(tokens[i]), float(tokens[i + 1])))

    alpha = 2.0 / (fps + 1.0)
    output = []
    sx = sy = None
    for x, y in values:
        if sx is None:
            sx, sy = x, y
        else:
            sx = alpha * x + (1.0 - alpha) * sx
            sy = alpha * y + (1.0 - alpha) * sy
        output.append(f'{sx:.4f} {sy:.4f}\n')
    return ''.join(output)


def assert_derived_behavior(binary):
    fps, frames = video_constants()
    rng = random.Random(91723)
    cases = [
        '',
        '1.25 -2.5\n',
        '\n'.join(f'{rng.uniform(-9000, 9000):.6f} {rng.uniform(-9000, 9000):.6f}'
                  for _ in range(frames + 37)) + '\n',
    ]
    for input_data in cases:
        proc = run([str(binary)], input=input_data)
        assert proc.returncode == 0, proc.stderr
        assert proc.stdout == expected_output(input_data, fps, frames)


def test_required_files_and_agent_binary_exist():
    for path in (CMAKE, SOURCE, BENCHMARK):
        assert path.exists(), f'Required file missing: {path}'
        assert path.is_file() and not path.is_symlink(), f'{path} must be a regular file'

    assert AGENT.exists(), f'Agent binary not found at {AGENT}'
    assert AGENT.is_file(), f'Path {AGENT} is not a file'
    assert os.access(AGENT, os.X_OK), f'Agent binary at {AGENT} is not executable'
    assert ORACLE.exists(), f'Oracle binary missing at {ORACLE}'
    assert hashlib.sha256(AGENT.read_bytes()).digest() != hashlib.sha256(ORACLE.read_bytes()).digest(), \
        'Agent binary is a byte-identical copy of the oracle'


def test_cmake_configures_and_compiles_submitted_source():
    text = CMAKE.read_text(errors='replace')
    lowered = text.lower()
    assert 'execute_process' in lowered, 'CMakeLists.txt must use execute_process during configuration'
    assert 'ffprobe' in lowered, 'CMake execute_process must invoke ffprobe (or an equivalent probe)'
    assert 'avg_frame_rate' in lowered, 'CMake must extract avg_frame_rate'
    assert 'nb_frames' in lowered, 'CMake must extract total frame count'
    assert 'video_fps' in lowered and 'max_frames' in lowered, 'Required compile definitions are missing'
    assert 'target_compile_definitions' in lowered or 'add_compile_definitions' in lowered, \
        'VIDEO_FPS and MAX_FRAMES must be passed as compile definitions'
    assert 'smoother.cpp' in lowered, 'The smoother target must compile smoother.cpp'

    shutil.rmtree(TMP_BUILD, ignore_errors=True)
    configure = run([
        'cmake', '--trace-expand', '-S', str(HOME), '-B', str(TMP_BUILD),
        '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON'
    ], timeout=60)
    assert configure.returncode == 0, configure.stdout + configure.stderr
    trace = configure.stdout + configure.stderr
    traced_exec = [line.lower() for line in trace.splitlines() if 'execute_process(' in line.lower()]
    assert any('ffprobe' in line for line in traced_exec), \
        'Configuration trace does not show execute_process invoking ffprobe'

    build = run(['cmake', '--build', str(TMP_BUILD), '--config', 'Release', '-j2'], timeout=60)
    assert build.returncode == 0, build.stdout + build.stderr

    commands_path = TMP_BUILD / 'compile_commands.json'
    assert commands_path.is_file(), 'CMake did not emit compilation commands'
    commands = json.loads(commands_path.read_text())
    source_commands = [entry for entry in commands if Path(entry.get('file', '')).resolve() == SOURCE.resolve()]
    assert source_commands, 'The CMake target did not compile /home/user/smoother.cpp'
    command_text = ' '.join(entry.get('command', '') + ' ' + ' '.join(entry.get('arguments', []))
                            for entry in source_commands)
    fps, frames = video_constants()
    assert re.search(rf'(?:-D|/D)VIDEO_FPS(?:=|\\s+){fps}(?:\\D|$)', command_text), command_text
    assert re.search(rf'(?:-D|/D)MAX_FRAMES(?:=|\\s+){frames}(?:\\D|$)', command_text), command_text

    rebuilt = TMP_BUILD / 'smoother'
    assert rebuilt.is_file() and os.access(rebuilt, os.X_OK), 'CMake did not build the smoother executable'
    assert hashlib.sha256(rebuilt.read_bytes()).digest() != hashlib.sha256(ORACLE.read_bytes()).digest(), \
        'CMake build produced a byte-identical oracle copy'
    assert_derived_behavior(rebuilt)


def test_cpp_source_itself_implements_smoother():
    source_text = SOURCE.read_text(errors='replace')
    forbidden = re.compile(
        r'oracle_smoother|\\b(?:system|popen|fork|vfork|exec[lvpe]*|posix_spawn)\\s*\\(',
        re.IGNORECASE,
    )
    assert not forbidden.search(source_text), 'smoother.cpp delegates work to an external program'

    fps, frames = video_constants()
    compile_proc = run([
        'g++', '-std=c++11', '-O2', f'-DVIDEO_FPS={fps}', f'-DMAX_FRAMES={frames}',
        str(SOURCE), '-o', str(DIRECT_BINARY)
    ], timeout=60)
    assert compile_proc.returncode == 0, compile_proc.stdout + compile_proc.stderr
    assert_derived_behavior(DIRECT_BINARY)


def test_fuzz_equivalence():
    oracle_path = '/app/oracle_smoother'
    agent_path = '/home/user/build/smoother'

    assert os.path.exists(oracle_path), f'Oracle binary missing at {oracle_path}'
    assert os.path.exists(agent_path), f'Agent binary missing at {agent_path}'

    random.seed(42)
    num_tests = 100
    for i in range(num_tests):
        num_lines = random.randint(1, 200)
        input_lines = []
        for _ in range(num_lines):
            x = random.uniform(-5000.0, 5000.0)
            y = random.uniform(-5000.0, 5000.0)
            input_lines.append(f'{x:.6f} {y:.6f}')
        input_data = '\n'.join(input_lines) + '\n'

        oracle_proc = run([oracle_path], input=input_data)
        assert oracle_proc.returncode == 0, f'Oracle failed on iteration {i}:\n{oracle_proc.stderr}'
        agent_proc = run([agent_path], input=input_data)
        assert agent_proc.returncode == 0, f'Agent failed on iteration {i}:\n{agent_proc.stderr}'
        if oracle_proc.stdout != agent_proc.stdout:
            pytest.fail(
                f'Mismatch on iteration {i} with {num_lines} lines.\n'
                f'Input preview: {input_data[:100]}...\n'
                f'Oracle output preview: {oracle_proc.stdout[:100]}...\n'
                f'Agent output preview: {agent_proc.stdout[:100]}...'
            )


def test_benchmark_orchestration_script():
    text = BENCHMARK.read_text(errors='replace').lower()
    assert '/app/oracle_smoother' in text, 'benchmark.sh must run the oracle'
    assert '/home/user/build/smoother' in text or 'build/smoother' in text, \
        'benchmark.sh must run the built smoother'
    assert '100' in text, 'benchmark.sh must generate 100 coordinate pairs'
    assert re.search(r'random|rand\\s*\\(|shuf', text), 'benchmark.sh must generate random coordinates'
    assert re.search(r'cmp|diff|sha(?:1|256)sum|md5sum', text), \
        'benchmark.sh must assert bit-exact output equality'
    proc = run(['bash', str(BENCHMARK)], cwd=str(HOME), timeout=60)
    assert proc.returncode == 0, proc.stdout + proc.stderr
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
