#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import re
import secrets
import string
import subprocess
import tempfile

WORKSPACE = '/home/user/workspace'
LIB_PATH = os.path.join(WORKSPACE, 'libtoken.so')
SCRIPT_PATH = os.path.join(WORKSPACE, 'security_tool.py')
TEST_SCRIPT_PATH = os.path.join(WORKSPACE, 'test_security_tool.py')


def test_libtoken_so_exists():
    lib_path = os.path.join(WORKSPACE, 'libtoken.so')
    assert os.path.isfile(lib_path), f"Shared library {lib_path} does not exist. Did you compile token_parser.c?"
    with open(lib_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{lib_path} is not an ELF shared library."
    ctypes.CDLL(lib_path)


def test_test_report_exists_and_passed():
    report_path = os.path.join(WORKSPACE, 'test_report.txt')
    assert os.path.isfile(report_path), f"Test report {report_path} does not exist."

    with open(report_path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert "OK" in content, f"Test report does not indicate success (missing 'OK'). Content:\n{content}"
    assert re.search(r"Ran 2 tests", content), "Test report does not indicate that 2 tests were run."


def test_security_tool_fixes():
    script_path = os.path.join(WORKSPACE, 'security_tool.py')
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    with open(script_path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert "argtypes" in content, "Missing 'argtypes' configuration in security_tool.py"
    assert "restype" in content, "Missing 'restype' configuration in security_tool.py"
    assert "create_string_buffer" in content, "Missing 'ctypes.create_string_buffer' in security_tool.py to safely pass mutable string."


def test_mock_fixture_fixes():
    test_script_path = os.path.join(WORKSPACE, 'test_security_tool.py')
    assert os.path.isfile(test_script_path), f"{test_script_path} does not exist."

    with open(test_script_path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert 'read_data=b"TOKEN' in content or "read_data=b'TOKEN" in content, "mock_open read_data must be updated to return bytes (e.g., b'TOKEN...')."

    tree = ast.parse(content, filename=test_script_path)
    read_data_values = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            name = node.func.id if isinstance(node.func, ast.Name) else None
            if name == 'mock_open':
                for keyword in node.keywords:
                    if keyword.arg == 'read_data':
                        read_data_values.append(keyword.value)
    assert read_data_values, "The test suite must use mock_open(read_data=...)."
    assert all(isinstance(value, ast.Constant) and isinstance(value.value, bytes)
               for value in read_data_values), "Every mock_open read_data fixture must actually be bytes, not str or a comment."
    assert any(value.value.startswith(b'TOKEN:') for value in read_data_values), "The binary token fixture is missing."


def test_run_test_suite_passes():
    result = subprocess.run(
        ['python3', '-m', 'unittest', 'test_security_tool.py'],
        cwd=WORKSPACE,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Test suite still fails when run. stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    combined = result.stdout + result.stderr
    assert re.search(r'Ran 2 tests', combined), f"The actual suite must run exactly 2 tests. Output:\n{combined}"
    assert re.search(r'^OK$', combined, re.MULTILINE), f"The actual suite did not finish with OK. Output:\n{combined}"


def test_compiled_parser_on_derived_inputs():
    lib = ctypes.CDLL(LIB_PATH)
    parse_token = lib.parse_token
    parse_token.argtypes = [ctypes.c_char_p]
    parse_token.restype = ctypes.c_char_p

    alphabet = string.ascii_letters + string.digits + '_-:'
    for _ in range(20):
        payload = ''.join(secrets.choice(alphabet) for _ in range(secrets.randbelow(80) + 1)).encode('ascii')
        token = b'TOKEN:' + str(len(payload)).encode('ascii') + b':' + payload
        buffer = ctypes.create_string_buffer(token)
        assert parse_token(buffer) == payload

        trailing = token + secrets.token_bytes(8)
        buffer = ctypes.create_string_buffer(trailing)
        assert parse_token(buffer) == payload

    malformed = [b'BAD:3:abc', b'TOKEN:20:short', b'TOKEN', b'TOKEN:5', b'']
    for token in malformed:
        buffer = ctypes.create_string_buffer(token)
        assert parse_token(buffer) is None, f"Parser accepted malformed token {token!r}."


def test_manager_general_behavior_and_ffi_types():
    import importlib.util
    spec = importlib.util.spec_from_file_location('submitted_security_tool', SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    manager = module.SecurityTokenManager(LIB_PATH)
    function = manager.lib.parse_token
    assert function.argtypes == [ctypes.c_char_p], f"parse_token.argtypes must be [ctypes.c_char_p], got {function.argtypes!r}"
    assert function.restype is ctypes.c_char_p, f"parse_token.restype must be ctypes.c_char_p, got {function.restype!r}"

    alphabet = string.ascii_letters + string.digits + '_-:'
    for _ in range(20):
        payload = ''.join(secrets.choice(alphabet) for _ in range(secrets.randbelow(80) + 1))
        expected = b'TOKEN:' + str(len(payload)).encode('ascii') + b':' + payload.encode('ascii')
        token = manager.create_token(payload)
        assert isinstance(token, bytes), "create_token must return bytes."
        assert token == expected, f"Incorrect token for derived payload {payload!r}."

        original = bytes(token)
        assert manager.extract_payload(token) == payload
        assert token == original, "extract_payload allowed the C parser to modify the immutable input bytes."

    for token in (b'NOT_A_TOKEN', b'TOKEN:99:x', b'TOKEN:4'):
        assert manager.extract_payload(token) is None


def test_manager_really_calls_the_requested_c_library_with_mutable_storage():
    import importlib.util
    nonce = ('ffi_' + secrets.token_hex(16)).encode('ascii')
    c_literal = nonce.decode('ascii')

    with tempfile.TemporaryDirectory() as directory:
        source = os.path.join(directory, 'probe.c')
        library = os.path.join(directory, 'probe.so')
        with open(source, 'w', encoding='ascii') as f:
            f.write(
                '#include <stddef.h>\n'
                'char* parse_token(char* input) {\n'
                f'  static char answer[] = "{c_literal}";\n'
                '  if (input == NULL) return NULL;\n'
                '  input[0] = (char)(input[0] ^ 1);\n'
                '  return answer;\n'
                '}\n'
            )
        result = subprocess.run(
            ['gcc', '-shared', '-fPIC', '-o', library, source],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Could not compile verifier probe library: {result.stderr}"

        spec = importlib.util.spec_from_file_location('probe_security_tool', SCRIPT_PATH)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        manager = module.SecurityTokenManager(library)

        raw = b'derived-input-' + secrets.token_bytes(12)
        saved = bytes(raw)
        assert manager.extract_payload(raw) == nonce.decode('ascii'), "extract_payload did not use parse_token from the requested C library."
        assert raw == saved, "The C function was given immutable Python bytes instead of a mutable copy."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
