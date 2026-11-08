#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import asyncio
import os
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

import websockets

APP_LIB = "/app/libtelemetry.so"
APP_SRC = "/app/libtelemetry.c"
AUDIO = "/app/telemetry.wav"
URI = "ws://127.0.0.1:8765"
EXPECTED = "SYSTEM_STABLE_ALL_GREEN"


def run_decoder(libpath):
    helper = r'''
import ctypes, json, sys
lib = ctypes.CDLL(sys.argv[1])
lib.init_decoder.argtypes = []
lib.init_decoder.restype = None
lib.decode_audio.argtypes = [ctypes.c_char_p]
lib.decode_audio.restype = ctypes.c_void_p
lib.free_string.argtypes = [ctypes.c_void_p]
lib.free_string.restype = None
lib.init_decoder()
missing = lib.decode_audio(b"/tmp/verifier-file-that-does-not-exist")
p = lib.decode_audio(b"/app/telemetry.wav")
if not p:
    raise RuntimeError("decode_audio returned NULL for telemetry.wav")
try:
    value = ctypes.string_at(p).decode("ascii")
finally:
    lib.free_string(p)
print(json.dumps({"missing_is_null": not bool(missing), "value": value}))
'''
    import json
    result = subprocess.run(
        ["python3", "-c", helper, libpath], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout.strip())


def listener_info():
    listeners = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                local, state, inode = fields[1], fields[3], fields[9]
                address, port = local.rsplit(":", 1)
                if port.upper() == "223D" and state == "0A":
                    listeners.append((table, address.upper(), inode))
    return listeners


def pid_for_inode(inode):
    needle = f"socket:[{inode}]"
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(f"{fd_dir}/{fd}") == needle:
                        return int(entry)
                except OSError:
                    pass
        except OSError:
            pass
    return None


def process_launch_info(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [x.decode() for x in f.read().split(b"\0") if x]
    assert argv, "Could not determine the WebSocket server command"
    executable = os.readlink(f"/proc/{pid}/exe")
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = os.environ.copy()
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            for item in f.read().split(b"\0"):
                if b"=" in item:
                    k, v = item.split(b"=", 1)
                    env[k.decode(errors="ignore")] = v.decode(errors="ignore")
    except OSError:
        pass
    return [executable] + argv[1:], cwd, env


async def exchange(valid_expected, invalid_messages):
    async with websockets.connect(URI) as websocket:
        await websocket.send("GET_TELEMETRY")
        response = await asyncio.wait_for(websocket.recv(), timeout=2.0)
        assert response == valid_expected, f"Expected {valid_expected!r}, got {response!r}"
        for message in invalid_messages:
            await websocket.send(message)
            response = await asyncio.wait_for(websocket.recv(), timeout=2.0)
            assert response == "INVALID_COMMAND", f"Expected 'INVALID_COMMAND', got {response!r}"


async def wait_and_exchange(expected, invalid_messages, process=None):
    deadline = time.time() + 8
    last = None
    while time.time() < deadline:
        if process is not None and process.poll() is not None:
            out, err = process.communicate(timeout=1)
            raise AssertionError(f"Restarted server exited early ({process.returncode}):\n{out}\n{err}")
        try:
            await exchange(expected, invalid_messages)
            return
        except Exception as exc:
            last = exc
            await asyncio.sleep(0.15)
    raise AssertionError(f"WebSocket server was unavailable or incorrect: {last}")


def test_complete_integration():
    # Preserve the original artifact assertion, and ensure it is an actual ELF library.
    assert os.path.isfile(APP_LIB), "Shared library /app/libtelemetry.so was not compiled."
    with open(APP_LIB, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libtelemetry.so is not an ELF shared library"

    # Independently compile the provided source and derive/check the library behavior through its ABI.
    reference = tempfile.mktemp(prefix="reference-telemetry-", suffix=".so")
    subprocess.run(
        ["gcc", "-shared", "-fPIC", APP_SRC, "-o", reference],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    submitted_result = run_decoder(APP_LIB)
    reference_result = run_decoder(reference)
    assert submitted_result == reference_result
    assert submitted_result["missing_is_null"] is True
    assert submitted_result["value"] == EXPECTED

    # Preserve the original live WebSocket assertions.
    listeners = listener_info()
    assert listeners, "WebSocket server is not running on port 8765"
    ipv4 = [x for x in listeners if x[0].endswith("tcp")]
    assert ipv4 and all(x[1] == "0100007F" for x in ipv4), \
        "Server must listen strictly on IPv4 address 127.0.0.1"
    asyncio.run(wait_and_exchange(EXPECTED, ["UNKNOWN_COMMAND"]))

    # Record how to restart the submitted foreground server, then replace only the
    # library with an instrumented ABI-compatible implementation. Its answer is
    # generated at verification time, so a hardcoded server cannot pass.
    pid = pid_for_inode(ipv4[0][2])
    assert pid is not None, "Could not identify the process serving port 8765"
    command, cwd, env = process_launch_info(pid)

    token = "AUDIT_" + uuid.uuid4().hex
    payload = token.encode().hex()
    log_path = "/tmp/telemetry-audit-" + uuid.uuid4().hex + ".log"
    probe_src = tempfile.mktemp(prefix="telemetry-probe-", suffix=".c")
    probe_so = tempfile.mktemp(prefix="telemetry-probe-", suffix=".so")
    backup = tempfile.mktemp(prefix="submitted-telemetry-", suffix=".so")
    shutil.copy2(APP_LIB, backup)

    source = f'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int initialized = 0;
static void *last_allocation = NULL;
static void event(const char *name, const char *arg) {{
    FILE *f = fopen("{log_path}", "a");
    if (!f) abort();
    fprintf(f, "%s%s%s\\n", name, arg ? " " : "", arg ? arg : "");
    fclose(f);
}}
void init_decoder(void) {{
    FILE *maps = fopen("/proc/self/maps", "r");
    char line[4096];
    if (maps) {{
        while (fgets(line, sizeof(line), maps)) {{
            if (strstr(line, "_socket.") || strstr(line, "_ssl.")) {{
                fclose(maps); event("LATE_INIT", NULL); abort();
            }}
        }}
        fclose(maps);
    }}
    initialized = 1;
    event("INIT", NULL);
}}
char *decode_audio(const char *filepath) {{
    if (!initialized) {{ event("DECODE_BEFORE_INIT", filepath); abort(); }}
    event("DECODE", filepath);
    if (!filepath || strcmp(filepath, "{AUDIO}") != 0) return NULL;
    FILE *f = fopen(filepath, "rb");
    if (!f) return NULL;
    fclose(f);
    const char *payload = "{payload}";
    char *result = malloc(strlen(payload) + 1);
    if (!result) abort();
    strcpy(result, payload);
    last_allocation = result;
    return result;
}}
void free_string(char *str) {{
    if (!str || str != last_allocation) {{ event("BAD_FREE", NULL); abort(); }}
    event("FREE", NULL);
    last_allocation = NULL;
    free(str);
}}
'''
    with open(probe_src, "w") as f:
        f.write(source)
    subprocess.run(["gcc", "-shared", "-fPIC", probe_src, "-o", probe_so], check=True)

    restarted = None
    try:
        os.kill(pid, signal.SIGTERM)
        deadline = time.time() + 3
        while time.time() < deadline:
            try:
                os.kill(pid, 0)
                time.sleep(0.05)
            except ProcessLookupError:
                break
        else:
            os.kill(pid, signal.SIGKILL)
            time.sleep(0.2)

        os.replace(probe_so, APP_LIB)
        restarted = subprocess.Popen(
            command, cwd=cwd, env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        random_invalid = "INVALID_" + uuid.uuid4().hex
        asyncio.run(wait_and_exchange(token, ["UNKNOWN_COMMAND", random_invalid], restarted))

        with open(log_path) as f:
            events = [line.strip() for line in f if line.strip()]
        assert "LATE_INIT" not in events, "C decoder was initialized after network modules"
        assert "DECODE_BEFORE_INIT" not in events
        assert "BAD_FREE" not in events
        assert "INIT" in events, "init_decoder() was not called"
        decode_event = "DECODE " + AUDIO
        assert decode_event in events, "decode_audio() was not called with /app/telemetry.wav"
        assert "FREE" in events, "free_string() was not called on the returned allocation"
        assert events.index("INIT") < events.index(decode_event) < events.index("FREE"), \
            "Required init/decode/free ordering was not observed"
    finally:
        if restarted is not None and restarted.poll() is None:
            restarted.terminate()
            try:
                restarted.wait(timeout=2)
            except subprocess.TimeoutExpired:
                restarted.kill()
        shutil.copy2(backup, APP_LIB)
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
