#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

PIPELINE = Path('/home/user/pipeline')
SCRIPT = PIPELINE / 'process.sh'
PATCH = PIPELINE / 'build.patch'
BATS = Path('/home/user/local/bin/bats')
BATS_SRC = Path('/home/user/bats-src')


def filtered(lines):
    result = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        key = line.split('=', 1)[0]
        if not key.startswith('DEBUG_') and not key.startswith('TEST_'):
            result.append(line)
    return sorted(result)


def expected_diff(old_lines, new_lines, workdir):
    old_filtered = Path(workdir) / 'expected-old.txt'
    new_filtered = Path(workdir) / 'expected-new.txt'
    old_filtered.write_text(''.join(x + '\n' for x in filtered(old_lines)))
    new_filtered.write_text(''.join(x + '\n' for x in filtered(new_lines)))
    proc = subprocess.run(
        ['diff', '-u', str(old_filtered), str(new_filtered)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={**os.environ, 'LC_ALL': 'C'},
    )
    assert proc.returncode in (0, 1), proc.stderr
    return proc.stdout


def assert_same_unified_diff(actual, expected):
    if not expected:
        assert actual == '', 'build.patch should be empty when filtered manifests are identical.'
        return

    actual_lines = actual.splitlines(keepends=True)
    expected_lines = expected.splitlines(keepends=True)
    assert len(actual_lines) >= 3, 'build.patch is not a complete unified diff.'
    assert actual_lines[0].startswith('--- '), 'Unified diff is missing its old-file header.'
    assert actual_lines[1].startswith('+++ '), 'Unified diff is missing its new-file header.'
    assert actual_lines[2:] == expected_lines[2:], 'Unified diff hunks do not match the filtered, sorted manifests.'


def run_and_check(old_lines, new_lines):
    with tempfile.TemporaryDirectory(prefix='manifest verifier ') as td:
        td_path = Path(td)
        old_path = td_path / 'old manifest.txt'
        new_path = td_path / 'new manifest.txt'
        # Deliberately omit the final newline to exercise the complete input.
        old_path.write_text('\n'.join(old_lines))
        new_path.write_text('\n'.join(new_lines))
        expected = expected_diff(old_lines, new_lines, td)

        if PATCH.exists():
            PATCH.unlink()
        proc = subprocess.run(
            [str(SCRIPT), str(old_path), str(new_path)],
            cwd=td,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
            env={**os.environ, 'LC_ALL': 'C'},
        )
        assert proc.returncode in (0, 1), f'process.sh failed with status {proc.returncode}: {proc.stderr}'
        assert PATCH.is_file(), 'process.sh did not create /home/user/pipeline/build.patch.'
        assert_same_unified_diff(PATCH.read_text(), expected)


def test_build_patch_exists_and_content():
    patch_path = '/home/user/pipeline/build.patch'
    assert os.path.isfile(patch_path), f'The file {patch_path} is missing. Did you run process.sh?'
    content = Path(patch_path).read_text()
    assert '-SIZE=1048576' in content, 'build.patch is missing the expected old SIZE line.'
    assert '+SIZE=1050000' in content, 'build.patch is missing the expected new SIZE line.'


def test_build_patch_no_debug_test():
    patch_path = '/home/user/pipeline/build.patch'
    assert os.path.isfile(patch_path), f'The file {patch_path} is missing.'
    content = Path(patch_path).read_text()
    assert 'DEBUG_' not in content, "build.patch contains 'DEBUG_' lines, which should have been filtered out."
    assert 'TEST_' not in content, "build.patch contains 'TEST_' lines, which should have been filtered out."


def test_process_sh_no_python():
    assert SCRIPT.is_file(), f'The file {SCRIPT} is missing.'
    content = SCRIPT.read_text()
    assert 'python' not in content.lower(), 'process.sh still contains a call to Python. The logic should be translated to Bash.'


def test_process_sh_uses_local():
    assert SCRIPT.is_file(), f'The file {SCRIPT} is missing.'
    content = SCRIPT.read_text()
    assert 'local ' in content, "process.sh does not use 'local' variables. You need to fix the variable scope bug."
    assert os.access(SCRIPT, os.X_OK), 'process.sh is not executable.'


def test_bats_installed():
    assert BATS.is_file(), f'BATS executable not found at {BATS}.'
    assert os.access(BATS, os.X_OK), f'BATS executable at {BATS} is not executable.'


def test_bats_source_and_real_execution():
    assert BATS_SRC.is_dir(), '/home/user/bats-src is missing.'
    assert (BATS_SRC / '.git').exists(), '/home/user/bats-src is not a Git clone.'
    assert (BATS_SRC / 'install.sh').is_file(), 'The bats-core install.sh is missing.'
    assert (BATS_SRC / 'bin/bats').is_file(), 'The bats-core source executable is missing.'
    remote = subprocess.run(
        ['git', '-C', str(BATS_SRC), 'config', '--get', 'remote.origin.url'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert remote.returncode == 0
    assert 'github.com/bats-core/bats-core' in remote.stdout.lower(), 'bats-src was not cloned from bats-core.'
    fsck = subprocess.run(['git', '-C', str(BATS_SRC), 'fsck', '--no-dangling'], text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert fsck.returncode == 0, f'bats-src is not a valid Git repository: {fsck.stderr}'

    version = subprocess.run([str(BATS), '--version'], text=True, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, timeout=10)
    assert version.returncode == 0
    assert re.search(r'\bBats\s+\d+', version.stdout, re.I), 'Installed executable does not report a Bats version.'

    with tempfile.TemporaryDirectory() as td:
        probe = Path(td) / 'probe.bats'
        probe.write_text("#!/usr/bin/env bats\n@test \"run captures output and status\" {\n  run bash -c 'printf bats-verifier'\n  [ \"$status\" -eq 0 ]\n  [ \"$output\" = bats-verifier ]\n}\n")
        result = subprocess.run([str(BATS), str(probe)], text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=20)
        assert result.returncode == 0, f'Installed Bats failed a real BATS test: {result.stdout}\n{result.stderr}'
        assert re.search(r'^ok\s+1\b', result.stdout, re.M), 'Installed Bats did not produce a passing TAP result.'


def test_bats_test_results():
    log_path = Path('/home/user/test_results.log')
    assert log_path.is_file(), f'Test results log not found at {log_path}.'
    content = log_path.read_text()
    assert 'ok' in content.lower(), "The BATS test results do not indicate a successful test run ('ok' not found)."
    assert re.search(r'^1\.\.\d+\s*$', content, re.M), 'test_results.log is not BATS TAP output.'
    assert re.search(r'^ok\s+\d+\b', content, re.M), 'test_results.log has no passing BATS test record.'


def test_submitted_bats_suite_runs():
    suite = PIPELINE / 'test.bats'
    assert suite.is_file(), '/home/user/pipeline/test.bats is missing.'
    assert re.search(r'(?m)^\s*@test\b', suite.read_text()), 'test.bats does not contain a BATS test case.'
    result = subprocess.run([str(BATS), str(suite)], cwd=str(PIPELINE), text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert result.returncode == 0, f'Submitted BATS suite failed: {result.stdout}\n{result.stderr}'
    assert re.search(r'^ok\s+\d+\b', result.stdout, re.M), 'Submitted suite produced no passing BATS test.'


def test_process_behavior_on_derived_inputs():
    token = secrets.token_hex(8).upper()
    old = [
        f'VERSION_{token}=1.0',
        '',
        f'DEBUG_{token}=secret-old',
        f'ZETA_{token}=last',
        f'  ALPHA_{token}=old value  ',
        f'TEST_{token}=ignore',
        f'SAME_{token}=kept',
    ]
    new = [
        f'TEST_{token}=different-ignore',
        f'VERSION_{token}=2.0',
        f'NEW_{token}=active',
        f'DEBUG_{token}=secret-new',
        f'SAME_{token}=kept',
        f'ALPHA_{token}=new value',
        f'ZETA_{token}=last',
    ]
    run_and_check(old, new)

    # Filtering must also make manifests containing only ignored differences equal.
    run_and_check(
        [f'KEEP_{token}=yes', f'DEBUG_{token}=one', '', f'TEST_{token}=one'],
        [f'TEST_{token}=two', f'KEEP_{token}=yes', f'DEBUG_{token}=two'],
    )


def test_regenerate_required_final_patch_exactly():
    old_path = PIPELINE / 'data/old_build.txt'
    new_path = PIPELINE / 'data/new_build.txt'
    old_lines = old_path.read_text().splitlines()
    new_lines = new_path.read_text().splitlines()
    run_and_check(old_lines, new_lines)
    content = PATCH.read_text()
    assert '-SIZE=1048576' in content
    assert '+SIZE=1050000' in content
    assert 'DEBUG_' not in content
    assert 'TEST_' not in content
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
