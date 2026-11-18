#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import tempfile

import pytest

WORKSPACE = '/home/user/workspace'


def test_pipeline_script_exists():
    script_path = os.path.join(WORKSPACE, 'pipeline.sh')
    assert os.path.isfile(script_path), f"Missing shell script: {script_path}"


def test_c_program_exists():
    c_path = os.path.join(WORKSPACE, 'calc_drift.c')
    assert os.path.isfile(c_path), f"Missing C program: {c_path}"


def test_executable_exists():
    exe_path = os.path.join(WORKSPACE, 'calc_drift')
    assert os.path.isfile(exe_path), f"Missing compiled executable: {exe_path}"
    assert os.access(exe_path, os.X_OK), f"Executable {exe_path} is not executable"


def test_normalized_server1_txt():
    txt_path = os.path.join(WORKSPACE, 'server1.txt')
    assert os.path.isfile(txt_path), f"Missing normalized file: {txt_path}"

    with open(txt_path, 'r') as f:
        lines = f.readlines()

    expected_lines = [
        "max_connections=100\n",
        "mode=dev\n",
        "port=8080\n"
    ]
    assert lines == expected_lines, f"Content of {txt_path} does not match expected sorted format."


def test_normalized_server2_txt():
    txt_path = os.path.join(WORKSPACE, 'server2.txt')
    assert os.path.isfile(txt_path), f"Missing normalized file: {txt_path}"

    with open(txt_path, 'r') as f:
        lines = f.readlines()

    expected_lines = [
        "max_connections=150\n",
        "mode=prod\n",
        "port=8081\n"
    ]
    assert lines == expected_lines, f"Content of {txt_path} does not match expected sorted format."


def test_drift_report_csv():
    csv_path = os.path.join(WORKSPACE, 'drift_report.csv')
    assert os.path.isfile(csv_path), f"Missing CSV report: {csv_path}"

    with open(csv_path, 'r') as f:
        content = [line.strip() for line in f.readlines() if line.strip()]

    expected_entries = ['server1,4', 'server2,3']

    for entry in expected_entries:
        assert entry in content, f"Expected entry '{entry}' not found in {csv_path}"


def test_pipeline_log():
    log_path = os.path.join(WORKSPACE, 'pipeline.log')
    assert os.path.isfile(log_path), f"Missing log file: {log_path}"

    with open(log_path, 'r') as f:
        content = f.read()

    expected_logs = [
        "[START] Processing server1",
        "[END] Processed server1",
        "[START] Processing server2",
        "[END] Processed server2"
    ]

    for log in expected_logs:
        assert log in content, f"Expected log line '{log}' not found in {log_path}"


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def test_pipeline_and_c_program_on_fresh_inputs():
    configs = os.path.join(WORKSPACE, 'configs')
    baseline_path = os.path.join(configs, 'baseline.txt')
    json_path = os.path.join(configs, 'server1.json')
    ini_path = os.path.join(configs, 'server2.ini')
    server1_path = os.path.join(WORKSPACE, 'server1.txt')
    server2_path = os.path.join(WORKSPACE, 'server2.txt')
    report_path = os.path.join(WORKSPACE, 'drift_report.csv')
    log_path = os.path.join(WORKSPACE, 'pipeline.log')
    exe_path = os.path.join(WORKSPACE, 'calc_drift')
    source_path = os.path.join(WORKSPACE, 'calc_drift.c')

    managed = [baseline_path, json_path, ini_path, server1_path, server2_path,
               report_path, log_path, exe_path]
    backups = {}
    for path in managed:
        if os.path.exists(path):
            with open(path, 'rb') as f:
                backups[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
        else:
            backups[path] = None

    token = secrets.token_hex(8)
    json_port = secrets.randbelow(7000) + 1000
    json_max = secrets.randbelow(800) + 200
    ini_port = secrets.randbelow(7000) + 1000
    ini_max = secrets.randbelow(800) + 200
    base_port = secrets.randbelow(7000) + 1000
    base_max = secrets.randbelow(800) + 200

    baseline = f"port={base_port}\nmode=base-{token}\nmax_connections={base_max}\n"
    sorted_baseline = f"max_connections={base_max}\nmode=base-{token}\nport={base_port}\n"
    expected_server1 = f"max_connections={json_max}\nmode=json-{token}\nport={json_port}\n"
    expected_server2 = f"max_connections={ini_max}\nmode=ini-{token}\nport={ini_port}\n"

    try:
        with open(baseline_path, 'w') as f:
            f.write(baseline)
        with open(json_path, 'w') as f:
            json.dump({
                'port': json_port,
                'max_connections': json_max,
                'mode': f'json-{token}'
            }, f, indent=2)
            f.write('\n')
        with open(ini_path, 'w') as f:
            f.write(f"[network]\nport={ini_port}\n\n[limits]\nmax_connections={ini_max}\n\n[app]\nmode=ini-{token}\n")

        for path in (server1_path, server2_path, report_path, log_path, exe_path):
            if os.path.exists(path):
                os.remove(path)

        result = subprocess.run(
            ['bash', os.path.join(WORKSPACE, 'pipeline.sh')],
            cwd=WORKSPACE,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, f"pipeline.sh failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"

        assert os.path.isfile(exe_path), 'pipeline.sh did not create calc_drift'
        assert os.access(exe_path, os.X_OK), 'pipeline.sh did not create an executable calc_drift'
        with open(exe_path, 'rb') as f:
            assert f.read(4) == b'\x7fELF', 'calc_drift is not a compiled native executable'

        with open(server1_path, 'r') as f:
            assert f.read() == expected_server1
        with open(server2_path, 'r') as f:
            assert f.read() == expected_server2

        expected_report = [
            f"server1,{levenshtein(sorted_baseline, expected_server1)}",
            f"server2,{levenshtein(sorted_baseline, expected_server2)}",
        ]
        with open(report_path, 'r') as f:
            report_lines = [line.rstrip('\n') for line in f if line.strip()]
        assert report_lines == expected_report, 'pipeline produced an incorrect drift report'

        with open(log_path, 'r') as f:
            log_lines = [line.rstrip('\n') for line in f]
        assert log_lines == [
            '[START] Processing server1',
            '[END] Processed server1',
            '[START] Processing server2',
            '[END] Processed server2',
        ], 'pipeline did not emit the required processing log'

        direct_a = f"alpha={token}\nbeta=123\n"
        direct_b = f"alpha={token[::-1]}\nbeta=987\ngamma=yes\n"
        target = f"probe-{token}"
        with tempfile.TemporaryDirectory() as td:
            a_path = os.path.join(td, 'a.txt')
            b_path = os.path.join(td, 'b.txt')
            rebuilt_exe = os.path.join(td, 'calc_drift_from_source')
            with open(a_path, 'w') as f:
                f.write(direct_a)
            with open(b_path, 'w') as f:
                f.write(direct_b)

            compile_result = subprocess.run(
                ['gcc', source_path, '-o', rebuilt_exe],
                cwd=WORKSPACE,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert compile_result.returncode == 0, f"calc_drift.c does not compile:\n{compile_result.stderr}"

            before = list(report_lines)
            run_result = subprocess.run(
                [rebuilt_exe, a_path, b_path, target],
                cwd=WORKSPACE,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=15,
            )
            assert run_result.returncode == 0, f"compiled calc_drift.c failed: {run_result.stderr}"
            with open(report_path, 'r') as f:
                after = [line.rstrip('\n') for line in f if line.strip()]
            assert after == before + [f"{target},{levenshtein(direct_a, direct_b)}"], \
                'calc_drift.c did not append the correct Levenshtein distance'
    finally:
        for path, backup in backups.items():
            if os.path.exists(path):
                os.remove(path)
            if backup is not None:
                data, mode = backup
                with open(path, 'wb') as f:
                    f.write(data)
                os.chmod(path, mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
