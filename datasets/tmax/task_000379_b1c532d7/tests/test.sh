#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import signal
import socket
import stat
import subprocess
import time

import numpy as np
from sklearn.decomposition import PCA

DATA_PATH = "/home/user/data.csv"
REDUCED_PATH = "/home/user/reduced.csv"
LOG_PATH = "/home/user/experiment.log"
SERVE_PATH = "/home/user/serve.sh"
BINARY_PATH = "/app/query_embedder"
PORT = 8888

EXPECTED_DATA = [
    ["id", "text"],
    ["1", "The quick brown fox"],
    ["2", "Jumps over the lazy dog"],
    ["3", "Data science is fun"],
    ["4", "Embeddings represent semantic meaning"],
    ["5", "Dimensionality reduction helps visualization"],
]


def read_source_data():
    assert os.path.exists(DATA_PATH), f"Source data {DATA_PATH} not found."
    with open(DATA_PATH, newline="") as f:
        rows = list(csv.reader(f))
    assert rows == EXPECTED_DATA, "The provided source dataset was modified."
    return rows[1:]


def run_embedder(text):
    assert os.path.exists(BINARY_PATH), f"Binary {BINARY_PATH} not found."
    proc = subprocess.run(
        [BINARY_PATH],
        input=(text + "\n").encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert proc.returncode == 0, f"Embedder failed: {proc.stderr.decode(errors='replace')}"
    output = proc.stdout.decode("utf-8").strip()
    values = np.asarray([float(x) for x in output.split(",")], dtype=float)
    assert values.shape == (64,), f"Expected a 64-dimensional embedding, got {values.shape}."
    assert np.isfinite(values).all(), "Embedder returned non-finite values."
    return output, values


def listening_inodes(require_all_interfaces=False):
    found = set()
    paths = [("/proc/net/tcp", True), ("/proc/net/tcp6", False)]
    for path, is_ipv4 in paths:
        try:
            with open(path) as f:
                lines = f.readlines()[1:]
        except FileNotFoundError:
            continue
        for line in lines:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            if state != "0A":
                continue
            address, port_hex = local_address.rsplit(":", 1)
            if int(port_hex, 16) != PORT:
                continue
            if require_all_interfaces and not (is_ipv4 and address == "00000000"):
                continue
            found.add(fields[9])
    return found


def pids_owning_inodes(inodes):
    pids = set()
    if not inodes:
        return pids
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return pids


def stop_existing_server():
    for _ in range(30):
        inodes = listening_inodes()
        if not inodes:
            return
        for pid in pids_owning_inodes(inodes):
            if pid != os.getpid():
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        time.sleep(0.1)
    for pid in pids_owning_inodes(listening_inodes()):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    time.sleep(0.2)


def request_server(query):
    with socket.create_connection(("127.0.0.1", PORT), timeout=5) as sock:
        sock.settimeout(5)
        sock.sendall((query + "\n").encode("utf-8"))
        response = bytearray()
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            response.extend(chunk)
    return bytes(response).decode("utf-8").strip()


def test_experiment_log():
    source_rows = read_source_data()
    assert os.path.exists(LOG_PATH), f"Experiment log {LOG_PATH} not found."
    with open(LOG_PATH) as f:
        content = f.read()
    expected = f"Run complete: {len(source_rows)} records processed"
    assert "Run complete: 5 records processed" in content, "Experiment log does not contain the expected success message."
    assert expected in content.splitlines(), "Experiment log does not contain the required exact line."


def test_reduced_csv():
    source_rows = read_source_data()
    assert os.path.exists(REDUCED_PATH), f"Reduced CSV {REDUCED_PATH} not found."

    with open(REDUCED_PATH, newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) == 6, f"Expected 6 rows in reduced.csv, found {len(rows)}."
    assert rows[0] == ["id", "pca1", "pca2"], f"Expected header ['id', 'pca1', 'pca2'], found {rows[0]}."

    actual = []
    for i, row in enumerate(rows[1:], start=1):
        assert len(row) == 3, f"Row {i} does not have 3 columns."
        assert row[0] == str(i), f"Row {i} id mismatch."
        try:
            actual.append([float(row[1]), float(row[2])])
        except ValueError:
            assert False, f"Row {i} contains non-float values for PCA components."

    actual = np.asarray(actual, dtype=float)
    assert np.isfinite(actual).all(), "PCA output contains non-finite values."

    embeddings = np.vstack([run_embedder(text)[1] for _, text in source_rows])
    expected = PCA(n_components=2).fit_transform(embeddings)

    # PCA component signs are arbitrary. Comparing centered Gram matrices accepts
    # sign flips (and equivalent orthogonal bases) while still validating the
    # actual two-dimensional PCA projection.
    assert np.allclose(actual.mean(axis=0), 0.0, atol=2e-5), "PCA coordinates are not centered."
    assert np.allclose(
        actual @ actual.T,
        expected @ expected.T,
        rtol=2e-4,
        atol=2e-5,
    ), "reduced.csv does not contain the PCA reduction of the supplied embeddings."


def test_tcp_server_serving():
    assert os.path.exists(SERVE_PATH), f"Server script {SERVE_PATH} not found."
    mode = os.stat(SERVE_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SERVE_PATH} is not a regular file."

    # Stop any pre-existing listener so this test necessarily executes serve.sh
    # and validates the server that it starts.
    stop_existing_server()
    assert not listening_inodes(), "Could not stop the pre-existing port 8888 listener."

    proc = subprocess.Popen(
        ["/bin/bash", SERVE_PATH],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        deadline = time.time() + 8
        while time.time() < deadline and not listening_inodes(require_all_interfaces=True):
            time.sleep(0.1)
        assert listening_inodes(require_all_interfaces=True), "serve.sh did not start a server listening on 0.0.0.0:8888."

        queries = [
            "test query",
            "verification-" + secrets.token_hex(16),
            "another sequential request " + secrets.token_hex(12),
        ]
        for query in queries:
            response_str = request_server(query)
            expected_str, expected_values = run_embedder(query)
            assert response_str == expected_str, (
                "TCP server response does not match binary output.\n"
                f"Expected: {expected_str}\nGot: {response_str}"
            )
            values = np.asarray([float(x) for x in response_str.split(",")], dtype=float)
            assert values.shape == (64,)
            assert np.isfinite(values).all()
            assert np.array_equal(values, expected_values)
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        stop_existing_server()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
