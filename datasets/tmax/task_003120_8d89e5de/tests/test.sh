#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile
import time
import uuid

import pytest

PROBE_DIR = '/app/fast-udp-probe-1.0'
PROBE_SOURCE = os.path.join(PROBE_DIR, 'probe.c')
PROBE_BINARY = os.path.join(PROBE_DIR, 'fast-udp-probe')
ENDPOINT_SCRIPT = '/app/router-sim/start_endpoint.sh'
RESULTS_FILE = '/home/user/results.txt'
MONITOR_SCRIPT = '/home/user/monitor.sh'


def parse_exact_throughput(output):
    match = re.fullmatch(r'Throughput:\s*([0-9]+(?:\.[0-9]+)?)\s*pps\n?', output)
    assert match is not None, f'Unexpected probe output: {output!r}'
    return float(match.group(1))


def run_probe(path):
    completed = subprocess.run(
        [path, '127.0.0.1', '8080'],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f'Probe exited with {completed.returncode}; stderr was {completed.stderr!r}'
    )
    return completed.stdout, parse_exact_throughput(completed.stdout)


def start_endpoint():
    # Stop the endpoint recorded by an earlier agent run, if any, then execute the
    # provided service script as required by the task.
    try:
        with open('/tmp/router_sim.pid') as f:
            old_pid = int(f.read().strip())
        os.kill(old_pid, 15)
        time.sleep(0.1)
    except (OSError, ValueError):
        pass

    completed = subprocess.run(
        [ENDPOINT_SCRIPT], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert completed.returncode == 0, (
        f'Endpoint startup failed: {completed.stderr!r}'
    )
    time.sleep(0.2)


def test_throughput_metric():
    results_file = RESULTS_FILE
    assert os.path.isfile(results_file), f"File {results_file} does not exist."

    with open(results_file, 'r') as f:
        content = f.read()

    match = re.search(r'Throughput:\s*([\d\.]+)\s*pps', content)
    assert match is not None, f"Could not find 'Throughput: <number> pps' in {results_file}. Content was: {content}"

    pps = float(match.group(1))
    assert pps >= 5000.0, f"Throughput {pps} pps is less than the required threshold of 5000.0 pps."

    # results.txt must consist of the exact stdout format produced by the probe,
    # rather than containing an unrelated or embellished self-reported value.
    exact_result_pps = parse_exact_throughput(content)

    assert os.path.isfile(PROBE_SOURCE), f'{PROBE_SOURCE} does not exist.'
    assert os.path.isfile(PROBE_BINARY), f'{PROBE_BINARY} does not exist.'
    assert os.access(PROBE_BINARY, os.X_OK), f'{PROBE_BINARY} is not executable.'
    with open(PROBE_BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'The submitted probe is not a compiled ELF executable.'

    start_endpoint()

    # Execute the submitted Makefile-built artifact.
    _, installed_pps = run_probe(PROBE_BINARY)
    assert installed_pps >= 5000.0, (
        f'Fresh execution of the submitted probe achieved only {installed_pps} pps.'
    )

    # Independently compile and execute probe.c so a wrapper or fabricated binary
    # cannot substitute for fixing the vendored C source.
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, 'fast-udp-probe')
        compiled = subprocess.run(
            ['gcc', '-o', rebuilt, PROBE_SOURCE],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compiled.returncode == 0, f'probe.c did not compile: {compiled.stderr}'
        _, rebuilt_pps = run_probe(rebuilt)

    assert rebuilt_pps >= 5000.0, (
        f'Fresh execution of independently compiled probe.c achieved only {rebuilt_pps} pps.'
    )

    # A genuine saved run should be of the same order of magnitude as fresh runs.
    lower = min(installed_pps, rebuilt_pps) / 10.0
    upper = max(installed_pps, rebuilt_pps) * 10.0
    assert lower <= exact_result_pps <= upper, (
        f'The saved result {exact_result_pps} pps is inconsistent with fresh probe '
        f'runs ({installed_pps} and {rebuilt_pps} pps).'
    )


def test_monitor_script_exists_and_executable():
    script_file = MONITOR_SCRIPT
    assert os.path.isfile(script_file), f"File {script_file} does not exist."
    assert os.access(script_file, os.X_OK), f"File {script_file} is not executable."


def test_monitor_script_logic():
    script_file = MONITOR_SCRIPT
    assert os.path.isfile(script_file), f"File {script_file} does not exist."

    with open(script_file, 'r') as f:
        content = f.read()

    # Preserve the original source-level assertions.
    assert 'probe.log' in content, f"{script_file} does not reference 'probe.log'."
    assert '1000' in content, f"{script_file} does not reference the 1000 byte limit."
    assert 'probe.log.1' in content, f"{script_file} does not reference 'probe.log.1'."
    assert 'probe.log.2' in content, f"{script_file} does not reference 'probe.log.2'."

    paths = [
        '/home/user/probe.log',
        '/home/user/probe.log.1',
        '/home/user/probe.log.2',
        '/home/user/probe.log.3',
    ]

    with tempfile.TemporaryDirectory() as td:
        backups = {}
        for path in paths:
            if os.path.lexists(path):
                saved = os.path.join(td, str(len(backups)))
                shutil.move(path, saved)
                backups[path] = saved

        saved_probe = os.path.join(td, 'real-probe')
        shutil.move(PROBE_BINARY, saved_probe)
        marker = os.path.join(td, 'invocation')
        expected_pps = 5000.0 + (int.from_bytes(os.urandom(4), 'big') % 500000) / 100.0
        expected_output = f'Throughput: {expected_pps:.2f} pps\n'

        # Replace the canonical probe temporarily with an unpredictable test double.
        # This proves monitor.sh actually invokes the probe and appends its stdout.
        with open(PROBE_BINARY, 'w') as f:
            f.write('#!/bin/bash\n')
            f.write('printf "%s\\n" "$@" > ' + repr(marker) + '\n')
            f.write("printf '%s' " + repr(expected_output) + '\n')
        os.chmod(PROBE_BINARY, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                              stat.S_IRGRP | stat.S_IXGRP |
                              stat.S_IROTH | stat.S_IXOTH)

        old_log = os.urandom(1001)
        old_backup1 = os.urandom(317)
        old_backup2 = os.urandom(211)

        try:
            with open('/home/user/probe.log', 'wb') as f:
                f.write(old_log)
            with open('/home/user/probe.log.1', 'wb') as f:
                f.write(old_backup1)
            with open('/home/user/probe.log.2', 'wb') as f:
                f.write(old_backup2)

            completed = subprocess.run(
                [MONITOR_SCRIPT],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert completed.returncode == 0, (
                f'monitor.sh failed with {completed.returncode}: {completed.stderr!r}'
            )

            assert os.path.isfile(marker), 'monitor.sh did not invoke the probe executable.'
            with open(marker) as f:
                args = f.read().splitlines()
            assert args == ['127.0.0.1', '8080'], (
                f'monitor.sh invoked the probe with incorrect arguments: {args!r}'
            )

            with open('/home/user/probe.log', 'rb') as f:
                assert f.read() == expected_output.encode(), (
                    'monitor.sh did not append the exact probe stdout to a new probe.log.'
                )
            with open('/home/user/probe.log.1', 'rb') as f:
                assert f.read() == old_log, 'probe.log was not rotated to probe.log.1.'
            with open('/home/user/probe.log.2', 'rb') as f:
                assert f.read() == old_backup1, 'probe.log.1 was not rotated to probe.log.2.'
            assert not os.path.exists('/home/user/probe.log.3'), (
                'monitor.sh kept more than the required two backups.'
            )
        finally:
            if os.path.lexists(PROBE_BINARY):
                os.remove(PROBE_BINARY)
            shutil.move(saved_probe, PROBE_BINARY)
            for path in paths:
                if os.path.lexists(path):
                    if os.path.isdir(path) and not os.path.islink(path):
                        shutil.rmtree(path)
                    else:
                        os.remove(path)
            for path, saved in backups.items():
                shutil.move(saved, path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
