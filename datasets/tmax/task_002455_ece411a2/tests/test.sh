#!/bin/bash
set -e
mkdir -p /logs/verifier

ORACLE=/app/legacy_detector
ORIGINAL_MODE=$(stat -c '%a' "$ORACLE")
chmod 700 "$ORACLE"
trap 'chmod "$ORIGINAL_MODE" "$ORACLE" 2>/dev/null || true' EXIT

cat << 'RUNNER_EOF' > /tmp/detector_sandbox_runner.py
import builtins
import os
import struct
import sys
import wave

script_path = os.path.realpath(sys.argv[1])
wav_path = os.path.realpath(sys.argv[2])

with open(script_path, 'rb') as f:
    source = f.read()
code = compile(source, script_path, 'exec')

stdlib_roots = tuple(
    os.path.realpath(p) + os.sep
    for p in ('/usr/lib/python3', '/usr/local/lib/python3')
)

def audit(event, args):
    if event in {
        'subprocess.Popen', 'os.system', 'os.exec', 'os.spawn',
        'os.posix_spawn', 'os.posix_spawnp', 'os.fork', 'os.forkpty',
        'pty.spawn', 'mmap.__new__', 'ctypes.dlopen', 'ctypes.dlsym',
        'ctypes.dlsym/handle'
    } or event.startswith('socket.'):
        raise PermissionError('external execution and native-code loading are forbidden')

    if event == 'import' and args and str(args[0]).split('.')[0] in {
        'subprocess', 'multiprocessing', 'ctypes', 'cffi', 'mmap'
    }:
        raise PermissionError('unsafe module import is forbidden')

    if event == 'open' and args:
        path = args[0]
        if isinstance(path, int):
            raise PermissionError('opening file descriptors is forbidden')
        try:
            real = os.path.realpath(os.fspath(path))
        except TypeError:
            raise PermissionError('unsupported open target')

        mode = args[1] if len(args) > 1 else 'r'
        flags = args[2] if len(args) > 2 and isinstance(args[2], int) else 0
        writing = (
            (isinstance(mode, str) and any(c in mode for c in 'wax+')) or
            bool(flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND))
        )
        if writing:
            raise PermissionError('writes are forbidden')
        if real == wav_path:
            return
        if any(real.startswith(root) for root in stdlib_roots):
            return
        raise PermissionError('filesystem access outside the input WAV is forbidden')

sys.addaudithook(audit)
sys.argv = [script_path, wav_path]
globals_dict = {
    '__name__': '__main__',
    '__file__': script_path,
    '__package__': None,
    '__builtins__': builtins,
}
exec(code, globals_dict, globals_dict)
RUNNER_EOF
chmod 755 /tmp/detector_sandbox_runner.py

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import math
import os
import pwd
import random
import stat
import struct
import subprocess
import tempfile
import wave

ORACLE = '/app/legacy_detector'
DETECTOR = '/home/user/detector.py'
RUNNER = '/tmp/detector_sandbox_runner.py'
USER = pwd.getpwnam('user')


def generate_random_wav(filepath, num_samples):
    """Generate a valid 16-bit Mono PCM WAV file at 8000Hz with random noise and sine waves."""
    with wave.open(filepath, 'w') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(8000)
        freq_start = random.uniform(100, 500)
        freq_end = random.uniform(500, 2000)
        noise_level = random.uniform(0.1, 0.5)
        data = bytearray(num_samples * 2)
        for i in range(num_samples):
            t = i / 8000.0
            current_freq = freq_start + (freq_end - freq_start) * (i / num_samples)
            sine_val = math.sin(2 * math.pi * current_freq * t)
            noise_val = random.uniform(-1.0, 1.0)
            val = sine_val * (1 - noise_level) + noise_val * noise_level
            int_val = max(-32768, min(32767, int(val * 32767)))
            struct.pack_into('<h', data, i * 2, int_val)
        wav_file.writeframes(data)
    os.chmod(filepath, 0o644)


def generate_values_wav(filepath, values):
    with wave.open(filepath, 'w') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(8000)
        wav_file.writeframes(b''.join(struct.pack('<h', value) for value in values))
    os.chmod(filepath, 0o644)


def derived_output(filepath):
    with open(filepath, 'rb') as f:
        raw = f.read()[44:]
    raw = raw[:len(raw) // 2 * 2]
    samples = [item[0] for item in struct.iter_unpack('<h', raw)]
    output = []
    for start in range(0, len(samples) - 255, 128):
        energy = sum((sample >> 4) * (sample >> 4)
                     for sample in samples[start:start + 256])
        output.append(str(energy))
    return ' '.join(output)


def demote():
    os.setgroups([])
    os.setgid(USER.pw_gid)
    os.setuid(USER.pw_uid)


def run_checked(command, wav_path, label, as_user=False):
    try:
        return subprocess.run(
            command + [wav_path], capture_output=True, text=True,
            check=True, timeout=5, preexec_fn=demote if as_user else None,
            env={'PATH': '/usr/bin:/bin', 'LANG': 'C', 'LC_ALL': 'C'}
        ).stdout.strip()
    except subprocess.CalledProcessError as exc:
        raise AssertionError(f'{label} failed on {wav_path}. Stderr: {exc.stderr}')
    except subprocess.TimeoutExpired:
        raise AssertionError(f'{label} timed out on {wav_path}.')


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE), f'Oracle program missing: {ORACLE}'
    assert os.path.isfile(DETECTOR), f'Agent program missing: {DETECTOR}'
    assert stat.S_ISREG(os.lstat(DETECTOR).st_mode), 'Detector must be a regular Python source file'
    with open(DETECTOR, 'rb') as f:
        source = f.read()
    assert source, 'Detector is empty'
    ast.parse(source, DETECTOR)

    oracle_cmd = [ORACLE]
    agent_cmd = ['/usr/bin/python3', '-I', '-S', RUNNER, DETECTOR]
    random.seed(42)

    with tempfile.TemporaryDirectory() as temp_dir:
        os.chmod(temp_dir, 0o755)
        cases = []
        edge_values = [-32768, -32767, -17, -16, -15, -1, 0, 1, 15, 16, 17, 32766, 32767]
        for length in (0, 1, 255, 256, 257, 383, 384, 385, 512):
            path = os.path.join(temp_dir, f'edge_{length}.wav')
            generate_values_wav(path, [edge_values[i % len(edge_values)] for i in range(length)])
            cases.append(path)

        for i in range(100):
            num_samples = random.randint(1000, 100000)
            path = os.path.join(temp_dir, f'test_{i}.wav')
            generate_random_wav(path, num_samples)
            cases.append(path)

        for i, wav_path in enumerate(cases):
            expected = derived_output(wav_path)
            oracle_output = run_checked(oracle_cmd, wav_path, 'Oracle')
            assert oracle_output == expected, f'Internal expected-output mismatch on case {i}'

            agent_output = run_checked(agent_cmd, wav_path, 'Agent program', as_user=True)
            assert agent_output == oracle_output, (
                f'Mismatch on fuzz case {i}.\n'
                f'Oracle output starts with: {oracle_output[:100]}...\n'
                f'Agent output starts with: {agent_output[:100]}...'
            )
            assert agent_output == expected, f'Derived-output mismatch on case {i}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
