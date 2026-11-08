#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import http.server
import os
import random
import signal
import subprocess
import threading
import time
import urllib.request

HOME = "/home/user"
PORT = 8080


def kill_port(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(name))
                    break
        except OSError:
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.25)


def get_api(value, timeout=2):
    with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/api/{value}", timeout=timeout) as response:
        return response.read().decode().strip()


def start_submitted_server():
    proc = subprocess.Popen(
        ["python3", f"{HOME}/mock_server.py"],
        cwd=HOME,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 5
    last_error = None
    while time.time() < deadline:
        try:
            assert get_api(0, timeout=0.5) == "0"
            return proc
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"mock_server.py did not start a working server on port 8080: {last_error}")


def run_emulator(a, b, expected):
    result_file = f"{HOME}/integration_result.txt"
    try:
        os.unlink(result_file)
    except FileNotFoundError:
        pass
    completed = subprocess.run(
        [f"{HOME}/emulator", "1", str(a), "1", str(b), "2", "3", "4"],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, f"emulator failed: {completed.stderr}"
    assert os.path.isfile(result_file), "emulator did not create integration_result.txt"
    with open(result_file) as f:
        actual = f.read().strip()
    assert actual == str(expected), f"Expected emulator result {expected}, got {actual}"


def main():
    # Preserve the original final-state assertions.
    result_file = f"{HOME}/integration_result.txt"
    assert os.path.isfile(result_file), f"{result_file} does not exist. Did the emulator run successfully?"
    with open(result_file) as f:
        content = f.read().strip()
    assert content == "4200", f"Expected integration_result.txt to contain '4200', but got '{content}'."

    exe_file = f"{HOME}/emulator"
    assert os.path.isfile(exe_file), f"{exe_file} does not exist. Was the code compiled?"
    assert os.access(exe_file, os.X_OK), f"{exe_file} is not executable."

    makefile_path = f"{HOME}/Makefile"
    assert os.path.isfile(makefile_path), f"{makefile_path} does not exist."
    with open(makefile_path) as f:
        makefile_content = f.read()
    assert "g++" in makefile_content, "Makefile still appears to use gcc or does not use g++."

    mock_server_path = f"{HOME}/mock_server.py"
    assert os.path.isfile(mock_server_path), f"{mock_server_path} does not exist."

    cpp_path = f"{HOME}/emulator.cpp"
    assert os.path.isfile(cpp_path), f"{cpp_path} does not exist."
    with open(cpp_path) as f:
        cpp_content = f.read()
    assert "a + b" in cpp_content or "b + a" in cpp_content, "emulator.cpp does not seem to have the ADD bug fixed."
    assert "8080" in cpp_content, "emulator.cpp does not seem to have the port bug fixed (should use 8080)."

    # Require the submitted Makefile to actually rebuild a native executable.
    os.unlink(exe_file)
    built = subprocess.run(
        ["make", "-C", HOME], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30
    )
    assert built.returncode == 0, f"make failed:\n{built.stdout}\n{built.stderr}"
    assert os.path.isfile(exe_file) and os.access(exe_file, os.X_OK), "make did not build an executable emulator"
    with open(exe_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", "emulator is not a compiled ELF executable"

    rng = random.SystemRandom()
    kill_port(PORT)

    # Exercise the submitted server on verifier-selected integer IDs.
    submitted = start_submitted_server()
    ids = [rng.randint(101, 50000), rng.randint(50001, 100000), -rng.randint(1, 9999)]
    for value in ids:
        actual = get_api(value)
        assert actual == str(value * 100), f"/api/{value} returned {actual!r}, expected {value * 100}"
    kill_port(PORT)
    try:
        submitted.wait(timeout=1)
    except subprocess.TimeoutExpired:
        submitted.kill()

    # Run the rebuilt emulator against a verifier-controlled server. Responses
    # are random, so passing requires ADD, an HTTP CALL to port 8080, and PRINT.
    cases = []
    response_for_path = {}
    for _ in range(3):
        a = rng.randint(-20000, 20000)
        b = rng.randint(-20000, 20000)
        answer = rng.randint(1000000, 2000000000)
        path = f"/api/{a + b}"
        while path in response_for_path:
            b += 1
            path = f"/api/{a + b}"
        response_for_path[path] = answer
        cases.append((a, b, path, answer))

    seen = []

    class ProbeHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            seen.append(self.path)
            if self.path not in response_for_path:
                self.send_response(404)
                self.end_headers()
                return
            body = str(response_for_path[self.path]).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), ProbeHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        for a, b, path, answer in cases:
            before = len(seen)
            run_emulator(a, b, answer)
            assert path in seen[before:], f"emulator did not request the expected endpoint {path}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    # Re-run the exact requested integration with the submitted fixture and
    # leave the required final result in place.
    kill_port(PORT)
    start_submitted_server()
    run_emulator(10, 32, 4200)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
