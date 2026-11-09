#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import math
import zlib
import struct
import shutil
import subprocess
from pathlib import Path

import h5py
import numpy as np

HOME = Path('/home/user')
SOURCE = HOME / 'fit_model.c'
DATA = HOME / 'data.h5'
COEFFS = HOME / 'coeffs.txt'
PLOT = HOME / 'fit.png'
BINARY = Path('/tmp/fit_model_verified')


def read_coeffs(require_format=True):
    assert COEFFS.is_file(), f'Missing required output file: {COEFFS}'
    lines = [line.strip() for line in COEFFS.read_text().splitlines() if line.strip()]
    assert len(lines) == 4, f'Expected 4 coefficients in {COEFFS}, but found {len(lines)}'
    if require_format:
        pattern = re.compile(r'^[+-]?(?:\d+\.\d{6})$')
        for i, line in enumerate(lines):
            assert pattern.fullmatch(line), f'Coefficient at line {i+1} is not formatted to 6 decimal places: {line}'
    try:
        values = np.array([float(line) for line in lines], dtype=float)
    except ValueError as exc:
        raise AssertionError(f'Invalid coefficient in {COEFFS}: {exc}')
    assert np.all(np.isfinite(values)), 'All coefficients must be finite'
    return values


def write_hdf5(x, y):
    with h5py.File(DATA, 'w') as f:
        f.create_dataset('x', data=np.asarray(x, dtype=np.float64), dtype='float64')
        f.create_dataset('y', data=np.asarray(y, dtype=np.float64), dtype='float64')


def run_model():
    if COEFFS.exists():
        COEFFS.unlink()
    result = subprocess.run([str(BINARY)], cwd=str(HOME), text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert result.returncode == 0, f'Compiled program failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    return read_coeffs()


def restore_original_data():
    rng = np.random.RandomState(42)
    x = np.linspace(10, 15, 50)
    y = 1.0 - 0.5*x + 0.1*x**2 + 0.02*x**3 + rng.normal(0, 0.5, 50)
    write_hdf5(x, y)


def test_fit_model_c_exists():
    """Verify that the C source code file exists."""
    assert SOURCE.is_file(), f'Missing required C source file: {SOURCE}'


def test_c_program_compiles_uses_required_libraries_and_handles_derived_inputs():
    text = SOURCE.read_text(errors='replace')
    assert text.strip(), 'fit_model.c is empty'
    lower = text.lower()
    assert 'h5fopen' in lower and 'h5dopen' in lower, 'C program must read the HDF5 file and datasets using HDF5 APIs'
    assert re.search(r'\bgsl_multifit_linear(?:_svd)?\s*\(', lower), 'C program must call a GSL SVD-based linear multifit routine'

    h5cc = shutil.which('h5cc')
    assert h5cc, 'h5cc is unavailable; the required HDF5 development tools were not installed'
    compile_result = subprocess.run(
        [h5cc, '-std=c11', '-O2', str(SOURCE), '-o', str(BINARY), '-lgsl', '-lgslcblas', '-lm'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    assert compile_result.returncode == 0, f'fit_model.c did not compile:\n{compile_result.stdout}\n{compile_result.stderr}'
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), 'Compilation did not produce an executable'

    symbols = subprocess.run(['nm', '-u', str(BINARY)], text=True, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, timeout=10).stdout.lower()
    assert 'h5fopen' in symbols and 'h5dopen' in symbols, 'Compiled executable does not use the HDF5 read APIs'
    assert 'gsl_multifit_linear' in symbols, 'Compiled executable does not use GSL linear multifit'

    rng = np.random.default_rng()
    challenges = []
    x1 = np.sort(rng.uniform(9.5, 15.5, 50))
    y1 = 2.7 - 0.83*x1 + 0.145*x1**2 - 0.0065*x1**3 + rng.normal(0, 0.08, 50)
    challenges.append((x1, y1))
    x2 = np.sort(rng.uniform(-3.5, 4.0, 50))
    y2 = -1.2 + 2.1*x2 - 0.37*x2**2 + 0.091*x2**3 + rng.normal(0, 0.05, 50)
    challenges.append((x2, y2))

    try:
        for x, y in challenges:
            write_hdf5(x, y)
            actual = run_model()
            design = np.column_stack((np.ones_like(x), x, x*x, x*x*x))
            expected = np.linalg.lstsq(design, y, rcond=None)[0]
            assert np.allclose(actual, expected, rtol=0, atol=5e-4), \
                f'Program output does not match the SVD/lstsq solution. Expected {expected}, got {actual}'
    finally:
        restore_original_data()

    run_model()


def test_coeffs_txt_correct():
    """Verify that coeffs.txt exists and contains the correct coefficients."""
    file_path = '/home/user/coeffs.txt'
    assert os.path.isfile(file_path), f'Missing required output file: {file_path}'

    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f'Expected 4 coefficients in {file_path}, but found {len(lines)}'

    expected_coeffs = [5.766103, -1.696156, 0.194723, 0.017773]
    tolerance = 0.0005

    for i, (line, expected) in enumerate(zip(lines, expected_coeffs)):
        try:
            val = float(line)
        except ValueError:
            assert False, f'Coefficient at line {i+1} is not a valid float: {line}'

        assert math.isclose(val, expected, abs_tol=tolerance), \
            f'Coefficient c{i} mismatch: expected {expected}, got {val} (tolerance {tolerance})'


def validate_png(path):
    data = path.read_bytes()
    assert data.startswith(b'\x89PNG\r\n\x1a\n'), f'{path} is not a valid PNG file based on its header.'
    assert len(data) > 3000, 'fit.png is too small to be a substantive plot'
    pos = 8
    width = height = None
    saw_idat = saw_iend = False
    compressed = bytearray()
    while pos < len(data):
        assert pos + 12 <= len(data), 'Truncated PNG chunk'
        length = struct.unpack('>I', data[pos:pos+4])[0]
        kind = data[pos+4:pos+8]
        end = pos + 12 + length
        assert end <= len(data), 'Truncated PNG chunk data'
        payload = data[pos+8:pos+8+length]
        stored_crc = struct.unpack('>I', data[pos+8+length:end])[0]
        assert (zlib.crc32(kind + payload) & 0xffffffff) == stored_crc, 'PNG chunk CRC mismatch'
        if kind == b'IHDR':
            assert length == 13, 'Invalid PNG IHDR'
            width, height = struct.unpack('>II', payload[:8])
        elif kind == b'IDAT':
            saw_idat = True
            compressed.extend(payload)
        elif kind == b'IEND':
            saw_iend = True
            assert length == 0, 'Invalid PNG IEND'
            break
        pos = end
    assert width is not None and width >= 200 and height >= 150, 'Plot image dimensions are unreasonably small'
    assert saw_idat and saw_iend, 'PNG is missing image data or its end marker'
    try:
        pixels = zlib.decompress(bytes(compressed))
    except zlib.error as exc:
        raise AssertionError(f'PNG image data is corrupt: {exc}')
    assert len(pixels) > width * height, 'PNG contains insufficient decoded image data'
    assert len(set(pixels)) >= 16, 'PNG appears blank or lacks plotted visual content'


def test_visualization_script_runs_and_creates_plot():
    scripts = []
    combined = ''
    for path in HOME.rglob('*'):
        if path.is_file() and path.suffix.lower() in ('.py', '.gp', '.gnuplot'):
            try:
                content = path.read_text(errors='replace')
            except OSError:
                continue
            if 'fit.png' in content or 'data.h5' in content:
                scripts.append((path, content))
                combined += '\n' + content.lower()

    assert scripts, 'Missing the required Python or gnuplot visualization script'
    assert 'fit.png' in combined and 'data.h5' in combined, 'Visualization script must read the dataset and write fit.png'
    has_scatter = 'scatter' in combined or 'with points' in combined or re.search(r"plot\s*\([^\n]*['\"](?:o|\.)", combined)
    has_line = 'plot' in combined or 'with lines' in combined
    assert has_scatter and has_line, 'Visualization script must contain both a data scatter/points plot and a fitted line plot'

    if PLOT.exists():
        PLOT.unlink()
    errors = []
    for path, content in scripts:
        if path.suffix.lower() == '.py':
            command = ['python3', str(path)]
        else:
            gnuplot = shutil.which('gnuplot')
            if not gnuplot:
                errors.append('gnuplot is not installed')
                continue
            command = [gnuplot, str(path)]
        try:
            result = subprocess.run(command, cwd=str(HOME), text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=60)
            if result.returncode != 0:
                errors.append(f'{path}: {result.stderr[-500:]}')
        except (subprocess.TimeoutExpired, OSError) as exc:
            errors.append(f'{path}: {exc}')
        if PLOT.is_file():
            try:
                validate_png(PLOT)
                return
            except AssertionError as exc:
                errors.append(f'{path}: {exc}')
                PLOT.unlink(missing_ok=True)
    assert False, 'No visualization script successfully generated a substantive fit.png: ' + '; '.join(errors)


def test_fit_png_exists_and_valid():
    """Verify that fit.png exists and is a valid PNG image."""
    file_path = '/home/user/fit.png'
    assert os.path.isfile(file_path), f'Missing required plot file: {file_path}'
    assert os.path.getsize(file_path) > 0, f'The plot file {file_path} is empty.'

    with open(file_path, 'rb') as f:
        header = f.read(8)

    png_magic = b'\x89PNG\r\n\x1a\n'
    assert header == png_magic, f'{file_path} is not a valid PNG file based on its header.'
    validate_png(Path(file_path))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
