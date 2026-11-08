#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import stat
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import pytest

RELEASE = Path('/home/user/release')
BINARY = RELEASE / 'logparser'
SOURCE = RELEASE / 'logparser.c'
E2E = RELEASE / 'e2e_test.go'
RESULTS = Path('/home/user/test_results.json')
LOGS = Path('/home/user/logs')


def run_parser(path):
    proc = subprocess.run(
        [str(BINARY), str(path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert proc.returncode == 0, f'logparser failed for {path}: {proc.stderr}'
    assert re.fullmatch(r'[0-9]+\n?', proc.stdout), (
        f'logparser output must contain only an integer, got {proc.stdout!r}'
    )
    return int(proc.stdout.strip())


def expected_for_logs():
    expected = {}
    for path in sorted(LOGS.iterdir()):
        if path.is_file() and path.suffix == '.txt':
            with path.open('r', errors='replace') as f:
                expected[path.name] = sum(1 for line in f if 'ERROR' in line)
    return expected


def load_results():
    assert RESULTS.is_file(), f'The results file {RESULTS} does not exist.'
    try:
        with RESULTS.open() as f:
            value = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'The file {RESULTS} does not contain valid JSON: {exc}')
    assert isinstance(value, dict), 'The results JSON must be a single object.'
    assert all(type(v) is int for v in value.values()), 'All result values must be integers.'
    return value


def run_e2e_source():
    # Go refuses to run files whose names end in _test.go, so execute an exact copy
    # under a runnable filename while retaining the required submitted path.
    with tempfile.TemporaryDirectory(prefix='e2e-run-') as td:
        runnable = Path(td) / 'main.go'
        shutil.copyfile(E2E, runnable)
        proc = subprocess.run(
            ['go', 'run', str(runnable)],
            cwd=RELEASE,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
    assert proc.returncode == 0, f'Go orchestrator failed:\n{proc.stdout}\n{proc.stderr}'


def test_00_makefile_builds_binary():
    proc = subprocess.run(
        ['make', '-B'], cwd=RELEASE, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
    )
    assert proc.returncode == 0, f'make failed:\n{proc.stdout}'
    assert BINARY.is_file(), f'Binary {BINARY} does not exist. Did make produce it?'
    assert os.access(BINARY, os.X_OK), f'Binary {BINARY} is not executable.'


def test_01_logparser_linked_with_math_lib():
    assert BINARY.is_file(), f'Binary {BINARY} does not exist.'
    try:
        output = subprocess.check_output(['ldd', str(BINARY)], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as exc:
        pytest.fail(f'Failed to run ldd on {BINARY}: {exc.output}')
    assert 'libm.' in output, 'The logparser binary is not linked with the math library (-lm).'


def test_02_c_source_bug_fixed():
    assert SOURCE.is_file(), f'File {SOURCE} is missing.'
    content = SOURCE.read_text()
    assert '/tmp/scratch.tmp' not in content, (
        "The hardcoded temporary file path '/tmp/scratch.tmp' is still present in logparser.c."
    )


def test_03_logparser_behavior_and_concurrency():
    with tempfile.TemporaryDirectory(prefix='parser-inputs-') as td:
        root = Path(td)

        special = root / 'substring-cases.txt'
        special.write_text(
            'INFO only\n'
            'prefixERRORsuffix\n'
            'error lowercase\n'
            'ERROR ERROR on one line\n'
            'NO_ERROR still contains the exact substring\n'
        )
        assert run_parser(special) == 3

        jobs = []
        rng = random.Random(827341)
        for index in range(20):
            path = root / f'dynamic_{index}_{rng.randrange(10**9)}.txt'
            wanted = 700 + index * 113
            total = 20000
            positions = set(rng.sample(range(total), wanted))
            with path.open('w') as f:
                for line_no in range(total):
                    if line_no in positions:
                        f.write(f'{line_no}: token-{rng.randrange(10**9)} ERROR detail\n')
                    else:
                        f.write(f'{line_no}: token-{rng.randrange(10**9)} normal\n')
            jobs.append((path, wanted))

        # Launch all parser processes together. Different expected counts and sizable
        # inputs expose implementations that still share one temporary file.
        with ThreadPoolExecutor(max_workers=len(jobs)) as pool:
            futures = [pool.submit(run_parser, path) for path, _ in jobs]
            actual = [future.result() for future in futures]
        assert actual == [wanted for _, wanted in jobs]


def test_04_e2e_source_uses_goroutines_and_channels():
    assert E2E.is_file(), f'Required Go source {E2E} is missing.'

    checker = r'''
package main
import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)
func main() {
    path := os.Getenv("TARGET_GO_SOURCE")
    file, err := parser.ParseFile(token.NewFileSet(), path, nil, 0)
    if err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(2) }
    hasGo, hasChan, hasSend := false, false, false
    ast.Inspect(file, func(n ast.Node) bool {
        switch n.(type) {
        case *ast.GoStmt: hasGo = true
        case *ast.ChanType: hasChan = true
        case *ast.SendStmt: hasSend = true
        }
        return true
    })
    if !(hasGo && hasChan && hasSend) { os.Exit(1) }
}
'''
    with tempfile.TemporaryDirectory(prefix='ast-check-') as td:
        checker_path = Path(td) / 'checker.go'
        checker_path.write_text(checker)
        env = os.environ.copy()
        env['TARGET_GO_SOURCE'] = str(E2E)
        proc = subprocess.run(
            ['go', 'run', str(checker_path)], env=env,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
    assert proc.returncode == 0, (
        'e2e_test.go must contain actual Go goroutine and channel send constructs '
        f'(and must parse as Go): {proc.stderr}'
    )


def test_05_e2e_executes_parser_concurrently_and_writes_derived_results():
    original_expected = {
        'app_01.txt': 1,
        'app_02.txt': 3,
        'app_03.txt': 0,
        'app_04.txt': 2,
        'app_05.txt': 4,
    }
    assert expected_for_logs() == original_expected, 'The supplied input logs are missing or changed.'

    nonce = random.SystemRandom().randrange(10**12)
    extra = LOGS / f'verifier_dynamic_{nonce}.txt'
    extra.write_text('ERROR first\nINFO middle\ncontainsERRORinside\nerror lowercase\nERROR last\n')

    real_binary = RELEASE / f'.logparser.verifier-real-{nonce}'
    call_log = Path(f'/tmp/logparser-calls-{nonce}')
    active = Path(f'/tmp/logparser-active-{nonce}')
    active.mkdir()

    os.replace(BINARY, real_binary)
    wrapper = f'''#!/bin/sh
set -eu
touch "{active}/$$"
count=$(find "{active}" -maxdepth 1 -type f | wc -l)
printf '%s %s\\n' "$count" "$1" >> "{call_log}"
sleep 0.4
rm -f "{active}/$$"
exec "{real_binary}" "$1"
'''
    BINARY.write_text(wrapper)
    BINARY.chmod(BINARY.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

    try:
        expected_with_extra = expected_for_logs()
        if RESULTS.exists():
            RESULTS.unlink()
        run_e2e_source()
        assert load_results() == expected_with_extra, (
            'The Go orchestrator did not derive results for every discovered .txt file.'
        )

        assert call_log.is_file(), 'The Go orchestrator never executed the logparser binary.'
        records = [line.split(' ', 1) for line in call_log.read_text().splitlines() if line]
        called = [Path(path).name for _, path in records]
        assert sorted(called) == sorted(expected_with_extra), (
            'The orchestrator must execute logparser once for every discovered .txt file.'
        )
        assert max(int(count) for count, _ in records) >= 2, (
            'logparser invocations did not overlap; files must be processed simultaneously.'
        )
    finally:
        if BINARY.exists():
            BINARY.unlink()
        if real_binary.exists():
            os.replace(real_binary, BINARY)
        extra.unlink(missing_ok=True)
        shutil.rmtree(active, ignore_errors=True)
        call_log.unlink(missing_ok=True)

    # Execute once more on the original supplied logs and retain the required final file.
    if RESULTS.exists():
        RESULTS.unlink()
    run_e2e_source()
    results = load_results()

    assert isinstance(results, dict), f'The JSON in {RESULTS} should be an object (dictionary).'
    for key, expected_val in original_expected.items():
        assert key in results, f"Key '{key}' is missing from the JSON results."
        assert results[key] == expected_val, (
            f'Expected {expected_val} errors for {key}, but got {results[key]}.'
        )
    for key in results:
        assert key in original_expected, f"Unexpected key '{key}' found in the JSON results."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
