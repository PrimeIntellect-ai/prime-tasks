#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure verification starts the submitted artifact rather than connecting to a
# server left running by the agent.
pkill -f '[w]s_server.py' 2>/dev/null || true
sleep 0.5

export LD_LIBRARY_PATH="/home/user/project${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import ctypes
import os
import random
import re
import signal
import string
import subprocess
import time

import pytest
import websockets

PROJECT_DIR = "/home/user/project"
OUTPUT_LOG = "/home/user/output.log"
EXPECTED_HEX = "506F6C79676C6F7444617461313233"
WS_SERVER = os.path.join(PROJECT_DIR, "ws_server.py")


def run_server():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = PROJECT_DIR + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    proc = subprocess.Popen(
        ["python3", WS_SERVER],
        cwd=PROJECT_DIR,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )

    async def wait_until_ready():
        last_error = None
        for _ in range(50):
            if proc.poll() is not None:
                stdout, stderr = proc.communicate(timeout=2)
                raise AssertionError(
                    f"ws_server.py exited before serving (code {proc.returncode}).\n"
                    f"stdout:\n{stdout}\nstderr:\n{stderr}"
                )
            try:
                async with websockets.connect("ws://localhost:8765", open_timeout=0.5):
                    return
            except Exception as exc:
                last_error = exc
                await asyncio.sleep(0.1)
        raise AssertionError(f"ws_server.py did not listen on ws://localhost:8765: {last_error}")

    try:
        asyncio.run(wait_until_ready())
    except Exception:
        stop_server(proc)
        raise
    return proc


def stop_server(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=3)
    time.sleep(0.2)


def websocket_roundtrips(messages):
    async def perform():
        async with websockets.connect("ws://localhost:8765", open_timeout=2) as ws:
            replies = []
            for message in messages:
                await ws.send(message)
                replies.append(await asyncio.wait_for(ws.recv(), timeout=3))
            return replies
    return asyncio.run(perform())


def test_make_builds_from_sources():
    for name in ("libencoder.so", "wrapper.so"):
        path = os.path.join(PROJECT_DIR, name)
        if os.path.exists(path):
            os.unlink(path)
    result = subprocess.run(
        ["make"], cwd=PROJECT_DIR, text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"


def test_shared_objects_exist():
    libencoder_so = os.path.join(PROJECT_DIR, "libencoder.so")
    wrapper_so = os.path.join(PROJECT_DIR, "wrapper.so")

    assert os.path.isfile(libencoder_so), f"{libencoder_so} does not exist."
    assert os.path.isfile(wrapper_so), f"{wrapper_so} does not exist."

    out_lib = subprocess.check_output(["file", libencoder_so]).decode("utf-8")
    assert "shared object" in out_lib, f"{libencoder_so} is not a valid shared object."

    out_wrap = subprocess.check_output(["file", wrapper_so]).decode("utf-8")
    assert "shared object" in out_wrap, f"{wrapper_so} is not a valid shared object."


def test_c_code_memory_fix():
    libencoder_c = os.path.join(PROJECT_DIR, "libencoder.c")
    assert os.path.isfile(libencoder_c), f"{libencoder_c} does not exist."

    with open(libencoder_c, "r") as f:
        content = f.read()

    bug_pattern = re.compile(r"malloc\s*\(\s*len\s*\*\s*2\s*\)")
    lines = content.split('\n')
    for line in lines:
        if bug_pattern.search(line):
            assert "+1" in line.replace(" ", "") or "calloc" in line, \
                "libencoder.c still seems to contain the memory allocation bug (allocating exactly len * 2 without +1)."


def test_c_implementation_under_address_sanitizer():
    tester = "/tmp/encoder_asan_test.c"
    binary = "/tmp/encoder_asan_test"
    with open(tester, "w") as f:
        f.write(r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libencoder.h"

int main(void) {
    size_t sizes[] = {0, 1, 2, 7, 64, 1024, 8192};
    const char hex[] = "0123456789ABCDEF";
    for (size_t nidx = 0; nidx < sizeof(sizes)/sizeof(sizes[0]); ++nidx) {
        size_t n = sizes[nidx];
        char *input = malloc(n + 1);
        if (!input) return 10;
        for (size_t i = 0; i < n; ++i) input[i] = (char)('!' + (i % 90));
        input[n] = '\0';
        char *out = hex_encode(input);
        if (!out) return 11;
        if (strlen(out) != n * 2) return 12;
        for (size_t i = 0; i < n; ++i) {
            unsigned char c = (unsigned char)input[i];
            if (out[2*i] != hex[c >> 4] || out[2*i+1] != hex[c & 15]) return 13;
        }
        free(out);
        free(input);
    }
    return 0;
}
''')
    compile_result = subprocess.run(
        ["gcc", "-fsanitize=address", "-fno-omit-frame-pointer", "-g",
         "-I", PROJECT_DIR, tester, os.path.join(PROJECT_DIR, "libencoder.c"), "-o", binary],
        text=True, capture_output=True, timeout=30,
    )
    assert compile_result.returncode == 0, compile_result.stdout + compile_result.stderr
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "abort_on_error=1:detect_leaks=0"
    result = subprocess.run([binary], env=env, text=True, capture_output=True, timeout=30)
    assert result.returncode == 0, f"memory-safety/encoding test failed:\n{result.stdout}\n{result.stderr}"


def test_ws_server_script_exists():
    assert os.path.isfile(WS_SERVER), f"{WS_SERVER} does not exist."
    with open(WS_SERVER, "r") as f:
        content = f.read()
    assert "websockets" in content, "ws_server.py does not seem to use the 'websockets' library."
    assert "ctypes" in content, "ws_server.py does not seem to use the 'ctypes' library."


def test_wrapper_functionality():
    wrapper_so = os.path.join(PROJECT_DIR, "wrapper.so")
    assert os.path.isfile(wrapper_so), "wrapper.so missing, cannot test functionality."
    try:
        wrapper = ctypes.CDLL(wrapper_so)
        wrapper.encode_string.argtypes = [ctypes.c_char_p]
        wrapper.encode_string.restype = ctypes.c_char_p

        test_str = b"Test"
        result = wrapper.encode_string(test_str)
        assert result.decode('utf-8').upper() == "54657374", "encode_string did not return the correct hex string."

        rng = random.Random(int.from_bytes(os.urandom(16), "big"))
        for length in (0, 1, 3, 31, 257, 2048):
            value = ''.join(rng.choice(string.ascii_letters + string.digits + string.punctuation) for _ in range(length)).encode()
            actual = wrapper.encode_string(value)
            assert actual is not None
            assert actual.decode("ascii").upper() == value.hex().upper()
    except Exception as e:
        pytest.fail(f"Failed to load wrapper.so or call encode_string: {e}")


def test_ws_server_really_calls_ctypes_wrapper():
    wrapper_path = os.path.join(PROJECT_DIR, "wrapper.so")
    backup_path = "/tmp/wrapper.so.submitted"
    probe_source = "/tmp/wrapper_probe.c"
    with open(wrapper_path, "rb") as src, open(backup_path, "wb") as dst:
        dst.write(src.read())
    with open(probe_source, "w") as f:
        f.write('#include <stdlib.h>\n#include <string.h>\nchar *encode_string(const char *s) { (void)s; return strdup("CTYPES_WRAPPER_PROBE_7D91"); }\n')

    proc = None
    try:
        result = subprocess.run(
            ["gcc", "-shared", "-fPIC", probe_source, "-o", wrapper_path],
            text=True, capture_output=True, timeout=20,
        )
        assert result.returncode == 0, result.stdout + result.stderr
        proc = run_server()
        replies = websocket_roundtrips(["not-a-hardcoded-hex-request"])
        assert replies == ["CTYPES_WRAPPER_PROBE_7D91"], \
            "The WebSocket server did not return the value produced by encode_string in wrapper.so"
    finally:
        if proc is not None:
            stop_server(proc)
        with open(backup_path, "rb") as src, open(wrapper_path, "wb") as dst:
            dst.write(src.read())


def test_websocket_service_dynamic_end_to_end():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    alphabet = string.ascii_letters + string.digits + " _-!@#$%^&*()"
    random_messages = [
        ''.join(rng.choice(alphabet) for _ in range(length))
        for length in (1, 5, 37, 193, 1025)
    ]
    messages = ["", "PolyglotData123"] + random_messages
    proc = run_server()
    try:
        replies = websocket_roundtrips(messages)
    finally:
        stop_server(proc)
    expected = [message.encode("utf-8").hex().upper() for message in messages]
    assert [str(reply).upper() for reply in replies] == expected


def test_output_log_correct():
    assert os.path.isfile(OUTPUT_LOG), f"{OUTPUT_LOG} does not exist."
    with open(OUTPUT_LOG, "r") as f:
        content = f.read().strip()
    assert EXPECTED_HEX.lower() in content.lower(), f"Expected hex string {EXPECTED_HEX} not found in {OUTPUT_LOG}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
