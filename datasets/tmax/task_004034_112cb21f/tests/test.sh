#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import shutil
import subprocess
from pathlib import Path

import pytest

TOOL = Path('/home/user/tool')
SRC = TOOL / 'src'
BUILD = TOOL / 'build'
VENV = TOOL / 'venv'
CI = TOOL / 'ci_build.py'


def run_ci(timeout=240):
    env = os.environ.copy()
    env['HOME'] = '/home/user'
    env['PIP_CACHE_DIR'] = '/home/user/.cache/pip'
    return subprocess.run(
        ['/usr/bin/python3', str(CI)],
        cwd=str(TOOL),
        env=env,
        text=True,
        capture_output=True,
        timeout=timeout,
    )


def clean_generated(remove_venv=False):
    shutil.rmtree(BUILD, ignore_errors=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    if remove_venv:
        shutil.rmtree(VENV, ignore_errors=True)


def result_details(result):
    return f'exit={result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'


def test_00_ci_build_executes_real_pipeline_and_propagates_failures():
    assert CI.is_file(), f'The script {CI} does not exist.'

    algo_path = SRC / 'algo.c'
    main_path = SRC / 'main.py'
    original_algo = algo_path.read_bytes()
    original_main = main_path.read_bytes()

    factor = secrets.randbelow(70) + 11
    offset = secrets.randbelow(500) + 1
    value = secrets.randbelow(30) + 3
    expected = value * factor + offset
    token = 'PROBE_' + secrets.token_hex(16)
    probe_path = BUILD / 'ci_probe.json'

    probe_algo = f'''#if !defined(__PIC__) || (__PIC__ < 2) || defined(__PIE__)\n#error "algo.c must be compiled with -fPIC"\n#endif\nint process_data(int val) {{\n    return val * {factor} + {offset};\n}}\n'''.encode()

    probe_main = f'''import ctypes\nimport json\nimport os\nimport requests\nimport sys\n\nlib = ctypes.CDLL("libalgo.so")\nlib.process_data.argtypes = [ctypes.c_int]\nlib.process_data.restype = ctypes.c_int\nresult = lib.process_data({value})\nif result != {expected}:\n    raise SystemExit(31)\nwith open({str(probe_path)!r}, "w") as f:\n    json.dump({{\n        "token": {token!r},\n        "result": result,\n        "ld_library_path": os.environ.get("LD_LIBRARY_PATH", ""),\n        "executable": sys.executable,\n        "prefix": sys.prefix,\n        "requests_version": requests.__version__,\n        "requests_file": requests.__file__,\n    }}, f)\nwith open({str(BUILD / 'output.txt')!r}, "w") as f:\n    f.write({token!r})\n'''.encode()

    try:
        clean_generated(remove_venv=True)
        algo_path.write_bytes(probe_algo)
        main_path.write_bytes(probe_main)

        result = run_ci()
        assert result.returncode == 0, 'ci_build.py failed on a valid clean build:\n' + result_details(result)
        assert algo_path.read_bytes() == probe_algo, 'ci_build.py modified src/algo.c'
        assert main_path.read_bytes() == probe_main, 'ci_build.py modified src/main.py'

        lib_path = BUILD / 'libalgo.so'
        output_path = BUILD / 'output.txt'
        assert lib_path.is_file(), 'The clean execution did not create build/libalgo.so'
        assert output_path.read_text().strip() == token, 'main.py was not executed to produce the probe output'
        assert probe_path.is_file(), 'The probe main.py did not run'

        elf = subprocess.run(
            ['readelf', '-h', str(lib_path)], capture_output=True, text=True, check=True
        ).stdout
        assert 'DYN (Shared object file)' in elf, 'libalgo.so is not an ELF shared object'

        loaded = ctypes.CDLL(str(lib_path))
        loaded.process_data.argtypes = [ctypes.c_int]
        loaded.process_data.restype = ctypes.c_int
        assert loaded.process_data(value) == expected, 'libalgo.so was not compiled from the supplied algo.c'

        probe = json.loads(probe_path.read_text())
        assert probe['token'] == token
        assert probe['result'] == expected
        ld_entries = [os.path.realpath(p) for p in probe['ld_library_path'].split(':') if p]
        assert os.path.realpath(BUILD) in ld_entries, 'main.py was not run with build in LD_LIBRARY_PATH'
        assert os.path.realpath(probe['prefix']) == os.path.realpath(VENV), 'main.py did not run inside the new virtual environment'
        assert os.path.realpath(probe['executable']).startswith(os.path.realpath(VENV) + os.sep)
        assert probe['requests_version'] == '2.31.0'
        assert os.path.realpath(probe['requests_file']).startswith(os.path.realpath(VENV) + os.sep), 'requests was not imported from the virtual environment'

        # A failing main.py is a failed CI step and must produce a non-zero exit.
        main_path.write_text('raise SystemExit(23)\n')
        output_path.unlink(missing_ok=True)
        probe_path.unlink(missing_ok=True)
        failed = run_ci()
        assert failed.returncode != 0, 'ci_build.py returned success even though main.py failed'
        assert not output_path.exists(), 'A failed main.py run fabricated output.txt'
    finally:
        algo_path.write_bytes(original_algo)
        main_path.write_bytes(original_main)

    # Leave and validate the final state produced by running the submitted script
    # against the original, unmodified project sources.
    clean_generated(remove_venv=False)
    final = run_ci()
    assert final.returncode == 0, 'ci_build.py failed on the original project:\n' + result_details(final)
    assert algo_path.read_bytes() == original_algo, 'ci_build.py modified the original src/algo.c'
    assert main_path.read_bytes() == original_main, 'ci_build.py modified the original src/main.py'


def test_build_output_exists_and_correct():
    output_path = '/home/user/tool/build/output.txt'
    assert os.path.isfile(output_path), f'Verification file {output_path} does not exist. The script may not have run main.py successfully.'

    with open(output_path, 'r') as f:
        content = f.read().strip()

    assert content == 'SUCCESS_420', f"Expected output.txt to contain 'SUCCESS_420', but got '{content}'"


def test_shared_library_compiled():
    lib_path = '/home/user/tool/build/libalgo.so'
    assert os.path.isfile(lib_path), f'Shared library {lib_path} does not exist. Compilation step failed.'


def test_virtual_environment_created():
    venv_python = '/home/user/tool/venv/bin/python'
    assert os.path.isfile(venv_python), f'Virtual environment Python executable {venv_python} does not exist.'
    assert os.access(venv_python, os.X_OK), f'{venv_python} is not executable.'


def test_requirements_installed_in_venv():
    venv_python = '/home/user/tool/venv/bin/python'
    try:
        result = subprocess.run(
            [venv_python, '-c', 'import requests; print(requests.__version__)'],
            capture_output=True,
            text=True,
            check=True,
        )
        assert '2.31.0' in result.stdout, f'Expected requests version 2.31.0, got {result.stdout}'
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to import 'requests' in the virtual environment. Error: {e.stderr}")


def test_ci_build_script_exists():
    script_path = '/home/user/tool/ci_build.py'
    assert os.path.isfile(script_path), f'The script {script_path} does not exist.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
