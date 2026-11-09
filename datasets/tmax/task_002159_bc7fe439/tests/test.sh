#!/bin/bash
mkdir -p /logs/verifier

if python3 - <<'PY'
import math
import os
import random
import re
import socket
import subprocess
import tempfile
import time

ROOT = "/app/spectra_fitter-1.0"
PREFIX = "/app/installed"
LIB = PREFIX + "/lib/libspectra_fitter.so"
HEADER = PREFIX + "/include/spectra_fitter.hpp"
SERVICE_SRC = "/home/user/service.cpp"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//.*", "", text)


# Verify that the requested source and installed artifacts exist.
for path in (
    ROOT + "/src/integrator.cpp",
    ROOT + "/CMakeLists.txt",
    SERVICE_SRC,
    LIB,
    HEADER,
):
    require(os.path.isfile(path), f"Required artifact is missing: {path}")

integrator = strip_comments(open(ROOT + "/src/integrator.cpp", encoding="utf-8").read())
require(not re.search(r"\bdt\s*\*=\s*2(?:\.0+)?\s*;", integrator),
        "The integrator source still doubles dt when adaptation is required")
require(
    re.search(r"\bdt\s*/=\s*2(?:\.0+)?\s*;", integrator)
    or re.search(r"\bdt\s*\*=\s*0?\.5\s*;", integrator)
    or re.search(r"\bdt\s*=\s*dt\s*/\s*2(?:\.0+)?\s*;", integrator)
    or re.search(r"\bdt\s*=\s*0?\.5\s*\*\s*dt\s*;", integrator),
    "The integrator source does not halve dt",
)

cmake = strip_comments(open(ROOT + "/CMakeLists.txt", encoding="utf-8").read())
require(re.search(r"(?:target_)?link_libraries\s*\([^)]*\bm\b[^)]*\)", cmake, re.S),
        "CMakeLists.txt does not link the standard math library")

ldd_output = subprocess.run(
    ["ldd", LIB], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True
).stdout
require("libm.so" in ldd_output, "The installed spectra_fitter library is not linked to libm")

service_source = strip_comments(open(SERVICE_SRC, encoding="utf-8").read())
for token in ("<sys/socket.h>", "SpectraFitter::fit_peak", "socket(", "bind(", "listen(", "accept("):
    require(token in service_source, f"service.cpp is missing required server/library use: {token}")

# Independently execute the installed library through its public API.
helper_source = r'''
#include <spectra_fitter.hpp>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <vector>
int main(int argc, char **argv) {
    if (argc != 6) return 2;
    std::vector<double> data;
    for (int i = 1; i < 6; ++i) data.push_back(std::strtod(argv[i], nullptr));
    std::cout << std::setprecision(17) << SpectraFitter::fit_peak(data) << "\n";
    return 0;
}
'''
helper_dir = tempfile.mkdtemp(prefix="verify_spectra_")
helper_cpp = os.path.join(helper_dir, "helper.cpp")
helper_bin = os.path.join(helper_dir, "helper")
with open(helper_cpp, "w", encoding="utf-8") as f:
    f.write(helper_source)
subprocess.run([
    "g++", "-std=c++11", helper_cpp,
    "-I" + PREFIX + "/include", "-L" + PREFIX + "/lib",
    "-Wl,-rpath," + PREFIX + "/lib", "-lspectra_fitter", "-o", helper_bin,
], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def compute_expected(init_val):
    t = 0.0
    dt = 0.1
    val = init_val
    while t < 1.0:
        error = dt * 0.5
        if error > 0.02:
            dt /= 2.0
            continue
        val += dt * math.sin(val)
        t += dt
    return val


fixed = [0.2, 0.8, 1.5, 0.7, 0.1]
rng = random.SystemRandom()
cases = [fixed]
for _ in range(8):
    cases.append([rng.uniform(-1.75, 2.25) for _ in range(5)])

for values in cases:
    output = subprocess.run(
        [helper_bin] + [format(x, ".17g") for x in values],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    ).stdout.strip()
    actual = float(output)
    expected = compute_expected(sum(values))
    require(math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12),
            f"Installed library returned {actual}, expected {expected} for {values}")


def listening_processes(port):
    inodes = set()
    target_port = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table, encoding="ascii").read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if state == "0A" and local.rsplit(":", 1)[1].upper() == target_port:
                inodes.add(fields[9])
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    found.append(int(name))
                    break
        except OSError:
            pass
    return found


# Preserve the original fixed request assertion, then exercise fresh inputs and
# require the listener to continue accepting connections.
def request(values):
    payload = ",".join(format(x, ".17g") for x in values) + "\n"
    last_error = None
    for _ in range(10):
        try:
            s = socket.create_connection(("127.0.0.1", 8181), timeout=5.0)
            break
        except OSError as exc:
            last_error = exc
            time.sleep(0.5)
    else:
        raise AssertionError(f"Could not connect to TCP server at 127.0.0.1:8181: {last_error}")
    try:
        s.settimeout(5.0)
        s.sendall(payload.encode("utf-8"))
        chunks = []
        while True:
            chunk = s.recv(1024)
            if not chunk:
                break
            chunks.append(chunk)
        return b"".join(chunks).decode("utf-8")
    finally:
        s.close()

response = request(fixed)
expected_response = f"RESULT: {compute_expected(3.3):.4f}\n"
require(response == expected_response,
        f"Server returned incorrect response. Expected {expected_response!r}, got {response!r}")

for values in cases[1:]:
    response = request(values)
    expected_response = f"RESULT: {compute_expected(sum(values)):.4f}\n"
    require(response == expected_response,
            f"Server returned incorrect response for {values}. Expected {expected_response!r}, got {response!r}")

# Ensure the active listener is a compiled ELF process using the installed library.
pids = listening_processes(8181)
require(pids, "No process is actively listening on port 8181")
valid_listener = False
for pid in pids:
    try:
        with open(f"/proc/{pid}/exe", "rb") as f:
            is_elf = f.read(4) == b"\x7fELF"
        maps = open(f"/proc/{pid}/maps", encoding="utf-8", errors="replace").read()
        if is_elf and LIB in maps:
            valid_listener = True
            break
    except OSError:
        pass
require(valid_listener, "The active listener is not a compiled ELF server using the installed spectra_fitter library")
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
