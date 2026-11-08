#!/bin/bash
mkdir -p /logs/verifier

if (
    set -e

    # The required artifact must actually generate the original outputs.
    rm -f /home/user/startup_order.log /home/user/valgrind_auth.log /home/user/leak_report.txt
    timeout 90 /home/user/orchestrate.sh

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

def test_orchestrate_script_exists_and_executable():
    script_path = "/home/user/orchestrate.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

def test_startup_order_log():
    log_path = "/home/user/startup_order.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."
    expected_order = [
        "ConfigService",
        "DatabaseService",
        "CacheService",
        "AuthService",
        "GatewayService"
    ]
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines() if line.strip()]
    assert lines == expected_order, f"Expected startup order {expected_order}, but got {lines}."

def test_valgrind_log_exists():
    log_path = "/home/user/valgrind_auth.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read()
    assert "Memcheck" in content or "valgrind" in content.lower() or "definitely lost" in content, \
        f"{log_path} does not appear to contain valid valgrind output."

def test_leak_report():
    report_path = "/home/user/leak_report.txt"
    assert os.path.isfile(report_path), f"File {report_path} does not exist."
    with open(report_path, "r") as f:
        content = f.read().strip()
    assert content == "4096", f"Expected leak_report.txt to contain '4096', but got '{content}'."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short

    # Exercise the script again with a shuffled, uniquely ordered graph and a
    # freshly compiled service whose leak size is unknown until verification.
    cp -a /home/user/api_topology.txt /tmp/api_topology.txt.verifier-backup
    cp -a /home/user/bin/auth_service /tmp/auth_service.verifier-backup
    trap 'cp -a /tmp/api_topology.txt.verifier-backup /home/user/api_topology.txt; cp -a /tmp/auth_service.verifier-backup /home/user/bin/auth_service' EXIT

    cat << 'EOF' > /home/user/api_topology.txt
AnalyticsService -> WorkerService
AuthService -> AnalyticsService
WorkerService -> SeedService
EdgeService -> AuthService
SeedService -> 
EOF

    leak_bytes="$(python3 -c 'import secrets; print(6001 + secrets.randbelow(2000))')"
    export LEAK_BYTES="$leak_bytes"

    cat > /tmp/auth_service_dynamic.c <<EOF
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

__attribute__((noinline)) static void make_leak(size_t n) {
    unsigned char *p = malloc(n);
    if (!p) exit(2);
    memset(p, 0xA5, n);
    __asm__ volatile("" : : "r"(p) : "memory");
}

int main(void) {
    make_leak((size_t)$leak_bytes);
    puts("dynamic AuthService complete");
    return 0;
}
EOF
    gcc -g -O0 /tmp/auth_service_dynamic.c -o /home/user/bin/auth_service

    rm -f /home/user/startup_order.log /home/user/valgrind_auth.log /home/user/leak_report.txt
    timeout 90 /home/user/orchestrate.sh

    cat << 'DYNAMIC_TEST_EOF' > /tmp/test_dynamic_state.py
import os
import re


def derived_topological_order(path):
    dependencies = {}
    nodes = set()
    with open(path) as f:
        for raw in f:
            if not raw.strip():
                continue
            service, dependency = raw.rstrip("\n").split("->", 1)
            service = service.strip()
            dependency = dependency.strip()
            nodes.add(service)
            dependencies.setdefault(service, set())
            if dependency:
                nodes.add(dependency)
                dependencies[service].add(dependency)
                dependencies.setdefault(dependency, set())

    result = []
    remaining = set(nodes)
    while remaining:
        ready = sorted(n for n in remaining if not (dependencies[n] & remaining))
        assert ready, "The verifier's generated graph unexpectedly contains a cycle"
        # The generated graph has exactly one ready service at each step.
        assert len(ready) == 1, f"Generated graph did not have a unique order: {ready}"
        node = ready[0]
        result.append(node)
        remaining.remove(node)
    return result


def test_dynamic_graph_was_traversed():
    expected = derived_topological_order("/home/user/api_topology.txt")
    with open("/home/user/startup_order.log") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, f"Expected dynamically derived order {expected}, got {actual}"


def test_real_full_valgrind_run_and_extraction():
    expected = int(os.environ["LEAK_BYTES"])
    with open("/home/user/valgrind_auth.log", errors="replace") as f:
        log = f.read()

    assert "Memcheck" in log, "Missing Memcheck header from valgrind output"
    assert re.search(r"Command:\s*/home/user/bin/auth_service(?:\s|$)", log), \
        "Valgrind log does not identify the required AuthService binary"

    summary = re.search(r"definitely lost:\s*([0-9][0-9,]*) bytes", log)
    assert summary, "Valgrind log has no definitely-lost summary"
    summary_bytes = int(summary.group(1).replace(",", ""))
    assert summary_bytes == expected, f"Expected valgrind to report {expected} bytes, got {summary_bytes}"

    full_record = re.search(
        r"([0-9][0-9,]*) bytes in \d+ blocks are definitely lost in loss record",
        log,
    )
    assert full_record, "Missing detailed loss record produced by --leak-check=full"
    assert int(full_record.group(1).replace(",", "")) == expected

    with open("/home/user/leak_report.txt") as f:
        report = f.read().strip()
    assert re.fullmatch(r"[0-9]+", report), f"Leak report is not a single integer: {report!r}"
    assert int(report) == expected, f"Expected extracted value {expected}, got {report}"
DYNAMIC_TEST_EOF

    python3 -m pytest /tmp/test_dynamic_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
