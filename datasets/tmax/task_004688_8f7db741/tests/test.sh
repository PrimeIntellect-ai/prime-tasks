#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import hashlib
import os
import random
import re
import secrets
import stat
import struct
import subprocess
import zlib
from pathlib import Path

SCRIPT = Path('/home/user/pipeline.sh')
SIM = Path('/home/user/sim.sh')
BEST = Path('/home/user/best_params.txt')
GRID = Path('/home/user/grid_data.txt')
PLOT = Path('/home/user/plot.gp')
PNG = Path('/home/user/heatmap.png')
OUTPUTS = (BEST, GRID, PLOT, PNG)
VALUES = [i / 2 for i in range(11)]


def remove_outputs():
    for path in OUTPUTS:
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def run_pipeline():
    remove_outputs()
    result = subprocess.run([str(SCRIPT)], capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, (
        f'Pipeline script failed to execute. stdout: {result.stdout} stderr: {result.stderr}'
    )


def query_sim():
    expected = []
    for y in VALUES:
        row = []
        for x in VALUES:
            result = subprocess.run(
                [str(SIM), f'{x:.1f}', f'{y:.1f}'],
                capture_output=True, text=True, timeout=10
            )
            assert result.returncode == 0, f'sim.sh failed for X={x}, Y={y}: {result.stderr}'
            row.append(float(result.stdout.strip()))
        expected.append(row)
    return expected


def read_matrix(expected=None):
    assert GRID.is_file(), f'{GRID} was not created'
    with GRID.open() as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 11, f'Expected 11 rows in {GRID}, found {len(lines)}'
    matrix = []
    for i, line in enumerate(lines):
        cols = line.split()
        assert len(cols) == 11, f'Expected 11 columns in row {i+1} of {GRID}, found {len(cols)}'
        try:
            matrix.append([float(value) for value in cols])
        except ValueError as exc:
            raise AssertionError(f'Non-numeric value in row {i+1} of {GRID}: {exc}')

    # Preserve the original verifier's two explicit assertions.
    val_0_0 = matrix[0][0]
    assert abs(val_0_0 - 81.50) < 0.01, f'Expected 81.50 at Y=0.0, X=0.0, got {val_0_0}'
    val_opt = matrix[7][5]
    assert abs(val_opt - 100.00) < 0.01, f'Expected 100.00 at Y=3.5, X=2.5, got {val_opt}'

    if expected is not None:
        for row in range(11):
            for col in range(11):
                assert abs(matrix[row][col] - expected[row][col]) < 0.011, (
                    f'Wrong grid value at Y={VALUES[row]:.1f}, X={VALUES[col]:.1f}: '
                    f'expected {expected[row][col]}, got {matrix[row][col]}'
                )
    return matrix


def parse_best():
    assert BEST.is_file(), f'{BEST} was not created'
    content = BEST.read_text().strip()
    match = re.fullmatch(
        r'X=([^,\s]+), Y=([^,\s]+), Z=([^,\s]+)', content
    )
    assert match, f'{BEST} does not have the required format: {content!r}'
    try:
        return content, tuple(float(value) for value in match.groups())
    except ValueError:
        raise AssertionError(f'{BEST} contains non-numeric parameter values: {content!r}')


def assert_best_matches(expected):
    content, (actual_x, actual_y, actual_z) = parse_best()
    best_z = max(max(row) for row in expected)
    locations = [
        (VALUES[col], VALUES[row])
        for row in range(11)
        for col in range(11)
        if abs(expected[row][col] - best_z) < 1e-9
    ]
    assert any(abs(actual_x - x) < 1e-9 and abs(actual_y - y) < 1e-9 for x, y in locations), (
        f'Best coordinates in {BEST} are wrong: {content}'
    )
    assert abs(actual_z - best_z) < 0.011, f'Best Z in {BEST} is wrong: {content}'


def inspect_png(path):
    assert path.is_file(), f'{path} was not created'
    data = path.read_bytes()
    png_signature = b'\x89PNG\r\n\x1a\n'
    assert data[:8] == png_signature, f'{path} is not a valid PNG file'

    offset = 8
    chunks = []
    saw_iend = False
    while offset < len(data):
        assert offset + 12 <= len(data), f'{path} has a truncated PNG chunk'
        length = struct.unpack('>I', data[offset:offset+4])[0]
        kind = data[offset+4:offset+8]
        payload_start = offset + 8
        payload_end = payload_start + length
        assert payload_end + 4 <= len(data), f'{path} has a truncated PNG payload'
        payload = data[payload_start:payload_end]
        supplied_crc = struct.unpack('>I', data[payload_end:payload_end+4])[0]
        calculated_crc = zlib.crc32(kind + payload) & 0xffffffff
        assert supplied_crc == calculated_crc, f'{path} has an invalid PNG checksum'
        chunks.append((kind, payload))
        offset = payload_end + 4
        if kind == b'IEND':
            saw_iend = True
            break

    assert saw_iend and offset == len(data), f'{path} is not a complete PNG file'
    ihdr = [payload for kind, payload in chunks if kind == b'IHDR']
    assert len(ihdr) == 1 and len(ihdr[0]) == 13, f'{path} has no valid IHDR chunk'
    width, height = struct.unpack('>II', ihdr[0][:8])
    assert width > 1 and height > 1, f'{path} is not a nontrivial image'
    compressed = b''.join(payload for kind, payload in chunks if kind == b'IDAT')
    assert compressed, f'{path} contains no image data'
    try:
        pixels = zlib.decompress(compressed)
    except zlib.error as exc:
        raise AssertionError(f'{path} contains invalid compressed image data: {exc}')
    assert pixels, f'{path} contains no decoded pixel data'
    palette = b''.join(payload for kind, payload in chunks if kind == b'PLTE')
    return ihdr[0] + palette + pixels


def run_gnuplot_and_inspect():
    try:
        PNG.unlink()
    except FileNotFoundError:
        pass
    result = subprocess.run(
        ['gnuplot', str(PLOT)], cwd='/home/user', capture_output=True, text=True, timeout=60
    )
    assert result.returncode == 0, f'plot.gp failed under Gnuplot: {result.stderr}'
    return inspect_png(PNG)


def check_plot_behavior():
    assert PLOT.is_file(), f'{PLOT} was not created'
    plot_content = PLOT.read_text()
    assert 'grid_data.txt' in plot_content, f"Expected 'grid_data.txt' to be referenced in {PLOT}"
    assert 'heatmap.png' in plot_content, f"Expected 'heatmap.png' to be referenced in {PLOT}"

    # The pipeline itself must have produced a structurally valid PNG.
    inspect_png(PNG)

    original_grid = GRID.read_bytes()
    rendered_original = run_gnuplot_and_inspect()
    try:
        changed = []
        for row in range(11):
            changed.append(' '.join('1000' if (row + col) % 2 else '-1000' for col in range(11)))
        GRID.write_text('\n'.join(changed) + '\n')
        rendered_changed = run_gnuplot_and_inspect()
        assert rendered_changed != rendered_original, (
            'Running plot.gp produced the same pixels after grid_data.txt changed; '
            'the script does not generate the heatmap from the grid data'
        )
    finally:
        GRID.write_bytes(original_grid)
        run_gnuplot_and_inspect()


def test_pipeline_script_exists_and_executable():
    assert SCRIPT.is_file(), f'Pipeline script not found at {SCRIPT}'
    assert os.access(SCRIPT, os.X_OK), f'Pipeline script at {SCRIPT} is not executable'
    first_line = SCRIPT.open('rb').readline().decode('utf-8', errors='replace').strip()
    assert re.search(r'^#!.*(?:/|\b)bash(?:\s|$)', first_line), 'pipeline.sh must be a Bash script'


def test_pipeline_execution_and_outputs():
    # First retain the original checks and extend them to every matrix entry.
    expected = query_sim()
    run_pipeline()

    content, _ = parse_best()
    normalized_content = ' '.join(content.split())
    assert 'X=2.5' in normalized_content, f'Expected X=2.5 in {BEST}, got: {content}'
    assert 'Y=3.5' in normalized_content, f'Expected Y=3.5 in {BEST}, got: {content}'
    assert '100.00' in normalized_content or '100' in normalized_content, (
        f'Expected Z=100.00 in {BEST}, got: {content}'
    )
    read_matrix(expected)
    assert_best_matches(expected)
    check_plot_behavior()

    # Replace the black box temporarily with an unpredictable one. This verifies
    # that pipeline.sh really executes every grid point and propagates all results.
    original_sim = SIM.read_bytes()
    original_mode = stat.S_IMODE(SIM.stat().st_mode)
    log_path = Path('/tmp/pipeline_sim_calls_' + secrets.token_hex(8))
    rng = random.SystemRandom()
    peak_x = rng.choice([i / 2 for i in range(1, 10)])
    peak_y = rng.choice([i / 2 for i in range(1, 10)])
    ax = rng.choice([1.25, 1.75, 2.25, 2.75])
    ay = rng.choice([1.50, 2.00, 2.50, 3.00])
    token = secrets.token_hex(12)
    replacement = f'''#!/bin/bash
if [ "$#" -ne 2 ]; then exit 1; fi
printf '%s\\t%s\\n' "$1" "$2" >> {log_path}
awk -v x="$1" -v y="$2" 'BEGIN {{ printf "%.2f\\n", 500 - {ax}*(x-{peak_x})^2 - {ay}*(y-{peak_y})^2 }}'
# {token}
'''

    try:
        SIM.write_text(replacement)
        os.chmod(SIM, 0o755)
        dynamic_expected = query_sim()
        log_path.write_text('')
        run_pipeline()

        calls = []
        for line in log_path.read_text().splitlines():
            fields = line.split('\t')
            assert len(fields) == 2, f'Malformed sim.sh invocation log line: {line!r}'
            calls.append((float(fields[0]), float(fields[1])))
        counts = collections.Counter(calls)
        required = {(x, y) for y in VALUES for x in VALUES}
        assert set(counts) == required, (
            'pipeline.sh did not invoke sim.sh on exactly the required X/Y grid; '
            f'missing={sorted(required-set(counts))}, extra={sorted(set(counts)-required)}'
        )
        assert all(counts[pair] >= 1 for pair in required)

        matrix = []
        with GRID.open() as f:
            lines = [line.strip() for line in f if line.strip()]
        assert len(lines) == 11, f'Expected 11 rows in dynamic {GRID}, found {len(lines)}'
        for i, line in enumerate(lines):
            cols = line.split()
            assert len(cols) == 11, f'Expected 11 columns in dynamic row {i+1}, found {len(cols)}'
            matrix.append([float(value) for value in cols])
        for row in range(11):
            for col in range(11):
                assert abs(matrix[row][col] - dynamic_expected[row][col]) < 0.011, (
                    f'Dynamic grid value wrong at Y={VALUES[row]:.1f}, X={VALUES[col]:.1f}'
                )
        assert_best_matches(dynamic_expected)
        check_plot_behavior()
    finally:
        SIM.write_bytes(original_sim)
        os.chmod(SIM, original_mode)
        try:
            log_path.unlink()
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
