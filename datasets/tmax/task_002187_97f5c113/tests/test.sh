#!/bin/bash
mkdir -p /logs/verifier

verify() {
    project_dir=/home/user/mathparser_mobile

    # The instruction forbids modifying the C sources or supplied test suite.
    python3 - <<'PY' || return 1
from pathlib import Path

project = Path('/home/user/mathparser_mobile')
expected = {
    'src/ops.h': b'''#ifndef OPS_H
#define OPS_H
double add(double a, double b) { return a + b; }
double mul(double a, double b) { return a * b; }
#endif
''',
    'src/parser.c': b'''#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <math.h>
#include "ops.h"

static PyObject* evaluate_expression(PyObject* self, PyObject* args) {
    double a, b;
    if (!PyArg_ParseTuple(args, "dd", &a, &b)) {
        return NULL;
    }
    // simple math op combining add, mul, and pow (requires libm)
    double result = pow(add(a, b), 2) + mul(a, b);
    return PyFloat_FromDouble(result);
}

static PyMethodDef MathParserMethods[] = {
    {"evaluate",  evaluate_expression, METH_VARARGS, "Evaluate a math expression."},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef mathparsermodule = {
    PyModuleDef_HEAD_INIT, "mathparser", NULL, -1, MathParserMethods
};

PyMODINIT_FUNC PyInit_mathparser(void) {
    return PyModule_Create(&mathparsermodule);
}
''',
    'test_parser.py': b'''import pytest
from hypothesis import given, strategies as st
import mathparser

@given(st.floats(min_value=-100, max_value=100), st.floats(min_value=-100, max_value=100))
def test_evaluate(a, b):
    # Expected: (a+b)^2 + (a*b)
    expected = ((a + b) ** 2) + (a * b)
    result = mathparser.evaluate(a, b)
    assert abs(result - expected) < 1e-6
''',
}
for relative, wanted in expected.items():
    path = project / relative
    assert path.is_file(), f'{path} is missing'
    assert path.read_bytes() == wanted, f'{path} was modified'
PY

    # Execute setup.py while capturing its Extension definition, ensuring the
    # requested source and math-library linkage remain configured.
    python3 - <<'PY' || return 1
import os
import runpy
import setuptools

project = '/home/user/mathparser_mobile'
os.chdir(project)
captured = {}
setuptools.setup = lambda **kwargs: captured.update(kwargs)
runpy.run_path('setup.py', run_name='__main__')
extensions = captured.get('ext_modules', [])
assert extensions, 'setup.py did not define an extension module'
ext = next((item for item in extensions if item.name == 'mathparser'), None)
assert ext is not None, "setup.py did not define the 'mathparser' extension"
assert 'src/parser.c' in [os.path.normpath(p) for p in ext.sources], 'mathparser is not built from src/parser.c'
assert 'm' in (ext.libraries or []), 'mathparser Extension is not linked with the math library'
PY

    # Force a clean in-place build so a pre-existing or fabricated artifact
    # cannot satisfy the verifier.
    rm -rf "$project_dir/build" || return 1
    find "$project_dir" -maxdepth 1 -type f -name 'mathparser*.so' -delete || return 1
    (cd "$project_dir" && python3 setup.py build_ext --inplace) || return 1

    # setup.py must not alter the protected inputs while building.
    python3 - <<'PY' || return 1
from pathlib import Path
project = Path('/home/user/mathparser_mobile')
expected_ops = b'''#ifndef OPS_H
#define OPS_H
double add(double a, double b) { return a + b; }
double mul(double a, double b) { return a * b; }
#endif
'''
assert (project / 'src/ops.h').read_bytes() == expected_ops
assert b'double result = pow(add(a, b), 2) + mul(a, b);' in (project / 'src/parser.c').read_bytes()
assert b'@given(st.floats(min_value=-100, max_value=100), st.floats(min_value=-100, max_value=100))' in (project / 'test_parser.py').read_bytes()
PY

    # Run the property-based suite requested by the instruction. Disable local
    # conftest files and require the supplied test to actually pass, not skip.
    pytest_out=$(cd /tmp && python3 -m pytest /home/user/mathparser_mobile/test_parser.py --noconftest -q 2>&1) || {
        printf '%s\n' "$pytest_out"
        return 1
    }
    printf '%s\n' "$pytest_out"
    printf '%s\n' "$pytest_out" | grep -Eq '(^|[[:space:]])1 passed([[:space:]]|$)' || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.machinery
import math
import os
import random
import sys
import pytest

def test_success_log_exists_and_correct():
    log_path = "/home/user/success.log"
    assert os.path.exists(log_path), f"File {log_path} does not exist. Did you create it?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "BUILD SUCCESS", f"Expected '{log_path}' to contain 'BUILD SUCCESS', but got '{content}'."

def test_extension_built_inplace():
    project_dir = "/home/user/mathparser_mobile"
    assert os.path.exists(project_dir), f"Directory {project_dir} is missing."

    so_files = glob.glob(os.path.join(project_dir, "mathparser*.so"))
    assert len(so_files) > 0, "No compiled C extension (.so file) found in the project directory. Did you build with --inplace?"

def test_mathparser_functionality():
    project_dir = "/home/user/mathparser_mobile"

    if project_dir not in sys.path:
        sys.path.insert(0, project_dir)

    try:
        import mathparser
    except ImportError as e:
        pytest.fail(f"Failed to import 'mathparser'. Is the C extension built correctly? Error: {e}")

    try:
        result = mathparser.evaluate(2.0, 3.0)
    except Exception as e:
        pytest.fail(f"Calling mathparser.evaluate(2.0, 3.0) raised an exception: {e}")

    expected = 31.0
    assert abs(result - expected) < 1e-6, f"mathparser.evaluate(2.0, 3.0) returned {result}, expected {expected}. Did the math library get linked properly?"


def test_compiled_extension_on_derived_inputs():
    project_dir = "/home/user/mathparser_mobile"
    if project_dir not in sys.path:
        sys.path.insert(0, project_dir)
    import mathparser

    module_path = os.path.realpath(mathparser.__file__)
    assert module_path.startswith(project_dir + os.sep)
    assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), module_path

    rng = random.Random(0x5A17C0DE)
    inputs = [(-100.0, -100.0), (-7.25, 3.5), (0.0, 0.0), (1.0, -1.0), (100.0, 100.0)]
    inputs.extend((rng.uniform(-100, 100), rng.uniform(-100, 100)) for _ in range(200))
    for a, b in inputs:
        expected = ((a + b) ** 2) + (a * b)
        actual = mathparser.evaluate(a, b)
        assert isinstance(actual, float)
        assert math.isfinite(actual)
        assert abs(actual - expected) < 1e-6, (a, b, actual, expected)
TEST_EOF

    (cd /tmp && python3 -m pytest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short --noconftest) || return 1
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
