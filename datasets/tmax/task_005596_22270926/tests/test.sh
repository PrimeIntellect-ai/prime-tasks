#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import contextlib
import os
import random
import struct
import subprocess
import time

SERVICE = '/home/user/stat_service.py'
STREAM = '/home/user/stream.txt'
EXPECTED_ORIGINAL = 'Processing complete. Final window average: 1.8500'


def encode_value(value):
    return base64.b64encode(struct.pack('>d', value)).decode('ascii')


def expected_score(value):
    if value.is_integer() and value > 0:
        return int(round(value * 10))
    return value


def expected_output(values):
    recent = [expected_score(value) for value in values[-10:]]
    average = sum(recent) / len(recent)
    return f'Processing complete. Final window average: {average:.4f}'


@contextlib.contextmanager
def installed_stream(values):
    with open(STREAM, 'rb') as source:
        original = source.read()
    try:
        with open(STREAM, 'w') as destination:
            for value in values:
                destination.write(encode_value(value) + '\n')
        yield
    finally:
        with open(STREAM, 'wb') as destination:
            destination.write(original)


def run_service(values, timeout=30):
    with installed_stream(values):
        return subprocess.run(
            ['python3', SERVICE], capture_output=True, text=True, timeout=timeout
        )


def run_service_with_peak_rss(values, timeout=30):
    with installed_stream(values):
        process = subprocess.Popen(
            ['python3', SERVICE], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True
        )
        peak_kb = 0
        deadline = time.monotonic() + timeout
        while process.poll() is None:
            if time.monotonic() > deadline:
                process.kill()
                process.communicate()
                raise AssertionError('The service did not finish within the timeout')
            try:
                with open(f'/proc/{process.pid}/status', 'r') as status:
                    for line in status:
                        if line.startswith('VmRSS:'):
                            peak_kb = max(peak_kb, int(line.split()[1]))
                            break
            except FileNotFoundError:
                pass
            time.sleep(0.001)
        stdout, stderr = process.communicate()
        return process.returncode, stdout, stderr, peak_kb


def test_success_log_exists():
    path = '/home/user/success.log'
    assert os.path.isfile(path), f'The file {path} does not exist. Did you redirect the output?'


def test_success_log_content():
    path = '/home/user/success.log'
    assert os.path.isfile(path), f'The file {path} does not exist.'
    with open(path, 'r') as f:
        content = f.read()
    assert EXPECTED_ORIGINAL in content, (
        f'The success.log does not contain the expected output.\n'
        f'Expected to find: {EXPECTED_ORIGINAL!r}\nActual content:\n{content}'
    )


def test_stat_service_fixed():
    assert os.path.isfile(SERVICE), f'The file {SERVICE} does not exist.'
    result = subprocess.run(['python3', SERVICE], capture_output=True, text=True)
    assert result.returncode == 0, (
        f'The script {SERVICE} still fails when executed.\nError output:\n{result.stderr}'
    )
    assert EXPECTED_ORIGINAL in result.stdout, (
        'The script output does not match the expected final average.\n'
        f'Expected to find: {EXPECTED_ORIGINAL!r}\nActual output:\n{result.stdout}'
    )


def test_service_handles_derived_streams_and_precision_case():
    rng = random.SystemRandom()
    choices = [0.5, 0.6, 0.7, 0.8, 0.9, 1.1, 1.2, 1.3, 1.4, 1.7]
    for _ in range(3):
        length = rng.randrange(140, 260)
        values = [rng.choice(choices) for _ in range(length)]
        values[rng.randrange(0, length - 10)] = rng.choice([1.0, 2.0, 3.0, 4.0])
        values[-10:] = [rng.choice(choices + [1.0, 2.0, 3.0]) for _ in range(10)]
        wanted = expected_output(values)
        result = run_service(values)
        assert result.returncode == 0, (
            f'The service failed on a generated stream.\nError output:\n{result.stderr}'
        )
        assert wanted in result.stdout, (
            'The service did not compute the generated stream correctly.\n'
            f'Expected to find: {wanted!r}\nActual output:\n{result.stdout}'
        )


def test_memory_use_does_not_grow_with_stream_history():
    short_values = [0.7] * 100000
    short_values[50] = 2.0
    long_values = [0.7] * 900000
    long_values[50] = 2.0

    short_rc, short_out, short_err, short_peak = run_service_with_peak_rss(short_values)
    long_rc, long_out, long_err, long_peak = run_service_with_peak_rss(long_values)

    assert short_rc == 0, f'Service failed on shorter stream:\n{short_err}'
    assert long_rc == 0, f'Service failed on long stream:\n{long_err}'
    assert expected_output(short_values) in short_out
    assert expected_output(long_values) in long_out
    assert short_peak > 0 and long_peak > 0, 'Could not measure service memory usage'
    assert long_peak <= short_peak + 16384, (
        'Memory usage grows with total stream history instead of remaining bounded by '
        f'the rolling window (short peak {short_peak} KiB, long peak {long_peak} KiB).'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
