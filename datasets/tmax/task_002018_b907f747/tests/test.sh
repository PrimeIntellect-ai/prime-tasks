#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'HOOK_EOF' > /tmp/latency_audit.c
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static void audit_connect(int fd, const struct sockaddr *addr) {
    char ip[INET_ADDRSTRLEN] = "unknown";
    unsigned port = 0;
    int socket_type = -1;
    socklen_t type_len = sizeof(socket_type);
    getsockopt(fd, SOL_SOCKET, SO_TYPE, &socket_type, &type_len);

    if (addr && addr->sa_family == AF_INET) {
        const struct sockaddr_in *in = (const struct sockaddr_in *)addr;
        inet_ntop(AF_INET, &in->sin_addr, ip, sizeof(ip));
        port = ntohs(in->sin_port);
    }

    int out = open("/tmp/latency_syscalls.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (out >= 0) {
        dprintf(out, "CONNECT %s %u %d\n", ip, port, socket_type);
        close(out);
    }
}

static void audit_poll(long timeout_ms) {
    int out = open("/tmp/latency_syscalls.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (out >= 0) {
        dprintf(out, "POLL %ld\n", timeout_ms);
        close(out);
    }
}

int connect(int fd, const struct sockaddr *addr, socklen_t len) {
    (void)len;
    audit_connect(fd, addr);

    const char *mode = getenv("LATENCY_AUDIT_MODE");
    if (mode && strcmp(mode, "timeout") == 0) {
        errno = EINPROGRESS;
        return -1;
    }

    int delay = 0;
    if (addr && addr->sa_family == AF_INET) {
        const struct sockaddr_in *in = (const struct sockaddr_in *)addr;
        unsigned long ip = ntohl(in->sin_addr.s_addr);
        const char *value = NULL;
        if (ip == 0x08080808UL)
            value = getenv("LATENCY_DELAY_8_MS");
        else if (ip == 0x01010101UL)
            value = getenv("LATENCY_DELAY_1_MS");
        if (value)
            delay = atoi(value);
    }
    if (delay > 0)
        usleep((useconds_t)delay * 1000U);
    return 0;
}

int poll(struct pollfd *fds, nfds_t nfds, int timeout) {
    for (nfds_t i = 0; i < nfds; i++)
        fds[i].revents = 0;
    audit_poll(timeout);
    return 0;
}

int ppoll(struct pollfd *fds, nfds_t nfds, const struct timespec *timeout,
          const sigset_t *mask) {
    (void)mask;
    for (nfds_t i = 0; i < nfds; i++)
        fds[i].revents = 0;
    long ms = -1;
    if (timeout)
        ms = timeout->tv_sec * 1000L + timeout->tv_nsec / 1000000L;
    audit_poll(ms);
    return 0;
}
HOOK_EOF

cc -shared -fPIC -O2 -o /tmp/latency_audit.so /tmp/latency_audit.c

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import socket
import subprocess
import pytest

BINARY = "/home/user/latency_monitor/target/release/latency_monitor"
LOG = "/home/user/latency.log"
HOOK = "/tmp/latency_audit.so"
AUDIT = "/tmp/latency_syscalls.log"
ENDPOINTS = {"8.8.8.8:53", "1.1.1.1:53"}


def test_rust_project_exists():
    assert os.path.isfile("/home/user/latency_monitor/Cargo.toml"), "Cargo.toml not found in /home/user/latency_monitor."


def test_rust_binary_exists_and_executable():
    assert os.path.isfile(BINARY), f"Release binary not found at {BINARY}."
    assert os.access(BINARY, os.X_OK), f"Binary at {BINARY} is not executable."


def read_json_lines():
    assert os.path.isfile(LOG), f"Log file {LOG} was not created."
    with open(LOG, "r") as f:
        raw = [line.rstrip("\n") for line in f if line.strip()]

    assert len(raw) >= 2, "Log file should contain at least two entries."
    parsed = []
    for line in raw:
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Log line is not valid JSON: {line}")
        assert "endpoint" in data, "JSON log missing 'endpoint' key."
        assert "latency_ms" in data, "JSON log missing 'latency_ms' key."
        assert "success" in data, "JSON log missing 'success' key."
        assert isinstance(data["latency_ms"], int) and not isinstance(data["latency_ms"], bool), "'latency_ms' must be an integer."
        assert isinstance(data["success"], bool), "'success' must be a boolean."
        parsed.append((line, data))

    endpoints_found = {data["endpoint"] for _, data in parsed}
    assert "8.8.8.8:53" in endpoints_found, "Endpoint 8.8.8.8:53 not found in logs."
    assert "1.1.1.1:53" in endpoints_found, "Endpoint 1.1.1.1:53 not found in logs."
    return parsed


def run_with_hook(env_updates):
    for path in (LOG, AUDIT):
        if os.path.exists(path):
            os.remove(path)
    env = os.environ.copy()
    env.update(env_updates)
    env["LD_PRELOAD"] = HOOK
    result = subprocess.run([BINARY], capture_output=True, timeout=8, env=env)
    assert result.returncode == 0, f"Binary execution failed with return code {result.returncode}."
    assert result.stdout == b"" and result.stderr == b"", "The monitor must exit silently."
    return result


def audit_lines():
    assert os.path.isfile(AUDIT), "No TCP syscall audit was produced; the binary did not use connect()."
    with open(AUDIT) as f:
        return [line.strip() for line in f if line.strip()]


def assert_tcp_attempts(lines):
    attempts = []
    for line in lines:
        match = re.fullmatch(r"CONNECT (\S+) (\d+) (-?\d+)", line)
        if match:
            attempts.append((f"{match.group(1)}:{match.group(2)}", int(match.group(3))))
    assert len(attempts) == 2, f"Expected exactly two connect attempts, got {attempts}."
    assert {endpoint for endpoint, _ in attempts} == ENDPOINTS, f"Wrong TCP destinations: {attempts}."
    assert all(kind == socket.SOCK_STREAM for _, kind in attempts), "Endpoints were not attempted with TCP stream sockets."


def test_binary_execution_tcp_attempts_latency_and_log_format():
    # Randomize which endpoint receives the short and long delay, so expected
    # latency values are derived by the verifier rather than fixed constants.
    short_delay = 80 + secrets.randbelow(51)
    long_delay = 360 + secrets.randbelow(71)
    if secrets.randbits(1):
        delay_8, delay_1 = short_delay, long_delay
    else:
        delay_8, delay_1 = long_delay, short_delay

    run_with_hook({
        "LATENCY_AUDIT_MODE": "delay",
        "LATENCY_DELAY_8_MS": str(delay_8),
        "LATENCY_DELAY_1_MS": str(delay_1),
    })
    assert_tcp_attempts(audit_lines())

    parsed = read_json_lines()
    assert len(parsed) == 2, "Each run must append exactly one JSON line per endpoint."
    by_endpoint = {}
    exact_pattern = re.compile(r'^\{"endpoint": "(8\.8\.8\.8:53|1\.1\.1\.1:53)", "latency_ms": ([0-9]+), "success": (true|false)\}$')
    for raw, data in parsed:
        assert exact_pattern.fullmatch(raw), f"JSON line does not have the exact required format: {raw}"
        assert set(data) == {"endpoint", "latency_ms", "success"}, "JSON entry has missing or extra keys."
        assert data["endpoint"] not in by_endpoint, "An endpoint was logged more than once."
        assert data["success"] is True, "A successfully completed intercepted connection must be logged as successful."
        by_endpoint[data["endpoint"]] = data

    expected = {"8.8.8.8:53": delay_8, "1.1.1.1:53": delay_1}
    for endpoint, delay in expected.items():
        measured = by_endpoint[endpoint]["latency_ms"]
        assert delay - 10 <= measured <= delay + 150, (
            f"Latency for {endpoint} was {measured}ms after a {delay}ms connect delay; "
            "the program does not appear to measure connection time."
        )


def test_connection_timeout_is_two_seconds():
    run_with_hook({"LATENCY_AUDIT_MODE": "timeout"})
    lines = audit_lines()
    assert_tcp_attempts(lines)
    timeouts = [int(m.group(1)) for line in lines if (m := re.fullmatch(r"POLL (-?\d+)", line))]
    assert len(timeouts) >= 2, "The program did not wait for each nonblocking TCP connection with a timeout."
    assert all(1950 <= value <= 2001 for value in timeouts), f"Connection timeout was not 2 seconds: {timeouts}."
    parsed = read_json_lines()
    assert len(parsed) == 2, "A timed-out attempt must still produce one line per endpoint."
    assert all(data["success"] is False for _, data in parsed), "Timed-out connections must be logged as unsuccessful."


def test_crontab_configuration():
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read crontab."
    crontab_content = result.stdout
    assert BINARY in crontab_content, f"Crontab does not contain the binary path {BINARY}."
    schedule_pattern = re.compile(r"^\s*\*\s+\*\s+\*\s+\*\s+\*\s+.*" + re.escape(BINARY), re.MULTILINE)
    assert schedule_pattern.search(crontab_content), "Crontab does not have the correct '* * * * *' schedule for the binary."

    active = [line.strip() for line in crontab_content.splitlines()
              if line.strip() and not line.lstrip().startswith("#") and BINARY in line]
    assert len(active) == 1, "The release binary must be scheduled exactly once."
    fields = active[0].split(None, 5)
    assert len(fields) == 6 and fields[:5] == ["*", "*", "*", "*", "*"], "The binary must run exactly once every minute."
    assert re.match(r"^" + re.escape(BINARY) + r"(?:\s|$)", fields[5]), "The cron command must run the compiled release binary."


def test_logrotate_configuration():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.isfile(conf_path), f"Logrotate config not found at {conf_path}."
    with open(conf_path, "r") as f:
        content = f.read()

    assert "/home/user/latency.log" in content, "Logrotate config does not target /home/user/latency.log."
    directives = ["size 10k", "rotate 5", "compress", "missingok", "notifempty"]
    for directive in directives:
        assert re.search(r"\b" + directive.replace(" ", r"\s+") + r"\b", content), f"Logrotate config missing directive: {directive}"

    # Strip comments, then inspect directives inside the block that actually
    # targets latency.log, so words placed only in comments cannot pass.
    uncommented = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    block_re = re.compile(r'(?:^|\n)\s*(?:"/home/user/latency\.log"|/home/user/latency\.log)\s*\{([^{}]*)\}', re.MULTILINE)
    blocks = block_re.findall(uncommented)
    assert len(blocks) == 1, "There must be one logrotate block specifically targeting /home/user/latency.log."
    lines = [line.strip() for line in blocks[0].splitlines() if line.strip()]
    tokens = [line.split() for line in lines]

    assert [t for t in tokens if t[0] == "size"] == [["size", "10k"]], "The active size directive must be exactly 'size 10k'."
    assert [t for t in tokens if t[0] == "rotate"] == [["rotate", "5"]], "The active rotate directive must keep exactly 5 copies."
    for name in ("compress", "missingok", "notifempty"):
        assert [t for t in tokens if t[0] == name] == [[name]], f"The active block must contain '{name}'."
    forbidden = {"nocompress", "nomissingok", "ifempty"}
    assert not any(t[0] in forbidden for t in tokens), "The logrotate block contains a directive contradicting the required policy."

    result = subprocess.run(["logrotate", "--debug", conf_path], capture_output=True, text=True)
    assert result.returncode == 0, f"logrotate rejected the configuration: {result.stdout}{result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
