#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
from pathlib import Path

import pytest
from scapy.all import rdpcap, UDP

REPO = Path('/home/user/math_stat_repo')
SOURCE = REPO / 'stat_calc.c'
FINAL = Path('/home/user/final_result.txt')
PCAP = Path('/home/user/traffic.pcap')
FLOAT_RE = re.compile(r'[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?\n?\Z')


def parse_single_number(raw):
    text = raw.decode('ascii')
    assert FLOAT_RE.fullmatch(text), f'Expected one numeric output, got {text!r}'
    return float(text.strip())


@pytest.fixture(scope='module')
def artifacts(tmp_path_factory):
    assert SOURCE.is_file(), 'stat_calc.c is missing.'

    # Recover the coefficient from the repository history rather than trusting
    # final_result.txt.
    git_base = ['git', '-c', f'safe.directory={REPO}', '-C', str(REPO)]
    commits = subprocess.check_output(git_base + ['rev-list', '--all'], text=True).splitlines()
    historical_coeffs = []
    coeff_pattern = re.compile(r'^\s*#define\s+SECRET_COEFF\s+([-+0-9.eE]+)', re.MULTILINE)
    for commit in commits:
        shown = subprocess.run(
            git_base + ['show', f'{commit}:config.h'],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
        )
        if shown.returncode == 0:
            historical_coeffs.extend(float(x) for x in coeff_pattern.findall(shown.stdout))
    assert historical_coeffs, 'SECRET_COEFF was not recoverable from Git history.'
    assert 42.42 in historical_coeffs, 'The original SECRET_COEFF is missing from Git history.'
    coeff = 42.42

    # Independently decode the required UDP payloads and verify the supplied
    # capture still contains the task's complete data set.
    payload_values = []
    for packet in rdpcap(str(PCAP)):
        if UDP in packet and int(packet[UDP].dport) == 8080:
            payload = bytes(packet[UDP].payload).decode('ascii').strip()
            assert payload and FLOAT_RE.fullmatch(payload), f'Invalid UDP/8080 payload: {payload!r}'
            payload_values.append(float(payload))
    assert payload_values == [float(i) for i in range(1, 101)], 'The required PCAP payloads are missing or altered.'

    # Locate an actual extracted text file. It must contain exactly the UDP/8080
    # values, one numeric value per line.
    extracted = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d != '.git']
        for name in files:
            path = Path(root) / name
            if path in (FINAL, PCAP, SOURCE) or not path.is_file():
                continue
            try:
                if path.stat().st_size > 1024 * 1024:
                    continue
                text = path.read_text(encoding='ascii')
            except (OSError, UnicodeError):
                continue
            lines = text.splitlines()
            if len(lines) != len(payload_values) or any(not line.strip() for line in lines):
                continue
            try:
                values = [float(line.strip()) for line in lines]
            except ValueError:
                continue
            if values == payload_values:
                extracted.append(path)
    assert extracted, 'No text file contains the extracted UDP/8080 payloads one per line.'
    numbers_file = extracted[0]

    build = tmp_path_factory.mktemp('build')
    executable = build / 'stat_calc'
    compiled = subprocess.run(
        ['gcc', '-O2', '-Wall', '-Wextra', '-pthread', str(SOURCE), '-o', str(executable)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert compiled.returncode == 0, f'stat_calc.c did not compile:\n{compiled.stderr}'

    # Count actual pthread_create calls, ensuring the submitted program still
    # exercises its multithreaded computation rather than bypassing it.
    hook_source = build / 'pthread_hook.c'
    hook_source.write_text(r'''
#define _GNU_SOURCE
#include <pthread.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

static _Atomic int thread_count = 0;

typedef int (*real_create_t)(pthread_t *, const pthread_attr_t *,
                             void *(*)(void *), void *);

int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                   void *(*start)(void *), void *arg) {
    static real_create_t real_create = NULL;
    if (!real_create)
        real_create = (real_create_t)dlsym(RTLD_NEXT, "pthread_create");
    atomic_fetch_add(&thread_count, 1);
    return real_create(thread, attr, start, arg);
}

__attribute__((destructor)) static void write_thread_count(void) {
    const char *path = getenv("PTHREAD_COUNT_FILE");
    if (!path) return;
    FILE *f = fopen(path, "w");
    if (f) {
        fprintf(f, "%d\n", atomic_load(&thread_count));
        fclose(f);
    }
}
''')
    hook = build / 'pthread_hook.so'
    hook_build = subprocess.run(
        ['gcc', '-shared', '-fPIC', '-pthread', str(hook_source), '-ldl', '-o', str(hook)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert hook_build.returncode == 0, hook_build.stderr

    run_number = 0
    def run_program(coefficient, input_path):
        nonlocal run_number
        run_number += 1
        count_file = build / f'thread_count_{run_number}'
        env = os.environ.copy()
        env['LD_PRELOAD'] = str(hook)
        env['PTHREAD_COUNT_FILE'] = str(count_file)
        result = subprocess.run(
            [str(executable), str(coefficient), str(input_path)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=15
        )
        assert result.returncode == 0, f'Compiled program failed: {result.stderr.decode(errors="replace")}'
        assert count_file.is_file(), 'Could not confirm pthread execution.'
        assert int(count_file.read_text().strip()) >= 2, 'The program did not perform a multithreaded calculation.'
        parse_single_number(result.stdout)
        return result.stdout

    return build, coeff, payload_values, numbers_file, run_program


def test_final_result_exists():
    """Check if the final result file exists."""
    assert os.path.isfile('/home/user/final_result.txt'), 'The file /home/user/final_result.txt does not exist.'


def test_final_result_value():
    """Check if the final result file contains the correct computed value."""
    with open('/home/user/final_result.txt', 'r') as f:
        content = f.read().strip()

    assert content, 'The file /home/user/final_result.txt is empty.'
    try:
        result_val = float(content)
    except ValueError:
        pytest.fail(f"The content of /home/user/final_result.txt ('{content}') is not a valid floating-point number.")

    expected_val = 214221.0
    assert result_val == expected_val, f'Expected the final result to be {expected_val}, but got {result_val}. Check your PCAP extraction, Git forensics, and race condition fix.'


def test_program_produces_saved_result(artifacts):
    _, coeff, payload_values, numbers_file, run_program = artifacts
    final_raw = FINAL.read_bytes()
    assert parse_single_number(final_raw) == coeff * sum(payload_values)

    # Execute the freshly compiled repaired source repeatedly on the extracted
    # PCAP data. Its exact stdout must be what was saved in final_result.txt.
    outputs = [run_program(coeff, numbers_file) for _ in range(5)]
    assert all(output == final_raw for output in outputs), 'final_result.txt is not the exact deterministic output of the repaired program.'


def test_race_is_fixed_on_unseen_inputs(artifacts):
    build, _, _, _, run_program = artifacts
    import secrets
    rng = secrets.SystemRandom()

    cases = [
        (1.25, [rng.randint(1, 1000) for _ in range(257)]),
        (-2.0, [rng.randint(1, 500) for _ in range(1003)]),
    ]
    for case_index, (coefficient, values) in enumerate(cases):
        input_path = build / f'unseen_{case_index}.txt'
        input_path.write_text(''.join(f'{value}\n' for value in values), encoding='ascii')
        expected = coefficient * sum(values)
        outputs = [run_program(coefficient, input_path) for _ in range(4)]
        assert len(set(outputs)) == 1, 'The program output is nondeterministic; the race condition remains.'
        assert parse_single_number(outputs[0]) == expected, 'The repaired program computed an incorrect weighted sum on unseen input.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
