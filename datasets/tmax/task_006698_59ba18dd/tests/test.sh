#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import pathlib
import re
import secrets
import stat
import subprocess
import tempfile

PIPELINE = pathlib.Path('/home/user/pipeline')
SCRIPT = PIPELINE / 'run_pipeline.sh'
SOURCE = PIPELINE / 'data_parser.c'
BINARY = PIPELINE / 'data_parser'
ANALYZER = PIPELINE / 'log_analyzer.py'
INPUT = PIPELINE / 'data/input.dat'
LOG = PIPELINE / 'data/app.log'
REPORT = PIPELINE / 'data/summary_report.json'


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def levels_in_log(path):
    counts = collections.Counter()
    with open(path) as f:
        for line in f:
            parts = line.rstrip('\n').split('|')
            if len(parts) >= 2:
                counts[parts[1].strip()] += 1
    return dict(counts)


def assert_parser_behavior(binary):
    nonce = secrets.token_hex(8)
    process_values = [f'item_{nonce}_{i}' for i in range(4)]
    event_count = 3
    lines = [f'PROCESS: {value}' for value in process_values]
    lines += [f'EVENT: event_{nonce}_{i}' for i in range(event_count)]
    lines += ['PROCESS', 'ID: 1001', 'UNRELATED']

    with tempfile.TemporaryDirectory() as td:
        input_path = pathlib.Path(td) / 'input.dat'
        output_path = pathlib.Path(td) / 'app.log'
        input_path.write_text('\n'.join(lines) + '\n')
        result = run([str(binary), str(input_path), str(output_path)])
        assert result.returncode == 0, (
            f'Parser failed on malformed PROCESS line.\nSTDOUT:\n{result.stdout}\n'
            f'STDERR:\n{result.stderr}'
        )
        assert output_path.is_file(), 'Parser did not create its output log'
        output_lines = output_path.read_text().splitlines()

    assert output_lines, 'Parser produced an empty log'
    for line in output_lines:
        assert re.match(r'^2023-10-01T\d\d:\d\d:\d\d\|[^|]+\|.*$', line), (
            f'Parser altered the required log structure: {line!r}'
        )
    assert output_lines.count('2023-10-01T10:00:00|INFO|Starting processing') == 1
    assert output_lines.count('2023-10-01T10:02:00|INFO|Processing complete') == 1
    for value in process_values:
        matches = [line for line in output_lines if 'Processing item:' in line and value in line]
        assert len(matches) == 1, f'Valid PROCESS value {value!r} was not logged exactly once'
    event_lines = [line for line in output_lines if line.endswith('|CRITICAL|Unexpected event found')]
    assert len(event_lines) == event_count, 'Not every valid EVENT record was processed'


def test_run_pipeline_success():
    """Ensure the pipeline script runs successfully without errors."""
    assert os.path.isfile(SCRIPT), f'Pipeline script missing at {SCRIPT}'
    assert os.access(SCRIPT, os.X_OK), f'Pipeline script at {SCRIPT} is not executable'
    result = run([str(SCRIPT)], cwd=str(PIPELINE))
    assert result.returncode == 0, (
        f'Pipeline script failed with return code {result.returncode}.\n'
        f'STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    )


def test_summary_report_generated_and_correct():
    """Ensure the summary report is generated and contains the correct counts."""
    assert os.path.isfile(REPORT), f'Summary report missing at {REPORT}'
    with open(REPORT) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            assert False, f'Summary report is not valid JSON: {e}'

    assert isinstance(data, dict), 'Summary report JSON should be a dictionary'
    assert 'CRITICAL' in data, "Summary report is missing the 'CRITICAL' log level count"
    assert data['CRITICAL'] == 1, f"Expected 1 CRITICAL log, but found {data['CRITICAL']}"
    assert 'INFO' in data, "Summary report is missing the 'INFO' log level count"
    assert data['INFO'] >= 3, f"Expected at least 3 INFO logs, but found {data['INFO']}"

    assert LOG.is_file(), f'Pipeline log missing at {LOG}'
    expected = levels_in_log(LOG)
    assert data == expected, f'Report {data!r} does not exactly tally app.log {expected!r}'


def test_c_source_and_recompiled_binary_process_dynamic_input():
    assert SOURCE.is_file(), 'data_parser.c is missing'
    assert BINARY.is_file(), 'Recompiled data_parser is missing'
    assert BINARY.read_bytes()[:4] == b'\x7fELF', 'data_parser must be a compiled binary'
    assert_parser_behavior(BINARY)

    with tempfile.TemporaryDirectory() as td:
        rebuilt = pathlib.Path(td) / 'data_parser'
        result = run(['gcc', '-o', str(rebuilt), str(SOURCE)])
        assert result.returncode == 0, (
            f'data_parser.c does not compile.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
        )
        assert_parser_behavior(rebuilt)


def test_analyzer_dynamically_tallies_every_encountered_level():
    assert ANALYZER.is_file(), 'log_analyzer.py is missing'
    nonce = secrets.token_hex(6).upper()
    dynamic_levels = [f'NOTICE_{nonce}', f'TRACE_{nonce}', f'ALERT_{nonce}']
    sequence = ['INFO', dynamic_levels[0], 'CRITICAL', dynamic_levels[1],
                dynamic_levels[0], dynamic_levels[2], dynamic_levels[2], dynamic_levels[2]]
    expected = dict(collections.Counter(sequence))

    with tempfile.TemporaryDirectory() as td:
        log_path = pathlib.Path(td) / 'synthetic.log'
        report_path = pathlib.Path(td) / 'summary.json'
        log_path.write_text(''.join(
            f'2026-01-01T00:00:{i:02d}|{level}|message {i}\n'
            for i, level in enumerate(sequence)
        ))
        result = run(['python3', str(ANALYZER), str(log_path), str(report_path)])
        assert result.returncode == 0, (
            f'Analyzer failed on dynamic levels.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
        )
        assert report_path.is_file(), 'Analyzer did not create a report'
        actual = json.loads(report_path.read_text())
    assert actual == expected, f'Analyzer returned {actual!r}; expected {expected!r}'


def test_wrapper_actually_invokes_parser_and_analyzer():
    nonce = secrets.token_hex(12)
    parser_marker = pathlib.Path(f'/tmp/parser_called_{nonce}')
    analyzer_marker = pathlib.Path(f'/tmp/analyzer_called_{nonce}')
    level = f'PIPELINE_{nonce.upper()}'
    saved_binary = BINARY.read_bytes()
    saved_binary_mode = stat.S_IMODE(BINARY.stat().st_mode)
    saved_analyzer = ANALYZER.read_bytes()
    saved_analyzer_mode = stat.S_IMODE(ANALYZER.stat().st_mode)

    parser_spy = f'''#!/bin/sh
[ "$1" = "/home/user/pipeline/data/input.dat" ] || exit 41
[ "$2" = "/home/user/pipeline/data/app.log" ] || exit 42
printf '2026-01-01T00:00:00|{level}|one\\n2026-01-01T00:00:01|{level}|two\\n' > "$2"
touch '{parser_marker}'
'''
    analyzer_spy = f'''import collections, json, pathlib, sys
if sys.argv[1:] != ['/home/user/pipeline/data/app.log', '/home/user/pipeline/data/summary_report.json']:
    raise SystemExit(43)
marker = pathlib.Path({str(analyzer_marker)!r})
counts = collections.Counter()
with open(sys.argv[1]) as src:
    for line in src:
        parts = line.rstrip('\\n').split('|')
        if len(parts) >= 2:
            counts[parts[1].strip()] += 1
with open(sys.argv[2], 'w') as dst:
    json.dump(dict(counts), dst)
marker.touch()
'''

    try:
        BINARY.write_text(parser_spy)
        BINARY.chmod(0o755)
        ANALYZER.write_text(analyzer_spy)
        ANALYZER.chmod(0o755)
        result = run([str(SCRIPT)], cwd=str(PIPELINE))
        assert result.returncode == 0, (
            f'Wrapper failed while exercising its components.\nSTDOUT:\n{result.stdout}\n'
            f'STDERR:\n{result.stderr}'
        )
        assert parser_marker.is_file(), 'Wrapper did not invoke data_parser'
        assert analyzer_marker.is_file(), 'Wrapper did not invoke log_analyzer.py'
        assert json.loads(REPORT.read_text()) == {level: 2}, (
            'Wrapper did not preserve the analyzer-generated report'
        )
    finally:
        BINARY.write_bytes(saved_binary)
        BINARY.chmod(saved_binary_mode)
        ANALYZER.write_bytes(saved_analyzer)
        ANALYZER.chmod(saved_analyzer_mode)
        parser_marker.unlink(missing_ok=True)
        analyzer_marker.unlink(missing_ok=True)

    result = run([str(SCRIPT)], cwd=str(PIPELINE))
    assert result.returncode == 0, 'Restored real pipeline no longer runs successfully'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
