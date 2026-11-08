#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import socket
import signal
import shutil
import random
import string
import subprocess
import tempfile
import threading
from pathlib import Path


def test_binary_exists():
    path = "/home/user/bin/net-aggregator"
    assert os.path.isfile(path), f"Compiled binary not found at {path}"
    assert os.access(path, os.X_OK), f"File at {path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable"


def test_config_correct():
    conf_path = "/home/user/app.conf"
    assert os.path.isfile(conf_path), f"Configuration file {conf_path} not found"
    with open(conf_path, "r") as f:
        content = f.read()
    assert "API_KEY=f47ac10b-58cc-4372-a567-0e02b2c3d479" in content, f"Expected API_KEY with the correct UUID in {conf_path}"

    dump = Path("/home/user/messy_config_dump.txt").read_text()
    prod_line = next((line for line in dump.splitlines() if "[PROD_KEY]" in line), None)
    assert prod_line is not None
    match = re.search(r"UUID=([0-9a-fA-F-]{36})", prod_line)
    assert match, "No UUID found on the [PROD_KEY] line"
    assert f"API_KEY={match.group(1)}" in content


def test_metrics_env():
    env_path = "/home/user/metrics.env"
    assert os.path.isfile(env_path), f"Environment file {env_path} not found"
    with open(env_path, "r") as f:
        content = f.read()
    assert "AGGREGATOR_CONF=/home/user/app.conf" in content, f"Expected AGGREGATOR_CONF to point to /home/user/app.conf in {env_path}"


def test_execution_time_and_success():
    script_path = "/home/user/start_metrics.sh"
    assert os.path.isfile(script_path), f"Wrapper script {script_path} not found"

    start_time = time.time()
    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    elapsed_time = time.time() - start_time

    assert result.returncode == 0, (
        f"start_metrics.sh failed with exit code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\n"
        f"STDERR:\n{result.stderr}\n"
        "Ensure the background listener is running and the C program is correctly compiled."
    )

    threshold = 0.5
    assert elapsed_time <= threshold, (
        f"Execution time {elapsed_time:.3f}s exceeded the threshold of {threshold}s. "
        "The string concatenation in parser.c might still be O(N^2)."
    )


def kill_port_8088_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].endswith(":1F98") and fields[3] == "0A":
                inodes.add(fields[9])

    victims = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(proc.name))
                    break
        except OSError:
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.1)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def run_with_observed_listener(binary, log_path, extra_env=None, timeout=5):
    kill_port_8088_listeners()
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 8088))
    server.listen(4)
    server.settimeout(timeout)
    accepted = []

    def accept_one():
        try:
            conn, _ = server.accept()
            accepted.append(True)
            conn.close()
        except OSError:
            pass

    thread = threading.Thread(target=accept_one)
    thread.start()
    env = os.environ.copy()
    env["AGGREGATOR_CONF"] = "/home/user/app.conf"
    if extra_env:
        env.update(extra_env)
    start = time.time()
    try:
        result = subprocess.run(
            [str(binary), "--test-run", str(log_path)],
            env=env, capture_output=True, text=True, timeout=timeout
        )
    finally:
        thread.join(timeout=timeout)
        server.close()
    elapsed = time.time() - start
    assert accepted, f"{binary} did not connect to the listener on 127.0.0.1:8088"
    assert result.returncode == 0, (
        f"{binary} failed with code {result.returncode}\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    return elapsed


def compile_audit_library(directory):
    source = Path(directory) / "audit.c"
    library = Path(directory) / "audit.so"
    source.write_text(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static FILE *watched_file;
static unsigned long successful_reads;
static unsigned long connect_calls;

typedef FILE *(*fopen_fn)(const char *, const char *);
typedef char *(*fgets_fn)(char *, int, FILE *);
typedef int (*connect_fn)(int, const struct sockaddr *, socklen_t);

FILE *fopen(const char *path, const char *mode) {
    static fopen_fn real_fopen;
    if (!real_fopen) real_fopen = (fopen_fn)dlsym(RTLD_NEXT, "fopen");
    FILE *result = real_fopen(path, mode);
    const char *wanted = getenv("AUDIT_LOG_PATH");
    if (wanted && path && strcmp(path, wanted) == 0) watched_file = result;
    return result;
}

char *fgets(char *buffer, int size, FILE *stream) {
    static fgets_fn real_fgets;
    if (!real_fgets) real_fgets = (fgets_fn)dlsym(RTLD_NEXT, "fgets");
    char *result = real_fgets(buffer, size, stream);
    if (result && stream == watched_file) successful_reads++;
    return result;
}

int connect(int fd, const struct sockaddr *address, socklen_t length) {
    static connect_fn real_connect;
    if (!real_connect) real_connect = (connect_fn)dlsym(RTLD_NEXT, "connect");
    connect_calls++;
    return real_connect(fd, address, length);
}

__attribute__((destructor)) static void write_report(void) {
    const char *path = getenv("AUDIT_REPORT");
    if (!path) return;
    char data[128];
    int length = snprintf(data, sizeof(data), "%lu %lu\n", connect_calls, successful_reads);
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd >= 0) {
        write(fd, data, (size_t)length);
        close(fd);
    }
}
''')
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", "-o", str(library), str(source), "-ldl"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr
    return library


def audit_binary(binary, log_path, line_count, audit_library, directory):
    report = Path(directory) / ("report_" + ''.join(random.choice(string.ascii_letters) for _ in range(12)))
    run_with_observed_listener(binary, log_path, {
        "LD_PRELOAD": str(audit_library),
        "AUDIT_LOG_PATH": str(log_path),
        "AUDIT_REPORT": str(report),
    })
    assert report.is_file(), f"No execution audit was produced by {binary}"
    connects, reads = map(int, report.read_text().split())
    assert connects >= 1, f"{binary} did not execute its TCP pre-flight connection"
    assert reads == line_count, f"{binary} read {reads} test lines; expected {line_count}"


def test_source_build_binary_and_parser_are_real():
    installed = Path("/home/user/bin/net-aggregator")

    env_without_conf = os.environ.copy()
    env_without_conf.pop("AGGREGATOR_CONF", None)
    missing_env = subprocess.run(
        [str(installed), "--test-run", "/home/user/test_logs.txt"],
        env=env_without_conf, capture_output=True, text=True, timeout=2
    )
    assert missing_env.returncode != 0, "The daemon must reject execution when AGGREGATOR_CONF is unset"

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        source_copy = td / "source"
        shutil.copytree("/app/net-aggregator-1.2.0", source_copy)
        build = subprocess.run(
            ["make", "clean", "all"], cwd=source_copy,
            capture_output=True, text=True, timeout=30
        )
        assert build.returncode == 0, f"Makefile build failed:\n{build.stdout}\n{build.stderr}"
        rebuilt = source_copy / "net-aggregator"
        assert rebuilt.is_file() and os.access(rebuilt, os.X_OK)
        assert rebuilt.read_bytes()[:4] == b"\x7fELF"

        line_count = 50000
        controlled_log = td / ("logs_" + os.urandom(8).hex() + ".txt")
        with controlled_log.open("w") as f:
            for i in range(line_count):
                token = os.urandom(12).hex()
                f.write(f"INFO item_{i}_{token} accepted from 10.{i % 251}.{(i * 7) % 251}.{(i * 13) % 251}\n")

        installed_elapsed = run_with_observed_listener(installed, controlled_log)
        assert installed_elapsed <= 0.5, f"Installed binary took {installed_elapsed:.3f}s; expected at most 0.5s"
        rebuilt_elapsed = run_with_observed_listener(rebuilt, controlled_log)
        assert rebuilt_elapsed <= 0.5, f"Makefile-built binary took {rebuilt_elapsed:.3f}s; expected at most 0.5s"

        audit_library = compile_audit_library(td)
        audit_binary(installed, controlled_log, line_count, audit_library, td)
        audit_binary(rebuilt, controlled_log, line_count, audit_library, td)

        harness = td / "parser_harness.c"
        harness.write_text(r'''
#include <stdio.h>
#include <stdlib.h>
#include "parser.h"
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 3;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    rewind(f);
    char *input = malloc((size_t)n + 1);
    char *output = malloc((size_t)n + 1);
    if (!input || !output) return 4;
    if (fread(input, 1, (size_t)n, f) != (size_t)n) return 5;
    fclose(f);
    input[n] = '\0';
    build_log_string(input, output);
    fwrite(output, 1, (size_t)n, stdout);
    free(input);
    free(output);
    return 0;
}
''')
        harness_bin = td / "parser_harness"
        compile_result = subprocess.run(
            ["gcc", "-O2", "-I", str(source_copy), str(harness),
             str(source_copy / "parser.c"), "-o", str(harness_bin)],
            capture_output=True, text=True, timeout=20
        )
        assert compile_result.returncode == 0, f"parser.c failed to compile:\n{compile_result.stderr}"

        for length in (0, 1, 37, 4096):
            data = ''.join(random.choice(string.ascii_letters + string.digits + " _-") for _ in range(length)).encode()
            input_path = td / f"parser_input_{length}"
            input_path.write_bytes(data)
            result = subprocess.run([str(harness_bin), str(input_path)], capture_output=True, timeout=2)
            assert result.returncode == 0
            assert result.stdout == data, "build_log_string did not preserve its input"

        large_data = os.urandom(250000).hex().encode()
        large_path = td / "large_parser_input"
        large_path.write_bytes(large_data)
        start = time.time()
        result = subprocess.run([str(harness_bin), str(large_path)], capture_output=True, timeout=1.0)
        parser_elapsed = time.time() - start
        assert result.returncode == 0 and result.stdout == large_data
        assert parser_elapsed <= 0.5, (
            f"build_log_string took {parser_elapsed:.3f}s on a long input; it is not linear-time"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
