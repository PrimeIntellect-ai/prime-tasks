#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import subprocess
from pathlib import Path

import pytest

BASE = Path('/home/user/polybuild')
SCRIPT = BASE / 'polybuild.py'
SOURCE = BASE / 'math_ops.c'
DSL = BASE / 'poly.dsl'
RESULT = BASE / 'result.out'
ORIGINAL_LIB = BASE / 'libop_lib.so'


def test_polybuild_script_exists():
    assert SCRIPT.is_file(), f'Expected script {SCRIPT} does not exist.'


def test_shared_library_compiled():
    assert ORIGINAL_LIB.is_file(), f'Expected compiled shared library {ORIGINAL_LIB} does not exist.'


def test_result_out_content():
    assert RESULT.is_file(), f'Expected output file {RESULT} does not exist.'
    assert RESULT.read_text().strip() == '176', "Expected result.out to contain '176'."


def trunc_div(a, b):
    if b == 0:
        return 0
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


def test_script_builds_loads_and_evaluates_generated_cases(tmp_path):
    original_source = SOURCE.read_bytes()
    original_dsl = DSL.read_bytes()
    instrument = tmp_path / 'instrument'
    instrument.mkdir()
    gcc_marker = tmp_path / 'gcc.used'
    abi_marker = tmp_path / 'ctypes_abi.used'

    sitecustomize = f'''\
import ctypes
import os
import subprocess

_gcc_marker = {str(gcc_marker)!r}
_abi_marker = {str(abi_marker)!r}
_orig_popen = subprocess.Popen

def _popen(*args, **kwargs):
    cmd = args[0] if args else kwargs.get('args', '')
    if isinstance(cmd, (list, tuple)):
        text = ' '.join(str(x) for x in cmd)
    else:
        text = str(cmd)
    if any(os.path.basename(tok) == 'gcc' for tok in text.replace(';', ' ').split()):
        open(_gcc_marker, 'a').close()
    return _orig_popen(*args, **kwargs)

subprocess.Popen = _popen
_orig_cdll = ctypes.CDLL

class _FunctionProxy:
    def __init__(self, function):
        object.__setattr__(self, '_function', function)
    def __getattr__(self, name):
        return getattr(self._function, name)
    def __setattr__(self, name, value):
        setattr(self._function, name, value)
    def __call__(self, *args, **kwargs):
        argtypes = getattr(self._function, 'argtypes', None)
        restype = getattr(self._function, 'restype', None)
        if (argtypes is not None and list(argtypes) == [ctypes.c_int32, ctypes.c_int32]
                and restype is ctypes.c_int32):
            open(_abi_marker, 'a').close()
        return self._function(*args, **kwargs)

class _LibraryProxy:
    def __init__(self, library):
        object.__setattr__(self, '_library', library)
    def __getattr__(self, name):
        value = getattr(self._library, name)
        return _FunctionProxy(value) if callable(value) else value
    def __getitem__(self, name):
        value = self._library[name]
        return _FunctionProxy(value) if callable(value) else value
    def __setattr__(self, name, value):
        setattr(self._library, name, value)

def _cdll(*args, **kwargs):
    return _LibraryProxy(_orig_cdll(*args, **kwargs))

ctypes.CDLL = _cdll
ctypes.cdll._dlltype = _cdll
'''
    (instrument / 'sitecustomize.py').write_text(sitecustomize)

    env = os.environ.copy()
    env['PYTHONPATH'] = str(instrument)
    final_run = None

    try:
        for _ in range(3):
            token = secrets.token_hex(8)
            alias = 'op_' + token
            library = BASE / f'lib{alias}.so'
            load_marker = tmp_path / f'loaded_{token}'

            k_add = secrets.randbelow(13) - 6
            k_sub = secrets.randbelow(13) - 6
            k_mul = secrets.randbelow(7) - 3
            k_div = secrets.randbelow(9) - 4
            a = secrets.randbelow(17) - 8
            b = secrets.randbelow(13) - 6
            c = secrets.randbelow(31) - 15
            d = secrets.randbelow(81) - 40
            e = secrets.randbelow(8) + 1

            SOURCE.write_text(f'''#include <stdint.h>\n#include <stdio.h>\n__attribute__((constructor)) static void loaded(void) {{ FILE *f=fopen("{load_marker}", "w"); if (f) fclose(f); }}\nint32_t op_add(int32_t x,int32_t y) {{ return x+y+({k_add}); }}\nint32_t op_sub(int32_t x,int32_t y) {{ return x-y+({k_sub}); }}\nint32_t op_mul(int32_t x,int32_t y) {{ return x*y+({k_mul}); }}\nint32_t op_div(int32_t x,int32_t y) {{ return y==0 ? 0 : x/y+({k_div}); }}\n''')
            expression = f'(op_add (op_mul {a} {b}) (op_sub {c} (op_div {d} {e})))'
            DSL.write_text(f'BUILD shared {alias} math_ops.c\nEVAL {alias} {expression}\n')

            for path in (library, RESULT, load_marker, gcc_marker, abi_marker):
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass

            run = subprocess.run(
                ['python3', str(SCRIPT)], cwd=BASE, env=env,
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
            )
            assert run.returncode == 0, f'polybuild.py failed:\n{run.stdout}\n{run.stderr}'
            assert gcc_marker.is_file(), 'polybuild.py did not invoke GCC through subprocess'
            assert library.is_file(), f'Expected generated library {library}'
            assert load_marker.is_file(), 'The newly compiled library was not loaded by the script'
            assert abi_marker.is_file(), 'No ctypes call used two c_int32 argtypes and c_int32 restype'
            assert RESULT.is_file(), 'polybuild.py did not create result.out'

            mul_value = a * b + k_mul
            div_value = trunc_div(d, e) + k_div
            sub_value = c - div_value + k_sub
            expected = mul_value + sub_value + k_add
            assert RESULT.read_text().strip() == str(expected)

            built = ctypes.CDLL(str(library))
            for name in ('op_add', 'op_sub', 'op_mul', 'op_div'):
                fn = getattr(built, name)
                fn.argtypes = [ctypes.c_int32, ctypes.c_int32]
                fn.restype = ctypes.c_int32
            assert built.op_add(7, -2) == 5 + k_add
            assert built.op_sub(7, -2) == 9 + k_sub
            assert built.op_mul(7, -2) == -14 + k_mul
            assert built.op_div(-17, 5) == trunc_div(-17, 5) + k_div
    finally:
        SOURCE.write_bytes(original_source)
        DSL.write_bytes(original_dsl)
        final_run = subprocess.run(
            ['python3', str(SCRIPT)], cwd=BASE, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )

    assert final_run.returncode == 0, f'polybuild.py failed on the original DSL: {final_run.stderr}'
    assert ORIGINAL_LIB.is_file()
    assert RESULT.read_text().strip() == '176'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
