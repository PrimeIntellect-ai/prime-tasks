#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYEOF' > /tmp/test_final_state.py
import os
import random
import socket
import subprocess
from concurrent.futures import ThreadPoolExecutor

BINARY = "/home/user/merger"
SOURCE = "/home/user/merger.c"
CONFIG = "/home/user/nginx.conf"

ORIGINAL = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void parse_and_merge(char *line1, char *line2) {
    int arr1[1000], arr2[1000], out[2000];
    int n1 = 0, n2 = 0;

    char *token = strtok(line1, " \n");
    while (token != NULL) {
        arr1[n1++] = atoi(token);
        token = strtok(NULL, " \n");
    }

    token = strtok(line2, " \n");
    while (token != NULL) {
        arr2[n2++] = atoi(token);
        token = strtok(NULL, " \n");
    }

    int i = 0, j = 0, k = 0;
    while (i < n1 && j < n2) {
        if (arr1[i] < arr2[j]) {
            out[k++] = arr1[i++];
        } else if (arr1[i] > arr2[j]) {
            out[k++] = arr2[j++];
        } else {
            out[k++] = arr1[i++];
            j++; // Bug: Drops duplicate elements
        }
    }
    while (i < n1) out[k++] = arr1[i++];
    while (j < n2) out[k++] = arr2[j++];

    for (int x = 0; x < k; x++) {
        printf("%d%s", out[x], (x == k - 1) ? "" : " ");
    }
    printf("\n");
    fflush(stdout);
}

int main() {
    char line1[8192], line2[8192];
    if (!fgets(line1, sizeof(line1), stdin)) return 0;
    if (!fgets(line2, sizeof(line2), stdin)) return 0;
    parse_and_merge(line1, line2);
    return 0;
}
'''


def encoded_case(a, b):
    return " ".join(map(str, a)) + "\n" + " ".join(map(str, b)) + "\n"


def expected_case(a, b):
    values = sorted(a + b)
    return " ".join(map(str, values)) + "\n"


def run_binary(path, a, b):
    result = subprocess.run(
        [path], input=encoded_case(a, b), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


def network_case(port, a, b):
    with socket.create_connection(("127.0.0.1", port), timeout=4) as sock:
        sock.settimeout(4)
        sock.sendall(encoded_case(a, b).encode())
        sock.shutdown(socket.SHUT_WR)
        chunks = []
        while True:
            chunk = sock.recv(8192)
            if not chunk:
                break
            chunks.append(chunk)
    return b"".join(chunks).decode()


def random_cases(count):
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    cases = [([], []), ([0, 0, 0], [0, 0]), ([-5, -5, 2], [-5, 2, 2])]
    for _ in range(count):
        a = sorted(rng.randint(-1000, 1000) for _ in range(rng.randint(0, 80)))
        b = sorted(rng.randint(-1000, 1000) for _ in range(rng.randint(0, 80)))
        cases.append((a, b))
    return cases


def listener_owners(port):
    wanted = f"{port:04X}"
    inodes = set()
    with open("/proc/net/tcp") as f:
        next(f)
        for line in f:
            fields = line.split()
            address, state, inode = fields[1], fields[3], fields[9]
            ip_hex, port_hex = address.split(":")
            if state == "0A" and ip_hex == "0100007F" and port_hex == wanted:
                inodes.add(inode)
    owners = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        exe = os.path.realpath(f"/proc/{pid}/exe")
                        cmd = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
                        owners.append((exe, cmd))
                    except OSError:
                        pass
                    break
        except OSError:
            pass
    return inodes, owners


def test_merger_binary_exists_and_executable():
    assert os.path.isfile(BINARY), f"Compiled binary not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"File at {BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "merger is not a compiled ELF binary"


def test_merger_logic_fixed():
    actual = run_binary(BINARY, [1, 2, 2, 3], [2, 3, 4])
    expected = "1 2 2 2 3 3 4\n"
    assert actual == expected, f"Binary logic incorrect. Expected {expected!r}, got {actual!r}"

    cases = random_cases(60)
    for a, b in cases:
        assert run_binary(BINARY, a, b) == expected_case(a, b)

    assert os.path.isfile(SOURCE), "Fixed merger.c is missing"
    built = "/tmp/merger_from_submitted_source"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", built],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, compile_result.stderr
    for a, b in cases[:25]:
        assert run_binary(built, a, b) == expected_case(a, b)


def test_nginx_config_exists_and_valid():
    assert os.path.isfile(CONFIG), f"Nginx config not found at {CONFIG}"
    content = open(CONFIG).read()
    assert "stream" in content, "Nginx config does not contain a 'stream' block"
    assert "8080" in content, "Nginx config does not mention port 8080"
    assert "9000" in content, "Nginx config does not mention port 9000"

    checked = subprocess.run(
        ["nginx", "-t", "-c", CONFIG], stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=15
    )
    assert checked.returncode == 0, checked.stdout
    dumped = subprocess.run(
        ["nginx", "-T", "-c", CONFIG], stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, timeout=15
    )
    assert dumped.returncode == 0, dumped.stdout
    normalized = " ".join(dumped.stdout.replace(";", " ; ").split())
    assert "listen 127.0.0.1:8080" in normalized
    assert "proxy_pass 127.0.0.1:9000" in normalized


def test_nginx_listening_on_8080():
    inodes, owners = listener_owners(8080)
    assert inodes, "Nothing is listening specifically on 127.0.0.1:8080"
    assert any(os.path.basename(exe) == "nginx" for exe, _ in owners), "Port 8080 is not owned by nginx"
    nginx_processes = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            cmd = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
            if os.path.basename(exe) == "nginx":
                nginx_processes.append(cmd)
        except OSError:
            pass
    assert any(CONFIG in cmd for cmd in nginx_processes), "Running nginx was not started with the custom config"


def test_socat_listening_on_9000():
    inodes, owners = listener_owners(9000)
    assert inodes, "Nothing is listening specifically on 127.0.0.1:9000"
    socats = [(exe, cmd) for exe, cmd in owners if os.path.basename(exe) == "socat"]
    assert socats, "Port 9000 is not owned by socat"
    assert any("fork" in cmd.lower() and BINARY in cmd for _, cmd in socats), \
        "socat listener must fork and execute /home/user/merger"


def test_end_to_end_proxy():
    actual = network_case(8080, [1, 5, 9], [2, 5, 8])
    expected = "1 2 5 5 8 9\n"
    assert actual == expected, f"End-to-end proxy test failed. Expected {expected!r}, got {actual!r}"

    cases = random_cases(35)
    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = [(a, b, pool.submit(network_case, 8080, a, b)) for a, b in cases]
        for a, b, future in futures:
            assert future.result(timeout=8) == expected_case(a, b)


def test_test_results_log_and_real_suite():
    path = "/home/user/test_results.log"
    assert os.path.isfile(path), f"Test results log not found at {path}"
    content = open(path, errors="replace").read()
    assert "1 passed" in content or "passed" in content.lower(), \
        "Test results log does not indicate a passing test"

    result = subprocess.run(
        ["python3", "-m", "pytest", "/home/user/test_merge.py"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180
    )
    assert result.returncode == 0, "The required property suite does not actually pass:\n" + result.stdout
    assert "passed" in result.stdout.lower(), result.stdout


def apply_single_unified_diff(original, patch_text):
    lines = patch_text.splitlines(keepends=True)
    old_header = next((i for i, line in enumerate(lines) if line.startswith("--- ")), None)
    assert old_header is not None and old_header + 1 < len(lines)
    assert lines[old_header + 1].startswith("+++ ")
    assert "merger.c" in lines[old_header] or "merger.c" in lines[old_header + 1]

    old = original.splitlines(keepends=True)
    output = []
    cursor = 0
    i = old_header + 2
    hunks = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("--- "):
            raise AssertionError("Patch must describe only the merger.c change")
        if not line.startswith("@@ "):
            i += 1
            continue
        hunks += 1
        header = line.split("@@", 2)[1].strip().split()
        old_spec, new_spec = header[0][1:], header[1][1:]
        old_start, old_count = (old_spec.split(",") + ["1"])[:2]
        new_start, new_count = (new_spec.split(",") + ["1"])[:2]
        old_start, old_count = int(old_start), int(old_count)
        new_start, new_count = int(new_start), int(new_count)
        target = old_start - 1
        assert target >= cursor
        output.extend(old[cursor:target])
        cursor = target
        consumed = produced = 0
        i += 1
        while i < len(lines) and not lines[i].startswith("@@ ") and not lines[i].startswith("--- "):
            item = lines[i]
            if item.startswith("\\ No newline at end of file"):
                i += 1
                continue
            assert item and item[0] in " +-", f"Invalid unified diff line: {item!r}"
            body = item[1:]
            if item[0] in " -":
                assert cursor < len(old) and old[cursor] == body, "Patch does not apply to the supplied original"
                cursor += 1
                consumed += 1
            if item[0] in " +":
                output.append(body)
                produced += 1
            i += 1
        assert consumed == old_count and produced == new_count, "Incorrect unified diff hunk counts"
    assert hunks, "Patch contains no unified diff hunks"
    output.extend(old[cursor:])
    return "".join(output)


def test_fix_patch_exists_and_valid():
    path = "/home/user/fix.patch"
    assert os.path.isfile(path), f"Patch file not found at {path}"
    content = open(path).read()
    assert "---" in content and "+++" in content, "Patch file does not appear to be a valid unified diff"
    assert "merger.c" in content, "Patch file does not reference merger.c"
    reconstructed = apply_single_unified_diff(ORIGINAL, content)
    submitted = open(SOURCE).read()
    assert reconstructed == submitted, "fix.patch does not transform the original buggy source into merger.c"
    assert reconstructed != ORIGINAL, "fix.patch makes no change"
PYEOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
