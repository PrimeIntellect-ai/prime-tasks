#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import signal
import socket
import subprocess
import tempfile
import threading
import time
import uuid

from scapy.all import IP, UDP, Raw, rdpcap

ROOT = "/home/user"
SRC = "/home/user/src"
ATTACKER = "172.16.44.99"
EXPECTED_PAYLOADS = [b"TYPE_A_DEADLOCK_TRIGGER", b"TYPE_B_DEADLOCK_TRIGGER"]


def test_attacker_ip_identified():
    filepath = "/home/user/attacker_ip.txt"
    assert os.path.isfile(filepath), f"{filepath} is missing. Did you identify the attacker's IP?"
    with open(filepath, "r") as f:
        content = f.read().strip()
    assert content == ATTACKER, f"Incorrect attacker IP found in {filepath}."


def test_supplied_pcap_contains_exact_incident():
    pcap = "/home/user/logs/crash_traffic.pcap"
    assert os.path.isfile(pcap), f"{pcap} is missing."
    packets = rdpcap(pcap)
    incident = []
    for packet in packets:
        if IP in packet and UDP in packet and Raw in packet:
            if packet[IP].src == ATTACKER and int(packet[UDP].dport) == 9000:
                incident.append(bytes(packet[Raw].load))
    assert incident == EXPECTED_PAYLOADS, "The supplied incident PCAP no longer contains the expected triggering pair."


def compile_harness(source_name, output_path, payload_a, payload_b):
    harness = f'''\
#define main included_server_main
#include "{SRC}/{source_name}"
#undef main
#include <atomic>
#include <iostream>
#include <string>
#include <thread>

int main(int argc, char **argv) {{
    const std::string a = {json.dumps(payload_a)};
    const std::string b = {json.dumps(payload_b)};
    if (argc > 1 && std::string(argv[1]) == "sequential") {{
        process_packet(a);
        process_packet(b);
        std::cout << stats[a] << " " << stats[b] << std::endl;
        return (stats[a] == 1 && stats[b] == 1) ? 0 : 3;
    }}

    std::atomic<int> ready(0);
    std::atomic<bool> go(false);
    auto call = [&](const std::string &payload) {{
        ready.fetch_add(1);
        while (!go.load()) std::this_thread::yield();
        process_packet(payload);
    }};
    std::thread first(call, a);
    std::thread second(call, b);
    while (ready.load() != 2) std::this_thread::yield();
    go.store(true);
    first.join();
    second.join();
    std::cout << stats[a] << " " << stats[b] << std::endl;
    return (stats[a] == 1 && stats[b] == 1) ? 0 : 4;
}}
'''
    harness_path = output_path + ".cpp"
    with open(harness_path, "w") as f:
        f.write(harness)
    result = subprocess.run(
        ["g++", "-std=c++14", harness_path, "-o", output_path, "-pthread"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")


def test_server_cpp_compiles_and_retains_unpatched_processing_behavior():
    server = os.path.join(SRC, "server")
    if os.path.lexists(server):
        os.unlink(server)
    result = subprocess.run(
        ["make"], cwd=SRC, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert result.returncode == 0, f"make failed: {result.stderr.decode('utf-8', errors='replace')}"
    assert os.path.isfile(server), f"{server} executable was not built."
    assert os.access(server, os.X_OK), f"{server} is not executable."

    suffix = uuid.uuid4().hex
    payload_a = "TYPE_A_VERIFY_" + suffix
    payload_b = "TYPE_B_VERIFY_" + suffix
    harness = "/tmp/server_original_harness"
    compile_harness("server.cpp", harness, payload_a, payload_b)

    sequential = subprocess.run(
        [harness, "sequential"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=2
    )
    assert sequential.returncode == 0 and sequential.stdout.strip() == b"1 1", \
        "server.cpp no longer performs the required TYPE_A/TYPE_B packet accounting."

    try:
        subprocess.run(
            [harness], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=0.8
        )
    except subprocess.TimeoutExpired:
        pass
    else:
        raise AssertionError("The compiled unpatched server.cpp no longer reproduces the documented lock-order deadlock.")


def test_reproduce_script_sends_exact_pcap_packets_with_triggering_timing():
    script_path = "/home/user/reproduce.py"
    assert os.path.isfile(script_path), f"{script_path} is missing."

    received = []
    ready = threading.Event()
    stop = threading.Event()

    def udp_server():
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(("127.0.0.1", 9000))
        sock.settimeout(0.05)
        ready.set()
        try:
            while not stop.is_set():
                try:
                    data, _ = sock.recvfrom(65535)
                    received.append(data)
                except socket.timeout:
                    pass
        finally:
            sock.close()

    thread = threading.Thread(target=udp_server)
    thread.start()
    assert ready.wait(1), "UDP capture listener failed to start."
    start = time.monotonic()
    try:
        result = subprocess.run(
            ["python3", script_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=2.0
        )
        elapsed = time.monotonic() - start
        time.sleep(0.15)
    finally:
        stop.set()
        thread.join(timeout=1)

    assert result.returncode == 0, f"reproduce.py failed: {result.stderr.decode('utf-8', errors='replace')}"
    assert elapsed <= 2.0, "reproduce.py did not complete within 2 seconds."
    assert collections.Counter(received) == collections.Counter(EXPECTED_PAYLOADS), \
        "reproduce.py must send exactly the two payloads from the incident PCAP."


def process_owns_udp_port(pid, port):
    inodes = set()
    fd_dir = f"/proc/{pid}/fd"
    try:
        for name in os.listdir(fd_dir):
            try:
                target = os.readlink(os.path.join(fd_dir, name))
            except OSError:
                continue
            if target.startswith("socket:[") and target.endswith("]"):
                inodes.add(target[8:-1])
    except FileNotFoundError:
        return False

    wanted = f"{port:04X}"
    for table in ("/proc/net/udp", "/proc/net/udp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[9] in inodes:
                        return True
        except OSError:
            pass
    return False


def start_bound_server(executable):
    proc = subprocess.Popen(
        [executable], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True
    )
    deadline = time.monotonic() + 1.5
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise AssertionError(f"{executable} exited before serving UDP traffic.")
        if process_owns_udp_port(proc.pid, 9000):
            return proc
        time.sleep(0.02)
    terminate_server(proc)
    raise AssertionError(f"{executable} did not bind UDP port 9000.")


def terminate_server(proc):
    if proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=0.5)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=1)


def run_reproducer():
    return subprocess.run(
        ["python3", "/home/user/reproduce.py"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=2.0,
    )


def test_reproducer_deadlocks_actual_unpatched_server():
    proc = start_bound_server(os.path.join(SRC, "server"))
    try:
        result = run_reproducer()
        assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
        time.sleep(0.25)
        assert proc.poll() is None, "The unpatched server exited while processing the regression traffic."
        task_count = len(os.listdir(f"/proc/{proc.pid}/task"))
        assert task_count >= 3, \
            "reproduce.py did not leave the two unpatched packet-processing threads deadlocked."
    finally:
        terminate_server(proc)


def test_server_fixed_compiles_and_patched():
    fixed_src = "/home/user/src/server_fixed.cpp"
    assert os.path.isfile(fixed_src), f"{fixed_src} is missing."

    fixed_bin = "/home/user/src/server_fixed"
    result = subprocess.run(
        ["g++", "-std=c++14", "server_fixed.cpp", "-o", "server_fixed", "-pthread"],
        cwd=SRC, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert result.returncode == 0, f"server_fixed.cpp failed to compile: {result.stderr.decode('utf-8', errors='replace')}"
    assert os.path.isfile(fixed_bin) and os.access(fixed_bin, os.X_OK)

    with open(fixed_src, "r") as f:
        content = f.read()
    stripped_content = "".join(content.split())
    naive_a_b = "lock_guard<std::mutex>lock1(mutex_A);std::this_thread::sleep_for(std::chrono::milliseconds(50));std::lock_guard<std::mutex>lock2(mutex_B);"
    naive_b_a = "lock_guard<std::mutex>lock1(mutex_B);std::this_thread::sleep_for(std::chrono::milliseconds(50));std::lock_guard<std::mutex>lock2(mutex_A);"
    assert not (naive_a_b in stripped_content and naive_b_a in stripped_content), \
        "server_fixed.cpp still appears to contain the inconsistent lock ordering deadlock."

    suffix = uuid.uuid4().hex
    harness = "/tmp/server_fixed_harness"
    compile_harness(
        "server_fixed.cpp", harness, "TYPE_A_VERIFY_" + suffix, "TYPE_B_VERIFY_" + suffix
    )
    completed = subprocess.run(
        [harness], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=2.0
    )
    assert completed.returncode == 0 and completed.stdout.strip() == b"1 1", \
        "server_fixed.cpp does not preserve packet processing and complete concurrent TYPE_A/TYPE_B work without deadlocking."

    proc = start_bound_server(fixed_bin)
    try:
        replay = run_reproducer()
        assert replay.returncode == 0, replay.stderr.decode("utf-8", errors="replace")
        time.sleep(0.3)
        assert proc.poll() is None, "The patched server exited or froze fatally under the regression traffic."
        assert process_owns_udp_port(proc.pid, 9000), \
            "The patched server stopped serving UDP port 9000 after the regression traffic."
    finally:
        terminate_server(proc)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
