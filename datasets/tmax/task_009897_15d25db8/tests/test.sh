#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

BASE = Path('/home/user/pipeline')
EXE = BASE / 'build' / 'standardize'
RAW_CONTENT = (
    '10.0,2.0,1.0\n'
    '20.0,4.0,1.0\n'
    '30.0,6.0,1.0\n'
    '40.0,8.0,1.0\n'
)
EXPECTED_CLEANED = (
    '-1.341641,-1.341641,0.000000\n'
    '-0.447214,-0.447214,0.000000\n'
    '0.447214,0.447214,0.000000\n'
    '1.341641,1.341641,0.000000'
)


def run_checked(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True,
                          timeout=kwargs.pop('timeout', 60), **kwargs)


def csv_input(matrix):
    return ''.join(','.join(str(x) for x in row) + '\n' for row in matrix)


def expected_matrix(matrix):
    rows = len(matrix)
    cols = len(matrix[0])
    means = [sum(row[c] for row in matrix) / rows for c in range(cols)]
    sigmas = [math.sqrt(sum((row[c] - means[c]) ** 2 for row in matrix) / rows)
              for c in range(cols)]
    return [[0.0 if sigmas[c] == 0 else (row[c] - means[c]) / sigmas[c]
             for c in range(cols)] for row in matrix]


def assert_program_output(program, matrix):
    result = run_checked([str(program)], input=csv_input(matrix))
    lines = result.stdout.splitlines()
    assert len(lines) == len(matrix), 'Wrong number of output rows.'
    expected = expected_matrix(matrix)
    for r, line in enumerate(lines):
        fields = line.split(',')
        assert len(fields) == len(matrix[0]), 'Wrong number of output columns.'
        for c, field in enumerate(fields):
            assert re.fullmatch(r'-?\d+\.\d{6}', field), \
                f'Value is not printed with exactly six decimals: {field!r}'
            actual = float(field)
            assert abs(actual - expected[r][c]) <= 0.0000011, \
                f'Incorrect standardized value at row {r}, column {c}.'


def test_directories_exist():
    for name in ['src', 'data', 'build', 'results']:
        assert (BASE / name).is_dir(), f'Directory {BASE / name} does not exist.'


def test_source_files_exist():
    assert (BASE / 'src' / 'standardize.c').is_file(), 'C source code standardize.c is missing.'
    assert (BASE / 'src' / 'Makefile').is_file(), 'Makefile is missing.'


def test_scripts_exist():
    for name in ['run_pipeline.sh', 'benchmark.sh']:
        path = BASE / name
        assert path.is_file(), f'{name} is missing.'
        assert os.access(path, os.X_OK), f'{name} is not executable.'
        first_line = path.read_text(errors='replace').splitlines()[0]
        assert 'bash' in first_line, f'{name} is not a bash script.'


def test_raw_dataset_exact():
    path = BASE / 'data' / 'raw_matrix.csv'
    assert path.is_file(), 'raw_matrix.csv is missing.'
    assert path.read_text() == RAW_CONTENT, 'raw_matrix.csv does not have the required contents.'


def test_source_compiles_and_implements_standardization():
    source = BASE / 'src' / 'standardize.c'
    with tempfile.TemporaryDirectory() as td:
        independently_built = Path(td) / 'standardize'
        run_checked(['gcc', '-O3', str(source), '-lm', '-o', str(independently_built)])
        assert independently_built.read_bytes().startswith(b'\x7fELF')
        assert_program_output(independently_built, [
            [-7.5, 2.0, 11.0, 0.25],
            [0.0, 2.0, -3.0, 1.25],
            [4.25, 2.0, 5.5, -8.0],
            [19.0, 2.0, 0.0, 3.5],
            [-2.25, 2.0, 8.0, 6.0],
        ])
        assert_program_output(independently_built, [[3.0, -4.0, 9.5]])


def test_makefile_builds_required_executable():
    makefile = (BASE / 'src' / 'Makefile').read_text(errors='replace')
    assert '-O3' in makefile, 'Makefile does not specify -O3.'
    assert '-lm' in makefile, 'Makefile does not specify -lm.'
    assert 'standardize.c' in makefile, 'Makefile does not compile standardize.c.'
    assert 'build/standardize' in makefile, 'Makefile does not target build/standardize.'
    if EXE.exists() or EXE.is_symlink():
        EXE.unlink()
    run_checked(['make', '-B', '-C', str(BASE / 'src')])
    assert EXE.is_file(), f'Executable {EXE} is missing.'
    assert os.access(EXE, os.X_OK), f'File {EXE} is not executable.'
    assert EXE.read_bytes().startswith(b'\x7fELF'), 'Built standardize is not a native executable.'
    assert_program_output(EXE, [
        [100.0, 4.0, -2.0],
        [50.0, 4.0, 7.0],
        [-25.0, 4.0, 1.0],
        [8.0, 4.0, 12.0],
    ])


def test_run_pipeline_script_uses_make_input_and_program():
    script = BASE / 'run_pipeline.sh'
    raw = BASE / 'data' / 'raw_matrix.csv'
    output = BASE / 'results' / 'cleaned_matrix.csv'
    dynamic = [
        [-10.0, 3.0, 1.5],
        [5.0, 3.0, -2.5],
        [20.0, 3.0, 8.0],
        [2.0, 3.0, 0.0],
    ]
    original = raw.read_text()
    try:
        raw.write_text(csv_input(dynamic))
        if output.exists():
            output.unlink()
        if EXE.exists():
            EXE.unlink()
        traced = run_checked(['bash', '-x', str(script)])
        trace = traced.stderr
        assert re.search(r'(?m)^\+\s+(?:command\s+)?(?:/\S*/)?make(?:\s|$)', trace), \
            'run_pipeline.sh did not call make.'
        assert EXE.is_file() and os.access(EXE, os.X_OK), 'Pipeline did not build the executable.'
        assert output.is_file(), 'Pipeline did not create cleaned_matrix.csv.'
        assert_program_output(EXE, dynamic)
        produced = output.read_text().splitlines()
        expected = expected_matrix(dynamic)
        assert len(produced) == len(dynamic)
        for r, line in enumerate(produced):
            fields = line.split(',')
            assert len(fields) == len(dynamic[0])
            for c, field in enumerate(fields):
                assert re.fullmatch(r'-?\d+\.\d{6}', field)
                assert abs(float(field) - expected[r][c]) <= 0.0000011
    finally:
        raw.write_text(original)
    run_checked([str(script)])


def test_executable_exists():
    assert EXE.is_file(), f'Executable {EXE} is missing.'
    assert os.access(EXE, os.X_OK), f'File {EXE} is not executable.'
    assert EXE.read_bytes().startswith(b'\x7fELF'), 'standardize is not a native executable.'


def test_cleaned_matrix_output():
    output_path = BASE / 'results' / 'cleaned_matrix.csv'
    assert output_path.is_file(), f'Output file {output_path} is missing.'
    assert output_path.read_text().strip() == EXPECTED_CLEANED, \
        f'Content of {output_path} does not match expected standardized matrix.'


def test_benchmark_executes_program_exactly_100_times_and_generates_data():
    benchmark = BASE / 'benchmark.sh'
    counter = Path('/tmp/standardize-call-count')
    backup = Path('/tmp/standardize-real-for-verifier')
    counter.unlink(missing_ok=True)
    backup.unlink(missing_ok=True)
    shutil.copy2(EXE, backup)
    wrapper = (
        '#!/bin/bash\n'
        f"printf 'x\\n' >> {shlex.quote(str(counter))}\n"
        f'exec {shlex.quote(str(backup))} "$@"\n'
    )
    try:
        EXE.write_text(wrapper)
        EXE.chmod(0o755)
        log = BASE / 'results' / 'benchmark.log'
        large = BASE / 'data' / 'large.csv'
        log.unlink(missing_ok=True)
        large.unlink(missing_ok=True)
        run_checked([str(benchmark)], timeout=120)
        calls = counter.read_text().splitlines() if counter.exists() else []
        assert len(calls) == 100, \
            f'benchmark.sh executed standardize {len(calls)} times instead of exactly 100.'
        assert large.is_file(), 'benchmark.sh did not create large.csv.'
        required_line = ','.join(['1.0'] * 100) + '\n'
        assert large.read_text() == required_line * 1000, \
            'large.csv is not exactly 1000 rows by 100 columns of 1.0.'
    finally:
        if backup.exists():
            os.replace(backup, EXE)
        counter.unlink(missing_ok=True)


def test_benchmark_log():
    log_path = BASE / 'results' / 'benchmark.log'
    assert log_path.is_file(), f'Benchmark log {log_path} is missing.'
    content = log_path.read_text()
    assert 'Benchmark completed successfully' in content, \
        f'Expected success message not found in {log_path}.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
