#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import secrets
import socket
import stat
import subprocess
import tempfile
import time

HOST = "127.0.0.1"
PORT = 8333
TIMEOUT = 3.0
SOURCE = "/home/user/kinetic_server.c"
BINARY = "/home/user/kinetic_server"


def listener_pids(port):
    target_port = f"{port:04X}"
    inodes = set()
    try:
        with open("/proc/net/tcp", "r") as f:
            next(f)
            for line in f:
                fields = line.split()
                address, state, inode = fields[1], fields[3], fields[9]
                ip_hex, port_hex = address.split(":")
                if ip_hex == "0100007F" and port_hex == target_port and state == "0A":
                    inodes.add(inode)
    except FileNotFoundError:
        pass

    result = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    result.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return result


def wait_for_listener(port, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listener_pids(port)
        if pids:
            return pids
        time.sleep(0.05)
    raise AssertionError(f"No TCP listener appeared on {HOST}:{port}")


def send_command(cmd, port=PORT):
    try:
        with socket.create_connection((HOST, port), timeout=TIMEOUT) as s:
            s.sendall(cmd.encode("utf-8"))
            response = s.recv(1024).decode("utf-8")
            return response.strip()
    except ConnectionRefusedError:
        raise AssertionError(f"Connection refused to {HOST}:{port}. Is the server running?")


def extract_parameters():
    text = subprocess.check_output(
        ["tesseract", "/app/lab_notes.png", "stdout"],
        text=True,
        stderr=subprocess.DEVNULL,
        timeout=15,
    )
    alpha_match = re.search(r"Alpha\s*:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+))", text, re.I)
    beta_match = re.search(r"Beta\s*:\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+))", text, re.I)
    assert alpha_match and beta_match, f"Could not extract Alpha and Beta from image OCR: {text!r}"
    return float(alpha_match.group(1)), float(beta_match.group(1))


def verify_original_process(alpha, beta):
    pids = wait_for_listener(PORT)
    matched = False
    diagnostics = []
    for pid in pids:
        try:
            argv = [x.decode(errors="replace") for x in open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0") if x]
            exe = os.readlink(f"/proc/{pid}/exe")
            diagnostics.append((pid, argv, exe))
            if len(argv) < 4:
                continue
            if not os.path.samefile(exe, BINARY):
                continue
            if not math.isclose(float(argv[-3]), alpha, rel_tol=0, abs_tol=1e-12):
                continue
            if not math.isclose(float(argv[-2]), beta, rel_tol=0, abs_tol=1e-12):
                continue
            if not os.path.samefile(argv[-1], "/app/protein.fasta"):
                continue
            matched = True
            break
        except (OSError, ValueError):
            continue
    assert matched, f"Port 8333 is not served by the requested binary with OCR-derived arguments: {diagnostics!r}"


def expected_root(alpha, beta, nc, length):
    lo, hi = 0.0, 1.0
    def equation(x):
        return x*x*x + alpha*nc*x - beta*length
    while equation(hi) < 0:
        hi *= 2.0
    for _ in range(200):
        mid = (lo + hi) / 2.0
        if equation(mid) < 0:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind((HOST, 0))
        return s.getsockname()[1]


def kill_test_server(proc, port):
    for pid in listener_pids(port):
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=1)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=1)


def dynamic_case(executable, preload, case_number):
    # Runtime randomness prevents a fixed-response listener from anticipating the test.
    alpha = secrets.randbelow(80) / 10.0 + 0.7
    beta = secrets.randbelow(150) / 10.0 + 1.1
    length = 37 + secrets.randbelow(47)
    nc = 1 + secrets.randbelow(length - 1)
    residues = list("C" * nc + "A" * (length - nc))
    random.SystemRandom().shuffle(residues)
    sequence = "".join(residues)

    fasta = tempfile.NamedTemporaryFile("w", prefix=f"kinetic_{case_number}_", suffix=".fasta", delete=False)
    try:
        # C characters in headers must not be counted.
        fasta.write(">HEADER_WITH_MANY_CCCCC residues\n")
        for i in range(0, len(sequence), 13):
            fasta.write(sequence[i:i+13] + "\n")
        fasta.close()

        test_port = free_port()
        env = os.environ.copy()
        env["LD_PRELOAD"] = preload
        env["KINETIC_TEST_PORT"] = str(test_port)
        proc = subprocess.Popen(
            [executable, format(alpha, ".12g"), format(beta, ".12g"), fasta.name],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
        )
        try:
            wait_for_listener(test_port)
            root = expected_root(alpha, beta, nc, length)
            with socket.create_connection((HOST, test_port), timeout=TIMEOUT) as s:
                s.settimeout(TIMEOUT)
                stream = s.makefile("rwb", buffering=0)

                stream.write(b"STATS\n")
                assert stream.readline() == f"C={nc} L={length}\n".encode()

                stream.write(b"SOLVE\n")
                assert stream.readline() == f"ROOT={root:.4f}\n".encode()

                stream.write(b"QUIT\n")
                assert stream.readline() == b"BYE\n"
                assert s.recv(1) == b"", "QUIT did not cleanly close the client connection"

            # QUIT must only close its client; the server must continue accepting clients.
            assert send_command("STATS\n", test_port) == f"C={nc} L={length}"
        finally:
            kill_test_server(proc, test_port)
    finally:
        try:
            os.unlink(fasta.name)
        except FileNotFoundError:
            pass


def main():
    assert os.path.isfile(SOURCE), f"Missing C source: {SOURCE}"
    st = os.stat(BINARY)
    assert stat.S_ISREG(st.st_mode), f"Compiled artifact is not a regular file: {BINARY}"
    assert st.st_mode & 0o111, f"Compiled artifact is not executable: {BINARY}"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "kinetic_server is not a compiled ELF executable"

    rebuilt = "/tmp/kinetic_server_rebuilt"
    subprocess.run(["gcc", SOURCE, "-o", rebuilt, "-lm"], check=True, timeout=30)
    with open(rebuilt, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    alpha, beta = extract_parameters()
    assert math.isclose(alpha, 2.5, rel_tol=0, abs_tol=1e-12)
    assert math.isclose(beta, 8.0, rel_tol=0, abs_tol=1e-12)
    verify_original_process(alpha, beta)

    # Preserve the original behavioral assertions against the submitted running server.
    response = send_command("STATS\n")
    assert response == "C=6 L=25", f"Expected 'C=6 L=25', got '{response}'"

    response = send_command("SOLVE\n")
    assert response == "ROOT=5.0000", f"Expected 'ROOT=5.0000', got '{response}'"

    response = send_command("QUIT\n")
    assert response == "BYE", f"Expected 'BYE', got '{response}'"

    resp1 = send_command("STATS\n")
    resp2 = send_command("STATS\n")
    assert resp1 == "C=6 L=25"
    assert resp2 == "C=6 L=25"

    # Remap bind(8333) only for isolated dynamic executions, leaving the submitted
    # required server on 8333 untouched.
    preload_source = "/tmp/remap_bind.c"
    preload = "/tmp/remap_bind.so"
    with open(preload_source, "w") as f:
        f.write(r'''#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>
#include <sys/socket.h>

typedef int (*bind_fn)(int, const struct sockaddr *, socklen_t);
int bind(int fd, const struct sockaddr *addr, socklen_t len) {
    static bind_fn real_bind = NULL;
    if (!real_bind) real_bind = (bind_fn)dlsym(RTLD_NEXT, "bind");
    if (addr && addr->sa_family == AF_INET && len >= sizeof(struct sockaddr_in)) {
        struct sockaddr_in copy;
        memcpy(&copy, addr, sizeof(copy));
        const char *p = getenv("KINETIC_TEST_PORT");
        if (p && ntohs(copy.sin_port) == 8333) {
            copy.sin_port = htons((unsigned short)strtoul(p, NULL, 10));
            return real_bind(fd, (const struct sockaddr *)&copy, sizeof(copy));
        }
    }
    return real_bind(fd, addr, len);
}
''')
    subprocess.run(["gcc", "-shared", "-fPIC", preload_source, "-o", preload, "-ldl"], check=True, timeout=30)

    dynamic_case(BINARY, preload, 1)
    dynamic_case(rebuilt, preload, 2)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
