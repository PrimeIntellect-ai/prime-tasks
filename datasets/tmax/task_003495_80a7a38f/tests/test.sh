#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import signal
import socket
import subprocess
import tempfile
import threading
import time
import uuid


def expected_metric(uptime, cpu, mem):
    status = "OK" if cpu < 90 and mem < 90 else "WARN"
    return f"[STAT] U:{uptime} C:{cpu} M:{mem} {status}\n"


def test_setup_complete_log():
    log_path = "/home/user/setup_complete.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "DONE", f"Expected 'DONE' in {log_path}, but got '{content}'."


def test_bridge_script_executable():
    script_path = "/home/user/bridge.sh"
    assert os.path.isfile(script_path), f"Bridge script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Bridge script {script_path} is not executable."


def test_metric_parser_executable():
    parser_path = "/home/user/metric_parser"
    assert os.path.isfile(parser_path), f"Metric parser {parser_path} is missing."
    assert os.access(parser_path, os.X_OK), f"Metric parser {parser_path} is not executable."
    with open(parser_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "metric_parser must be a compiled executable."


def test_metric_parser_not_copied_oracle():
    agent_parser = "/home/user/metric_parser"
    oracle_parser = "/app/bin/oracle_parser"
    with open(agent_parser, "rb") as f:
        agent_bytes = f.read()
    with open(oracle_parser, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "metric_parser must not be a byte-for-byte copy of the oracle."


def test_metric_parser_fuzz_equivalence():
    agent_parser = "/home/user/metric_parser"
    oracle_parser = "/app/bin/oracle_parser"

    assert os.path.isfile(agent_parser), f"Agent parser {agent_parser} is missing."
    assert os.path.isfile(oracle_parser), f"Oracle parser {oracle_parser} is missing."

    random.seed(42)
    for _ in range(1000):
        uptime = random.randint(0, 99999)
        cpu = random.randint(0, 999)
        mem = random.randint(0, 999)
        test_input = f"UPTIME:{uptime}:CPU:{cpu}:MEM:{mem}\n"

        agent_proc = subprocess.run(
            [agent_parser], input=test_input, text=True, capture_output=True, timeout=3
        )
        oracle_proc = subprocess.run(
            [oracle_parser], input=test_input, text=True, capture_output=True, timeout=3
        )

        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Output mismatch for input: {test_input!r}\n"
            f"Expected (Oracle): {oracle_proc.stdout!r}\n"
            f"Got (Agent): {agent_proc.stdout!r}\n"
            f"Agent stderr: {agent_proc.stderr!r}"
        )


def test_metric_parser_source_exists_compiles_and_works():
    source = "/home/user/metric_parser.c"
    assert os.path.isfile(source), f"C source {source} is missing."
    assert not os.path.islink(source), f"C source {source} must be a regular source file."

    output = os.path.join(tempfile.gettempdir(), "metric_parser_from_source")
    compile_proc = subprocess.run(
        ["gcc", source, "-o", output], text=True, capture_output=True, timeout=15
    )
    assert compile_proc.returncode == 0, f"metric_parser.c did not compile:\n{compile_proc.stderr}"

    oracle = "/app/bin/oracle_parser"
    hidden_oracle = f"/tmp/oracle_parser.hidden.{uuid.uuid4().hex}"
    os.replace(oracle, hidden_oracle)
    try:
        rng = random.SystemRandom()
        cases = [(0, 0, 0), (1, 89, 89), (2, 90, 89), (3, 89, 90), (99999, 999, 999)]
        cases.extend((rng.randint(0, 99999), rng.randint(0, 999), rng.randint(0, 999)) for _ in range(200))
        for uptime, cpu, mem in cases:
            raw = f"UPTIME:{uptime}:CPU:{cpu}:MEM:{mem}\n"
            proc = subprocess.run(
                [output], input=raw, text=True, capture_output=True, timeout=3
            )
            assert proc.returncode == 0, f"Parser compiled from source failed: {proc.stderr!r}"
            assert proc.stdout == expected_metric(uptime, cpu, mem), (
                f"Parser compiled from metric_parser.c produced the wrong result for {raw!r}: "
                f"{proc.stdout!r}"
            )
    finally:
        os.replace(hidden_oracle, oracle)
        if os.path.exists(output):
            os.unlink(output)


def test_bridge_transfers_multiple_live_metrics_through_parser():
    parser = "/home/user/metric_parser"
    real_parser = "/home/user/metric_parser.verifier-real"
    marker = f"/tmp/parser-called-{uuid.uuid4().hex}"
    rng = random.SystemRandom()
    cases = [
        (rng.randint(100000, 999999), rng.randint(0, 89), rng.randint(0, 89)),
        (rng.randint(100000, 999999), rng.randint(90, 999), rng.randint(0, 89)),
        (rng.randint(100000, 999999), rng.randint(0, 89), rng.randint(90, 999)),
    ]
    raw_lines = [f"UPTIME:{u}:CPU:{c}:MEM:{m}\n" for u, c, m in cases]
    expected = [expected_metric(u, c, m).strip() for u, c, m in cases]
    received = []
    errors = []
    ready_emitter = threading.Event()
    ready_collector = threading.Event()

    def emitter():
        try:
            with socket.socket() as s:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                s.bind(("127.0.0.1", 9001))
                s.listen(5)
                s.settimeout(12)
                ready_emitter.set()
                for line in raw_lines:
                    conn, _ = s.accept()
                    with conn:
                        conn.sendall(line.encode())
        except Exception as exc:
            errors.append(f"emitter: {exc}")

    def collector():
        try:
            with socket.socket() as s:
                s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                s.bind(("127.0.0.1", 9002))
                s.listen(5)
                s.settimeout(12)
                ready_collector.set()
                while len(received) < len(expected):
                    conn, _ = s.accept()
                    with conn:
                        conn.settimeout(3)
                        chunks = []
                        while True:
                            data = conn.recv(4096)
                            if not data:
                                break
                            chunks.append(data)
                    received.extend(b"".join(chunks).decode().splitlines())
        except Exception as exc:
            errors.append(f"collector: {exc}")

    et = threading.Thread(target=emitter, daemon=True)
    ct = threading.Thread(target=collector, daemon=True)
    et.start()
    ct.start()
    assert ready_emitter.wait(3), "Test emitter could not listen on port 9001."
    assert ready_collector.wait(3), "Test collector could not listen on port 9002."

    os.replace(parser, real_parser)
    with open(parser, "w") as f:
        f.write(f"#!/bin/sh\necho called >> {marker}\nexec {real_parser} \"$@\"\n")
    os.chmod(parser, 0o755)

    bridge = None
    try:
        bridge = subprocess.Popen(
            ["/home/user/bridge.sh"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        deadline = time.time() + 12
        while time.time() < deadline and len(received) < len(expected) and not errors:
            time.sleep(0.1)
    finally:
        if bridge is not None:
            try:
                os.killpg(bridge.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                bridge.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(bridge.pid, signal.SIGKILL)
                bridge.wait(timeout=2)
        if os.path.exists(parser):
            os.unlink(parser)
        os.replace(real_parser, parser)

    et.join(timeout=1)
    ct.join(timeout=1)
    assert not errors, "; ".join(errors)
    calls = 0
    if os.path.exists(marker):
        with open(marker) as f:
            calls = len(f.readlines())
        os.unlink(marker)
    assert calls >= len(cases), "bridge.sh did not pipe each live metric through /home/user/metric_parser."
    assert received[:len(expected)] == expected, (
        f"bridge.sh did not continuously transfer correctly parsed network metrics. "
        f"Expected {expected!r}, got {received!r}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
