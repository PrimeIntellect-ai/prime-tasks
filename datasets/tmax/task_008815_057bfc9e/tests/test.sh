#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import shutil
import subprocess
import tempfile
import time

PROJECT = "/home/user/project"
LIB = os.path.join(PROJECT, "libprocessor.so")
SOURCE = os.path.join(PROJECT, "processor.c")
INTEGRATION = os.path.join(PROJECT, "integration.py")
SERVER = os.path.join(PROJECT, "server.py")
RESULT = "/home/user/result.log"


def kill_mock_servers():
    subprocess.run(
        ["pkill", "-f", "/home/user/project/server.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    time.sleep(0.3)


def test_libprocessor_so_exists():
    path = "/home/user/project/libprocessor.so"
    assert os.path.isfile(path), f"Shared library {path} is missing. Did you compile the C code?"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not an ELF shared library."


def test_integration_py_exists_and_uses_ctypes():
    path = "/home/user/project/integration.py"
    assert os.path.isfile(path), f"Python script {path} is missing."
    with open(path, "r") as f:
        content = f.read()
    assert "ctypes" in content, f"{path} does not seem to use the 'ctypes' module as required."


def test_result_log_content():
    path = "/home/user/result.log"
    assert os.path.isfile(path), f"Result log file {path} is missing. Did the integration script run successfully?"

    with open(path, "r") as f:
        content = f.read().strip()

    expected_output = "ZYX_DAOLYAP_GNOL_11224488_ESNOPSER_NEKOT"
    assert content == expected_output, f"Content of {path} is incorrect. Expected '{expected_output}', but got '{content}'."


def test_shared_library_processes_derived_inputs():
    lib = ctypes.CDLL(LIB)
    fn = lib.process_payload
    fn.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    fn.restype = None

    inputs = [
        b"a",
        b"sixteen_chars_123",
        ("payload_" + secrets.token_hex(24)).encode("ascii"),
        ("long_" + secrets.token_hex(80)).encode("ascii"),
    ]
    for value in inputs:
        output = ctypes.create_string_buffer(len(value) + 64)
        fn(value, output)
        assert output.value == value[::-1], (
            f"process_payload returned {output.value!r} for {value!r}; expected {value[::-1]!r}"
        )


def test_repaired_processor_source_builds_and_handles_standard_payloads():
    assert os.path.isfile(SOURCE), f"C source {SOURCE} is missing."
    with tempfile.TemporaryDirectory() as td:
        harness = os.path.join(td, "harness.c")
        executable = os.path.join(td, "processor_test")
        with open(harness, "w") as f:
            f.write(r'''
#include <stdio.h>
#include <string.h>
void process_payload(const char* input, char* output);
int main(void) {
    char input[97];
    char output[256];
    char expected[97];
    for (int i = 0; i < 96; ++i) input[i] = (char)('A' + (i % 26));
    input[96] = '\0';
    for (int i = 0; i < 96; ++i) expected[i] = input[95 - i];
    expected[96] = '\0';
    process_payload(input, output);
    return strcmp(output, expected) == 0 ? 0 : 2;
}
''')
        compiled = subprocess.run(
            ["gcc", "-fsanitize=address", "-fno-omit-frame-pointer", SOURCE, harness, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert compiled.returncode == 0, f"processor.c did not compile: {compiled.stderr}"
        run = subprocess.run(
            [executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
            env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0:halt_on_error=1"},
        )
        assert run.returncode == 0, f"Rebuilt processor failed or triggered a memory error: {run.stderr}"


def test_integration_fetches_payload_and_invokes_library():
    payload = "DYNAMIC_" + secrets.token_hex(24)
    marker = "LIBRARY_" + secrets.token_hex(16) + ":"

    with tempfile.TemporaryDirectory() as td:
        saved_server = os.path.join(td, "server.py")
        saved_lib = os.path.join(td, "libprocessor.so")
        probe_c = os.path.join(td, "probe.c")
        probe_so = os.path.join(td, "libprocessor.so")
        shutil.copy2(SERVER, saved_server)
        shutil.copy2(LIB, saved_lib)

        with open(probe_c, "w") as f:
            f.write(
                '#include <string.h>\n'
                'void process_payload(const char* input, char* output) {\n'
                f'    strcpy(output, "{marker}");\n'
                '    strcat(output, input);\n'
                '}\n'
            )
        subprocess.run(["gcc", "-shared", "-fPIC", probe_c, "-o", probe_so], check=True)

        test_server = f'''from http.server import BaseHTTPRequestHandler, HTTPServer
class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/token":
            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            self.wfile.write({payload!r}.encode("ascii"))
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, format, *args):
        pass
if __name__ == "__main__":
    ReusableHTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
'''

        kill_mock_servers()
        try:
            shutil.copy2(probe_so, LIB)
            with open(SERVER, "w") as f:
                f.write(test_server)
            if os.path.exists(RESULT):
                os.remove(RESULT)

            run = subprocess.run(
                ["python3", INTEGRATION],
                cwd=PROJECT,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=12,
            )
            assert run.returncode == 0, "integration.py did not complete successfully."
            assert os.path.isfile(RESULT), "integration.py did not create /home/user/result.log."
            with open(RESULT, "r") as f:
                actual = f.read()
            expected = marker + payload
            assert actual == expected, (
                "integration.py did not fetch the live API payload, pass it to process_payload, "
                "and write the library's exact output."
            )
        finally:
            kill_mock_servers()
            shutil.copy2(saved_server, SERVER)
            shutil.copy2(saved_lib, LIB)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
