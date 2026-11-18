#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure the verifier-controlled server can bind to the required port.
pkill -f '^/home/user/venv/bin/python /home/user/server.py' 2>/dev/null || true
if command -v fuser >/dev/null 2>&1; then
    fuser -k 8765/tcp >/dev/null 2>&1 || true
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import shutil
import subprocess
import time
import uuid

import pytest

SO_PATH = "/home/user/parser/target/release/libparser.so"
RS_PATH = "/home/user/parser/src/lib.rs"
CLIENT_PATH = "/home/user/client.py"
RESULT_PATH = "/home/user/benchmark_result.json"


def test_rust_library_compiled():
    assert os.path.exists(SO_PATH), f"Compiled shared library not found at {SO_PATH}. Did you compile in release mode?"
    assert os.path.isfile(SO_PATH), f"{SO_PATH} is not a regular file."
    with open(SO_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SO_PATH} is not an ELF shared library."


def test_rust_source_fixed():
    assert os.path.exists(RS_PATH), f"Rust source file missing at {RS_PATH}."
    with open(RS_PATH, "r") as f:
        content = f.read()
    assert "into_raw()" in content, "The Rust bug does not appear to be fixed. Expected to see `into_raw()` used to hand over ownership of the CString."
    assert "as_ptr()" not in content.split("BUG:")[1] if "BUG:" in content else True, "The buggy `as_ptr()` return might still be present."


def test_benchmark_result_json():
    assert os.path.exists(RESULT_PATH), f"Benchmark result file not found at {RESULT_PATH}."
    with open(RESULT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULT_PATH} does not contain valid JSON.")

    assert "message_count" in data, "JSON missing 'message_count' key."
    assert data["message_count"] == 100, f"Expected message_count to be 100, got {data['message_count']}."
    assert "total_time_ms" in data, "JSON missing 'total_time_ms' key."
    assert isinstance(data["total_time_ms"], (int, float)), "total_time_ms must be a number."
    assert data["total_time_ms"] > 0, f"Expected total_time_ms to be > 0, got {data['total_time_ms']}."
    assert "last_message_decoded" in data, "JSON missing 'last_message_decoded' key."
    expected_last_message = "FINAL_TEST_MESSAGE_SUCCESS"
    assert data["last_message_decoded"] == expected_last_message, f"Expected last_message_decoded to be '{expected_last_message}', got '{data['last_message_decoded']}'."


def test_client_script_exists():
    assert os.path.exists(CLIENT_PATH), f"Client script not found at {CLIENT_PATH}."
    assert os.path.isfile(CLIENT_PATH), f"{CLIENT_PATH} is not a regular file."


def test_native_library_decodes_runtime_inputs():
    lib = ctypes.CDLL(SO_PATH)
    decode = lib.decode_message
    decode.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
    decode.restype = ctypes.c_void_p

    token = uuid.uuid4().hex
    cases = [
        b"\x00" + ("utf8_" + token).encode("utf-8"),
        b"\x00" + ("snowman_\u2603_" + token).encode("utf-8"),
        b"\x01" + ("utf16_" + token).encode("utf-16le"),
        b"\x01" + ("wide_\u03a9_" + token).encode("utf-16le"),
    ]
    expected = [
        "utf8_" + token,
        "snowman_\u2603_" + token,
        "utf16_" + token,
        "wide_\u03a9_" + token,
    ]

    for encoded, wanted in zip(cases, expected):
        buf = (ctypes.c_uint8 * len(encoded)).from_buffer_copy(encoded)
        ptr = decode(buf, len(encoded))
        assert ptr, "decode_message returned a null pointer for a valid message."
        assert ctypes.string_at(ptr).decode("utf-8") == wanted


def _contains_subsequence(actual, expected):
    pos = 0
    for item in actual:
        if pos < len(expected) and item == expected[pos]:
            pos += 1
    return pos == len(expected)


def test_client_runs_pipeline_and_uses_ffi(tmp_path):
    token = uuid.uuid4().hex
    messages = [f"Probe_{i:02d}_{token}" for i in range(99)]
    final_message = f"RUNTIME_FINAL_{token}"
    expected_decoded = messages + [final_message]

    ready_path = tmp_path / "server.ready"
    server_script = tmp_path / "runtime_server.py"
    server_script.write_text(
        "import asyncio\n"
        "import websockets\n"
        f"messages = {messages!r}\n"
        f"final_message = {final_message!r}\n"
        f"ready_path = {str(ready_path)!r}\n"
        "done = asyncio.Event()\n"
        "async def handler(ws):\n"
        "    try:\n"
        "        for message in messages:\n"
        "            await ws.send(b'\\x00' + message.encode('utf-8'))\n"
        "        await ws.send(b'\\x01' + final_message.encode('utf-16le'))\n"
        "    finally:\n"
        "        done.set()\n"
        "async def main():\n"
        "    async with websockets.serve(handler, '127.0.0.1', 8765):\n"
        "        open(ready_path, 'w').close()\n"
        "        await done.wait()\n"
        "        await asyncio.sleep(0.2)\n"
        "asyncio.run(main())\n"
    )

    # Temporarily install an ABI-compatible instrumented decoder. The native
    # submission was exercised above; this proves the client loads the required
    # path and passes every WebSocket payload through decode_message.
    call_log = tmp_path / "ffi_calls.log"
    spy_c = tmp_path / "spy.c"
    spy_so = tmp_path / "libparser_spy.so"
    spy_c.write_text(r'''
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>

static char output[16384];

char *decode_message(const uint8_t *data, size_t len) {
    size_t j = 0;
    if (!data || len == 0) return NULL;
    if (data[0] == 0) {
        for (size_t i = 1; i < len && j + 1 < sizeof(output); i++) output[j++] = (char)data[i];
    } else {
        for (size_t i = 1; i + 1 < len && j + 1 < sizeof(output); i += 2) {
            uint16_t ch = (uint16_t)data[i] | ((uint16_t)data[i + 1] << 8);
            if (ch < 0x80) output[j++] = (char)ch;
            else output[j++] = '?';
        }
    }
    output[j] = '\0';
    FILE *f = fopen("''' + str(call_log) + r'''", "a");
    if (f) { fprintf(f, "%s\n", output); fclose(f); }
    return output;
}
''')
    subprocess.run(["cc", "-shared", "-fPIC", "-O2", str(spy_c), "-o", str(spy_so)], check=True)

    backup = tmp_path / "submitted_libparser.so"
    shutil.copy2(SO_PATH, backup)
    shutil.copy2(spy_so, SO_PATH)

    server = None
    try:
        if os.path.exists(RESULT_PATH):
            os.unlink(RESULT_PATH)

        server = subprocess.Popen(
            ["/home/user/venv/bin/python", str(server_script)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        deadline = time.time() + 10
        while not ready_path.exists() and time.time() < deadline:
            if server.poll() is not None:
                out, err = server.communicate()
                pytest.fail(f"Verifier WebSocket server exited early. stdout={out!r} stderr={err!r}")
            time.sleep(0.05)
        assert ready_path.exists(), "Verifier WebSocket server did not become ready."

        run = subprocess.run(
            ["/home/user/venv/bin/python", CLIENT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert run.returncode == 0, f"client.py failed. stdout={run.stdout!r} stderr={run.stderr!r}"

        server.wait(timeout=10)
        assert server.returncode == 0, "Verifier WebSocket server failed while serving the client."
    finally:
        shutil.copy2(backup, SO_PATH)
        if server is not None and server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()

    assert os.path.exists(RESULT_PATH), "client.py did not create benchmark_result.json when executed."
    with open(RESULT_PATH, "r") as f:
        result = json.load(f)
    assert set(result) == {"message_count", "total_time_ms", "last_message_decoded"}, "benchmark_result.json has the wrong structure."
    assert result["message_count"] == 100
    assert isinstance(result["total_time_ms"], float), "total_time_ms must be a float."
    assert result["total_time_ms"] > 0
    assert result["last_message_decoded"] == final_message, "The client did not report the runtime-generated final message."

    assert call_log.exists(), "decode_message was never called by client.py."
    calls = call_log.read_text().splitlines()
    assert _contains_subsequence(calls, expected_decoded), "client.py did not pass all 100 received payloads through decode_message in order."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
