#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import signal
import struct
import subprocess
import tempfile
import time
import pytest

APP = "/home/user/app"
WORK = "/home/user/workspace"
SHARED = f"{APP}/shared_logs"


def read_environ(pid):
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            entries = f.read().split(b"\0")
        return dict(e.split(b"=", 1) for e in entries if b"=" in e)
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return {}


def service_pids(role):
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        env = read_environ(int(name))
        if env.get(b"SERVICE_ROLE") == role.encode():
            found.append(int(name))
    return found


def kill_service_fixtures():
    for role in ("generator", "aggregator", "sink"):
        for pid in service_pids(role):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    time.sleep(0.2)


def descendants(root_pid):
    parent = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/stat", "r") as f:
                stat = f.read()
            rest = stat[stat.rfind(")") + 2:].split()
            parent[int(name)] = int(rest[1])
        except (FileNotFoundError, ProcessLookupError, ValueError, IndexError):
            pass

    result = set()
    changed = True
    while changed:
        changed = False
        for pid, ppid in parent.items():
            if pid not in result and (ppid == root_pid or ppid in result):
                result.add(pid)
                changed = True
    return result


def parser_descendants(root_pid):
    parser = f"{WORK}/alert_parser"
    result = []
    for pid in descendants(root_pid):
        try:
            if os.path.samefile(f"/proc/{pid}/exe", parser):
                result.append(pid)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return result


def tail_follow_descendants(root_pid):
    result = []
    for pid in descendants(root_pid):
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        if args and os.path.basename(args[0]) == "tail" and any(
            a == "-f" or a == "-F" or a.startswith("--follow") for a in args[1:]
        ):
            result.append(pid)
    return result


def wait_until(predicate, timeout, interval=0.05):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(interval)
    return predicate()


def expected_output(data):
    lines = []
    for offset in range(0, len(data) - 7, 8):
        ts, alert_id, severity = struct.unpack_from("<IHH", data, offset)
        lines.append(f"ALERT: {alert_id} at {ts} with severity {severity}\n".encode())
    return b"".join(lines)


def test_config_env_fixed():
    config_path = f"{APP}/config.env"
    assert os.path.isfile(config_path), f"{config_path} is missing"
    with open(config_path, "r") as f:
        content = f.read()

    assert re.search(r"^SHARED_DIR=/home/user/app/shared_logs/?$", content, re.MULTILINE), \
        "config.env does not contain the correct SHARED_DIR path"
    assert re.search(r"^LOG_MODE=binary$", content, re.MULTILINE), \
        "config.env does not contain the correct LOG_MODE=binary"


def test_shared_dir_exists():
    assert os.path.isdir(SHARED), f"Shared directory {SHARED} was not created"


def test_alert_parser_fuzz_equivalence():
    oracle_path = f"{APP}/oracle_parser"
    agent_path = f"{WORK}/alert_parser"
    source_path = f"{WORK}/alert_parser.c"

    assert os.path.isfile(oracle_path), f"Oracle parser {oracle_path} missing"
    assert os.path.isfile(source_path), f"C source {source_path} missing"
    assert not os.path.islink(source_path), "alert_parser.c must be an actual source file"
    assert os.path.isfile(agent_path), f"Agent parser {agent_path} missing"
    assert not os.path.islink(agent_path), "alert_parser must not be a symlink"
    assert os.access(agent_path, os.X_OK), f"Agent parser {agent_path} is not executable"
    assert not os.path.samefile(agent_path, oracle_path), "alert_parser must not be the oracle or a hard link to it"
    with open(agent_path, "rb") as f:
        agent_bytes = f.read()
    with open(oracle_path, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "alert_parser must not be a byte-for-byte copy of the oracle"

    rebuilt = "/tmp/rebuilt_alert_parser"
    compile_proc = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", "-O2", source_path, "-o", rebuilt],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert compile_proc.returncode == 0, f"alert_parser.c does not compile:\n{compile_proc.stderr}"

    derived_inputs = [
        b"",
        b"\x00" * 7,
        struct.pack("<IHH", 0, 0, 0),
        struct.pack("<IHH", 0xFFFFFFFF, 0xFFFF, 0xFFFF),
        struct.pack("<IHH", 123456789, 42, 7) + b"partial",
        b"".join(struct.pack("<IHH", ts, ident, sev) for ts, ident, sev in [
            (1, 2, 3), (4000000000, 65530, 9), (99, 0, 65535)
        ]),
    ]
    for binary in (rebuilt, agent_path):
        for data in derived_inputs:
            proc = subprocess.run([binary], input=data, capture_output=True, timeout=2)
            assert proc.returncode == 0, f"{binary} exited with {proc.returncode}"
            assert proc.stdout == expected_output(data), \
                f"{binary} produced incorrect output for {data.hex()}"

    random.seed(42)
    for _ in range(1000):
        length = random.randint(0, 1024)
        input_data = bytes(random.getrandbits(8) for _ in range(length))
        try:
            oracle_proc = subprocess.run(
                [oracle_path], input=input_data, capture_output=True, timeout=1
            )
            oracle_out = oracle_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input of length {length}")
        try:
            agent_proc = subprocess.run(
                [agent_path], input=input_data, capture_output=True, timeout=1
            )
            agent_out = agent_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on input of length {length}")
        assert agent_out == oracle_out, \
            f"Output mismatch on input of length {length}. Input: {input_data.hex()}"


def test_start_services_launches_working_pipeline():
    start_path = f"{APP}/start_services.sh"
    assert os.path.isfile(start_path), f"{start_path} is missing"
    assert os.access(start_path, os.X_OK), f"{start_path} is not executable"
    for fixture in ("generator.sh", "aggregator.sh", "sink.sh"):
        path = f"{APP}/{fixture}"
        assert os.path.isfile(path), f"Required service fixture {path} is missing"
        assert os.access(path, os.X_OK), f"Required service fixture {path} is not executable"

    kill_service_fixtures()
    os.makedirs(SHARED, exist_ok=True)
    for name in ("generator.bin", "aggregated.bin", "sink.bin"):
        try:
            os.remove(f"{SHARED}/{name}")
        except FileNotFoundError:
            pass

    try:
        proc = subprocess.run(
            [start_path], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
            text=True, timeout=3
        )
        assert proc.returncode == 0, f"start_services.sh failed: {proc.stderr}"

        roles = {}
        for role in ("generator", "aggregator", "sink"):
            pids = wait_until(lambda r=role: service_pids(r), 2.0)
            assert pids, f"The {role} service was not started"
            roles[role] = set(pids)
            for pid in pids:
                env = read_environ(pid)
                assert env.get(b"SHARED_DIR", b"").rstrip(b"/") == SHARED.encode(), \
                    f"The {role} service is not using the shared directory"
                assert env.get(b"LOG_MODE") == b"binary", \
                    f"The {role} service is not using binary log mode"

        time.sleep(1.3)
        for role, original in roles.items():
            assert original.intersection(service_pids(role)), f"The {role} service did not stay running"

        for name in ("generator.bin", "aggregated.bin", "sink.bin"):
            path = f"{SHARED}/{name}"
            assert wait_until(lambda p=path: os.path.isfile(p) and os.path.getsize(p) >= 8, 3.0), \
                f"Service pipeline did not populate {path}"
    finally:
        kill_service_fixtures()


def test_monitor_script_exists_and_operates():
    monitor_path = f"{WORK}/monitor.sh"
    parser_path = f"{WORK}/alert_parser"
    input_path = f"{SHARED}/generator.bin"
    alerts_path = f"{WORK}/alerts.log"

    assert os.path.isfile(monitor_path), f"{monitor_path} is missing"
    assert os.access(monitor_path, os.X_OK), f"{monitor_path} is not executable"
    os.makedirs(SHARED, exist_ok=True)
    open(input_path, "wb").close()
    open(alerts_path, "wb").close()

    monitor = subprocess.Popen(
        [monitor_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    try:
        assert wait_until(lambda: monitor.poll() is None and parser_descendants(monitor.pid), 2.5), \
            "monitor.sh did not launch alert_parser"
        assert wait_until(lambda: tail_follow_descendants(monitor.pid), 2.0), \
            "monitor.sh is not following generator.bin with tail -f/-F"

        records = [(1700000000, 101, 2), (1700000001, 65535, 9)]
        payload = b"".join(struct.pack("<IHH", *record) for record in records)
        with open(input_path, "ab", buffering=0) as f:
            f.write(payload)

        wanted = expected_output(payload)
        def alerts_contain_records():
            try:
                with open(alerts_path, "rb") as f:
                    return wanted in f.read()
            except FileNotFoundError:
                return False
        assert wait_until(alerts_contain_records, 3.5), \
            "monitor.sh did not continuously populate alerts.log with parsed records"

        old_parsers = set(parser_descendants(monitor.pid))
        assert old_parsers, "No parser process was available for restart testing"
        killed_at = time.monotonic()
        for pid in old_parsers:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

        new_parsers = wait_until(
            lambda: set(parser_descendants(monitor.pid)) - old_parsers,
            1.2,
            interval=0.02,
        )
        assert new_parsers, "monitor.sh did not restart alert_parser within 1 second"
        assert time.monotonic() - killed_at <= 1.2
        assert monitor.poll() is None, "monitor.sh exited while restarting the parser"
    finally:
        try:
            os.killpg(monitor.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            monitor.wait(timeout=1)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(monitor.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def test_bashrc_exported_variable():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} is missing"
    with open(bashrc_path, "r") as f:
        content = f.read()
    assert re.search(r"MONITOR_ACTIVE=1", content), ".bashrc does not set MONITOR_ACTIVE=1"
    assert re.search(r"^\s*export\s+(?:MONITOR_ACTIVE=1|MONITOR_ACTIVE(?:\s|$))", content, re.MULTILINE), \
        ".bashrc does not export MONITOR_ACTIVE"
    proc = subprocess.run(
        ["bash", "--noprofile", "--rcfile", bashrc_path, "-ic", "printf %s \"$MONITOR_ACTIVE\""],
        capture_output=True, text=True, timeout=3
    )
    assert proc.stdout == "1", "MONITOR_ACTIVE is not exported as 1 by .bashrc"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
