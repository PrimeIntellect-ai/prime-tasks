#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import os
import random
import signal
import socket
import string
import struct
import subprocess
import time
from pathlib import Path

HOST = "127.0.0.1"
PORT = 9090


def send_request(payload, timeout=5):
    with socket.create_connection((HOST, PORT), timeout=timeout) as sock:
        sock.sendall(payload.encode("utf-8"))
        response = b""
        while not response.endswith(b"\n"):
            chunk = sock.recv(1024)
            if not chunk:
                break
            response += chunk
        return response.decode("utf-8")


def assert_original_responses():
    cases = [
        ("café\n", "12.50\n"),
        ("DROP\n", "NOT_FOUND\n"),
        ("apple\n", "5.00\n"),
        ("unknown_token\n", "NOT_FOUND\n"),
    ]
    for query, expected in cases:
        actual = send_request(query)
        assert actual == expected, (query, expected, actual)


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9:
                local = fields[1]
                state = fields[3]
                if local.rsplit(":", 1)[-1].upper() == f"{PORT:04X}" and state == "0A":
                    inodes.add(fields[9])

    found = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.append(int(proc.name))
                    break
        except OSError:
            pass
    return sorted(set(found))


def require_c_artifact(pid):
    exe = os.path.realpath(f"/proc/{pid}/exe")
    assert os.path.isfile(exe), "Listening process has no executable artifact"
    with open(exe, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Server is not a compiled native executable"

    banned = {"python", "python3", "node", "ruby", "perl", "php", "java", "bash", "dash", "sh"}
    assert os.path.basename(exe).lower() not in banned, "Listener is an interpreter, not the requested C server"

    roots = {Path("/home/user"), Path("/app"), Path("/root")}
    try:
        roots.add(Path(os.readlink(f"/proc/{pid}/cwd")))
    except OSError:
        pass

    sources = []
    for root in roots:
        if root.exists() and root.is_dir():
            try:
                sources.extend(root.rglob("*.c"))
            except OSError:
                pass
    suitable = False
    for source in set(sources):
        try:
            text = source.read_text(errors="ignore")
        except OSError:
            continue
        if "main" in text and "socket" in text and ("listen" in text or "bind" in text):
            suitable = True
            break
    assert suitable, "No C source implementing a socket server was found"
    return exe


def process_details(pid, exe):
    raw = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    argv = [part.decode(errors="surrogateescape") for part in raw if part]
    assert argv, "Could not recover server command line"
    argv[0] = exe
    cwd = os.readlink(f"/proc/{pid}/cwd")

    env = os.environ.copy()
    try:
        entries = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
        env = {}
        for entry in entries:
            if b"=" in entry:
                key, value = entry.split(b"=", 1)
                env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    except OSError:
        pass
    return argv, cwd, env


def make_dynamic_inputs():
    rng = random.SystemRandom()
    window = rng.randint(2, 5)
    ignored = "IGN" + "".join(rng.choice(string.ascii_uppercase) for _ in range(10))
    suffix = "".join(rng.choice(string.ascii_lowercase) for _ in range(9))
    tokens = [f"café_{suffix}", f"piñata_{suffix}", f"jalapeño_{suffix}", f"plain_{suffix}"]

    rows = []
    series = {token: [] for token in tokens}
    base = rng.randint(10000, 90000)
    for token_index, token in enumerate(tokens):
        count = window + 4 + token_index
        for i in range(count):
            timestamp = base + i * 17 + token_index
            value = float(rng.randint(-300, 700))
            rows.append((timestamp, token, value))
            series[token].append((timestamp, value))

    for i in range(4):
        rows.append((base + 500 + i, ignored, float(9000 + i)))
    rng.shuffle(rows)

    expected = {}
    for token, values in series.items():
        ordered = [value for _, value in sorted(values)]
        avgs = []
        for i in range(len(ordered)):
            start = max(0, i - window + 1)
            avgs.append(sum(ordered[start:i + 1]) / (i - start + 1))
        expected[token] = f"{max(avgs):.2f}\n"

    data = "".join(f"{ts},{token},{value:.1f}\n" for ts, token, value in rows)
    Path("/home/user/dataset.csv").write_bytes(data.encode("iso-8859-1"))

    subprocess.run([
        "convert", "-size", "900x220", "xc:white", "-fill", "black",
        "-font", "DejaVu-Sans", "-pointsize", "52",
        "-draw", f"text 20,75 'WINDOW={window}' text 20,155 'IGNORE={ignored}'",
        "/app/config.png"
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return ignored, tokens, expected, suffix


def wait_for_server(timeout=15):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with socket.create_connection((HOST, PORT), timeout=0.5):
                return
        except OSError as exc:
            last_error = exc
            time.sleep(0.2)
    raise AssertionError(f"Restarted server did not listen on port {PORT}: {last_error}")


def main():
    # Preserve all response assertions from the original verifier.
    assert_original_responses()

    pids = listener_pids()
    assert pids, "No process is listening on 127.0.0.1:9090"
    primary = pids[0]
    exe = require_c_artifact(primary)
    argv, cwd, env = process_details(primary, exe)

    ignored, tokens, expected, suffix = make_dynamic_inputs()

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    wait_for_server()

    # These token names, values, row order, window, and ignore token are generated
    # only after the submitted server has first been checked.
    for token in tokens:
        actual = send_request(token + "\n")
        assert actual == expected[token], (token, expected[token], actual)
    assert send_request(ignored + "\n") == "NOT_FOUND\n"
    assert send_request("absent_" + suffix + "\n") == "NOT_FOUND\n"

    # It must remain available for further sequential requests.
    assert send_request(tokens[0] + "\n") == expected[tokens[0]]
    assert listener_pids(), "Server stopped after handling sequential requests"


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
