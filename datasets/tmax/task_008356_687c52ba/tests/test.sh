#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import shutil
import subprocess
import tempfile


def test_cmakelists_linked():
    cmakelists_path = '/home/user/project/CMakeLists.txt'
    assert os.path.isfile(cmakelists_path), f"{cmakelists_path} is missing"
    with open(cmakelists_path, 'r') as f:
        content = f.read()

    assert re.search(r'target_link_libraries\s*\(\s*test_encoder\s+protorest\s*\)', content, re.IGNORECASE), \
        "CMakeLists.txt is missing target_link_libraries(test_encoder protorest)"


def _remove_c_comments(source):
    out = []
    i = 0
    state = 'code'
    while i < len(source):
        if state == 'code':
            if source.startswith('//', i):
                state = 'line_comment'
                i += 2
            elif source.startswith('/*', i):
                state = 'block_comment'
                i += 2
            elif source[i] == '"':
                out.append(source[i])
                state = 'string'
                i += 1
            elif source[i] == "'":
                out.append(source[i])
                state = 'char'
                i += 1
            else:
                out.append(source[i])
                i += 1
        elif state == 'line_comment':
            if source[i] == '\n':
                out.append('\n')
                state = 'code'
            i += 1
        elif state == 'block_comment':
            if source.startswith('*/', i):
                state = 'code'
                i += 2
            else:
                if source[i] == '\n':
                    out.append('\n')
                i += 1
        else:
            out.append(source[i])
            if source[i] == '\\' and i + 1 < len(source):
                out.append(source[i + 1])
                i += 2
            elif (state == 'string' and source[i] == '"') or (state == 'char' and source[i] == "'"):
                state = 'code'
                i += 1
            else:
                i += 1
    return ''.join(out)


def _function_body(source, name):
    match = re.search(r'\b(?:void|int)\s+' + re.escape(name) + r'\s*\([^;]*?\)\s*\{', source, re.DOTALL)
    assert match is not None, f"{name} function is missing"
    start = match.end() - 1
    depth = 0
    for pos in range(start, len(source)):
        if source[pos] == '{':
            depth += 1
        elif source[pos] == '}':
            depth -= 1
            if depth == 0:
                return source[start + 1:pos]
    raise AssertionError(f"{name} function is malformed")


def test_test_encoder_c_contains_test():
    test_c_path = '/home/user/project/tests/test_encoder.c'
    assert os.path.isfile(test_c_path), f"{test_c_path} is missing"
    with open(test_c_path, 'r') as f:
        content = f.read()

    assert "test_rest_payload" in content, "test_rest_payload function is missing in test_encoder.c"
    assert '"Migrating to Py3"' in content, "test_rest_payload does not contain the correct input string"
    assert '{"payload": "TWlncmF0aW5nIHRvIFB5Mw=="}' in content, "test_rest_payload does not contain the correct expected JSON string"

    main_match = re.search(r'int\s+main\s*\([^)]*\)\s*\{([^}]+)\}', content)
    assert main_match is not None, "main function not found in test_encoder.c"
    assert "test_rest_payload" in main_match.group(1), "test_rest_payload is not called in main()"

    uncommented = _remove_c_comments(content)
    body = _function_body(uncommented, 'test_rest_payload')
    assert 'generate_rest_payload' in body, "test_rest_payload must call generate_rest_payload"
    assert '"Migrating to Py3"' in body, "test_rest_payload must use the required input"
    assert '{"payload": "TWlncmF0aW5nIHRvIFB5Mw=="}' in body, "test_rest_payload must use the exact expected JSON"
    assert re.search(r'\bassert\s*\(', body), "test_rest_payload must contain an assertion"


def test_build_success():
    build_dir = '/home/user/project/build'
    assert os.path.isdir(build_dir), f"Build directory {build_dir} is missing"

    cmake_res = subprocess.run(['cmake', '..'], cwd=build_dir, capture_output=True, text=True)
    assert cmake_res.returncode == 0, f"CMake configuration failed:\n{cmake_res.stderr}"

    make_res = subprocess.run(['make'], cwd=build_dir, capture_output=True, text=True)
    assert make_res.returncode == 0, f"Make build failed (possibly linker error):\n{make_res.stderr}"

    executable_path = os.path.join(build_dir, 'test_encoder')
    assert os.path.isfile(executable_path), f"Executable {executable_path} was not built"


def test_fresh_cmake_build_succeeds():
    build_dir = tempfile.mkdtemp(prefix='protorest-build-')
    try:
        configured = subprocess.run(
            ['cmake', '/home/user/project'], cwd=build_dir, capture_output=True, text=True
        )
        assert configured.returncode == 0, f"Fresh CMake configuration failed:\n{configured.stderr}"
        built = subprocess.run(
            ['cmake', '--build', '.', '--target', 'test_encoder'],
            cwd=build_dir, capture_output=True, text=True
        )
        assert built.returncode == 0, f"Fresh build of test_encoder failed:\n{built.stderr}"
        executable = os.path.join(build_dir, 'test_encoder')
        assert os.path.isfile(executable), "Fresh build did not produce test_encoder"
        run = subprocess.run([executable], cwd=build_dir, capture_output=True, text=True)
        assert run.returncode == 0, f"Freshly built test executable failed:\n{run.stderr}"
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def test_executable_runs_successfully():
    executable_path = '/home/user/project/build/test_encoder'
    assert os.path.isfile(executable_path), f"Executable {executable_path} is missing"

    run_res = subprocess.run([executable_path], capture_output=True, text=True)
    assert run_res.returncode == 0, f"Test executable failed to run, possibly due to assertion failure:\n{run_res.stderr}"


def test_encoder_behavior_directly():
    cases = [
        b'A', b'AB', b'ABC', b'ABCD', b'Migrating to Py3',
        bytes(range(1, 18)), b'padding-check-22-bytes'
    ]
    checks = []
    for index, data in enumerate(cases):
        expected = json.dumps({'payload': base64.b64encode(data).decode('ascii')}, separators=(', ', ': '))
        values = ', '.join(str(value) for value in data)
        checks.append(f'''\n        {{\n            const unsigned char input_{index}[] = {{{values}}};\n            char output_{index}[512] = {{0}};\n            generate_rest_payload(input_{index}, sizeof(input_{index}), output_{index});\n            if (strcmp(output_{index}, {json.dumps(expected)}) != 0) {{\n                fprintf(stderr, "case {index}: expected %s, got %s\\n", {json.dumps(expected)}, output_{index});\n                return {index + 1};\n            }}\n        }}''')

    harness = '''
#include "encoder.h"
#include <stdio.h>
#include <string.h>
int main(void) {
''' + ''.join(checks) + '''
    return 0;
}
'''

    with tempfile.TemporaryDirectory(prefix='encoder-check-') as tmp:
        harness_path = os.path.join(tmp, 'harness.c')
        executable = os.path.join(tmp, 'encoder_check')
        with open(harness_path, 'w') as f:
            f.write(harness)
        compiled = subprocess.run([
            'cc', '-std=c99', '-I/home/user/project/src',
            harness_path, '/home/user/project/src/encoder.c', '-o', executable
        ], capture_output=True, text=True)
        assert compiled.returncode == 0, f"Could not compile encoder behavior harness:\n{compiled.stderr}"
        run = subprocess.run([executable], capture_output=True, text=True)
        assert run.returncode == 0, f"Encoder behavior is incorrect:\n{run.stderr}"


def test_added_test_rejects_unpadded_payload():
    test_source = '/home/user/project/tests/test_encoder.c'
    with tempfile.TemporaryDirectory(prefix='test-quality-') as tmp:
        stub_path = os.path.join(tmp, 'buggy_encoder.c')
        executable = os.path.join(tmp, 'test_with_bug')
        with open(stub_path, 'w') as f:
            f.write(r'''
#include "encoder.h"
#include <string.h>
void base64_encode(const unsigned char *data, size_t len, char *out) {
    (void)data; (void)len;
    strcpy(out, "TWlncmF0aW5nIHRvIFB5MwAA");
}
void generate_rest_payload(const unsigned char *data, size_t len, char *out) {
    (void)data; (void)len;
    strcpy(out, "{\"payload\": \"TWlncmF0aW5nIHRvIFB5MwAA\"}");
}
''')
        compiled = subprocess.run([
            'cc', '-std=c99', '-I/home/user/project/src', test_source, stub_path, '-o', executable
        ], capture_output=True, text=True)
        assert compiled.returncode == 0, f"Could not independently compile the submitted test:\n{compiled.stderr}"
        run = subprocess.run([executable], capture_output=True, text=True)
        assert run.returncode != 0, "test_rest_payload does not reject the original unpadded result"


def test_test_result_log():
    log_path = '/home/user/test_result.log'
    assert os.path.isfile(log_path), f"{log_path} is missing"
    with open(log_path, 'r') as f:
        content = f.read().strip()

    assert content == "SUCCESS", f"Expected 'SUCCESS' in {log_path}, but got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
