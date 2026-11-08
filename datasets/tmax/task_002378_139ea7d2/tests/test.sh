#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import math
import os
import re
import secrets
import shutil
import subprocess

import numpy as np
from scipy.integrate import solve_ivp
from scipy.linalg import svd

PROJECT = '/home/user/sim_project'
SO_PATH = os.path.join(PROJECT, 'libspectrum.so')
SCRIPT_PATH = os.path.join(PROJECT, 'simulate.py')
OUTPUT_PATH = os.path.join(PROJECT, 'singular_values.txt')
EXPECTED_ORIGINAL = [93.7547, 36.1772, 8.4116]


def read_output():
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, 'r') as f:
        content = f.read().strip()
    assert content, f"{OUTPUT_PATH} is empty."
    values_str = content.split(',')
    assert len(values_str) == 3, f"Expected 3 comma-separated values, got {len(values_str)}: {content}"
    try:
        values = [float(v.strip()) for v in values_str]
    except ValueError:
        assert False, f"Could not parse values in {OUTPUT_PATH} as floats. Content: {content}"
    assert re.fullmatch(r'-?\d+\.\d{4},-?\d+\.\d{4},-?\d+\.\d{4}', content), \
        f"Output is not one line of three comma-separated values formatted to exactly 4 decimal places: {content}"
    return content, values


def assert_original_output():
    _, values = read_output()
    for i, (val, exp) in enumerate(zip(values, EXPECTED_ORIGINAL)):
        assert math.isclose(val, exp, abs_tol=0.005), \
            f"Singular value {i+1} is {val}, expected approximately {exp}."


def run_script():
    result = subprocess.run(
        ['python3', SCRIPT_PATH], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120
    )
    assert result.returncode == 0, \
        f"simulate.py failed with exit code {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"


def resolved_calls(tree):
    names = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                names[alias.asname or alias.name.split('.')[0]] = alias.name
        elif isinstance(node, ast.ImportFrom) and node.module:
            for alias in node.names:
                names[alias.asname or alias.name] = node.module + '.' + alias.name

    def resolve(node):
        if isinstance(node, ast.Name):
            return names.get(node.id, node.id)
        if isinstance(node, ast.Attribute):
            base = resolve(node.value)
            return base + '.' + node.attr if base else node.attr
        return ''

    return [resolve(node.func) for node in ast.walk(tree) if isinstance(node, ast.Call)]


def test_libspectrum_compiled():
    """Test that libspectrum.so has been compiled and is executable."""
    assert os.path.isfile(SO_PATH), f"{SO_PATH} was not compiled or is missing."
    with open(SO_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{SO_PATH} is not an ELF shared library."

    try:
        lib = ctypes.CDLL(SO_PATH)
        get_spectrum = lib.get_spectrum
    except (OSError, AttributeError) as exc:
        assert False, f"Could not load get_spectrum from {SO_PATH}: {exc}"

    get_spectrum.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_double), ctypes.c_int]
    get_spectrum.restype = None
    length = 257
    for comp_id, center in enumerate((50.0, 100.0, 150.0)):
        out = (ctypes.c_double * length)()
        get_spectrum(comp_id, out, length)
        expected = [math.exp(-((i - center) ** 2) / 200.0) for i in range(length)]
        assert np.allclose(np.ctypeslib.as_array(out), expected, rtol=1e-12, atol=1e-14), \
            f"get_spectrum returned incorrect values for component {comp_id}."


def test_singular_values_output():
    """Test that singular_values.txt exists and contains the correct values."""
    assert_original_output()


def test_simulation_script_and_behavior():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, 'r') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        assert False, f"simulate.py is not valid Python: {exc}"

    calls = resolved_calls(tree)
    assert any(name == 'scipy.integrate.solve_ivp' for name in calls), \
        "simulate.py must call scipy.integrate.solve_ivp."
    assert any(name == 'scipy.linalg.svd' for name in calls), \
        "simulate.py must call scipy.linalg.svd."
    assert any(name.startswith('ctypes.') and name.rsplit('.', 1)[-1] in ('CDLL', 'PyDLL', 'LoadLibrary') for name in calls), \
        "simulate.py must load the spectral library using ctypes."

    if os.path.exists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    run_script()
    assert_original_output()

    backup = '/tmp/libspectrum.original.so'
    challenge_c = '/tmp/spectrum_challenge.c'
    challenge_so = '/tmp/libspectrum.challenge.so'
    shutil.copy2(SO_PATH, backup)

    nonce = secrets.randbelow(1000000)
    centers = [31.0 + (nonce % 7), 96.0 + ((nonce // 7) % 9), 164.0 - ((nonce // 63) % 8)]
    widths = [117.0 + (nonce % 13), 241.0 + ((nonce // 13) % 17), 359.0 + ((nonce // 221) % 19)]
    amps = [0.73 + (nonce % 11) / 100.0, 1.11 + ((nonce // 11) % 13) / 100.0, 1.47 + ((nonce // 143) % 17) / 100.0]

    c_source = '''#include <math.h>
void get_spectrum(int comp_id, double* out_array, int length) {
    const double centers[3] = {%.17g, %.17g, %.17g};
    const double widths[3] = {%.17g, %.17g, %.17g};
    const double amps[3] = {%.17g, %.17g, %.17g};
    for (int i = 0; i < length; ++i) {
        double d = (double)i - centers[comp_id];
        out_array[i] = amps[comp_id] * exp(-(d*d) / widths[comp_id]);
    }
}
''' % tuple(centers + widths + amps)

    with open(challenge_c, 'w') as f:
        f.write(c_source)
    subprocess.run(['gcc', '-shared', '-fPIC', challenge_c, '-o', challenge_so, '-lm'], check=True)

    challenge_content = None
    try:
        os.replace(challenge_so, SO_PATH)
        if os.path.exists(OUTPUT_PATH):
            os.unlink(OUTPUT_PATH)
        run_script()
        challenge_content, challenge_values = read_output()
    finally:
        shutil.copy2(backup, SO_PATH)
        if os.path.exists(OUTPUT_PATH):
            os.unlink(OUTPUT_PATH)
        run_script()

    t_eval = np.linspace(0.0, 10.0, 100)
    def kinetics(t, y):
        a, b, c = y
        return [-0.5*a, 0.5*a - 0.2*b, 0.2*b]
    concentrations = solve_ivp(kinetics, (0.0, 10.0), [1.0, 0.0, 0.0], t_eval=t_eval).y.T
    x = np.arange(200, dtype=float)
    spectra = np.vstack([
        amps[i] * np.exp(-((x - centers[i]) ** 2) / widths[i]) for i in range(3)
    ])
    expected = svd(concentrations @ spectra)[1][:3]
    expected_text = ','.join(f'{value:.4f}' for value in expected)
    assert challenge_content == expected_text, \
        f"simulate.py did not recompute the challenged library's result: got {challenge_content}, expected {expected_text}"

    assert_original_output()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
