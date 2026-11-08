#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

import pytest

OUTPUT = Path('/home/user/imputed_data.json')
EXPECTED = [10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 22.0, 24.0, 26.0, 28.0, 30.0]


def test_imputed_data_json():
    output_path = '/home/user/imputed_data.json'

    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"Output path {output_path} is not a file."

    with open(output_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} does not contain valid JSON.")

    assert isinstance(data, list), f"JSON root must be a list, but got {type(data).__name__}."
    assert len(data) == 11, f"Expected 11 data points, but got {len(data)}."

    expected_y = [10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 22.0, 24.0, 26.0, 28.0, 30.0]

    mse = 0.0
    for i, item in enumerate(data):
        assert isinstance(item, dict), f"Item at index {i} is not a dictionary."
        assert 'time' in item, f"Item at index {i} is missing 'time' key."
        assert 'value' in item, f"Item at index {i} is missing 'value' key."

        time_val = item['time']
        value_val = item['value']

        assert isinstance(time_val, int), f"Time at index {i} must be an integer."
        assert isinstance(value_val, (int, float)), f"Value at index {i} must be a number."
        assert time_val == i, f"Expected time {i} at index {i}, but got {time_val}."

        mse += (value_val - expected_y[i]) ** 2

    mse /= len(data)

    threshold = 0.5
    assert mse <= threshold, f"MSE is {mse:.4f}, which exceeds the threshold of {threshold}."


def read_and_check(path, expected, mse_limit=0.003):
    raw = Path(path).read_text()
    data = json.loads(raw)
    assert isinstance(data, list) and len(data) == 11
    assert len(re.findall(r'"value"\s*:\s*-?\d+\.\d(?!\d)', raw)) == 11, \
        'Every value must be formatted with exactly one decimal place.'
    mse = 0.0
    for i, item in enumerate(data):
        assert isinstance(item, dict)
        assert set(item) == {'time', 'value'}
        assert type(item['time']) is int and item['time'] == i
        assert isinstance(item['value'], (int, float)) and not isinstance(item['value'], bool)
        mse += (float(item['value']) - expected[i]) ** 2
    mse /= 11
    assert mse <= mse_limit, f'Generated output MSE {mse} exceeds {mse_limit}'


def source_groups():
    files = []
    for root in ('/home/user', '/app', '/tmp'):
        for directory, dirs, names in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {'.git', '__pycache__'}]
            for name in names:
                if name.endswith('.c'):
                    files.append(Path(directory) / name)
    groups = []
    for path in files:
        groups.append((path.parent, [path]))
    for directory in sorted({p.parent for p in files}):
        members = sorted(p for p in files if p.parent == directory)
        if len(members) > 1:
            groups.append((directory, members))
    return groups


def input_aliases(source, cwd, explicit):
    aliases = {
        Path(explicit),
        cwd / 'ocr_output.txt', cwd / 'ocr.txt', cwd / 'output.txt',
        Path('/home/user/ocr_output.txt'), Path('/home/user/ocr.txt'),
        Path('/app/ocr_output.txt'), Path('/app/ocr.txt'),
        Path('/tmp/ocr_output.txt'), Path('/tmp/ocr.txt'),
    }
    literals = re.findall(r'fopen\s*\(\s*"([^"\\]+)"', source)
    literals += [s for s in re.findall(r'"([^"\\]+)"', source)
                 if 'ocr' in s.lower() and '%' not in s]
    for literal in literals:
        p = Path(literal)
        if p.suffix.lower() in {'.json', '.png', '.jpg', '.jpeg'}:
            continue
        p = p if p.is_absolute() else cwd / p
        try:
            resolved = p.resolve()
        except OSError:
            continue
        if any(str(resolved).startswith(prefix) for prefix in ('/home/user/', '/app/', '/tmp/')):
            aliases.add(resolved)
    return aliases


def install_input(paths, content):
    for path in paths:
        if path == Path('/app/data_table.png') or path == OUTPUT:
            continue
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        except (OSError, UnicodeError):
            pass


def generated_path(preferred):
    for path in (Path(preferred), OUTPUT):
        if path.is_file():
            return path
    return None


def test_c_ocr_regex_interpolation_workflow():
    original = OUTPUT.read_bytes()
    groups = source_groups()
    assert groups, 'No C source file was found under /home/user, /app, or /tmp.'

    ocr = subprocess.run(
        ['tesseract', '/app/data_table.png', 'stdout'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert ocr.returncode == 0 and ocr.stdout.strip(), 'Tesseract failed to extract OCR text.'

    nonce = int.from_bytes(os.urandom(2), 'big')
    base1 = 40.0 + (nonce % 100) / 10.0
    step1 = float(2 + nonce % 5)
    base2 = 75.0 + ((nonce // 7) % 100) / 10.0
    step2 = float(3 + (nonce // 11) % 6)

    def synthetic(base, step):
        missing = {2, 5, 8}
        lines = ['Historical Sensor Export', 'Time Sensor_Y', 'junk that must be ignored']
        for x in range(11):
            if x in missing:
                lines.append(f'{x}    #ERR')
            else:
                lines.append(f'{x}    {base + step*x:.1f}')
        lines += ['footer noise', 'not_a_pair']
        return '\n'.join(lines) + '\n', [base + step*x for x in range(11)]

    cases = [
        (ocr.stdout, EXPECTED, 0.5),
        (*synthetic(base1, step1), 0.003),
        (*synthetic(base2, step2), 0.003),
    ]
    failures = []

    try:
        with tempfile.TemporaryDirectory(prefix='verify_c_') as td:
            td = Path(td)
            for group_index, (cwd, sources) in enumerate(groups):
                combined = '\n'.join(p.read_text(errors='ignore') for p in sources)
                if not re.search(r'#\s*include\s*[<"]regex\.h[>"]', combined):
                    continue
                if not re.search(r'\bregcomp\s*\(', combined) or not re.search(r'\bregexec\s*\(', combined):
                    continue
                if not re.search(r'\b(?:f?printf|snprintf)\s*\(', combined):
                    continue
                if not re.search(r'%[^"\n]*\.1f', combined):
                    continue
                if '"time"' not in combined and '\\"time\\"' not in combined:
                    continue

                exe = td / f'candidate_{group_index}'
                build = subprocess.run(
                    ['gcc', '-std=c11', '-O2', *map(str, sources), '-lm', '-o', str(exe)],
                    text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
                )
                if build.returncode != 0:
                    failures.append(build.stderr[-500:])
                    continue

                supplied_input = td / f'input_{group_index}.txt'
                supplied_output = td / f'output_{group_index}.json'
                aliases = input_aliases(combined, cwd, supplied_input)
                modes = [
                    ([str(exe), str(supplied_input), str(supplied_output)], False),
                    ([str(exe), str(supplied_input)], False),
                    ([str(exe)], True),
                    ([str(exe)], False),
                ]

                for command, use_stdin in modes:
                    mode_ok = True
                    for content, expected, limit in cases:
                        install_input(aliases, content)
                        for out in (supplied_output, OUTPUT):
                            try:
                                out.unlink()
                            except FileNotFoundError:
                                pass
                        env = os.environ.copy()
                        env.update({'OCR_INPUT': str(supplied_input), 'JSON_OUTPUT': str(supplied_output)})
                        try:
                            run = subprocess.run(
                                command, cwd=str(cwd), env=env,
                                input=content if use_stdin else None,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=10
                            )
                            out = generated_path(supplied_output)
                            if run.returncode != 0 or out is None:
                                mode_ok = False
                                break
                            read_and_check(out, expected, limit)
                        except Exception as exc:
                            failures.append(str(exc))
                            mode_ok = False
                            break
                    if mode_ok:
                        return

        pytest.fail('No submitted C program using POSIX regex regenerated correct JSON from Tesseract OCR and independently generated interpolation cases. ' + ' '.join(failures[-3:]))
    finally:
        OUTPUT.write_bytes(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
