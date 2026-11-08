#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import struct
import subprocess
import tempfile
import time

import numpy as np

HOME = '/home/user'
SOURCE = f'{HOME}/mlops_eval.c'
BINARY = f'{HOME}/mlops_eval'
TRUTH = f'{HOME}/artifacts/truth.bin'
INFERENCE = f'{HOME}/artifacts/inference.bin'
LOG = f'{HOME}/metrics.log'
NUM_FLOATS = 2_500_000


def calculate_metrics(truth_file, inference_file):
    truth = np.fromfile(truth_file, dtype='<f4')
    inference = np.fromfile(inference_file, dtype='<f4')
    assert truth.size == NUM_FLOATS
    assert inference.size == NUM_FLOATS
    differences = np.abs(truth.astype(np.float64) - inference.astype(np.float64))
    return float(np.sum(differences, dtype=np.float64) / NUM_FLOATS), float(np.max(differences))


def read_records(path):
    assert os.path.exists(path), f'{path} does not exist.'
    size = os.path.getsize(path)
    assert size > 0, f'{path} is empty.'
    assert size % 24 == 0, f'{path} size ({size}) is not a multiple of 24 bytes.'
    with open(path, 'rb') as handle:
        data = handle.read()
    return [struct.unpack('<QffQ', data[i:i + 24]) for i in range(0, len(data), 24)]


def assert_record(record, expected_mae, expected_max, earliest, latest):
    timestamp, mae, max_ae, time_us = record
    assert abs(mae - expected_mae) < 1e-4, f'MAE mismatch: expected {expected_mae}, got {mae}'
    assert abs(max_ae - expected_max) < 1e-4, f'MaxAE mismatch: expected {expected_max}, got {max_ae}'
    assert time_us > 0, f'Compute time should be greater than 0, got {time_us}'
    assert timestamp > 0, f'Timestamp should be greater than 0, got {timestamp}'
    assert earliest - 1 <= timestamp <= latest + 1, f'Timestamp {timestamp} is not current'


def test_submission_and_original_execution():
    assert os.path.exists(SOURCE), f'Source file {SOURCE} does not exist.'
    with open(SOURCE, 'r', errors='replace') as handle:
        code = handle.read()
    assert 'mmap' in code, "The string 'mmap' was not found in the source code."

    assert os.path.isfile(BINARY), f'Compiled executable {BINARY} does not exist.'
    assert os.stat(BINARY).st_mode & stat.S_IXUSR, f'{BINARY} is not executable.'

    assert os.path.exists(TRUTH), f'{TRUTH} missing.'
    assert os.path.exists(INFERENCE), f'{INFERENCE} missing.'
    assert os.path.getsize(TRUTH) == NUM_FLOATS * 4
    assert os.path.getsize(INFERENCE) == NUM_FLOATS * 4

    expected_mae, expected_max = calculate_metrics(TRUTH, INFERENCE)
    original_records = read_records(LOG)
    timestamp, mae, max_ae, time_us = original_records[-1]
    assert abs(mae - expected_mae) < 1e-4, f'MAE mismatch. Expected approx {expected_mae}, got {mae}'
    assert abs(max_ae - expected_max) < 1e-4, f'MaxAE mismatch. Expected approx {expected_max}, got {max_ae}'
    assert time_us > 0, f'Compute time should be greater than 0, got {time_us}'
    assert timestamp > 0, f'Timestamp should be greater than 0, got {timestamp}'


def test_compiled_source_on_unseen_data_and_runtime_mmap():
    with tempfile.TemporaryDirectory(prefix='mlops_verify_') as directory:
        executable = os.path.join(directory, 'mlops_eval')
        subprocess.run(
            ['gcc', '-O3', '-Wall', SOURCE, '-o', executable, '-lm'],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )

        symbols = subprocess.run(
            ['nm', '-D', executable], check=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True
        ).stdout
        assert re.search(r'\b(mmap|mmap64)(@|$)', symbols, re.MULTILINE), 'Compiled program does not reference mmap.'
        assert not re.search(r'\bfread(@|$)', symbols, re.MULTILINE), 'Compiled program must not use fread.'

        assert subprocess.run([executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode != 0
        assert subprocess.run([executable, 'a', 'b', 'c', 'd'], stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode != 0

        seed = int.from_bytes(os.urandom(16), 'little')
        rng = np.random.default_rng(seed)
        truth = rng.uniform(-50.0, 50.0, NUM_FLOATS).astype('<f4')
        noise = rng.normal(0.0, 1.25, NUM_FLOATS).astype('<f4')
        inference = (truth + noise).astype('<f4')
        truth_path = os.path.join(directory, 'truth.bin')
        inference_path = os.path.join(directory, 'inference.bin')
        log_path = os.path.join(directory, 'metrics.bin')
        truth.tofile(truth_path)
        inference.tofile(inference_path)
        expected_mae, expected_max = calculate_metrics(truth_path, inference_path)

        shim_source = os.path.join(directory, 'mmap_trace.c')
        shim_library = os.path.join(directory, 'mmap_trace.so')
        trace_path = os.path.join(directory, 'mmap.trace')
        with open(shim_source, 'w') as handle:
            handle.write(r'''
#define _GNU_SOURCE
#include <sys/mman.h>
#include <sys/types.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
struct event { uint64_t length; int prot; int flags; };
void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
    if (!real_mmap) real_mmap = dlsym(RTLD_NEXT, "mmap");
    void *result = real_mmap(addr, length, prot, flags, fd, offset);
    const char *path = getenv("MLOPS_MMAP_TRACE");
    if (path && fd >= 0) {
        int out = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (out >= 0) {
            struct event e = { (uint64_t)length, prot, flags };
            write(out, &e, sizeof(e));
            close(out);
        }
    }
    return result;
}
''')
        subprocess.run(
            ['gcc', '-shared', '-fPIC', shim_source, '-o', shim_library, '-ldl'],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )

        env = os.environ.copy()
        env['LD_PRELOAD'] = shim_library
        env['MLOPS_MMAP_TRACE'] = trace_path

        for expected_count in (1, 2):
            before = int(time.time())
            result = subprocess.run(
                [executable, inference_path, truth_path, log_path], env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                timeout=30
            )
            after = int(time.time())
            assert result.returncode == 0, result.stderr
            match = re.fullmatch(r'MAE: (-?\d+\.\d{6}), MaxAE: (-?\d+\.\d{6})\n?', result.stdout)
            assert match, f'Unexpected console output: {result.stdout!r}'
            assert abs(float(match.group(1)) - expected_mae) < 2e-6
            assert abs(float(match.group(2)) - expected_max) < 2e-6

            records = read_records(log_path)
            assert len(records) == expected_count, 'Program did not append exactly one 24-byte record.'
            assert_record(records[-1], expected_mae, expected_max, before, after)

        assert os.path.exists(trace_path), 'No runtime mmap call was observed.'
        event_size = struct.calcsize('@Qii')
        with open(trace_path, 'rb') as handle:
            trace = handle.read()
        assert len(trace) % event_size == 0
        events = [struct.unpack('@Qii', trace[i:i + event_size]) for i in range(0, len(trace), event_size)]
        input_maps = [event for event in events if event[0] == NUM_FLOATS * 4 and (event[1] & 1)]
        assert len(input_maps) >= 4, 'Both input files must be mmaped read-only on every execution.'
        assert all((prot & 2) == 0 for _, prot, _ in input_maps), 'Input mappings must not be writable.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
