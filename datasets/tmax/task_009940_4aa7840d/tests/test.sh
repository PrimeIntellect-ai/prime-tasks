#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import socket
import sqlite3
import struct
import subprocess
import threading
import time
import pytest

SCRIPT_PATH = "/home/user/secure_deploy.sh"
VERIFIER_DIR = "/home/user/verifier"
VERIFIER_BIN = "/home/user/verifier/verifier"
DB_PATH = "/home/user/deploy.db"
VALGRIND_LOG = "/home/user/valgrind.log"
WS_RESPONSE_FILE = "/home/user/ws_response.txt"

PIN = random.SystemRandom().randint(2000, 9000)

MAIN_SOURCE = f'''#include <stdio.h>

extern double compute_hash(double val);

int get_deployment_pin() {{
    return {PIN};
}}

int main(int argc, char** argv) {{
    double res = compute_hash(42.0);
    printf("Result: %f\\n", res);
    return 0;
}}
'''

CRYPTO_SOURCE = '''#include <math.h>

double compute_hash(double val) {
    return sqrt(val) * 2.5;
}
'''

BROKEN_MAKEFILE = '''all: verifier

verifier: main.o crypto_utils.o
\tgcc -o verifier -lm main.o crypto_utils.o

main.o: main.c
\tgcc -c main.c

crypto_utils.o: crypto_utils.c
\tgcc -c crypto_utils.c

clean:
\trm -f *.o verifier
'''


def reset_inputs():
    os.makedirs(VERIFIER_DIR, exist_ok=True)
    with open(os.path.join(VERIFIER_DIR, "main.c"), "w") as f:
        f.write(MAIN_SOURCE)
    with open(os.path.join(VERIFIER_DIR, "crypto_utils.c"), "w") as f:
        f.write(CRYPTO_SOURCE)
    with open(os.path.join(VERIFIER_DIR, "Makefile"), "w") as f:
        f.write(BROKEN_MAKEFILE)

    for name in ("main.o", "crypto_utils.o", "verifier"):
        try:
            os.remove(os.path.join(VERIFIER_DIR, name))
        except FileNotFoundError:
            pass
    for path in (VALGRIND_LOG, WS_RESPONSE_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    try:
        os.remove(DB_PATH)
    except FileNotFoundError:
        pass
    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE releases (id INTEGER PRIMARY KEY, version TEXT)")
    conn.execute("INSERT INTO releases (version) VALUES ('v1.0.0')")
    conn.commit()
    conn.close()


def recv_exact(conn, count):
    data = b""
    while len(data) < count:
        chunk = conn.recv(count - len(data))
        if not chunk:
            raise RuntimeError("WebSocket connection closed early")
        data += chunk
    return data


def websocket_server(received_messages, ready, error_box):
    server = None
    conn = None
    try:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", 8765))
        server.listen(1)
        server.settimeout(45)
        ready.set()
        conn, _ = server.accept()
        conn.settimeout(15)

        request = b""
        while b"\r\n\r\n" not in request:
            request += conn.recv(4096)
        match = re.search(br"(?im)^Sec-WebSocket-Key:\s*([^\r\n]+)", request)
        if not match:
            raise RuntimeError("Missing WebSocket key")
        accept = hashlib.sha1(match.group(1).strip() + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest()
        import base64
        response = (
            b"HTTP/1.1 101 Switching Protocols\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n"
            b"Sec-WebSocket-Accept: " + base64.b64encode(accept) + b"\r\n\r\n"
        )
        conn.sendall(response)

        first, second = recv_exact(conn, 2)
        opcode = first & 0x0f
        masked = bool(second & 0x80)
        length = second & 0x7f
        if length == 126:
            length = struct.unpack("!H", recv_exact(conn, 2))[0]
        elif length == 127:
            length = struct.unpack("!Q", recv_exact(conn, 8))[0]
        mask = recv_exact(conn, 4) if masked else b""
        payload = recv_exact(conn, length)
        if masked:
            payload = bytes(value ^ mask[i % 4] for i, value in enumerate(payload))
        if opcode != 1:
            raise RuntimeError(f"Expected a text frame, got opcode {opcode}")
        received_messages.append(payload.decode("utf-8"))

        reply = b'{"status": "ok"}'
        conn.sendall(bytes([0x81, len(reply)]) + reply)
        time.sleep(0.1)
        conn.sendall(b"\x88\x00")
    except Exception as exc:
        error_box.append(exc)
        ready.set()
    finally:
        if conn is not None:
            conn.close()
        if server is not None:
            server.close()


@pytest.fixture(scope="module")
def run_script():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    with open(SCRIPT_PATH, "rb") as f:
        script_bytes = f.read()
    assert script_bytes.startswith(b"#!") and b"bash" in script_bytes.splitlines()[0], "secure_deploy.sh is not a Bash script."
    script_text = script_bytes.decode("utf-8", errors="replace")
    assert re.search(r"/usr/local/bin/websocat\s+ws://localhost:8765(?:\s|$)", script_text), "Script does not contain the required exact websocat command and endpoint."

    reset_inputs()
    received_messages = []
    errors = []
    ready = threading.Event()
    thread = threading.Thread(target=websocket_server, args=(received_messages, ready, errors), daemon=True)
    thread.start()
    assert ready.wait(5), "WebSocket test server failed to start."
    assert not errors, f"WebSocket test server failed: {errors}"

    result = subprocess.run(
        ["/bin/bash", "-x", SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=60,
        env={**os.environ, "LC_ALL": "C"},
    )
    thread.join(timeout=5)
    yield result, received_messages, errors


def test_script_execution(run_script):
    result, _, errors = run_script
    assert result.returncode == 0, f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    assert not errors, f"WebSocket server error: {errors}"


def test_required_commands_executed_in_order(run_script):
    result, _, _ = run_script
    trace = result.stderr
    patterns = [
        r"(?m)^\++\s+(?:command\s+)?make(?:\s|$)",
        r"(?m)^\++\s+(?:command\s+)?(?:/usr/bin/)?valgrind\b[^\n]*?/home/user/verifier/verifier\s+/dev/null(?:\s|$)",
        r"(?m)^\++\s+(?:command\s+)?(?:/usr/bin/)?objdump\b[^\n]*?/home/user/verifier/verifier(?:\s|$)",
        r"(?m)^\++\s+(?:command\s+)?/usr/local/bin/websocat\s+ws://localhost:8765(?:\s|$)",
    ]
    positions = []
    for pattern in patterns:
        match = re.search(pattern, trace)
        assert match, f"Required command was not actually executed; missing trace pattern: {pattern}"
        positions.append(match.start())
    assert positions == sorted(positions), "make, valgrind, objdump, and websocat were not executed in the required order."


def test_makefile_fixed_and_project_built(run_script):
    makefile_path = os.path.join(VERIFIER_DIR, "Makefile")
    with open(makefile_path) as f:
        content = f.read()
    target = re.search(r"(?m)^verifier\s*:\s*([^\n]+)", content)
    assert target, "Makefile has no verifier target."
    assert "main.o" in target.group(1) and "crypto_utils.o" in target.group(1), "Verifier target does not depend on both supplied object files."

    recipes = [line.strip() for line in content.splitlines() if line.startswith("\t") and "-lm" in line]
    assert recipes, "Makefile link recipe does not link libm."
    valid_order = False
    for recipe in recipes:
        lm_pos = recipe.find("-lm")
        if "$^" in recipe and recipe.find("$^") < lm_pos:
            valid_order = True
        elif "main.o" in recipe and "crypto_utils.o" in recipe:
            valid_order = recipe.find("main.o") < lm_pos and recipe.find("crypto_utils.o") < lm_pos
    assert valid_order, "Makefile still places -lm before the object files."

    assert os.path.isfile(VERIFIER_BIN), "Verifier binary was not compiled."
    assert os.access(VERIFIER_BIN, os.X_OK), "Verifier binary is not executable."
    with open(VERIFIER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Verifier is not a compiled ELF binary."
    for obj in ("main.o", "crypto_utils.o"):
        path = os.path.join(VERIFIER_DIR, obj)
        assert os.path.isfile(path), f"Expected make output {obj} is missing."
        assert os.path.getmtime(path) >= os.path.getmtime(os.path.join(VERIFIER_DIR, obj.replace('.o', '.c'))), f"{obj} was not freshly built from its supplied source."

    symbols = subprocess.check_output(["nm", VERIFIER_BIN], text=True)
    for symbol in ("main", "compute_hash", "get_deployment_pin"):
        assert re.search(rf"\b{symbol}$", symbols, re.MULTILINE), f"Compiled binary is missing supplied-source symbol {symbol}."
    execution = subprocess.run([VERIFIER_BIN, "/dev/null"], capture_output=True, text=True, timeout=5)
    assert execution.returncode == 0, "Compiled verifier does not run successfully."
    assert "Result: 16.201852" in execution.stdout, "Compiled verifier does not exhibit the behavior of the supplied sources."


def test_pin_in_compiled_binary(run_script):
    disassembly = subprocess.check_output(["objdump", "-d", VERIFIER_BIN], text=True)
    function = re.search(r"<get_deployment_pin>:(.*?)(?=\n[0-9a-f]+\s+<|\Z)", disassembly, re.DOTALL)
    assert function, "Compiled binary has no get_deployment_pin assembly function."
    immediate = re.search(r"mov\s+\$0x([0-9a-fA-F]+)\s*,\s*%eax", function.group(1))
    assert immediate, "get_deployment_pin does not load an immediate PIN into eax."
    assert int(immediate.group(1), 16) == PIN, "Binary was not built from the supplied PIN-bearing source."


def test_sqlite_schema_migrated(run_script):
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    columns = {col[1]: col for col in conn.execute("PRAGMA table_info(releases)").fetchall()}
    row = conn.execute("SELECT version, is_secure FROM releases WHERE id = 1").fetchone()
    conn.close()
    assert "is_secure" in columns, "Column 'is_secure' was not added to the 'releases' table."
    assert "INTEGER" in columns["is_secure"][2].upper(), "Column 'is_secure' is not of type INTEGER."
    default = columns["is_secure"][4]
    assert default is not None and re.sub(r"[()'\"\s]", "", str(default)) == "1", "Column 'is_secure' does not have DEFAULT 1."
    assert row == ("v1.0.0", 1), "The migration did not apply DEFAULT 1 to the existing release."


def test_real_valgrind_run(run_script):
    assert os.path.isfile(VALGRIND_LOG), f"Valgrind log {VALGRIND_LOG} is missing."
    with open(VALGRIND_LOG, "r", errors="replace") as f:
        content = f.read()
    assert "Memcheck" in content or "valgrind" in content.lower(), "Valgrind log does not contain expected valgrind output."
    assert re.search(r"Command:\s+/home/user/verifier/verifier\s+/dev/null", content), "Valgrind was not run on the compiled verifier with /dev/null."
    assert "HEAP SUMMARY:" in content, "Valgrind log has no completed heap summary."
    assert re.search(r"ERROR SUMMARY:\s+0 errors", content), "Valgrind did not complete successfully without memory errors."


def test_websocket_message_and_response(run_script):
    _, received_messages, _ = run_script
    assert len(received_messages) > 0, "No WebSocket messages were received by the server."
    expected = f'{{"status": "ready", "pin": {PIN}, "leaks_checked": true}}'
    assert received_messages[-1] == expected, f"WebSocket payload was not exact. Expected {expected!r}, got {received_messages[-1]!r}."
    assert os.path.isfile(WS_RESPONSE_FILE), f"Response file {WS_RESPONSE_FILE} is missing."
    with open(WS_RESPONSE_FILE) as f:
        response = f.read().strip()
    assert response == '{"status": "ok"}', f"Server response was not saved correctly: {response!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
