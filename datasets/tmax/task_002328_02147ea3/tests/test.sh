#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import sqlite3
import stat
import string
import subprocess
from pathlib import Path

import pytest

PROJECT = Path('/home/user/project')
DB = Path('/home/user/logs.db')


def run(cmd, **kwargs):
    kwargs.setdefault('cwd', PROJECT)
    kwargs.setdefault('capture_output', True)
    kwargs.setdefault('text', True)
    kwargs.setdefault('timeout', 30)
    return subprocess.run(cmd, **kwargs)


def reset_database():
    DB.unlink(missing_ok=True)
    conn = sqlite3.connect(DB)
    conn.execute('CREATE TABLE access_logs (id INTEGER PRIMARY KEY, payload TEXT)')
    conn.execute("INSERT INTO access_logs (payload) VALUES ('<script>alert(1)</script>')")
    conn.commit()
    conn.close()


def test_sanitizer_c_fixed():
    c_file_path = '/home/user/project/sanitizer.c'
    assert os.path.isfile(c_file_path), f'File {c_file_path} does not exist.'
    with open(c_file_path, 'r') as f:
        content = f.read()
    assert 'stdio.h' in content, 'sanitizer.c does not include stdio.h'
    assert 'string.h' in content, 'sanitizer.c does not include string.h'

    makefile = PROJECT / 'Makefile'
    assert makefile.is_file(), 'Makefile does not exist.'
    dry_run = run(['make', '-n', 'build'])
    assert dry_run.returncode == 0, dry_run.stderr
    assert '-Werror' in dry_run.stdout, 'The build target no longer uses -Werror.'

    cleaned = run(['make', 'clean'])
    assert cleaned.returncode == 0, cleaned.stdout + cleaned.stderr
    built = run(['make', 'build'])
    assert built.returncode == 0, built.stdout + built.stderr


def test_sanitizer_executable():
    exe_path = '/home/user/project/sanitizer'
    assert os.path.isfile(exe_path), f'Executable {exe_path} does not exist. Did the build succeed?'
    assert os.access(exe_path, os.X_OK), f'{exe_path} is not executable.'
    with open(exe_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'sanitizer is not a compiled executable.'

    result = subprocess.run([exe_path, 'a<b>c'], capture_output=True, text=True)
    assert result.stdout.strip() == 'a_b_c', "sanitizer did not correctly replace '<' and '>'"

    rng = random.SystemRandom()
    cases = [
        '<', '>', '<>', '<<>>', 'plain', 'a b<c>d',
        'x<y>z<q>r', '123>456<789', 'no_angles_here'
    ]
    alphabet = string.ascii_letters + string.digits + ' _-./<>'
    for _ in range(40):
        value = ''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 80)))
        if rng.randrange(2):
            pos = rng.randrange(len(value) + 1)
            value = value[:pos] + rng.choice('<>') + value[pos:]
        cases.append(value)

    for value in cases:
        expected = value.replace('<', '_').replace('>', '_') + '\n'
        result = subprocess.run([exe_path, value], capture_output=True, text=True, timeout=5)
        assert result.returncode == 0, f'sanitizer failed for input {value!r}'
        assert result.stdout == expected, f'incorrect sanitizer output for input {value!r}'


def test_migrate_script_actually_migrates_fresh_database():
    script = PROJECT / 'migrate.sh'
    assert script.is_file(), 'migrate.sh does not exist.'
    assert os.access(script, os.X_OK), 'migrate.sh is not executable.'

    reset_database()
    first = run([str(script)])
    assert first.returncode == 0, first.stdout + first.stderr
    second = run([str(script)])
    assert second.returncode == 0, 'migrate.sh is not safe to run again: ' + second.stdout + second.stderr

    conn = sqlite3.connect(DB)
    columns = conn.execute('PRAGMA table_info(access_logs)').fetchall()
    rows = conn.execute('SELECT payload, threat_level FROM access_logs').fetchall()
    conn.close()
    matching = [col for col in columns if col[1] == 'threat_level']
    assert len(matching) == 1, 'migrate.sh did not add exactly one threat_level column.'
    assert matching[0][2].upper() == 'INTEGER'
    assert str(matching[0][4]) == '0'
    assert rows == [('<script>alert(1)</script>', 0)], 'migration did not preserve existing data/defaults.'


def test_fuzz_script_generates_and_checks_required_inputs(tmp_path):
    fuzz = PROJECT / 'fuzz.sh'
    sanitizer = PROJECT / 'sanitizer'
    results = PROJECT / 'test_results.txt'
    assert fuzz.is_file(), 'fuzz.sh does not exist.'
    assert os.access(fuzz, os.X_OK), 'fuzz.sh is not executable.'

    original = sanitizer.read_bytes()
    original_mode = sanitizer.stat().st_mode
    probe = '''#!/bin/bash
printf '%s\\0' "$1" >> "$FUZZ_LOG"
if [ "${FUZZ_BAD:-0}" = 1 ]; then
    printf '%s\\n' "$1"
else
    printf '%s' "$1" | tr '<>' '__'
    printf '\\n'
fi
'''
    try:
        sanitizer.write_text(probe)
        sanitizer.chmod(0o755)

        results.unlink(missing_ok=True)
        bad_log = tmp_path / 'bad.log'
        env = os.environ.copy()
        env.update(FUZZ_LOG=str(bad_log), FUZZ_BAD='1')
        failed = run([str(fuzz)], env=env)
        assert failed.returncode != 0, 'fuzz.sh accepted sanitizer output containing an angle bracket.'
        assert results.is_file(), 'fuzz.sh did not write test_results.txt on failure.'
        assert 'FUZZING_FAILED' in results.read_text().splitlines()

        results.unlink(missing_ok=True)
        good_log = tmp_path / 'good.log'
        env = os.environ.copy()
        env.update(FUZZ_LOG=str(good_log), FUZZ_BAD='0')
        passed = run([str(fuzz)], env=env)
        assert passed.returncode == 0, passed.stdout + passed.stderr
        assert results.is_file(), 'fuzz.sh did not write test_results.txt on success.'
        assert 'FUZZING_PASSED' in results.read_text().splitlines()

        calls = good_log.read_bytes().split(b'\0')
        if calls and calls[-1] == b'':
            calls.pop()
        assert len(calls) == 50, f'fuzz.sh invoked sanitizer {len(calls)} times instead of 50.'
        pattern = re.compile(rb'^[A-Za-z0-9]*[<>][A-Za-z0-9]*$')
        for value in calls:
            assert 11 <= len(value) <= 21, 'fuzzer did not use a 10-20 character base plus one injection.'
            assert pattern.fullmatch(value), f'invalid fuzz input: {value!r}'
            assert value.count(b'<') + value.count(b'>') == 1, 'each fuzz input must have one injected bracket.'
    finally:
        sanitizer.write_bytes(original)
        os.chmod(sanitizer, stat.S_IMODE(original_mode))


def test_ci_pipeline_orchestration_and_real_run(tmp_path):
    pipeline = PROJECT / 'ci_pipeline.sh'
    assert pipeline.is_file(), 'ci_pipeline.sh does not exist.'
    assert os.access(pipeline, os.X_OK), 'ci_pipeline.sh is not executable.'

    paths = [PROJECT / 'Makefile', PROJECT / 'migrate.sh', PROJECT / 'fuzz.sh']
    backups = {p: (p.read_bytes(), p.stat().st_mode) for p in paths}
    log = tmp_path / 'ci.log'
    fake_makefile = '''clean:
\t@echo clean >> "$(CI_LOG)"
\t@if [ "$$CI_FAIL" = clean ]; then exit 17; fi
build:
\t@echo build >> "$(CI_LOG)"
\t@if [ "$$CI_FAIL" = build ]; then exit 18; fi
'''
    fake_migrate = '''#!/bin/bash
echo migrate >> "$CI_LOG"
[ "${CI_FAIL:-}" != migrate ]
'''
    fake_fuzz = '''#!/bin/bash
echo fuzz >> "$CI_LOG"
[ "${CI_FAIL:-}" != fuzz ]
'''
    success = PROJECT / 'ci_success'

    try:
        (PROJECT / 'Makefile').write_text(fake_makefile)
        (PROJECT / 'migrate.sh').write_text(fake_migrate)
        (PROJECT / 'fuzz.sh').write_text(fake_fuzz)
        (PROJECT / 'migrate.sh').chmod(0o755)
        (PROJECT / 'fuzz.sh').chmod(0o755)

        expected = {
            'clean': ['clean'],
            'build': ['clean', 'build'],
            'migrate': ['clean', 'build', 'migrate'],
            'fuzz': ['clean', 'build', 'migrate', 'fuzz'],
        }
        for failure, wanted in expected.items():
            success.unlink(missing_ok=True)
            log.unlink(missing_ok=True)
            env = os.environ.copy()
            env.update(CI_LOG=str(log), CI_FAIL=failure)
            result = run([str(pipeline)], env=env)
            assert result.returncode != 0, f'pipeline ignored failure in {failure}.'
            got = log.read_text().splitlines() if log.exists() else []
            assert got == wanted, f'pipeline did not stop immediately after {failure}: {got}'
            assert not success.exists(), 'pipeline created ci_success despite a failed command.'

        success.unlink(missing_ok=True)
        log.unlink(missing_ok=True)
        env = os.environ.copy()
        env.update(CI_LOG=str(log), CI_FAIL='')
        result = run([str(pipeline)], env=env)
        assert result.returncode == 0, result.stdout + result.stderr
        assert log.read_text().splitlines() == ['clean', 'build', 'migrate', 'fuzz']
        assert success.is_file(), 'successful pipeline did not create ci_success.'
        assert success.stat().st_size == 0, 'ci_success must be empty.'
    finally:
        for path, (data, mode) in backups.items():
            path.write_bytes(data)
            os.chmod(path, stat.S_IMODE(mode))

    reset_database()
    success.unlink(missing_ok=True)
    (PROJECT / 'test_results.txt').unlink(missing_ok=True)
    result = run([str(pipeline)], timeout=60)
    assert result.returncode == 0, 'real CI pipeline failed: ' + result.stdout + result.stderr
    assert success.is_file() and success.stat().st_size == 0


def test_database_schema_migrated():
    db_path = '/home/user/logs.db'
    assert os.path.isfile(db_path), f'Database {db_path} does not exist.'
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute('PRAGMA table_info(access_logs);')
    columns = cursor.fetchall()
    column_names = [col[1] for col in columns]
    assert 'threat_level' in column_names, "Column 'threat_level' was not added to access_logs."
    for col in columns:
        if col[1] == 'threat_level':
            assert col[2].upper() == 'INTEGER', 'threat_level column is not of type INTEGER.'
            assert str(col[4]) == '0', 'threat_level column does not have DEFAULT 0.'
    conn.close()


def test_scripts_are_executable():
    scripts = [
        '/home/user/project/migrate.sh',
        '/home/user/project/fuzz.sh',
        '/home/user/project/ci_pipeline.sh'
    ]
    for script in scripts:
        assert os.path.isfile(script), f'Script {script} does not exist.'
        st = os.stat(script)
        assert bool(st.st_mode & stat.S_IXUSR), f'Script {script} is not executable.'


def test_ci_success_file_exists():
    success_file = '/home/user/project/ci_success'
    assert os.path.isfile(success_file), f'CI success file {success_file} was not created. Did the pipeline complete successfully?'


def test_fuzzing_results():
    results_file = '/home/user/project/test_results.txt'
    assert os.path.isfile(results_file), f'Test results file {results_file} does not exist.'
    with open(results_file, 'r') as f:
        content = f.read()
    assert 'FUZZING_PASSED' in content, f"{results_file} does not contain 'FUZZING_PASSED'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
