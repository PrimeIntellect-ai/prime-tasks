#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import secrets
import subprocess
import pytest

HOME = "/home/user"


def test_makefile_exists():
    path = "/home/user/Makefile"
    assert os.path.isfile(path), f"Makefile does not exist at {path}"
    with open(path, "r") as f:
        content = f.read()
    for target in ["build", "run", "bench", "all"]:
        assert target in content, f"Makefile is missing target: {target}"


def test_python_scripts_exist():
    for script in ["parse_routes.py", "rate_limit.py"]:
        path = f"/home/user/{script}"
        assert os.path.isfile(path), f"Python script {script} does not exist at {path}"


def test_libfilter_so_exists():
    path = "/home/user/libfilter.so"
    assert os.path.isfile(path), f"Shared library {path} does not exist"


def test_routes_json():
    path = "/home/user/routes.json"
    assert os.path.isfile(path), f"JSON output {path} does not exist"

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} does not contain valid JSON")

    expected = [
        {"path": "/api/login", "method": "POST", "limit": 2},
        {"path": "/api/data", "method": "GET", "limit": 4}
    ]

    assert isinstance(data, list), f"{path} must contain a JSON array"
    data_sorted = sorted(data, key=lambda x: x.get("path", ""))
    expected_sorted = sorted(expected, key=lambda x: x["path"])
    assert data_sorted == expected_sorted, f"Parsed JSON data in {path} does not match expected output"


def test_banned_ips():
    path = "/home/user/banned_ips.txt"
    assert os.path.isfile(path), f"Output file {path} does not exist"

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["10.0.0.5", "192.168.1.100"]
    assert lines == expected, f"Banned IPs in {path} do not match expected output"


def test_benchmark_log():
    path = "/home/user/benchmark.log"
    assert os.path.isfile(path), f"Benchmark log {path} does not exist"

    with open(path, "r") as f:
        content = f.read()

    assert "User time" in content or "Maximum resident set size" in content or "Elapsed (wall clock) time" in content, \
        f"{path} does not appear to contain the output of /usr/bin/time -v"


def test_dynamic_build_parser_rate_limiter_and_make_targets():
    tracked = [
        f"{HOME}/route.conf",
        f"{HOME}/requests.log",
        f"{HOME}/src/filter.c",
        f"{HOME}/libfilter.so",
        f"{HOME}/routes.json",
        f"{HOME}/banned_ips.txt",
        f"{HOME}/benchmark.log",
    ]
    saved = {}
    for path in tracked:
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = (f.read(), os.stat(path).st_mode)
        else:
            saved[path] = None

    def write(path, content):
        with open(path, "w") as f:
            f.write(content)

    def remove_outputs(include_library=False):
        names = ["routes.json", "banned_ips.txt"]
        if include_library:
            names.append("libfilter.so")
        for name in names:
            path = f"{HOME}/{name}"
            if os.path.exists(path):
                os.remove(path)

    def make(target):
        result = subprocess.run(
            ["make", target], cwd=HOME, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
        )
        assert result.returncode == 0, f"make {target} failed:\n{result.stdout}"

    def assert_outputs(expected_routes, expected_banned):
        with open(f"{HOME}/routes.json") as f:
            actual_routes = json.load(f)
        assert sorted(actual_routes, key=lambda r: r["path"]) == sorted(expected_routes, key=lambda r: r["path"])
        with open(f"{HOME}/banned_ips.txt") as f:
            actual_banned = [line.strip() for line in f if line.strip()]
        assert actual_banned == sorted(expected_banned)

    try:
        token = secrets.token_hex(6)
        rng = random.SystemRandom()
        limit_a = rng.randint(2, 4)
        limit_b = rng.randint(2, 4)
        path_a = f"/dynamic/{token}/alpha"
        path_b = f"/dynamic/{token}/beta"
        ip_a = f"192.0.2.{rng.randint(1, 200)}"
        ip_safe = f"198.51.100.{rng.randint(1, 200)}"
        ip_burst = f"203.0.113.{rng.randint(1, 200)}"
        invalid_ip = f"10.77.{rng.randint(1, 200)}.{rng.randint(1, 200)}"
        formerly_invalid = "999.1.2.3"

        routes = [
            {"path": path_a, "method": "PATCH", "limit": limit_a},
            {"path": path_b, "method": "GET", "limit": limit_b},
        ]
        route_text = (
            f"<route {path_a}>\nmethod PATCH\nlimit {limit_a}\n</route>\n"
            f"<route {path_b}>\nmethod GET\nlimit {limit_b}\n</route>\n"
        )

        log_lines = []
        for i in range(limit_a + 1):
            log_lines.append(f"{ip_a} {1000 + i * 7} {path_a}")
        for i in range(limit_b + 2):
            log_lines.append(f"{ip_safe} {2000 + i * 70} {path_b}")
        for i in range(limit_b + 1):
            log_lines.append(f"{ip_burst} {3000 + i * 5} {path_b}")
        for i in range(limit_a + 2):
            log_lines.append(f"{invalid_ip} {4000 + i * 4} {path_a}")
        for i in range(limit_a + 1):
            log_lines.append(f"{formerly_invalid} {5000 + i * 6} {path_a}")
        log_text = "\n".join(log_lines) + "\n"
        expected_banned = [ip_a, ip_burst, formerly_invalid]

        c_string_ip = invalid_ip.replace("\\", "\\\\").replace('"', '\\"')
        c_source = f'''#include <string.h>
int is_valid_ip(const char *ip) {{
    return strcmp(ip, "{c_string_ip}") != 0;
}}
'''
        write(f"{HOME}/src/filter.c", c_source)
        write(f"{HOME}/route.conf", route_text)
        write(f"{HOME}/requests.log", log_text)

        remove_outputs(include_library=True)
        make("build")
        assert os.path.isfile(f"{HOME}/libfilter.so")
        library = ctypes.CDLL(f"{HOME}/libfilter.so")
        library.is_valid_ip.argtypes = [ctypes.c_char_p]
        library.is_valid_ip.restype = ctypes.c_int
        assert library.is_valid_ip(invalid_ip.encode()) == 0
        assert library.is_valid_ip(formerly_invalid.encode()) != 0

        remove_outputs()
        make("run")
        assert_outputs(routes, expected_banned)

        remove_outputs(include_library=True)
        make("all")
        assert os.path.isfile(f"{HOME}/libfilter.so")
        assert_outputs(routes, expected_banned)

        benchmark = f"{HOME}/benchmark.log"
        banned = f"{HOME}/banned_ips.txt"
        if os.path.exists(benchmark):
            os.remove(benchmark)
        if os.path.exists(banned):
            os.remove(banned)
        make("bench")
        assert os.path.isfile(banned), "make bench did not execute the rate limiter"
        with open(banned) as f:
            assert [line.strip() for line in f if line.strip()] == sorted(expected_banned)
        assert os.path.isfile(benchmark), "make bench did not create benchmark.log"
        with open(benchmark) as f:
            benchmark_content = f.read()
        assert any(marker in benchmark_content for marker in [
            "User time", "Maximum resident set size", "Elapsed (wall clock) time"
        ]), "make bench did not capture /usr/bin/time -v output"
    finally:
        for path, original in saved.items():
            if original is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                data, mode = original
                with open(path, "wb") as f:
                    f.write(data)
                os.chmod(path, mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
