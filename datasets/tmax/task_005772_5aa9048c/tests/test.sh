#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HOME = Path('/home/user')
INPUTS = {HOME / 'demographics.csv', HOME / 'activity.csv'}
OUTPUTS = {HOME / 'training_data.csv', HOME / 'report.json', HOME / 'plot.png'}


def candidate_scripts():
    candidates = []
    for path in HOME.iterdir():
        if not path.is_file() or path in INPUTS or path in OUTPUTS:
            continue
        try:
            raw = path.read_bytes()
            text = raw.decode('utf-8')
        except (OSError, UnicodeDecodeError):
            continue
        suffix = path.suffix.lower()
        executable = bool(path.stat().st_mode & stat.S_IXUSR)
        shebang = text.startswith('#!')
        if suffix not in {'.py', '.sh', '.bash', '.pl', '.rb'} and not executable and not shebang:
            continue
        score = sum(name in text for name in ('demographics.csv', 'activity.csv', 'training_data.csv', 'report.json', 'plot.png'))
        candidates.append((score, path, text))
    return sorted(candidates, key=lambda item: (-item[0], str(item[1])))


def python_loop_lines(paths):
    tracked = {}
    for path in paths:
        if path.suffix.lower() != '.py':
            continue
        try:
            tree = ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
        except (OSError, SyntaxError, UnicodeDecodeError):
            continue
        lines = set()
        for node in ast.walk(tree):
            is_10000_loop = False
            if isinstance(node, (ast.For, ast.AsyncFor)):
                call = node.iter
                if isinstance(call, ast.Call) and isinstance(call.func, ast.Name) and call.func.id == 'range':
                    is_10000_loop = any(isinstance(arg, ast.Constant) and arg.value == 10000 for arg in call.args)
                elif isinstance(call, ast.Call):
                    is_10000_loop = any(isinstance(arg, ast.Constant) and arg.value == 10000 for arg in call.args)
            elif isinstance(node, ast.While):
                is_10000_loop = any(isinstance(n, ast.Constant) and n.value == 10000 for n in ast.walk(node.test))
            if is_10000_loop and node.body:
                lines.add(node.body[0].lineno)
        if lines:
            tracked[str(path.resolve())] = sorted(lines)
    return tracked


def execute_artifact():
    candidates = candidate_scripts()
    assert candidates, 'No script artifact was written in /home/user.'
    score, script, script_text = candidates[0]
    assert score >= 3, 'Could not identify a script that creates the required artifacts.'

    combined_text = '\n'.join(item[2] for item in candidates)
    lower = combined_text.lower()
    assert '10000' in combined_text, 'The script does not contain the required 10,000-pass benchmark.'
    assert 'age' in lower and 'avg_latency' in lower, 'The benchmark does not reference age and avg_latency.'
    assert ('*' in combined_text or 'multiply' in lower or 'mul(' in lower), 'No multiplication operation was found in the script.'
    assert ('scatter' in lower or 'geom_point' in lower or 'with points' in lower), 'No scatter-plot operation was found in the script.'

    for output in OUTPUTS:
        try:
            output.unlink()
        except FileNotFoundError:
            pass

    trace_file = Path(tempfile.mktemp(prefix='benchmark_trace_', dir='/tmp'))
    suffix = script.suffix.lower()
    if suffix == '.py':
        py_paths = [item[1] for item in candidates if item[1].suffix.lower() == '.py']
        tracked = python_loop_lines(py_paths)
        assert tracked, 'No executable Python loop bounded to 10,000 passes was found.'
        wrapper = Path(tempfile.mktemp(prefix='run_submission_', suffix='.py', dir='/tmp'))
        wrapper.write_text("""import json, os, runpy, sys\ntracked = json.loads(os.environ['TRACKED_LOOP_LINES'])\ncounts = {name: 0 for name in tracked}\ndef tracer(frame, event, arg):\n    if event == 'line':\n        name = os.path.realpath(frame.f_code.co_filename)\n        if name in tracked and frame.f_lineno in tracked[name]:\n            counts[name] += 1\n    return tracer\ntry:\n    sys.settrace(tracer)\n    runpy.run_path(sys.argv[1], run_name='__main__')\nfinally:\n    sys.settrace(None)\n    with open(os.environ['TRACE_FILE'], 'w') as f:\n        json.dump(counts, f)\n""", encoding='utf-8')
        env = os.environ.copy()
        env['TRACKED_LOOP_LINES'] = json.dumps(tracked)
        env['TRACE_FILE'] = str(trace_file)
        command = [sys.executable, str(wrapper), str(script)]
    elif suffix in {'.sh', '.bash'}:
        env = os.environ.copy()
        command = ['bash', str(script)]
    elif suffix == '.pl':
        env = os.environ.copy()
        command = ['perl', str(script)]
    elif suffix == '.rb':
        env = os.environ.copy()
        command = ['ruby', str(script)]
    else:
        env = os.environ.copy()
        command = [str(script)]

    start = time.monotonic()
    completed = subprocess.run(command, cwd=str(HOME), env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, timeout=180)
    elapsed = time.monotonic() - start
    assert completed.returncode == 0, f'Script execution failed:\n{completed.stderr[-4000:]}'
    for output in OUTPUTS:
        assert output.is_file(), f'Script execution did not create {output}.'

    if suffix == '.py':
        assert trace_file.is_file(), 'The Python benchmark trace was not produced.'
        counts = json.loads(trace_file.read_text(encoding='utf-8'))
        assert sum(counts.values()) >= 10000, 'The required 10,000-pass benchmark loop did not execute.'

    return elapsed


ELAPSED = execute_artifact()


def test_training_data_csv():
    file_path = '/home/user/training_data.csv'
    assert os.path.isfile(file_path), f'Missing file: {file_path}'

    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 6, f'Expected 6 lines in {file_path} (header + 5 rows), got {len(lines)}'
    assert lines[0] == 'user_id,age,event_count,avg_latency', f'Incorrect header in {file_path}'

    expected_rows = [
        '1,25,2,125.0',
        '2,30,1,200.0',
        '3,22,1,50.0',
        '4,35,2,305.0',
        '5,28,2,125.0'
    ]
    for i, expected in enumerate(expected_rows):
        actual = lines[i + 1].split(',')
        exp = expected.split(',')
        assert actual[0] == exp[0], f'Row {i+1} user_id mismatch: expected {exp[0]}, got {actual[0]}'
        assert actual[1] == exp[1], f'Row {i+1} age mismatch: expected {exp[1]}, got {actual[1]}'
        assert actual[2] == exp[2], f'Row {i+1} event_count mismatch: expected {exp[2]}, got {actual[2]}'
        assert float(actual[3]) == float(exp[3]), f'Row {i+1} avg_latency mismatch: expected {exp[3]}, got {actual[3]}'


def test_report_json():
    file_path = '/home/user/report.json'
    assert os.path.isfile(file_path), f'Missing file: {file_path}'
    with open(file_path, 'r') as f:
        data = json.load(f)

    assert 'row_count' in data, f"Missing 'row_count' in {file_path}"
    assert data['row_count'] == 5, f"Expected row_count to be 5, got {data['row_count']}"
    assert 'total_inference_time_seconds' in data, f"Missing 'total_inference_time_seconds' in {file_path}"
    value = data['total_inference_time_seconds']
    assert isinstance(value, (int, float)) and not isinstance(value, bool), 'total_inference_time_seconds must be a number'
    assert math.isfinite(value), 'total_inference_time_seconds must be finite'
    assert value > 0, 'total_inference_time_seconds must be greater than 0'
    assert value <= ELAPSED + 0.1, 'Reported benchmark time exceeds the wall-clock duration of the executed script.'


def test_plot_png():
    from PIL import Image, ImageStat

    file_path = '/home/user/plot.png'
    assert os.path.isfile(file_path), f'Missing file: {file_path}'
    size = os.path.getsize(file_path)
    assert size > 0, f'{file_path} is empty.'
    with open(file_path, 'rb') as f:
        header = f.read(8)
    assert header == b'\x89PNG\r\n\x1a\n', f'{file_path} is not a valid PNG file (invalid magic bytes).'

    with Image.open(file_path) as image:
        image.verify()
    with Image.open(file_path) as image:
        image = image.convert('RGB')
        width, height = image.size
        assert width >= 100 and height >= 100, 'Plot image is too small to be a usable scatter plot.'
        colors = image.getcolors(maxcolors=width * height)
        assert colors is None or len(colors) >= 16, 'Plot image lacks meaningful rendered content.'
        extrema = ImageStat.Stat(image).extrema
        assert any(low != high for low, high in extrema), 'Plot image is blank.'


if __name__ == '__main__':
    test_training_data_csv()
    test_report_json()
    test_plot_png()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
