#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

BASE = Path('/home/user/qa_env')
EXPECTED_INPUTS = {
    'file1.txt': ['zebra', 'apple'],
    'file2.txt': ['mango', 'banana'],
}
EXPECTED_LINES = [
    '6170706c65',
    '62616e616e61',
    '6d616e676f',
    '7a65627261',
]
EXPECTED_BYTES = ('\n'.join(EXPECTED_LINES) + '\n').encode()


def expected_output(lines):
    return ('\n'.join(s.encode('utf-8').hex() for s in sorted(lines)) + '\n').encode()


def invoke_library(lib_path, input_specs, tmp_path):
    input_paths = []
    all_lines = []
    for index, (lines, final_newline) in enumerate(input_specs):
        path = tmp_path / f'input_{index}.txt'
        data = '\n'.join(lines)
        if final_newline:
            data += '\n'
        path.write_text(data, encoding='utf-8')
        input_paths.append(str(path))
        all_lines.extend(lines)

    output_path = tmp_path / 'result.txt'
    helper = tmp_path / 'invoke.py'
    helper.write_text(
        "import ctypes, json, sys\n"
        "lib = ctypes.CDLL(sys.argv[1])\n"
        "fn = lib.process_data\n"
        "fn.argtypes = [ctypes.POINTER(ctypes.c_char_p), ctypes.c_int, ctypes.c_char_p]\n"
        "fn.restype = ctypes.c_int\n"
        "paths = json.loads(sys.argv[2])\n"
        "arr = (ctypes.c_char_p * len(paths))(*[p.encode() for p in paths])\n"
        "rc = fn(arr, len(paths), sys.argv[3].encode())\n"
        "sys.exit(0 if rc == 0 else 20)\n",
        encoding='utf-8',
    )
    result = subprocess.run(
        [sys.executable, str(helper), str(lib_path), json.dumps(input_paths), str(output_path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'process_data failed for {lib_path}: rc={result.returncode}, stderr={result.stderr}'
    )
    assert output_path.is_file(), 'process_data did not create its requested output file.'
    assert output_path.read_bytes() == expected_output(all_lines), (
        'process_data did not sort and lowercase-hex-encode the supplied lines correctly.'
    )


def run_test_runner():
    return subprocess.run(
        [sys.executable, str(BASE / 'test_runner.py')],
        cwd=str(BASE),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )


def test_qa_env_directory_exists():
    assert os.path.isdir('/home/user/qa_env'), '/home/user/qa_env directory is missing.'


def test_input_files_exist_and_have_required_contents():
    for name, expected in EXPECTED_INPUTS.items():
        path = BASE / 'inputs' / name
        assert path.is_file(), f'{name} is missing.'
        assert path.read_text(encoding='utf-8').splitlines() == expected, (
            f'{name} does not contain the required lines.'
        )


def test_shared_library_exists_and_exports_symbol():
    lib_path = str(BASE / 'libqa.so')
    assert os.path.isfile(lib_path), f'{lib_path} is missing.'
    try:
        output = subprocess.check_output(['nm', '-D', lib_path], stderr=subprocess.STDOUT, text=True)
        assert 'process_data' in output, f"Symbol 'process_data' not found in {lib_path}."
    except FileNotFoundError:
        output = subprocess.check_output(['objdump', '-T', lib_path], stderr=subprocess.STDOUT, text=True)
        assert 'process_data' in output, f"Symbol 'process_data' not found in {lib_path}."


def test_sorter_source_compiles_and_both_libraries_process_unseen_data(tmp_path):
    source = BASE / 'sorter.c'
    assert source.is_file(), f'{source} is missing.'
    rebuilt = tmp_path / 'rebuilt_libqa.so'
    compile_result = subprocess.run(
        ['gcc', '-shared', '-fPIC', '-O2', '-o', str(rebuilt), str(source)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f'sorter.c does not compile: {compile_result.stderr}'

    cases = [
        ([['kiwi', 'apricot', 'fig'], ['pear', 'grape']], True),
        ([['delta', 'alpha', 'delta'], ['charlie', 'bravo']], False),
        ([['Zed', 'aardvark', 'item 10'], ['item 2', 'Beta']], True),
    ]
    for lib in (BASE / 'libqa.so', rebuilt):
        for case_num, (groups, final_newline) in enumerate(cases):
            case_dir = tmp_path / f'{lib.name}_{case_num}'
            case_dir.mkdir()
            specs = [(lines, final_newline if i == len(groups) - 1 else True)
                     for i, lines in enumerate(groups)]
            invoke_library(lib, specs, case_dir)


def test_golden_file_contents():
    golden_path = BASE / 'golden.txt'
    assert golden_path.is_file(), f'{golden_path} is missing.'
    with golden_path.open('r', encoding='utf-8') as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == EXPECTED_LINES, 'golden.txt does not contain the correct hex-encoded output.'


def test_test_runner_script_structure():
    script_path = BASE / 'test_runner.py'
    assert script_path.is_file(), f'{script_path} is missing.'
    content = script_path.read_text(encoding='utf-8')
    assert 'ctypes' in content, "test_runner.py does not contain 'ctypes'."
    tree = ast.parse(content)
    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    names = []
    for call in calls:
        func = call.func
        if isinstance(func, ast.Name):
            names.append(func.id)
        elif isinstance(func, ast.Attribute):
            parts = []
            while isinstance(func, ast.Attribute):
                parts.append(func.attr)
                func = func.value
            if isinstance(func, ast.Name):
                parts.append(func.id)
            names.append('.'.join(reversed(parts)))
    assert any(name.endswith('CDLL') for name in names), 'test_runner.py does not load the shared library with ctypes.'
    assert 'process_data' in content, 'test_runner.py does not call or reference process_data.'
    assert 'diff' in content and 'test_result.log' in content, 'test_runner.py does not run diff into test_result.log.'
    assert any(name in ('subprocess.run', 'subprocess.call', 'subprocess.Popen',
                        'subprocess.check_call', 'subprocess.check_output', 'os.system')
               for name in names), 'test_runner.py does not invoke a system command for diff.'


def test_runner_executes_pipeline_on_unseen_inputs_and_restores_required_state():
    paths = [BASE / 'inputs' / 'file1.txt', BASE / 'inputs' / 'file2.txt', BASE / 'golden.txt']
    backups = {path: path.read_bytes() for path in paths}
    output = BASE / 'output.txt'
    log = BASE / 'test_result.log'
    probe_groups = [['nectarine', 'avocado'], ['plum', 'blueberry', 'coconut']]
    probe_expected = expected_output([line for group in probe_groups for line in group])

    try:
        paths[0].write_text('\n'.join(probe_groups[0]) + '\n', encoding='utf-8')
        paths[1].write_text('\n'.join(probe_groups[1]) + '\n', encoding='utf-8')
        paths[2].write_bytes(probe_expected)
        output.unlink(missing_ok=True)
        log.unlink(missing_ok=True)
        result = run_test_runner()
        assert result.returncode == 0, f'test_runner.py failed: {result.stderr}'
        assert output.is_file(), 'test_runner.py did not generate output.txt.'
        assert output.read_bytes() == probe_expected, 'test_runner.py produced incorrect output for unseen inputs.'
        assert log.is_file(), 'test_runner.py did not generate test_result.log.'
        assert log.stat().st_size == 0, 'diff reported differences for unseen inputs.'
    finally:
        for path, data in backups.items():
            path.write_bytes(data)
        output.unlink(missing_ok=True)
        log.unlink(missing_ok=True)
        final_result = run_test_runner()
        assert final_result.returncode == 0, f'test_runner.py failed on required inputs: {final_result.stderr}'


def test_output_file_matches_golden():
    output_path = BASE / 'output.txt'
    golden_path = BASE / 'golden.txt'
    assert output_path.is_file(), f'{output_path} is missing.'
    assert output_path.read_bytes() == golden_path.read_bytes(), 'output.txt does not exactly match golden.txt.'


def test_test_result_log_is_empty():
    log_path = BASE / 'test_result.log'
    assert log_path.is_file(), f'{log_path} is missing.'
    size = log_path.stat().st_size
    assert size == 0, f'{log_path} is not empty (size is {size} bytes).'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
