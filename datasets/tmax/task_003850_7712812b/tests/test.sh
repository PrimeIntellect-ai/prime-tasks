#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import socket
import stat
import subprocess
import tempfile
import time

SOURCE = "/home/user/server.c"
SERVER = "/home/user/server"
REBUILT = "/tmp/vsrv_check"
ORACLE = "/app/data_oracle"


def verify_artifacts():
    st = os.stat(SOURCE)
    assert stat.S_ISREG(st.st_mode), f"{SOURCE} is not a regular file"
    assert st.st_size > 0, f"{SOURCE} is empty"

    st = os.stat(SERVER)
    assert stat.S_ISREG(st.st_mode), f"{SERVER} is not a regular file"
    assert os.access(SERVER, os.X_OK), f"{SERVER} is not executable"
    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{SERVER} is not an ELF executable"

    proc = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", REBUILT, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"server.c did not compile as C:\n{proc.stderr}"


def generate_csv(path, data):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "value"])
        writer.writerows(data)


def independent_correlation(data1, data2):
    left = {}
    right = {}
    for row_id, value in data1:
        left.setdefault(row_id, []).append(float(value))
    for row_id, value in data2:
        right.setdefault(row_id, []).append(float(value))

    pairs = []
    for row_id in left.keys() & right.keys():
        for x in left[row_id]:
            for y in right[row_id]:
                pairs.append((x, y))

    if len(pairs) < 2:
        return "nan"
    mx = math.fsum(x for x, _ in pairs) / len(pairs)
    my = math.fsum(y for _, y in pairs) / len(pairs)
    covariance = math.fsum((x - mx) * (y - my) for x, y in pairs)
    xnorm = math.fsum((x - mx) ** 2 for x, _ in pairs)
    ynorm = math.fsum((y - my) ** 2 for _, y in pairs)
    if xnorm == 0.0 or ynorm == 0.0:
        return "nan"
    return f"{covariance / math.sqrt(xnorm * ynorm):.4f}"


def oracle_correlation(path1, path2):
    proc = subprocess.run(
        [ORACLE, path1, path2],
        capture_output=True,
        text=True,
        check=True,
        timeout=15,
    )
    return proc.stdout.strip()


def transact(path1, path2, use_eof=False):
    deadline = time.monotonic() + 3.0
    while True:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5.0)
        try:
            s.connect(("127.0.0.1", 9000))
            break
        except OSError:
            s.close()
            if time.monotonic() >= deadline:
                raise AssertionError("Could not connect to TCP server on 127.0.0.1:9000")
            time.sleep(0.05)

    try:
        payload = f"{path1}\n{path2}".encode("utf-8")
        if use_eof:
            s.sendall(payload)
            s.shutdown(socket.SHUT_WR)
        else:
            s.sendall(payload + b"\0")

        chunks = []
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            chunks.append(chunk)
            if sum(map(len, chunks)) > 4096:
                raise AssertionError("Server returned an excessively large response")
        return b"".join(chunks).decode("utf-8").strip()
    finally:
        s.close()


def stop_servers():
    subprocess.run(["pkill", "-x", "server"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-x", "vsrv_check"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.1)


def run_binary(binary, cases):
    proc = subprocess.Popen(
        [binary], cwd="/home/user", stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    try:
        for name, path1, path2, expected, use_eof in cases:
            actual = transact(path1, path2, use_eof)
            assert actual == expected, (
                f"{name}: expected {expected!r}, got {actual!r}"
            )
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        stop_servers()


def make_random_data(rng, index):
    base = rng.randrange(10000, 900000) + index * 100
    common = [str(base + i) for i in range(8)]
    ids1 = common + [str(base + 20 + i) for i in range(3)]
    ids2 = common + [str(base + 40 + i) for i in range(3)]

    while True:
        data1 = [(row_id, f"{rng.uniform(-250, 250):.6f}") for row_id in ids1]
        data2 = [(row_id, f"{rng.uniform(-250, 250):.6f}") for row_id in ids2]
        if index % 2 == 0:
            data1.append((common[2], f"{rng.uniform(-250, 250):.6f}"))
        if index % 3 == 0:
            data2.append((common[5], f"{rng.uniform(-250, 250):.6f}"))
        rng.shuffle(data1)
        rng.shuffle(data2)
        expected = independent_correlation(data1, data2)
        if expected != "nan" and abs(float(expected)) < 0.97:
            return data1, data2, expected


def main():
    verify_artifacts()
    stop_servers()
    rng = random.SystemRandom()

    fixed = [
        ("positive", [("1", "10"), ("2", "20"), ("3", "30"), ("4", "40")],
         [("2", "20"), ("3", "30"), ("4", "40"), ("5", "50")]),
        ("negative_with_floats", [("10", "1.5"), ("20", "2.5"), ("30", "3.5"), ("40", "4.5")],
         [("10", "10.0"), ("20", "8.0"), ("30", "6.0"), ("40", "4.0")]),
        ("missing_data", [("1", "100"), ("2", "200"), ("4", "400"), ("5", "500")],
         [("2", "20"), ("3", "30"), ("4", "40"), ("6", "60")]),
    ]

    with tempfile.TemporaryDirectory(prefix="corr_verify_") as td:
        cases = []
        for i, (name, data1, data2) in enumerate(fixed):
            path1 = os.path.join(td, f"fixed_{i}_a.csv")
            path2 = os.path.join(td, f"fixed_{i}_b.csv")
            generate_csv(path1, data1)
            generate_csv(path2, data2)
            expected = oracle_correlation(path1, path2)
            cases.append((name, path1, path2, expected, False))

        for i in range(10):
            data1, data2, expected = make_random_data(rng, i)
            path1 = os.path.join(td, f"random_{i}_{rng.randrange(1 << 30)}_a.csv")
            path2 = os.path.join(td, f"random_{i}_{rng.randrange(1 << 30)}_b.csv")
            generate_csv(path1, data1)
            generate_csv(path2, data2)
            cases.append((f"randomized_join_{i}", path1, path2, expected, i % 2 == 1))

        rng.shuffle(cases)
        run_binary(SERVER, cases)
        rng.shuffle(cases)
        run_binary(REBUILT, cases)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
