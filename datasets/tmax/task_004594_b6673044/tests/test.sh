#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import tempfile
import pytest


def test_part1_log_merger():
    merged_log = "/home/user/merged_access.log"
    assert os.path.exists(merged_log), f"{merged_log} does not exist."
    assert os.path.getsize(merged_log) > 0, f"{merged_log} is empty."

    binary = "/home/user/log_merger/log_merger"
    assert os.path.exists(binary), f"{binary} does not exist. Did you run make?"
    assert os.access(binary, os.X_OK), f"{binary} is not executable."

    project = "/home/user/log_merger"
    makefile = os.path.join(project, "Makefile")
    object_file = os.path.join(project, "main.o")
    assert os.path.isfile(makefile), f"{makefile} does not exist."

    # Remove previous build products and require the submitted Makefile to build them.
    for path in (binary, object_file):
        if os.path.lexists(path):
            os.remove(path)

    build = subprocess.run(
        ["make"], cwd=project, capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, (
        f"make failed with exit code {build.returncode}\n"
        f"stdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )
    assert os.path.isfile(object_file), "make did not compile main.c into main.o."
    assert os.path.isfile(binary), "make did not create log_merger."
    assert os.access(binary, os.X_OK), "rebuilt log_merger is not executable."

    with open(object_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", "main.o is not a compiled ELF object file."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_merger is not a compiled ELF executable."

    # Exercise the rebuilt utility on verifier-controlled inputs.
    with tempfile.TemporaryDirectory() as td:
        first = os.path.join(td, "first.log")
        second = os.path.join(td, "second.log")
        first_data = b"verifier-first-9f31\nverifier-first-2a77\n"
        second_data = b"verifier-second-c814\nverifier-second-005b\n"
        with open(first, "wb") as f:
            f.write(first_data)
        with open(second, "wb") as f:
            f.write(second_data)

        proc = subprocess.run(
            [binary, first, second], capture_output=True, timeout=10
        )
        assert proc.returncode == 0, "rebuilt log_merger failed on valid inputs."
        assert proc.stdout == first_data + second_data, (
            "rebuilt log_merger did not correctly merge verifier-controlled logs."
        )

    node1 = "/home/user/logs/node1.log"
    node2 = "/home/user/logs/node2.log"
    expected_node1 = b"node1 log entry 1\nnode1 log entry 2\n"
    expected_node2 = b"node2 log entry 1\nnode2 log entry 2\n"
    with open(node1, "rb") as f:
        assert f.read() == expected_node1, "node1.log was modified."
    with open(node2, "rb") as f:
        assert f.read() == expected_node2, "node2.log was modified."

    proc = subprocess.run(
        [binary, node1, node2], capture_output=True, timeout=10
    )
    assert proc.returncode == 0, "log_merger failed on the specified logs."
    expected_merged = expected_node1 + expected_node2
    assert proc.stdout == expected_merged, "log_merger produced incorrect output for the specified logs."
    with open(merged_log, "rb") as f:
        actual_merged = f.read()
    assert actual_merged == proc.stdout, (
        "merged_access.log is not the output produced by log_merger for node1.log and node2.log."
    )


def generate_fuzz_strings(n=2000):
    random.seed(42)
    chars = string.ascii_letters + string.digits + "/.%<>_-"

    components = [
        "../", ".env", ".php", "<script>", "admin/",
        "%2e%2e%2f", "%2E%2E%2F", "%2eenv", "%2Ephp", "%3cscript%3e", "admin%2f",
        "//", "///", "/./", "/../", "/a/b/./c//d/",
        "a", "b", "1", "2"
    ]

    payloads = []
    for _ in range(n):
        length = random.randint(1, 255)
        parts = []
        cur_len = 0
        while cur_len < length:
            if random.random() < 0.5:
                comp = random.choice(components)
            else:
                comp = "".join(random.choices(chars, k=random.randint(1, 10)))
            if cur_len + len(comp) > length:
                comp = comp[:length - cur_len]
            parts.append(comp)
            cur_len += len(comp)

        payloads.append("".join(parts))
    return payloads


def test_part2_waf_evaluator_fuzz():
    agent_script = "/home/user/waf_eval_pure.sh"
    oracle_bin = "/app/waf_evaluator_stripped"

    assert os.path.exists(agent_script), f"{agent_script} does not exist."

    payloads = generate_fuzz_strings(2000)

    for payload in payloads:
        oracle_proc = subprocess.run(
            [oracle_bin, payload],
            capture_output=True,
            text=True
        )
        oracle_out = oracle_proc.stdout.strip()
        oracle_code = oracle_proc.returncode

        agent_proc = subprocess.run(
            ["bash", agent_script, payload],
            capture_output=True,
            text=True
        )
        agent_out = agent_proc.stdout.strip()
        agent_code = agent_proc.returncode

        assert oracle_code == agent_code, f"Exit code mismatch on payload: {repr(payload)}\nOracle exited with {oracle_code}, Agent exited with {agent_code}\nOracle stdout: {oracle_out}\nAgent stdout: {agent_out}"
        assert oracle_out == agent_out, f"Stdout mismatch on payload: {repr(payload)}\nOracle stdout: {repr(oracle_out)}\nAgent stdout: {repr(agent_out)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
