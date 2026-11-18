#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.util
import os
import re
import sqlite3
import subprocess
import tempfile
from pathlib import Path

PROJECT = Path('/home/user/project')
VENV = PROJECT / 'venv'


def test_venv_exists():
    venv_path = '/home/user/project/venv'
    assert os.path.isdir(venv_path), f'Virtual environment directory {venv_path} does not exist. Did you create it?'


def test_venv_is_functional_and_requirements_installed():
    python = VENV / 'bin' / 'python'
    assert (VENV / 'pyvenv.cfg').is_file(), 'venv is not a real Python virtual environment.'
    assert python.is_file() and os.access(python, os.X_OK), 'venv Python executable is missing.'

    prefix = subprocess.run(
        [str(python), '-c', 'import sys; print(sys.prefix); print(sys.base_prefix)'],
        text=True, capture_output=True, check=True
    ).stdout.splitlines()
    assert len(prefix) >= 2 and os.path.realpath(prefix[0]) == os.path.realpath(VENV)
    assert os.path.realpath(prefix[0]) != os.path.realpath(prefix[1]), 'Python is not running in a virtual environment.'

    subprocess.run([str(python), '-m', 'pip', 'check'], check=True, text=True, capture_output=True)
    requirements = PROJECT / 'requirements.txt'
    assert requirements.is_file()
    names = []
    for line in requirements.read_text().splitlines():
        line = line.split('#', 1)[0].strip()
        if not line or line.startswith(('-', '.')) or '://' in line:
            continue
        name = re.split(r'[<>=!~;\[\s]', line, maxsplit=1)[0]
        if name:
            names.append(name)
    code = 'import importlib.metadata as m,sys; [m.distribution(x) for x in sys.argv[1:]]'
    subprocess.run([str(python), '-c', code, *names], check=True, text=True, capture_output=True)
    subprocess.run([str(VENV / 'bin' / 'pytest'), '--version'], check=True, text=True, capture_output=True)


def test_makefile_fixed():
    makefile_path = '/home/user/project/Makefile'
    assert os.path.isfile(makefile_path), f'{makefile_path} is missing.'
    with open(makefile_path, 'r') as f:
        content = f.read()
    assert '-shared' in content, "Makefile does not contain the '-shared' flag for gcc."
    assert '-fPIC' in content, "Makefile does not contain the '-fPIC' flag for gcc."


def test_library_builds_loads_and_computes():
    library = PROJECT / 'libcompute.so'
    subprocess.run(['make', 'clean'], cwd=PROJECT, text=True, capture_output=True)
    if library.exists() or library.is_symlink():
        library.unlink()
    built = subprocess.run(['make'], cwd=PROJECT, text=True, capture_output=True)
    assert built.returncode == 0, f'make failed:\n{built.stdout}\n{built.stderr}'
    assert library.is_file() and not library.is_symlink(), 'make did not create libcompute.so.'

    lib = ctypes.CDLL(str(library))
    add = lib.fast_add
    add.argtypes = [ctypes.c_int, ctypes.c_int]
    add.restype = ctypes.c_int
    cases = [(-173, 41), (0, 0), (19, 28), (4096, -2047), (-333, -777)]
    for left, right in cases:
        assert add(left, right) == left + right

    spec = importlib.util.spec_from_file_location('submitted_main', PROJECT / 'main.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for left, right in cases:
        assert module.compute_math(left, right) == left + right


def test_db_py_fixed():
    db_py_path = '/home/user/project/db.py'
    assert os.path.isfile(db_py_path), f'{db_py_path} is missing.'
    with open(db_py_path, 'r') as f:
        content = f.read()
    assert 'SELECT account_id' in content, "db.py was not updated to select 'account_id' instead of 'user_id'."
    assert 'SELECT user_id' not in content, "db.py still contains 'SELECT user_id', which is the old schema."


def test_database_migration_and_queries_work():
    spec = importlib.util.spec_from_file_location('submitted_db', PROJECT / 'db.py')
    db = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(db)

    with tempfile.TemporaryDirectory() as directory:
        path = os.path.join(directory, 'users.db')
        conn = sqlite3.connect(path)
        conn.execute('CREATE TABLE users (user_id INTEGER PRIMARY KEY, name TEXT)')
        conn.executemany('INSERT INTO users (user_id, name) VALUES (?, ?)', [(7, 'Iris'), (42, 'Noah')])
        conn.commit()
        conn.close()

        db.apply_migration(path, str(PROJECT / 'schema_migration.sql'))
        conn = sqlite3.connect(path)
        columns = [row[1] for row in conn.execute('PRAGMA table_info(users)')]
        rows = conn.execute('SELECT account_id, name FROM users ORDER BY account_id').fetchall()
        conn.close()
        assert 'account_id' in columns and 'user_id' not in columns
        assert rows == [(7, 'Iris'), (42, 'Noah')]
        assert db.get_user_id(path, 'Iris') == 7
        assert db.get_user_id(path, 'Noah') == 42
        assert db.get_user_id(path, 'Missing') is None


def test_ci_results_log():
    log_path = '/home/user/ci_results.log'
    assert os.path.isfile(log_path), f'CI results log {log_path} does not exist. Did you run the CI script?'
    with open(log_path, 'r') as f:
        content = f.read()
    assert '1 passed' in content, f"{log_path} does not indicate a successful test run ('1 passed' not found)."


def test_ci_script_really_passes_and_writes_log():
    log = Path('/home/user/ci_results.log')
    if log.exists() or log.is_symlink():
        log.unlink()
    env = os.environ.copy()
    env['VIRTUAL_ENV'] = str(VENV)
    env['PATH'] = str(VENV / 'bin') + os.pathsep + env.get('PATH', '')
    result = subprocess.run(
        [str(PROJECT / 'run_ci.sh')], cwd=PROJECT, env=env,
        text=True, capture_output=True, timeout=120
    )
    assert result.returncode == 0, f'run_ci.sh failed:\n{result.stdout}\n{result.stderr}'
    assert log.is_file(), 'run_ci.sh did not create /home/user/ci_results.log.'
    content = log.read_text()
    assert '1 passed' in content, f'CI log does not show the end-to-end test passing:\n{content}'
    assert not re.search(r'\b[1-9][0-9]* failed\b', content), f'CI log contains test failures:\n{content}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
