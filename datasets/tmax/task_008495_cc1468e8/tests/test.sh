#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import string
import subprocess
import time
from pathlib import Path

HOME = Path('/home/user')
INCOMING = HOME / 'incoming'
PROCESSED = HOME / 'processed'
HEADER = 'Date,State,Token'


def expected_lines(input_path):
    result = [HEADER]
    translation = str.maketrans({c: ' ' for c in string.punctuation})
    with open(input_path, 'r', encoding='utf-8') as f:
        for raw in f:
            raw = raw.rstrip('\r\n')
            if not raw:
                continue
            fields = raw.split('|')
            assert len(fields) == 4, f'Invalid verifier input line: {raw!r}'
            date = fields[0]
            for state, report in zip(('NY', 'CA', 'TX'), fields[1:]):
                for token in report.translate(translation).split():
                    result.append(f'{date},{state},{token.lower()}')
    return result


def output_lines(path):
    with open(path, 'r', encoding='utf-8') as f:
        return [line.strip() for line in f if line.strip()]


def assert_output_matches(input_path, output_path):
    assert os.path.isfile(output_path), f'{output_path} does not exist.'
    assert output_lines(output_path) == expected_lines(input_path), \
        f'Contents of {output_path} do not match {input_path}.'


def test_process_reports_c_exists_and_executes_correctly():
    source = HOME / 'process_reports.c'
    assert source.is_file(), '/home/user/process_reports.c does not exist.'

    binary = Path('/tmp/process_reports_test')
    subprocess.run(
        ['gcc', str(source), '-o', str(binary)],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert binary.is_file() and os.access(binary, os.X_OK), 'C source did not produce an executable.'

    probe_in = Path('/tmp/process_reports_probe.dat')
    probe_out = Path('/tmp/process_reports_probe.csv')
    probe_in.write_text(
        "2041-07-08|MiXeD-case_can't/STOP... 42?|Tabs\tAND spaces!|;Leading,, punctuation---ends.\n"
        "2041-07-09|One TWO three|A+B=C|Question? Answer!\n",
        encoding='utf-8'
    )
    subprocess.run([str(binary), str(probe_in), str(probe_out)], check=True, timeout=15)
    assert_output_matches(probe_in, probe_out)


def test_run_pipeline_sh_exists_and_executable():
    filepath = '/home/user/run_pipeline.sh'
    assert os.path.isfile(filepath), f'{filepath} does not exist.'
    st = os.stat(filepath)
    assert bool(st.st_mode & stat.S_IXUSR), f'{filepath} is not executable by the user.'


def test_existing_processed_files_and_contents():
    expected_files = ['day1.csv', 'day2.csv', 'day3.csv']
    for filename in expected_files:
        filepath = PROCESSED / filename
        assert filepath.is_file(), f'{filepath} does not exist.'

    # Preserve the original exact day1 assertion.
    expected_day1 = [
        'Date,State,Token',
        '2023-11-01,NY,hello',
        '2023-11-01,NY,world',
        '2023-11-01,CA,nothing',
        '2023-11-01,CA,to',
        '2023-11-01,CA,report',
        '2023-11-01,TX,critical',
        '2023-11-01,TX,error',
        '2023-11-01,TX,on',
        '2023-11-01,TX,db',
        '2023-11-02,NY,all',
        '2023-11-02,NY,systems',
        '2023-11-02,NY,go',
        '2023-11-02,CA,running',
        '2023-11-02,CA,smoothly',
        '2023-11-02,TX,wait',
        '2023-11-02,TX,what'
    ]
    assert output_lines(PROCESSED / 'day1.csv') == expected_day1, \
        'Contents of /home/user/processed/day1.csv do not match expected output.'

    # Also verify every supplied input rather than existence alone.
    for name in ('day1', 'day2', 'day3'):
        assert_output_matches(INCOMING / f'{name}.dat', PROCESSED / f'{name}.csv')


def test_pipeline_compiles_processes_arbitrary_files_and_runs_in_parallel():
    probe = INCOMING / 'verifier_unseen.dat'
    probe.write_text(
        '2050-01-02|Fresh INPUT; with punctuation!|California-Rocks, TODAY.|TX/value: Nine.\n'
        '2050-01-03|UPPER lower|semi;colon and/slash|empty---then word\n',
        encoding='utf-8'
    )

    # Long, ordinary records keep workers alive long enough to observe overlap.
    bulk_line = '2051-03-04|Alpha beta gamma!|Delta epsilon?|Zeta eta.\n'
    bulk_names = []
    for i in range(12):
        path = INCOMING / f'_parallel_{i}.dat'
        path.write_text(bulk_line * 15000, encoding='utf-8')
        bulk_names.append(path)

    for path in [probe] + bulk_names:
        os.chown(path, 1000, 1000)

    compiled = HOME / 'process_reports'
    if compiled.exists() or compiled.is_symlink():
        compiled.unlink()

    proc = subprocess.Popen(
        ['runuser', '-u', 'user', '--', '/home/user/run_pipeline.sh'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    peak_parallel = 0
    deadline = time.time() + 60
    while proc.poll() is None and time.time() < deadline:
        active = 0
        for entry in Path('/proc').iterdir():
            if not entry.name.isdigit():
                continue
            try:
                args = (entry / 'cmdline').read_bytes().split(b'\0')
            except (FileNotFoundError, PermissionError, ProcessLookupError):
                continue
            if args and os.path.basename(args[0].decode(errors='ignore')) == 'process_reports':
                if any(b'_parallel_' in arg for arg in args[1:]):
                    active += 1
        peak_parallel = max(peak_parallel, active)
        time.sleep(0.001)

    if proc.poll() is None:
        proc.kill()
        proc.wait()
        raise AssertionError('run_pipeline.sh timed out')
    stdout, stderr = proc.communicate()
    assert proc.returncode == 0, f'run_pipeline.sh failed:\n{stdout}\n{stderr}'

    assert compiled.is_file() and os.access(compiled, os.X_OK), \
        'run_pipeline.sh did not compile /home/user/process_reports.'
    with open(compiled, 'rb') as f:
        assert f.read(4) == b'\x7fELF', '/home/user/process_reports is not a compiled executable.'

    assert_output_matches(probe, PROCESSED / 'verifier_unseen.csv')
    for name in ('day1', 'day2', 'day3'):
        assert_output_matches(INCOMING / f'{name}.dat', PROCESSED / f'{name}.csv')
    for path in bulk_names:
        out = PROCESSED / (path.stem + '.csv')
        assert out.is_file(), f'{out} does not exist.'
        with open(out, 'r', encoding='utf-8') as f:
            assert f.readline().strip() == HEADER, f'{out} has no correct header.'

    assert peak_parallel >= 2, \
        'The pipeline did not run multiple process_reports workers concurrently.'


def test_cron_backup_and_actual_user_crontab_contain_job():
    filepath = HOME / 'cron_backup.txt'
    assert filepath.is_file(), '/home/user/cron_backup.txt does not exist.'
    content = filepath.read_text(encoding='utf-8')

    pattern = r'^30\s+2\s+\*\s+\*\s+\*.*/home/user/run_pipeline\.sh(?:\s|$)'
    assert re.search(pattern, content, re.MULTILINE) is not None, \
        "Cron job '30 2 * * * /home/user/run_pipeline.sh' not found in /home/user/cron_backup.txt."

    actual = subprocess.run(
        ['crontab', '-u', 'user', '-l'], capture_output=True, text=True
    )
    assert actual.returncode == 0, f'user has no readable crontab: {actual.stderr}'
    assert re.search(pattern, actual.stdout, re.MULTILINE) is not None, \
        "Cron job is not installed in user's actual crontab."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
