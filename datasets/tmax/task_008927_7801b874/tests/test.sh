#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import sqlite3
import subprocess
from pathlib import Path

HOME = Path('/home/user')
SCRIPT = HOME / 'run_analysis.sh'
SOURCE = HOME / 'find_cycle.cpp'
CSV = HOME / 'latest_deps.csv'
DEADLOCK = HOME / 'deadlock.txt'
DB = HOME / 'etl.db'
MARKER = Path('/tmp/verifier_cycle_executed')
WRAPDIR = Path('/tmp/verifier-bin')


def install_gpp_wrapper():
    WRAPDIR.mkdir(exist_ok=True)
    wrapper = WRAPDIR / 'g++'
    wrapper.write_text(r'''#!/bin/bash
set -e
/usr/bin/g++ "$@"
out="a.out"
expect_out=0
for arg in "$@"; do
    if [ "$expect_out" = 1 ]; then
        out="$arg"
        expect_out=0
    elif [ "$arg" = "-o" ]; then
        expect_out=1
    elif [[ "$arg" == -o* && "$arg" != "-o" ]]; then
        out="${arg#-o}"
    fi
done
if [[ "$out" != /* ]]; then
    out="$PWD/$out"
fi
real="${out}.__verifier_real"
rm -f "$real"
mv "$out" "$real"
cat > "$out" <<EOF
#!/bin/bash
touch /tmp/verifier_cycle_executed
exec "$real" "\$@"
EOF
chmod +x "$out"
''')
    wrapper.chmod(0o755)


def run_analysis():
    env = os.environ.copy()
    env['PATH'] = str(WRAPDIR) + ':' + env.get('PATH', '')
    subprocess.run(
        ['/bin/bash', str(SCRIPT)], cwd=str(HOME), env=env,
        check=True, timeout=30, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True
    )


def read_pairs():
    lines = [line.strip() for line in CSV.read_text().splitlines() if line.strip()]
    pairs = []
    for line in lines:
        parts = line.split(',')
        assert len(parts) == 2, f'Invalid CSV line format: {line}'
        pairs.append((parts[0].strip(), parts[1].strip()))
    return pairs


def test_implementation_and_original_database():
    for filepath in [SCRIPT, SOURCE]:
        assert filepath.exists(), f'Required file {filepath} is missing.'
        assert filepath.is_file(), f'{filepath} is not a regular file.'

    script_text = SCRIPT.read_text(errors='replace')
    assert re.search(r'ROW_NUMBER\s*\(\s*\)\s*OVER\s*\(', script_text, re.I | re.S), \
        'run_analysis.sh must use ROW_NUMBER() as a SQL window function.'
    assert re.search(r'(^|[^A-Za-z0-9_])g\+\+([^A-Za-z0-9_]|$)', script_text), \
        'run_analysis.sh must compile the C++ source with g++.'
    assert re.search(r'-std(?:=|\s+)c\+\+17', script_text), \
        'run_analysis.sh must compile using -std=c++17.'

    MARKER.unlink(missing_ok=True)
    run_analysis()

    required_files = [SCRIPT, SOURCE, CSV, DEADLOCK]
    for filepath in required_files:
        assert filepath.exists(), f'Required file {filepath} is missing.'

    expected_pairs = {
        ('10', '20'), ('20', '30'), ('30', '40'),
        ('40', '50'), ('50', '10'), ('60', '10')
    }
    actual_pairs = set(read_pairs())
    assert actual_pairs == expected_pairs, \
        f'CSV dependencies do not match expected latest state. Got: {actual_pairs}'

    content = DEADLOCK.read_text().strip()
    expected_content = '10,20,30,40,50'
    assert content == expected_content, \
        f"Expected deadlock.txt to contain '{expected_content}', but got '{content}'."
    assert MARKER.exists(), 'The C++ executable compiled by run_analysis.sh was not executed.'


def test_hidden_database_and_cpp_program():
    rng = random.SystemRandom()
    ids = rng.sample(range(10000, 90000), 8)
    a, b, c, d, tail, isolated, old_target, new_target = ids

    if DB.exists():
        DB.unlink()
    con = sqlite3.connect(DB)
    con.execute('CREATE TABLE task_runs (run_id INTEGER, task_id INTEGER, depends_on INTEGER, execution_time DATETIME)')
    rows = [
        (1, a, old_target, '2024-01-01 01:00:00'),
        (2, a, b,          '2024-02-01 01:00:00'),
        (3, b, c,          '2024-02-01 02:00:00'),
        (4, c, d,          '2024-02-01 03:00:00'),
        (5, d, a,          '2024-02-01 04:00:00'),
        (6, tail, new_target, '2024-01-01 05:00:00'),
        (7, tail, a,          '2024-02-01 05:00:00'),
        (8, isolated, b,      '2024-01-01 06:00:00'),
        (9, isolated, None,   '2024-02-01 06:00:00'),
    ]
    con.executemany('INSERT INTO task_runs VALUES (?, ?, ?, ?)', rows)
    con.commit()
    con.close()

    CSV.unlink(missing_ok=True)
    DEADLOCK.unlink(missing_ok=True)
    MARKER.unlink(missing_ok=True)
    run_analysis()

    expected_pairs = {(str(a), str(b)), (str(b), str(c)), (str(c), str(d)),
                      (str(d), str(a)), (str(tail), str(a))}
    pairs = read_pairs()
    assert len(pairs) == len(expected_pairs), 'latest_deps.csv has missing or duplicate rows.'
    assert set(pairs) == expected_pairs, \
        f'Windowed latest-run export is incorrect. Got: {set(pairs)}'
    assert DEADLOCK.read_text().strip() == ','.join(map(str, sorted([a, b, c, d])))
    assert MARKER.exists(), 'run_analysis.sh did not execute the C++ executable it compiled.'

    # Compile and exercise find_cycle.cpp independently so the shell script cannot
    # substitute a hardcoded result for a nonfunctional C++ implementation.
    binary = Path('/tmp/verifier_find_cycle')
    subprocess.run(['/usr/bin/g++', '-std=c++17', str(SOURCE), '-o', str(binary)],
                   check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    x, y, z, branch = rng.sample(range(100000, 900000), 4)
    CSV.write_text(f'{x},{y}\n{y},{z}\n{z},{x}\n{branch},{x}\n')
    DEADLOCK.unlink(missing_ok=True)
    subprocess.run([str(binary)], cwd=str(HOME), check=True, timeout=15,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert DEADLOCK.exists(), 'The standalone C++ program did not create deadlock.txt.'
    assert DEADLOCK.read_text().strip() == ','.join(map(str, sorted([x, y, z]))), \
        'The standalone C++ program did not detect and sort the hidden cycle.'


install_gpp_wrapper()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
