#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import secrets
import string
import subprocess
import tempfile

import pytest

SANITIZER = "/home/user/sanitizer.py"
PIPELINE = "/home/user/pipeline.sh"
TIMESTAMP_RE = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')
SENSOR_RE = re.compile(r'^[A-Z]{3}-\d{4}(-[A-Z])?$')


def get_expected_rows(input_csv):
    expected_rows = []
    with open(input_csv, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            return []

        expected_rows.append(headers)
        try:
            timestamp_idx = headers.index('timestamp')
            sensor_id_idx = headers.index('sensor_id')
        except ValueError:
            timestamp_idx = 0
            sensor_id_idx = 1

        for row in reader:
            if any('\n' in cell or '\r' in cell for cell in row):
                continue
            if timestamp_idx >= len(row) or not TIMESTAMP_RE.match(row[timestamp_idx]):
                continue
            if sensor_id_idx >= len(row) or not SENSOR_RE.match(row[sensor_id_idx]):
                continue
            expected_rows.append(row)
    return expected_rows


def run_sanitizer(input_path, output_path):
    result = subprocess.run(
        ["python3", SANITIZER, input_path, output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, result.stderr.decode(errors='replace')
    assert os.path.isfile(output_path), f"Sanitizer did not create {output_path}"


def test_sanitizer_on_clean_corpus():
    clean_dir = "/app/corpora/clean/"
    assert os.path.isfile(SANITIZER), f"Sanitizer script missing at {SANITIZER}"
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.csv')]
    if not clean_files:
        pytest.skip("No clean CSVs found to test.")

    failed_files = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for fname in clean_files:
            input_path = os.path.join(clean_dir, fname)
            output_path = os.path.join(tmpdir, fname)
            subprocess.run(["python3", SANITIZER, input_path, output_path], capture_output=True)
            if not os.path.exists(output_path):
                failed_files.append(fname)
                continue
            with open(input_path, 'r', newline='', encoding='utf-8') as f1, \
                 open(output_path, 'r', newline='', encoding='utf-8') as f2:
                if f1.read() != f2.read():
                    failed_files.append(fname)
    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean files modified or failed: {', '.join(failed_files)}"


def test_sanitizer_on_evil_corpus():
    evil_dir = "/app/corpora/evil/"
    assert os.path.isfile(SANITIZER), f"Sanitizer script missing at {SANITIZER}"
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.csv')]
    if not evil_files:
        pytest.skip("No evil CSVs found to test.")

    failed_files = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for fname in evil_files:
            input_path = os.path.join(evil_dir, fname)
            output_path = os.path.join(tmpdir, fname)
            subprocess.run(["python3", SANITIZER, input_path, output_path], capture_output=True)
            if not os.path.exists(output_path):
                failed_files.append(fname)
                continue
            expected_rows = get_expected_rows(input_path)
            with open(output_path, 'r', newline='', encoding='utf-8') as f:
                actual_rows = list(csv.reader(f))
            if actual_rows != expected_rows:
                failed_files.append(fname)
    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil files bypassed or improperly sanitized: {', '.join(failed_files)}"


def test_pipeline_orchestration():
    assert os.path.isfile(PIPELINE), f"Pipeline script missing at {PIPELINE}"
    clean_dir = "/app/corpora/clean/"
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.csv')]

    with tempfile.TemporaryDirectory() as tmpdir:
        result = subprocess.run(["bash", PIPELINE, clean_dir, tmpdir], capture_output=True)
        assert result.returncode == 0, f"Pipeline script failed with error: {result.stderr.decode()}"
        report_path = os.path.join(tmpdir, "report.html")
        assert os.path.isfile(report_path), "HTML report was not generated at the output directory."
        with open(report_path, 'r', encoding='utf-8') as f:
            report_content = f.read()
        assert "Sanitization Complete" in report_content, "Report missing exact string 'Sanitization Complete'."
        assert str(len(clean_files)) in report_content, "Report does not seem to list the correct number of files processed."
        output_csvs = [f for f in os.listdir(tmpdir) if f.endswith('.csv')]
        assert len(output_csvs) == len(clean_files), "Output directory does not contain the same number of CSV files as the input."


def token(n=10):
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(n))


def valid_sensor():
    prefix = ''.join(secrets.choice(string.ascii_uppercase) for _ in range(3))
    digits = ''.join(secrets.choice(string.digits) for _ in range(4))
    suffix = ('-' + secrets.choice(string.ascii_uppercase)) if secrets.randbelow(2) else ''
    return prefix + '-' + digits + suffix


def valid_timestamp():
    return f"{random.randint(2001, 2090):04d}-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}T{random.randint(0, 23):02d}:{random.randint(0, 59):02d}:{random.randint(0, 59):02d}Z"


def write_csv(path, rows):
    with open(path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerows(rows)


def make_random_case(path, clean_only=False):
    header = ['timestamp', 'sensor_id', 'sensor_notes']
    rows = []
    for _ in range(random.randint(4, 8)):
        rows.append([valid_timestamp(), valid_sensor(), f"valid {token()}, comma, and quote \"{token(4)}\""])
    if not clean_only:
        rows.extend([
            [valid_timestamp().replace('T', ' ', 1), valid_sensor(), 'bad timestamp ' + token()],
            [valid_timestamp()[:-1], valid_sensor(), 'missing UTC marker ' + token()],
            [valid_timestamp(), 'aa-' + ''.join(secrets.choice(string.digits) for _ in range(4)), 'bad id ' + token()],
            [valid_timestamp(), valid_sensor() + '-ZZ', 'bad suffix ' + token()],
            [valid_timestamp(), valid_sensor(), 'embedded ' + token() + '\nnewline ' + token()],
            [valid_timestamp(), valid_sensor(), 'embedded ' + token() + '\rnewline ' + token()],
        ])
        random.SystemRandom().shuffle(rows)
    write_csv(path, [header] + rows)


def expected_bytes(input_path):
    rows = get_expected_rows(input_path)
    with tempfile.NamedTemporaryFile(mode='w+', newline='', encoding='utf-8', delete=False) as f:
        expected_path = f.name
    try:
        write_csv(expected_path, rows)
        with open(expected_path, 'rb') as f:
            return f.read()
    finally:
        os.unlink(expected_path)


def test_sanitizer_on_generated_unpredictable_inputs():
    assert os.path.isfile(SANITIZER), f"Sanitizer script missing at {SANITIZER}"
    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(5):
            input_path = os.path.join(tmpdir, f"input-{token()}-{i}.csv")
            output_path = os.path.join(tmpdir, f"output-{token()}-{i}.csv")
            make_random_case(input_path, clean_only=(i == 0))
            expected = expected_bytes(input_path)
            run_sanitizer(input_path, output_path)
            with open(output_path, 'rb') as f:
                actual = f.read()
            assert actual == expected, f"Incorrect sanitization for generated case {i}"


def test_pipeline_on_generated_mixed_inputs():
    assert os.path.isfile(PIPELINE), f"Pipeline script missing at {PIPELINE}"
    with tempfile.TemporaryDirectory() as root:
        input_dir = os.path.join(root, 'input-' + token())
        output_dir = os.path.join(root, 'output-' + token())
        os.mkdir(input_dir)
        names = [f"{token()}.csv", f"space {token()}.csv", f"{token()}-third.csv"]
        expected = {}
        for i, name in enumerate(names):
            path = os.path.join(input_dir, name)
            make_random_case(path, clean_only=(i == 1))
            expected[name] = expected_bytes(path)
        with open(os.path.join(input_dir, 'ignore-' + token() + '.txt'), 'w') as f:
            f.write('not a csv')

        result = subprocess.run(
            ["bash", PIPELINE, input_dir, output_dir],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, result.stderr.decode(errors='replace')
        output_csvs = sorted(f for f in os.listdir(output_dir) if f.endswith('.csv'))
        assert output_csvs == sorted(names), "Pipeline did not produce one corresponding CSV per input CSV"
        for name in names:
            with open(os.path.join(output_dir, name), 'rb') as f:
                assert f.read() == expected[name], f"Pipeline output for {name} was not sanitized correctly"

        report_path = os.path.join(output_dir, 'report.html')
        assert os.path.isfile(report_path), "HTML report was not generated at the output directory."
        with open(report_path, encoding='utf-8') as f:
            report = f.read()
        assert 'Sanitization Complete' in report
        assert str(len(names)) in report
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
