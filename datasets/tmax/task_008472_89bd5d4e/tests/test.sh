#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess
from collections import defaultdict

CPP_FILE = "/home/user/config_manager.cpp"
LOG_FILE = "/home/user/data/config_events.log"
PLAN_FILE = "/home/user/deployment_plan.txt"
BINARY_FILE = "/home/user/config_manager"


def compute_expected(log_text):
    configs = defaultdict(dict)
    deps = defaultdict(set)
    services = set()
    pattern = re.compile(r"\[(.*?)\] SERVICE=(.*?) DEPENDS_ON=(.*?) CONFIG=(.*?):(.*)")

    for raw_line in log_text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        match = pattern.match(line)
        if match:
            timestamp, service, depends_on, key, value = match.groups()
            services.add(service)
            if key not in configs[service] or timestamp > configs[service][key][0]:
                configs[service][key] = (timestamp, value)
            if depends_on.strip():
                for dep in depends_on.split(","):
                    dep = dep.strip()
                    if dep:
                        deps[service].add(dep)
                        services.add(dep)

    in_degree = {s: 0 for s in services}
    adj = {s: [] for s in services}
    for service, service_deps in deps.items():
        for dep in service_deps:
            adj[dep].append(service)
            in_degree[service] += 1

    queue = sorted(s for s in services if in_degree[s] == 0)
    sorted_services = []
    while queue:
        current = queue.pop(0)
        sorted_services.append(current)
        for dependent in adj[current]:
            in_degree[dependent] -= 1
            if in_degree[dependent] == 0:
                queue.append(dependent)
        queue.sort()

    expected_lines = []
    for service in sorted_services:
        sorted_keys = sorted(configs[service])
        config_str = ",".join(
            f"{key}={configs[service][key][1]}" for key in sorted_keys
        )
        expected_lines.append(f"SERVICE:{service} CONFIG:{config_str}")
    return "\n".join(expected_lines)


def test_01_cpp_file_exists_and_contains_required_headers():
    assert os.path.isfile(CPP_FILE), f"C++ source file {CPP_FILE} is missing."
    with open(CPP_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    assert "<regex>" in content, "The C++ source code must include <regex>."
    has_threading = any(
        header in content
        for header in ["<thread>", "<future>", "omp.h", "<mutex>", "pthread"]
    )
    assert has_threading, (
        "The C++ source code must include multi-threading headers "
        "(e.g., <thread>, <future>, or omp.h)."
    )


def test_02_deployment_plan_contents():
    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} is missing."
    with open(LOG_FILE, "r", encoding="utf-8") as f:
        log_text = f.read()
    expected_output = compute_expected(log_text)

    assert os.path.isfile(PLAN_FILE), f"Deployment plan {PLAN_FILE} is missing."
    with open(PLAN_FILE, "r", encoding="utf-8") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, (
        f"Deployment plan contents are incorrect.\n"
        f"Expected:\n{expected_output}\n\nActual:\n{actual_output}"
    )


def run_and_check(log_text):
    with open(LOG_FILE, "w", encoding="utf-8") as f:
        f.write(log_text)
    if os.path.exists(PLAN_FILE):
        os.remove(PLAN_FILE)

    result = subprocess.run(
        [BINARY_FILE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Compiled tool exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(PLAN_FILE), "The executed tool did not create deployment_plan.txt."
    with open(PLAN_FILE, "r", encoding="utf-8") as f:
        actual = f.read().strip()
    expected = compute_expected(log_text)
    assert actual == expected, (
        f"Executed tool produced an incorrect plan.\n"
        f"Expected:\n{expected}\n\nActual:\n{actual}"
    )


def test_03_compile_and_execute_on_unpredictable_input():
    with open(LOG_FILE, "r", encoding="utf-8") as f:
        original_log = f.read()
    original_plan = None
    if os.path.isfile(PLAN_FILE):
        with open(PLAN_FILE, "rb") as f:
            original_plan = f.read()

    if os.path.exists(BINARY_FILE):
        os.remove(BINARY_FILE)
    compile_result = subprocess.run(
        [
            "g++", "-O3", "-std=c++17", "-pthread",
            CPP_FILE, "-o", BINARY_FILE,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, (
        f"config_manager.cpp did not compile as C++17.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )
    assert os.path.isfile(BINARY_FILE) and os.access(BINARY_FILE, os.X_OK), (
        "Compilation did not produce an executable /home/user/config_manager."
    )

    token = secrets.token_hex(6)
    names = {
        "a": f"Alpha{token}",
        "b": f"Beta{token}",
        "c": f"Charlie{token}",
        "d": f"Delta{token}",
        "e": f"Echo{token}",
    }
    values = [secrets.token_hex(5) for _ in range(8)]
    lines = [
        f"[2025-04-03 09:00:00] SERVICE={names['a']} DEPENDS_ON= CONFIG=port:{values[0]}",
        f"[2025-04-03 09:09:00] SERVICE={names['a']} DEPENDS_ON= CONFIG=port:{values[1]}",
        f"[2025-04-03 09:04:00] SERVICE={names['a']} DEPENDS_ON= CONFIG=mode:{values[2]}",
        f"[2025-04-03 09:01:00] SERVICE={names['b']} DEPENDS_ON= CONFIG=size:{values[3]}",
        f"[2025-04-03 09:02:00] SERVICE={names['c']} DEPENDS_ON= CONFIG=solo:{values[4]}",
        f"[2025-04-03 09:03:00] SERVICE={names['d']} DEPENDS_ON={names['a']} CONFIG=zeta:{values[5]}",
        f"[2025-04-03 09:08:00] SERVICE={names['d']} DEPENDS_ON={names['b']} CONFIG=zeta:{values[6]}",
        f"[2025-04-03 09:05:00] SERVICE={names['d']} DEPENDS_ON={names['a']} CONFIG=alpha:{values[7]}",
        f"[2025-04-03 09:06:00] SERVICE={names['e']} DEPENDS_ON={names['d']} CONFIG=ready:true",
    ]
    lines.append(lines[5])
    random.SystemRandom().shuffle(lines)
    generated_log = "\n".join(lines) + "\n"

    try:
        # Re-run against the supplied log so a stale hand-written plan cannot pass.
        run_and_check(original_log)
        # Then exercise parsing, latest-value merging, dependency union, key sorting,
        # duplicate handling, and deterministic topological ordering on fresh data.
        run_and_check(generated_log)
    finally:
        with open(LOG_FILE, "w", encoding="utf-8") as f:
            f.write(original_log)
        if original_plan is None:
            if os.path.exists(PLAN_FILE):
                os.remove(PLAN_FILE)
        else:
            with open(PLAN_FILE, "wb") as f:
                f.write(original_plan)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
