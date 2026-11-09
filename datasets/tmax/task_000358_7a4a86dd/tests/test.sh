#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

PROJECT_DIR = "/home/user/project"
SRC_DIR = os.path.join(PROJECT_DIR, "src")
INCLUDE_DIR = os.path.join(PROJECT_DIR, "include")
MAKEFILE = os.path.join(PROJECT_DIR, "Makefile")
BENCHMARK_SH = os.path.join(PROJECT_DIR, "benchmark.sh")
SORTED_OUTPUT = os.path.join(PROJECT_DIR, "sorted_output.txt")
HTTP_PARSER = os.path.join(PROJECT_DIR, "http_parser")
REQUESTS_LOG = os.path.join(PROJECT_DIR, "requests.log")

ORIGINAL_EXPECTED = [
    "Method: DELETE, URI: /api/v1/users/123, Version: HTTP/1.1",
    "Method: GET, URI: /api/v1/users, Version: HTTP/1.1",
    "Method: GET, URI: /health, Version: HTTP/1.1",
    "Method: POST, URI: /api/v1/login, Version: HTTP/1.1",
    "Method: PUT, URI: /api/v1/settings, Version: HTTP/1.0",
]


def run(cmd, **kwargs):
    return subprocess.run(cmd, timeout=60, **kwargs)


def test_directories_exist():
    assert os.path.isdir(SRC_DIR), f"Directory {SRC_DIR} does not exist."
    assert os.path.isdir(INCLUDE_DIR), f"Directory {INCLUDE_DIR} does not exist."


def test_files_moved():
    assert os.path.isfile(os.path.join(SRC_DIR, "main.c")), "main.c was not moved to src/"
    assert os.path.isfile(os.path.join(SRC_DIR, "parser.c")), "parser.c was not moved to src/"
    assert os.path.isfile(os.path.join(INCLUDE_DIR, "parser.h")), "parser.h was not moved to include/"
    assert not os.path.exists(os.path.join(PROJECT_DIR, "main.c")), "main.c should not be in the project root."
    assert not os.path.exists(os.path.join(PROJECT_DIR, "parser.c")), "parser.c should not be in the project root."
    assert not os.path.exists(os.path.join(PROJECT_DIR, "parser.h")), "parser.h should not be in the project root."


def test_benchmark_script_exists_and_executable():
    assert os.path.isfile(BENCHMARK_SH), f"{BENCHMARK_SH} does not exist."
    assert os.access(BENCHMARK_SH, os.X_OK), f"{BENCHMARK_SH} is not executable."

    with open(BENCHMARK_SH, "r", errors="replace") as f:
        active = "\n".join(line for line in f if not line.lstrip().startswith("#"))
    assert re.search(r"(?m)^\s*(?:/usr/bin/time|time)\b", active), "benchmark.sh does not use the time command or shell keyword."
    assert re.search(r"(?:^|[|;&]\s*)(?:/usr/bin/|/bin/)?sort(?:\s|$)", active, re.M), "benchmark.sh does not use sort."


def test_makefile_compiles():
    subprocess.run(["make", "clean"], cwd=PROJECT_DIR, capture_output=True)
    result = run(["make"], cwd=PROJECT_DIR, capture_output=True, text=True)
    assert result.returncode == 0, f"Makefile failed to compile:\n{result.stderr}"
    assert "warning:" not in (result.stdout + result.stderr).lower(), f"Compilation produced warnings:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(HTTP_PARSER), f"Binary {HTTP_PARSER} was not created by make."
    assert os.access(HTTP_PARSER, os.X_OK), f"Binary {HTTP_PARSER} is not executable."
    with open(HTTP_PARSER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "http_parser is not a compiled ELF executable."


def generated_case(count=40):
    nonce = secrets.token_hex(8)
    methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD"]
    versions = ["HTTP/1.0", "HTTP/1.1"]
    request_lines = []
    expected = []
    for i in range(count):
        method = methods[(i * 5 + 1) % len(methods)]
        uri = f"/generated/{nonce}/{i:03d}?value={count-i}"
        version = versions[i % 2]
        separator1 = "\t" if i % 3 == 0 else " "
        separator2 = "  " if i % 4 == 0 else " "
        request_lines.append(f"{method}{separator1}{uri}{separator2}{version}\n")
        expected.append(f"Method: {method}, URI: {uri}, Version: {version}")
    request_lines.extend(["\n", "BROKEN\n", "GET /only-two-fields\n"])
    return "".join(request_lines), expected


def test_parser_on_generated_input():
    contents, expected = generated_case()
    fd, path = tempfile.mkstemp(prefix="parser-input-", suffix=".log")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(contents)
        result = run([HTTP_PARSER, path], cwd=PROJECT_DIR, capture_output=True, text=True)
        assert result.returncode == 0, f"http_parser failed:\n{result.stderr}"
        assert result.stderr == "", f"http_parser wrote unexpected stderr:\n{result.stderr}"
        actual = result.stdout.splitlines()
        assert actual == expected, f"Parser output is incorrect for generated input.\nExpected:\n{expected}\nActual:\n{actual}"
    finally:
        os.unlink(path)


def run_benchmark_with_trace():
    trace_fd, trace_path = tempfile.mkstemp(prefix="benchmark-trace-")
    os.close(trace_fd)
    env_fd, env_path = tempfile.mkstemp(prefix="benchmark-bash-env-")
    os.close(env_fd)
    with open(env_path, "w") as f:
        f.write("set -T\n")
        f.write("trap 'printf '%s\\n' \"$BASH_COMMAND\" >> \"$VERIFIER_TRACE\"' DEBUG\n")
    env = os.environ.copy()
    env["BASH_ENV"] = env_path
    env["VERIFIER_TRACE"] = trace_path
    env["LC_ALL"] = "C"
    try:
        result = run(["bash", BENCHMARK_SH], cwd=PROJECT_DIR, env=env, capture_output=True, text=True)
        with open(trace_path, "r", errors="replace") as f:
            trace = f.read()
        return result, trace
    finally:
        os.unlink(env_path)
        os.unlink(trace_path)


def assert_benchmark_commands(trace):
    assert re.search(r"(?m)(?:^|/)make\s+clean(?:\s|$)", trace), "benchmark.sh did not execute make clean."
    assert re.search(r"(?m)^(?:/[^\s]*/)?make\s*$", trace), "benchmark.sh did not execute make."
    assert re.search(r"(?m)http_parser[^\n]*requests\.log", trace), "benchmark.sh did not execute http_parser on requests.log."
    assert re.search(r"(?m)(?:^|/)sort(?:\s|$)", trace), "benchmark.sh did not execute sort."


def test_sorted_output_correct_after_running_benchmark():
    if os.path.exists(SORTED_OUTPUT):
        os.unlink(SORTED_OUTPUT)
    result, trace = run_benchmark_with_trace()
    assert result.returncode == 0, f"benchmark.sh failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert_benchmark_commands(trace)
    assert os.path.isfile(SORTED_OUTPUT), f"{SORTED_OUTPUT} does not exist after running benchmark.sh."
    with open(SORTED_OUTPUT, "r") as f:
        actual_output = [line.strip() for line in f if line.strip()]
    assert actual_output == ORIGINAL_EXPECTED, f"Sorted output does not match expected output.\nExpected:\n{ORIGINAL_EXPECTED}\nActual:\n{actual_output}"


def test_benchmark_uses_current_input_and_sorts_it():
    with open(REQUESTS_LOG, "rb") as f:
        original = f.read()
    contents, expected = generated_case(27)
    try:
        with open(REQUESTS_LOG, "w") as f:
            f.write(contents)
        if os.path.exists(SORTED_OUTPUT):
            os.unlink(SORTED_OUTPUT)
        if os.path.exists(HTTP_PARSER):
            os.unlink(HTTP_PARSER)
        result, trace = run_benchmark_with_trace()
        assert result.returncode == 0, f"benchmark.sh failed on generated input:\n{result.stdout}\n{result.stderr}"
        assert_benchmark_commands(trace)
        assert os.path.isfile(HTTP_PARSER), "benchmark.sh did not rebuild http_parser."
        assert os.path.isfile(SORTED_OUTPUT), "benchmark.sh did not create sorted_output.txt."
        with open(SORTED_OUTPUT, "r") as f:
            actual = [line.rstrip("\n") for line in f]
        assert actual == sorted(expected), f"benchmark.sh did not save the parser's alphabetically sorted output.\nExpected:\n{sorted(expected)}\nActual:\n{actual}"
    finally:
        with open(REQUESTS_LOG, "wb") as f:
            f.write(original)


def test_memory_management_fixed():
    parser_c_path = os.path.join(SRC_DIR, "parser.c")
    with open(parser_c_path, "r") as f:
        content = f.read()

    has_allocation = "strdup" in content or "malloc" in content
    assert has_allocation, "parser.c does not seem to allocate memory for the parsed strings (e.g., using strdup)."
    assert content.count("free(") >= 3, "parser.c does not seem to free the allocated strings in free_requests."

    asan_binary = os.path.join(tempfile.gettempdir(), "http_parser_asan")
    compile_result = run([
        "gcc", "-std=gnu11", "-Wall", "-Wextra", "-Werror", "-g",
        "-fsanitize=address", "-fno-omit-frame-pointer",
        "-I" + INCLUDE_DIR,
        os.path.join(SRC_DIR, "main.c"), os.path.join(SRC_DIR, "parser.c"),
        "-o", asan_binary,
    ], capture_output=True, text=True)
    assert compile_result.returncode == 0, f"Sanitizer build failed or produced warnings:\n{compile_result.stderr}"

    contents, expected = generated_case(120)
    fd, input_path = tempfile.mkstemp(prefix="asan-parser-input-", suffix=".log")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(contents)
        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:detect_stack_use_after_return=1"
        result = run([asan_binary, input_path], env=env, capture_output=True, text=True)
        assert result.returncode == 0, f"AddressSanitizer/LeakSanitizer detected a memory error or leak:\n{result.stderr}"
        assert result.stdout.splitlines() == expected, "Sanitized parser produced incorrect output."
    finally:
        if os.path.exists(input_path):
            os.unlink(input_path)
        if os.path.exists(asan_binary):
            os.unlink(asan_binary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
