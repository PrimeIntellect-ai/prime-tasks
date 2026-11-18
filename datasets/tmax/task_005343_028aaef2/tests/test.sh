#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import signal
import socket
import subprocess
import threading
import time
from pathlib import Path

SANITIZER = Path("/home/user/sanitizer.sh")
BRIDGE = Path("/home/user/run_bridge.sh")


def test_scripts_exist_and_executable():
    sanitizer_path = "/home/user/sanitizer.sh"
    bridge_path = "/home/user/run_bridge.sh"

    assert os.path.isfile(sanitizer_path), f"{sanitizer_path} does not exist or is not a file."
    assert os.access(sanitizer_path, os.X_OK), f"{sanitizer_path} is not executable."

    assert os.path.isfile(bridge_path), f"{bridge_path} does not exist or is not a file."
    assert os.access(bridge_path, os.X_OK), f"{bridge_path} is not executable."


def test_sanitizer_clean_corpus():
    clean_dir = Path("/app/corpora/clean")
    sanitizer_path = "/home/user/sanitizer.sh"

    assert clean_dir.exists() and clean_dir.is_dir(), "Clean corpus directory missing."

    modified_files = []

    for file_path in clean_dir.iterdir():
        if file_path.is_file():
            with open(file_path, "rb") as f:
                input_data = f.read()

            result = subprocess.run([sanitizer_path], input=input_data, capture_output=True)
            if result.stdout != input_data:
                modified_files.append(file_path.name)

    assert not modified_files, f"{len(modified_files)} of {len(list(clean_dir.iterdir()))} clean files modified: {', '.join(modified_files)}"


def test_sanitizer_evil_corpus():
    evil_dir = Path("/app/corpora/evil")
    sanitizer_path = "/home/user/sanitizer.sh"

    assert evil_dir.exists() and evil_dir.is_dir(), "Evil corpus directory missing."

    bypassed_files = []

    for file_path in evil_dir.iterdir():
        if file_path.is_file():
            with open(file_path, "rb") as f:
                input_data = f.read()

            result = subprocess.run([sanitizer_path], input=input_data, capture_output=True)
            if result.stdout.strip():
                bypassed_files.append(file_path.name)

    assert not bypassed_files, f"{len(bypassed_files)} of {len(list(evil_dir.iterdir()))} evil files bypassed: {', '.join(bypassed_files)}"


def make_line(value, token):
    return f'[2099-07-14T01:02:03Z] INFO: latency={value}ms query="SELECT {token}"\n'.encode()


def test_sanitizer_randomized_mixed_streams():
    rng = random.SystemRandom()
    for _ in range(4):
        token = secrets.token_hex(12)
        valid_values = [
            "0",
            str(rng.randint(1, 999999)),
            f"{rng.randint(0, 9999)}.{rng.randint(1, 999999)}",
        ]
        invalid_values = [
            f"-{rng.randint(1, 9999)}.{rng.randint(1, 999)}",
            "NaN",
            "null",
            f"{rng.randint(1, 999)}x{rng.randint(1, 99)}",
            f"{rng.randint(1, 99)}..{rng.randint(1, 99)}",
            f"{rng.randint(1, 99)}.{rng.randint(1, 99)}e3",
            f"{rng.randint(1, 99)}_{rng.randint(1, 99)}",
        ]
        records = [(make_line(v, token + "_valid_" + str(i)), True)
                   for i, v in enumerate(valid_values)]
        records += [(make_line(v, token + "_invalid_" + str(i)), False)
                    for i, v in enumerate(invalid_values)]
        rng.shuffle(records)
        input_data = b"".join(line for line, _ in records)
        expected = b"".join(line for line, is_valid in records if is_valid)

        result = subprocess.run(
            [str(SANITIZER)], input=input_data, capture_output=True, timeout=4
        )
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert result.stdout == expected, (
            "sanitizer did not preserve exactly the dynamically generated valid "
            "lines while rejecting malformed latency values"
        )


def test_bridge_script_content():
    bridge_path = "/home/user/run_bridge.sh"

    with open(bridge_path, "r") as f:
        content = f.read()

    assert "8081" in content, "run_bridge.sh does not reference port 8081"
    assert "8082" in content, "run_bridge.sh does not reference port 8082"
    assert "sanitizer.sh" in content, "run_bridge.sh does not reference sanitizer.sh"


def test_bridge_forwards_through_sanitizer():
    token = secrets.token_hex(16)
    valid_a = make_line(f"{random.randint(10, 900)}.{random.randint(1, 999)}", token + "_a")
    invalid_a = make_line(f"-{random.randint(1, 900)}.{random.randint(1, 999)}", token + "_badneg")
    valid_b = make_line(str(random.randint(1, 9000)), token + "_b")
    invalid_b = make_line("NaN", token + "_badnan")
    payload = valid_a + invalid_a + valid_b + invalid_b
    expected = valid_a + valid_b

    source_listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sink_listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    for listener, port in ((source_listener, 8081), (sink_listener, 8082)):
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", port))
        listener.listen(2)
        listener.settimeout(6)

    original_bytes = SANITIZER.read_bytes()
    original_mode = SANITIZER.stat().st_mode
    saved = Path(f"/tmp/sanitizer-original-{secrets.token_hex(8)}")
    marker = Path(f"/tmp/sanitizer-called-{secrets.token_hex(8)}")
    saved.write_bytes(original_bytes)
    saved.chmod(original_mode)
    SANITIZER.write_text(
        "#!/bin/sh\n"
        f"printf called > '{marker}'\n"
        f"exec '{saved}'\n"
    )
    SANITIZER.chmod(original_mode | 0o111)

    received = bytearray()
    errors = []
    source_done = threading.Event()

    def serve_source():
        try:
            conn, _ = source_listener.accept()
            with conn:
                conn.sendall(payload)
                conn.shutdown(socket.SHUT_WR)
            source_done.set()
        except Exception as exc:
            errors.append(f"emitter side: {exc}")
        finally:
            source_listener.close()

    def receive_sink():
        try:
            conn, _ = sink_listener.accept()
            with conn:
                conn.settimeout(0.2)
                deadline = time.monotonic() + 6
                last_data = None
                while time.monotonic() < deadline:
                    try:
                        chunk = conn.recv(65536)
                        if not chunk:
                            break
                        received.extend(chunk)
                        last_data = time.monotonic()
                    except socket.timeout:
                        if last_data is not None and time.monotonic() - last_data > 0.7:
                            break
        except Exception as exc:
            errors.append(f"aggregator side: {exc}")
        finally:
            sink_listener.close()

    source_thread = threading.Thread(target=serve_source, daemon=True)
    sink_thread = threading.Thread(target=receive_sink, daemon=True)
    process = None
    try:
        source_thread.start()
        sink_thread.start()
        process = subprocess.Popen(
            [str(BRIDGE)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        source_thread.join(8)
        sink_thread.join(8)
    finally:
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=2)
            except Exception:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        source_listener.close()
        sink_listener.close()
        SANITIZER.write_bytes(original_bytes)
        SANITIZER.chmod(original_mode)
        saved.unlink(missing_ok=True)

    assert not source_thread.is_alive(), "bridge never connected to localhost:8081"
    assert not sink_thread.is_alive(), "bridge never delivered a stream to localhost:8082"
    assert not errors, "; ".join(errors)
    assert marker.exists(), "bridge did not execute /home/user/sanitizer.sh"
    marker.unlink(missing_ok=True)
    assert bytes(received) == expected, (
        "bridge did not forward exactly the dynamically sanitized stream from "
        "localhost:8081 to localhost:8082"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
