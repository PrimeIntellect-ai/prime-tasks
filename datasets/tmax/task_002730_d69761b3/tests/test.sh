#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import os
import secrets
import stat
import subprocess
from pathlib import Path

from PIL import Image
from scipy import stats

HOME = Path('/home/user')
RAW = HOME / 'raw_latency_data.csv'
SUMMARY = HOME / 'summary.csv'
PVALUE = HOME / 'p_value.txt'
PLOT = HOME / 'latency_plot.png'
ETL = HOME / 'etl.sh'
ANALYZE = HOME / 'analyze_and_plot.py'
PIPELINE = HOME / 'run_pipeline.sh'
OUTPUTS = (SUMMARY, PVALUE, PLOT)


def run(cmd):
    env = os.environ.copy()
    env.pop('DISPLAY', None)
    subprocess.run(cmd, cwd=HOME, env=env, check=True, timeout=45)


def remove_outputs():
    for path in OUTPUTS:
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def assert_executable(path):
    assert path.is_file(), f'Missing file: {path}'
    assert path.stat().st_mode & stat.S_IXUSR, f'File {path} is not executable'


def expected_summary(groups):
    return {f'{name},{sum(values) / len(values):.2f}' for name, values in groups.items()}


def check_summary(groups):
    assert SUMMARY.is_file(), f'Missing file: {SUMMARY}'
    lines = [line.strip() for line in SUMMARY.read_text().splitlines() if line.strip()]
    assert len(lines) >= 3, f'Expected at least 3 lines in {SUMMARY} (header + 2 groups), found {len(lines)}'
    assert lines[0] == 'server_group,avg_latency', f'Incorrect header in {SUMMARY}: {lines[0]}'
    data_lines = set(lines[1:])
    expected_lines = expected_summary(groups)
    assert expected_lines.issubset(data_lines), f'Expected data {expected_lines} not found in {SUMMARY}. Found: {data_lines}'
    assert len(lines) == 3, f'Expected exactly a header and two data rows in {SUMMARY}, found: {lines}'
    assert len(data_lines) == 2 and data_lines == expected_lines, f'Unexpected rows in {SUMMARY}: {data_lines}'


def expected_p(groups):
    value = stats.ttest_ind(groups['A'], groups['B']).pvalue
    return f'{value:.4f}'


def check_p_value(groups, literal=None):
    assert PVALUE.is_file(), f'Missing file: {PVALUE}'
    content = PVALUE.read_text().strip()
    if literal is not None:
        assert content == literal, f"Expected p-value '{literal}' in {PVALUE}, found '{content}'"
    expected = expected_p(groups)
    assert content == expected, f"Expected derived p-value '{expected}' in {PVALUE}, found '{content}'"
    float(content)


def check_plot():
    assert PLOT.is_file(), f'Missing file: {PLOT}'
    with PLOT.open('rb') as f:
        magic = f.read(4)
    assert magic == b'\x89PNG', f'File {PLOT} is not a valid PNG file (invalid magic bytes)'

    with Image.open(PLOT) as image:
        image.load()
        assert image.format == 'PNG', f'{PLOT} is not a decodable PNG image'
        assert image.width >= 100 and image.height >= 100, f'Plot is unexpectedly small: {image.size}'
        rgba = image.convert('RGBA')
        extrema = rgba.getextrema()
        assert any(lo != hi for lo, hi in extrema[:3]), 'Plot image is blank or a single color'
        return hashlib.sha256(rgba.tobytes()).hexdigest()


def write_dataset(groups):
    rows = ['timestamp,server_group,latency_ms']
    index = 0
    for group in ('A', 'B'):
        for value in groups[group]:
            rows.append(f'2026-01-01T00:{index:02d}:00Z,{group},{value}')
            index += 1
    RAW.write_text('\n'.join(rows) + '\n')


def make_probe():
    rng = secrets.SystemRandom()
    a = [float(rng.randrange(35, 115)) + rng.choice((0.1, 0.3, 0.7)) for _ in range(6)]
    b = [float(rng.randrange(125, 245)) + rng.choice((0.2, 0.4, 0.8)) for _ in range(7)]
    return {'A': a, 'B': b}


assert_executable(PIPELINE)
assert_executable(ETL)
assert ANALYZE.is_file(), f'Missing file: {ANALYZE}'

# The desktop-only plt.show() call must actually have been removed.
tree = ast.parse(ANALYZE.read_text(), filename=str(ANALYZE))
for node in ast.walk(tree):
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
        if node.func.attr == 'show' and isinstance(node.func.value, ast.Name) and node.func.value.id == 'plt':
            raise AssertionError('analyze_and_plot.py still calls plt.show()')

original_raw = RAW.read_bytes()
original_groups = {
    'A': [102.5, 98.1, 105.0, 101.2, 99.5],
    'B': [115.2, 110.8, 118.5, 112.4, 114.1],
}

try:
    # Execute the submitted master pipeline from a clean state and retain all
    # assertions made by the original verifier.
    remove_outputs()
    run([str(PIPELINE)])
    check_summary(original_groups)
    check_p_value(original_groups, literal='0.0001')
    original_plot_hash = check_plot()

    # Exercise etl.sh itself on an unpredictable dataset, so fixed output files
    # or calculations tied to the setup data cannot pass.
    probe = make_probe()
    write_dataset(probe)
    try:
        SUMMARY.unlink()
    except FileNotFoundError:
        pass
    run([str(ETL)])
    check_summary(probe)

    # Exercise the repaired Python artifact itself and verify a fully decoded,
    # nonblank plot whose rendered pixels change with the input data.
    for path in (PVALUE, PLOT):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    run(['python3', str(ANALYZE)])
    check_p_value(probe)
    probe_plot_hash = check_plot()
    assert probe_plot_hash != original_plot_hash, 'Plot pixels did not change when the input data changed'

    # Finally exercise orchestration on another unpredictable input after all
    # products have been deleted.
    probe2 = make_probe()
    write_dataset(probe2)
    remove_outputs()
    run([str(PIPELINE)])
    check_summary(probe2)
    check_p_value(probe2)
    second_plot_hash = check_plot()
    assert second_plot_hash != original_plot_hash, 'Pipeline produced a fixed plot independent of its input'
finally:
    RAW.write_bytes(original_raw)

# Leave the requested final state corresponding to the supplied raw dataset.
remove_outputs()
run([str(PIPELINE)])
check_summary(original_groups)
check_p_value(original_groups, literal='0.0001')
check_plot()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
