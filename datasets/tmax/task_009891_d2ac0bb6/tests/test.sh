#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import time

EXPORTER_DIR = "/home/user/exporter"
METRICS_FILE = os.path.join(EXPORTER_DIR, "metrics.prom")
SERVICE_SCRIPT = os.path.join(EXPORTER_DIR, "service.sh")
COLLECTOR_EXEC = os.path.join(EXPORTER_DIR, "collector")
COLLECTOR_SOURCE = os.path.join(EXPORTER_DIR, "collector.c")
QUOTA_FILE = os.path.join(EXPORTER_DIR, "quota.txt")
MOCK_ROUTE_FILE = os.path.join(EXPORTER_DIR, "mock_route.txt")


def available_bytes():
    vfs = os.statvfs(EXPORTER_DIR)
    return vfs.f_bavail * vfs.f_frsize


def parse_exact_metrics():
    with open(METRICS_FILE, "r") as f:
        content = f.read()
    match = re.fullmatch(
        r"network_gateway_routes_total (\d+)\n"
        r"disk_available_bytes (\d+)\n"
        r"disk_quota_bytes (\d+)\n?",
        content,
    )
    assert match, f"metrics.prom has incorrect format: {content!r}"
    return tuple(int(value) for value in match.groups())


def make_routes(flags):
    lines = ["Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT"]
    for index, flag in enumerate(flags):
        destination = secrets.randbits(32)
        gateway = secrets.randbits(32)
        lines.append(
            f"eth{index % 3}\t{destination:08X}\t{gateway:08X}\t{flag:04X}\t0\t0\t100\tFFFFFFFF\t0\t0\t0"
        )
    return "\n".join(lines) + "\n"


def assert_available_is_current(reported, before, after):
    # A few filesystem blocks can change while the process and verifier run.
    low = min(before, after) - 128 * 1024 * 1024
    high = max(before, after) + 128 * 1024 * 1024
    assert low <= reported <= high, (
        f"disk_available_bytes {reported} is not derived from statvfs; "
        f"observed range was {before}..{after}"
    )


def test_directories_and_files_exist():
    assert os.path.isdir(EXPORTER_DIR), f"Directory {EXPORTER_DIR} does not exist."
    assert os.path.isfile(METRICS_FILE), f"Metrics file {METRICS_FILE} does not exist."
    assert os.path.isfile(SERVICE_SCRIPT), f"Service script {SERVICE_SCRIPT} does not exist."
    assert os.path.isfile(COLLECTOR_EXEC), f"Collector executable {COLLECTOR_EXEC} does not exist."
    assert os.path.isfile(COLLECTOR_SOURCE), f"Collector source {COLLECTOR_SOURCE} does not exist."
    assert os.path.isfile(QUOTA_FILE), f"Quota file {QUOTA_FILE} does not exist."
    assert os.path.isfile(MOCK_ROUTE_FILE), f"Mock route file {MOCK_ROUTE_FILE} does not exist."


def test_service_script_executable():
    st = os.stat(SERVICE_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"{SERVICE_SCRIPT} is not executable."


def test_collector_is_executable_elf():
    st = os.stat(COLLECTOR_EXEC)
    assert st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), "collector is not executable"
    with open(COLLECTOR_EXEC, "rb") as f:
        header = f.read(20)
    assert len(header) >= 20 and header[:4] == b"\x7fELF", "collector is not a compiled ELF executable"
    assert header[4] in (1, 2) and header[5] in (1, 2), "collector has an invalid ELF header"
    byteorder = "little" if header[5] == 1 else "big"
    assert int.from_bytes(header[16:18], byteorder) in (2, 3), "collector is not an executable ELF file"


def test_metrics_content():
    with open(METRICS_FILE, "r") as f:
        content = f.read()

    metrics = {}
    for line in content.strip().split("\n"):
        parts = line.strip().split()
        if len(parts) == 2:
            metrics[parts[0]] = parts[1]

    assert "network_gateway_routes_total" in metrics, "network_gateway_routes_total missing in metrics.prom"
    assert metrics["network_gateway_routes_total"] == "2", f"Expected network_gateway_routes_total to be 2, got {metrics['network_gateway_routes_total']}"
    assert "disk_quota_bytes" in metrics, "disk_quota_bytes missing in metrics.prom"
    assert metrics["disk_quota_bytes"] == "53687091200", f"Expected disk_quota_bytes to be 53687091200, got {metrics['disk_quota_bytes']}"
    assert "disk_available_bytes" in metrics, "disk_available_bytes missing in metrics.prom"
    avail_bytes = metrics["disk_available_bytes"]
    assert re.match(r"^\d+$", avail_bytes), f"disk_available_bytes is not a valid integer: {avail_bytes}"
    assert int(avail_bytes) > 0, "disk_available_bytes should be greater than 0"


def test_mock_files_content():
    with open(QUOTA_FILE, "r") as f:
        quota_content = f.read().strip()
    assert quota_content == "53687091200", "quota.txt does not contain the expected value."

    with open(MOCK_ROUTE_FILE, "r") as f:
        route_content = f.read().strip()
    expected_route_lines = 5
    assert len(route_content.split('\n')) >= expected_route_lines, "mock_route.txt does not contain the expected number of lines."
    assert "010011AC" in route_content, "mock_route.txt does not seem to contain the expected mock data."


def test_collector_computes_metrics_from_changed_inputs():
    with open(QUOTA_FILE, "rb") as f:
        original_quota = f.read()
    with open(MOCK_ROUTE_FILE, "rb") as f:
        original_routes = f.read()

    try:
        for _ in range(2):
            flags = [secrets.randbits(16) for _ in range(9)]
            # Force both gateway and non-gateway examples in every run.
            flags[0] |= 0x0002
            flags[1] &= ~0x0002
            expected_routes = sum(bool(flag & 0x0002) for flag in flags)
            quota = secrets.randbelow(8_000_000_000_000) + 1000
            with open(MOCK_ROUTE_FILE, "w") as f:
                f.write(make_routes(flags))
            with open(QUOTA_FILE, "w") as f:
                f.write(f"{quota}\n")
            if os.path.exists(METRICS_FILE):
                os.remove(METRICS_FILE)

            before = available_bytes()
            result = subprocess.run(
                [COLLECTOR_EXEC], cwd=EXPORTER_DIR, timeout=5,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            after = available_bytes()
            assert result.returncode == 0, f"collector failed: {result.stderr}"
            assert os.path.isfile(METRICS_FILE), "collector did not create metrics.prom"
            route_count, reported_available, reported_quota = parse_exact_metrics()
            assert route_count == expected_routes
            assert reported_quota == quota
            assert_available_is_current(reported_available, before, after)
    finally:
        with open(QUOTA_FILE, "wb") as f:
            f.write(original_quota)
        with open(MOCK_ROUTE_FILE, "wb") as f:
            f.write(original_routes)
        subprocess.run([COLLECTOR_EXEC], cwd=EXPORTER_DIR, timeout=5,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def test_service_start_and_stop_execute_collector():
    with open(QUOTA_FILE, "rb") as f:
        original_quota = f.read()
    with open(MOCK_ROUTE_FILE, "rb") as f:
        original_routes = f.read()

    pid_file = os.path.join(EXPORTER_DIR, "collector.pid")
    started = False
    try:
        flags = [0x0001, 0x0002, 0x0003, 0x0005, 0x000A, 0x00F0]
        expected_routes = sum(bool(flag & 0x0002) for flag in flags)
        quota = secrets.randbelow(8_000_000_000_000) + 1000
        with open(MOCK_ROUTE_FILE, "w") as f:
            f.write(make_routes(flags))
        with open(QUOTA_FILE, "w") as f:
            f.write(f"{quota}\n")
        for path in (METRICS_FILE, pid_file):
            if os.path.exists(path):
                os.remove(path)

        before = available_bytes()
        result = subprocess.run(
            [SERVICE_SCRIPT, "start"], cwd=EXPORTER_DIR, timeout=5,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        assert result.returncode == 0, "service.sh start failed"
        started = True
        assert os.path.isfile(pid_file), "service.sh start did not create collector.pid"

        deadline = time.time() + 3
        parsed = None
        while time.time() < deadline:
            if os.path.isfile(METRICS_FILE):
                try:
                    parsed = parse_exact_metrics()
                    if parsed[0] == expected_routes and parsed[2] == quota:
                        break
                except (AssertionError, OSError):
                    pass
            time.sleep(0.05)
        assert parsed is not None, "service.sh start did not cause collector to write metrics"
        route_count, reported_available, reported_quota = parsed
        assert route_count == expected_routes
        assert reported_quota == quota
        assert_available_is_current(reported_available, before, available_bytes())

        stopped = subprocess.run(
            [SERVICE_SCRIPT, "stop"], cwd=EXPORTER_DIR, timeout=5,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        assert stopped.returncode == 0, "service.sh stop failed"
        started = False
        assert not os.path.exists(pid_file), "service.sh stop did not remove collector.pid"
    finally:
        if started and os.path.exists(pid_file):
            subprocess.run([SERVICE_SCRIPT, "stop"], cwd=EXPORTER_DIR, timeout=5,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with open(QUOTA_FILE, "wb") as f:
            f.write(original_quota)
        with open(MOCK_ROUTE_FILE, "wb") as f:
            f.write(original_routes)
        subprocess.run([COLLECTOR_EXEC], cwd=EXPORTER_DIR, timeout=5,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
