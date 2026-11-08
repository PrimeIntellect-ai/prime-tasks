#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import pathlib
import secrets
import sqlite3
import subprocess
import sysconfig
import tempfile

PROJECT = pathlib.Path('/home/user/project')
SOURCE = PROJECT / 'fib_ext' / 'fib_ext.c'
VENV_PYTHON = pathlib.Path('/home/user/venv/bin/python')
DB = PROJECT / 'data.db'
FINAL = PROJECT / 'final_sum.txt'


def get_fib_sum(n):
    if n <= 0:
        return 0
    fibs = [0] * n
    if n > 1:
        fibs[1] = 1
    for i in range(2, n):
        fibs[i] = fibs[i - 1] + fibs[i - 2]
    return sum(fibs)


def fresh_database(rows):
    if DB.exists():
        DB.unlink()
    if FINAL.exists():
        FINAL.unlink()
    conn = sqlite3.connect(DB)
    conn.execute('CREATE TABLE computations (id INTEGER PRIMARY KEY, n_value INTEGER)')
    conn.executemany('INSERT INTO computations (id, n_value) VALUES (?, ?)', rows)
    conn.commit()
    conn.close()


def read_calls(path):
    if not path.exists():
        return []
    return [int(line) for line in path.read_text().splitlines() if line.strip()]


def run_migration(mode, call_log):
    monitor = pathlib.Path('/tmp/fib_monitor')
    monitor.mkdir(exist_ok=True)
    (monitor / 'sitecustomize.py').write_text(r'''import os
import fib_ext
_real_get_fibs = fib_ext.get_fibs

def _tracked(n):
    with open(os.environ['FIB_CALL_LOG'], 'a') as f:
        f.write(str(n) + '\n')
    if os.environ.get('FIB_MONITOR_MODE') == 'probe':
        return [n + 7] * n
    return _real_get_fibs(n)

fib_ext.get_fibs = _tracked
''')
    if call_log.exists():
        call_log.unlink()
    env = os.environ.copy()
    env['PYTHONPATH'] = str(monitor)
    env['FIB_CALL_LOG'] = str(call_log)
    env['FIB_MONITOR_MODE'] = mode
    result = subprocess.run(
        [str(VENV_PYTHON), str(PROJECT / 'migrate.py')],
        cwd=str(PROJECT), env=env, text=True, capture_output=True, timeout=120
    )
    assert result.returncode == 0, 'migrate.py failed:\n' + result.stdout + result.stderr


def test_fib_ext_c_fixed_and_installed():
    filepath = str(SOURCE)
    assert os.path.isfile(filepath), f'File {filepath} does not exist'
    content = SOURCE.read_text()

    # Preserve the original source assertions.
    assert 'i <= n' not in content, "Bug 1 (out-of-bounds write 'i <= n') was not fixed in fib_ext.c"
    assert 'free(' in content, "Bug 2 (memory leak) was not fixed: missing 'free(...)' in fib_ext.c"

    assert VENV_PYTHON.is_file(), 'The required virtual environment was not created'
    inspect_code = r'''import fib_ext, json, os, sys
assert callable(fib_ext.get_fibs)
print(json.dumps({'prefix': sys.prefix, 'file': os.path.realpath(fib_ext.__file__)}))
'''
    result = subprocess.run(
        [str(VENV_PYTHON), '-c', inspect_code], cwd='/tmp', text=True,
        capture_output=True, timeout=30, env={**os.environ, 'PYTHONPATH': ''}
    )
    assert result.returncode == 0, 'Could not import fib_ext from the venv:\n' + result.stderr
    info = json.loads(result.stdout.strip().splitlines()[-1])
    assert pathlib.Path(info['prefix']).resolve() == pathlib.Path('/home/user/venv').resolve()
    module_path = pathlib.Path(info['file'])
    assert str(module_path).startswith('/home/user/venv/'), f'fib_ext was not installed in the venv: {module_path}'
    assert any(str(module_path).endswith(s) for s in sysconfig.get_config_var('EXT_SUFFIX'),) if False else module_path.suffix == '.so'

    behavior = r'''import fib_ext

def expected(n):
    a, b, out = 0, 1, []
    for _ in range(n):
        out.append(a & ((1 << 64) - 1))
        a, b = b, (a + b) & ((1 << 64) - 1)
    return out

assert fib_ext.get_fibs(0) is None
for n in (1, 2, 3, 10, 50, 90, 1000):
    assert fib_ext.get_fibs(n) == expected(n), n
'''
    result = subprocess.run([str(VENV_PYTHON), '-c', behavior], cwd='/tmp', text=True, capture_output=True, timeout=60)
    assert result.returncode == 0, 'Installed extension is functionally incorrect:\n' + result.stderr


def test_submitted_c_has_no_out_of_bounds_write():
    # Rebuild the submitted source with AddressSanitizer and exercise the allocation boundary.
    with tempfile.TemporaryDirectory() as td:
        td = pathlib.Path(td)
        setup = td / 'setup.py'
        setup.write_text("""from setuptools import setup, Extension
setup(name='asan_fib_ext', ext_modules=[Extension('fib_ext', sources=[%r], extra_compile_args=['-fsanitize=address','-fno-omit-frame-pointer'], extra_link_args=['-fsanitize=address'])])
""" % str(SOURCE))
        build = subprocess.run([str(VENV_PYTHON), 'setup.py', 'build_ext'], cwd=td, text=True, capture_output=True, timeout=120)
        assert build.returncode == 0, 'Submitted C source could not be rebuilt:\n' + build.stdout + build.stderr
        candidates = list((td / 'build').rglob('fib_ext*.so'))
        assert candidates, 'AddressSanitizer build did not produce a C extension'
        libdir = candidates[0].parent
        libasan = subprocess.run(['gcc', '-print-file-name=libasan.so'], text=True, capture_output=True, check=True).stdout.strip()
        env = os.environ.copy()
        env['PYTHONPATH'] = str(libdir)
        env['LD_PRELOAD'] = libasan
        env['ASAN_OPTIONS'] = 'detect_leaks=0:abort_on_error=1'
        code = "import fib_ext; [fib_ext.get_fibs(n) for n in (1,2,3,31,1000,100000)]"
        checked = subprocess.run([str(VENV_PYTHON), '-c', code], cwd='/tmp', env=env, text=True, capture_output=True, timeout=90)
        assert checked.returncode == 0, 'Memory-safety instrumentation detected an invalid access:\n' + checked.stdout + checked.stderr


def test_installed_extension_releases_allocated_arrays():
    # The original leak grows resident memory by about 48 MB in this loop.
    code = r'''import fib_ext, gc

def rss():
    with open('/proc/self/status') as f:
        for line in f:
            if line.startswith('VmRSS:'):
                return int(line.split()[1])

for _ in range(2):
    x = fib_ext.get_fibs(500000)
    del x
    gc.collect()
before = rss()
for _ in range(12):
    x = fib_ext.get_fibs(500000)
    del x
    gc.collect()
after = rss()
assert after - before < 24576, (before, after)
'''
    result = subprocess.run([str(VENV_PYTHON), '-c', code], cwd='/tmp', text=True, capture_output=True, timeout=120)
    assert result.returncode == 0, 'The installed extension appears to leak its C arrays:\n' + result.stdout + result.stderr


def test_migrate_executes_and_uses_extension_results():
    migrate = PROJECT / 'migrate.py'
    assert migrate.is_file(), f'File {migrate} does not exist'

    # First use distinctive monitored return values. This prevents a Python-only
    # Fibonacci implementation from passing merely by calling fib_ext incidentally.
    probe_rows = [(1, 6), (2, 13), (3, 21)]
    fresh_database(probe_rows)
    probe_log = pathlib.Path('/tmp/fib_probe_calls.log')
    run_migration('probe', probe_log)
    assert collections.Counter(read_calls(probe_log)) == collections.Counter(n for _, n in probe_rows)
    conn = sqlite3.connect(DB)
    values = conn.execute('SELECT id, n_value, fib_sum FROM computations ORDER BY id').fetchall()
    conn.close()
    expected_probe = [(i, n, n * (n + 7)) for i, n in probe_rows]
    assert values == expected_probe, 'migrate.py did not derive fib_sum from fib_ext.get_fibs results'
    assert FINAL.read_text().strip() == str(sum(n * (n + 7) for _, n in probe_rows))

    # Now run the actual installed C extension on fresh, unpredictable input.
    extra = sorted({secrets.randbelow(35) + 3 for _ in range(4)})
    final_ns = [5, 10, 50, 90] + extra
    final_rows = [(i + 1, n) for i, n in enumerate(final_ns)]
    fresh_database(final_rows)
    real_log = pathlib.Path('/tmp/fib_real_calls.log')
    run_migration('real', real_log)
    assert collections.Counter(read_calls(real_log)) == collections.Counter(final_ns), 'migrate.py did not call the installed extension once for every row'


def test_database_schema_and_values():
    db_path = str(DB)
    assert os.path.isfile(db_path), f'Database {db_path} does not exist'
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('PRAGMA table_info(computations)')
    columns = [row[1] for row in c.fetchall()]
    assert 'fib_sum' in columns, "Column 'fib_sum' was not added to computations table"
    c.execute('SELECT n_value, fib_sum FROM computations ORDER BY id')
    rows = c.fetchall()
    for n_value, fib_sum in rows:
        expected_sum = get_fib_sum(n_value)
        assert fib_sum == expected_sum, f'Incorrect fib_sum for n_value={n_value}. Expected {expected_sum}, got {fib_sum}'
    conn.close()


def test_final_sum_txt():
    txt_path = str(FINAL)
    assert os.path.isfile(txt_path), f'File {txt_path} does not exist'
    db_path = str(DB)
    assert os.path.isfile(db_path), f'Database {db_path} does not exist'
    conn = sqlite3.connect(db_path)
    rows = conn.execute('SELECT n_value FROM computations').fetchall()
    conn.close()
    expected_total = sum(get_fib_sum(row[0]) for row in rows)
    content = FINAL.read_text().strip()
    assert content.isdigit(), f'Content of {txt_path} is not an integer: {content}'
    assert int(content) == expected_total, f'Incorrect total sum in {txt_path}. Expected {expected_total}, got {content}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
