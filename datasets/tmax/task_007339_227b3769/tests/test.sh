#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import ctypes
import heapq
import os
import pathlib
import random
import re
import secrets
import subprocess

import pytest

HOME = pathlib.Path("/home/user")
ENV = HOME / "environment"
SCRIPT = HOME / "setup_env.sh"
SO = ENV / "libchecksum.so"
LOG = HOME / "test_plan.log"


def run_setup():
    result = subprocess.run(
        [str(SCRIPT)],
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"setup_env.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_execute_setup_script_from_clean_outputs():
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."
    SO.unlink(missing_ok=True)
    LOG.unlink(missing_ok=True)
    run_setup()


def test_setup_script_exists_and_executable():
    script_path = "/home/user/setup_env.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_libchecksum_so_exists():
    so_path = "/home/user/environment/libchecksum.so"
    assert os.path.isfile(so_path), f"Shared library {so_path} was not compiled or is missing."


def test_test_plan_log_content():
    log_path = "/home/user/test_plan.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."

    expected_lines = [
        "1. libA.c: -2105151528",
        "2. libB.c: 1111624890",
        "3. libC.c: -967156102",
        "4. libD.c: -908992055",
        "5. libE.c: -1106591039"
    ]

    with open(log_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {log_path}, found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch in {log_path}. Expected '{expected}', got '{actual}'."


def test_script_uses_python_ctypes():
    text = SCRIPT.read_text()
    assert re.search(r"\bpython3?\b", text), "setup_env.sh must invoke Python."
    assert re.search(r"\bctypes\b", text), "setup_env.sh must use Python's ctypes module."
    assert "custom_hash" in text, "setup_env.sh must call the custom_hash symbol."


def compute_hash(data, salt):
    value = (2166136261 ^ salt) & 0xffffffff
    for byte in data:
        value ^= byte
        value = (value * 16777619) & 0xffffffff
        value = ((value << 7) | (value >> 25)) & 0xffffffff
    return value - (1 << 32) if value >= (1 << 31) else value


def topo_order(graph):
    indegree = {service: len(deps) for service, deps in graph.items()}
    users = {service: [] for service in graph}
    for service, deps in graph.items():
        for dep in deps:
            users[dep].append(service)
    ready = [service for service, degree in indegree.items() if degree == 0]
    heapq.heapify(ready)
    result = []
    while ready:
        service = heapq.heappop(ready)
        result.append(service)
        for user in users[service]:
            indegree[user] -= 1
            if indegree[user] == 0:
                heapq.heappush(ready, user)
    assert len(result) == len(graph)
    return result


def test_rebuilds_parses_topologically_sorts_and_calls_library():
    paths = [ENV / "deps.txt", ENV / "checksum.c", SO, LOG]
    paths.extend(sorted((ENV / "src").glob("*.c")))
    backups = {path: path.read_bytes() if path.exists() else None for path in paths}
    marker = pathlib.Path("/tmp/verifier_hash_calls")

    try:
        services = ["libA", "libB", "libC", "libD", "libE"]
        shuffled = services[:]
        random.SystemRandom().shuffle(shuffled)
        graph = {
            shuffled[0]: [],
            shuffled[1]: [],
            shuffled[2]: [shuffled[0]],
            shuffled[3]: [shuffled[1]],
            shuffled[4]: [shuffled[2], shuffled[3]],
        }

        dep_lines = []
        line_order = services[:]
        random.SystemRandom().shuffle(line_order)
        for service in line_order:
            deps = graph[service][:]
            random.SystemRandom().shuffle(deps)
            dep_lines.append(f"{service}:" + (" " + " ".join(deps) if deps else ""))
        (ENV / "deps.txt").write_text("\n".join(dep_lines) + "\n")

        salt = secrets.randbits(32)
        checksum_source = f'''#include <stdint.h>
#include <stdio.h>
int32_t custom_hash(const char* filepath) {{
    FILE *calls = fopen("/tmp/verifier_hash_calls", "a");
    if (calls) {{ fprintf(calls, "%s\\n", filepath); fclose(calls); }}
    FILE *f = fopen(filepath, "rb");
    if (!f) return -1;
    uint32_t hash = 2166136261u ^ {salt}u;
    int c;
    while ((c = fgetc(f)) != EOF) {{
        hash ^= (uint8_t)c;
        hash *= 16777619u;
        hash = (hash << 7) | (hash >> 25);
    }}
    fclose(f);
    return (int32_t)hash;
}}
'''
        (ENV / "checksum.c").write_text(checksum_source)

        source_data = {}
        for service in services:
            nonce = secrets.token_hex(18)
            data = (f"/* verifier nonce {nonce} */\nvoid {service}(void) {{}}\n").encode()
            (ENV / "src" / f"{service}.c").write_bytes(data)
            source_data[service] = data

        marker.unlink(missing_ok=True)
        SO.unlink(missing_ok=True)
        LOG.unlink(missing_ok=True)
        run_setup()

        assert SO.is_file(), "setup_env.sh did not rebuild libchecksum.so."
        assert LOG.is_file(), "setup_env.sh did not regenerate test_plan.log."

        order = topo_order(graph)
        expected_lines = [
            f"{index}. {service}.c: {compute_hash(source_data[service], salt)}"
            for index, service in enumerate(order, 1)
        ]
        actual_lines = [line.strip() for line in LOG.read_text().splitlines() if line.strip()]
        assert actual_lines == expected_lines, (
            "Generated log does not reflect the current dependency graph, alphabetical "
            "topological tie-breaking, and current custom_hash implementation."
        )

        assert marker.is_file(), "The compiled custom_hash function was not called."
        called = [pathlib.Path(line.strip()).name for line in marker.read_text().splitlines() if line.strip()]
        expected_called = [f"{service}.c" for service in order]
        assert collections.Counter(called) == collections.Counter(expected_called), (
            "custom_hash must be called exactly once for each corresponding service source file."
        )

        library = ctypes.CDLL(str(SO))
        function = library.custom_hash
        function.argtypes = [ctypes.c_char_p]
        function.restype = ctypes.c_int32
        sample = ENV / "src" / f"{order[0]}.c"
        assert function(os.fsencode(sample)) == compute_hash(sample.read_bytes(), salt), (
            "libchecksum.so does not export the custom_hash implementation from checksum.c."
        )
    finally:
        marker.unlink(missing_ok=True)
        for path, content in backups.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
