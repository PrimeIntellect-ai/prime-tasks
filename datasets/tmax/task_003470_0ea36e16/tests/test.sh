#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import socket
import subprocess
import time
import secrets
import random
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

import pytest

HOST = "127.0.0.1"
PORT = 9090
SCRIPT = Path("/app/bash-metrics-daemon-1.0/server.sh")

ORIGINAL_SOURCE = '''#!/bin/bash

handle_client() {
    read -r auth_line
    if [[ "$auth_line" == "AUTH x-daemon-token-99" ]]; then
        echo "OK"
    else
        echo "ERROR: UNAUTHORIZED"
        exit 1
    fi

    while read -r line; do
        if [[ -z "$line" ]]; then continue; fi

        # Parse command
        cmd=$(echo "$line" | awk '{print $1}')

        if [[ "$cmd" == "METRIC" ]]; then
            # Extract values
            values=($(echo "$line" | cut -d' ' -f3-))
            sum=0
            count=${#values[@]}

            for v in "${values[@]}"; do
                sum=$(echo "$sum + $v" | bc)
            done

            avg=$(echo "$sum / $count" | bc)
            echo "AVG: $avg"
        fi
    done
}

export -f handle_client
socat TCP-LISTEN:9090,reuseaddr,fork EXEC:"bash -c handle_client"
'''


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[3] == "0A":
                try:
                    port = int(fields[1].split(":")[1], 16)
                except (ValueError, IndexError):
                    continue
                if port == PORT:
                    inodes.add(fields[9])

    pids = set()
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
                    pids.add(int(proc.name))
        except OSError:
            pass
    return pids


def stop_existing_listener():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.4)


def wait_for_server(proc):
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        try:
            with socket.create_connection((HOST, PORT), timeout=0.3):
                return
        except OSError as exc:
            last_error = exc
            if proc.poll() is not None:
                break
            time.sleep(0.1)
    pytest.fail(f"Patched server.sh did not start a listener on {HOST}:{PORT}: {last_error}")


@pytest.fixture(scope="session", autouse=True)
def launch_submitted_server():
    assert SCRIPT.is_file(), f"Missing daemon source: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Daemon source is not executable: {SCRIPT}"
    source = SCRIPT.read_text()
    assert source.startswith("#!") and "bash" in source.splitlines()[0], "server.sh must be a Bash script"
    assert source != ORIGINAL_SOURCE, "server.sh is still byte-identical to the vulnerable vendored source"

    stop_existing_listener()
    proc = subprocess.Popen(
        [str(SCRIPT)],
        cwd=str(SCRIPT.parent),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        wait_for_server(proc)
        yield
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        stop_existing_listener()


def authenticated_connection():
    s = socket.create_connection((HOST, PORT), timeout=5)
    s.settimeout(5)
    f = s.makefile("rw", encoding="utf-8", newline="\n")
    f.write("AUTH x-daemon-token-99\n")
    f.flush()
    assert f.readline() == "OK\n"
    return s, f


def expected_average(values):
    avg = sum(values, Decimal(0)) / Decimal(len(values))
    rounded = avg.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)
    return f"AVG: {rounded:.4f}\n"


def test_daemon_protocol():
    try:
        s = socket.create_connection((HOST, PORT), timeout=5)
    except Exception as e:
        pytest.fail(f"Could not connect to daemon at {HOST}:{PORT}. Did you start it in the background? Error: {e}")

    with s:
        s.settimeout(5)
        f = s.makefile('rw', encoding='utf-8')

        f.write("AUTH x-daemon-token-99\n")
        f.flush()
        resp = f.readline()
        assert resp == "OK\n", f"Expected 'OK\\n' after AUTH, got {repr(resp)}"

        f.write("METRIC MEM 10.1 20.2 30.3\n")
        f.flush()
        resp = f.readline()
        assert resp == "AVG: 20.2000\n", f"Expected 'AVG: 20.2000\\n' for valid metric, got {repr(resp)}. Ensure 4 decimal places precision."

        f.write("METRIC CPU 100 200 NaN 300\n")
        f.flush()
        resp = f.readline()
        assert resp == "ERROR: BAD INPUT\n", f"Expected 'ERROR: BAD INPUT\\n' for NaN metric, got {repr(resp)}"

        f.write("METRIC MEM 1 2 3\n")
        f.flush()
        try:
            resp = f.readline()
        except Exception as e:
            pytest.fail(f"Connection dropped after BAD INPUT. The server must not crash or exit. Error: {e}")
        assert resp == "AVG: 2.0000\n", f"Expected 'AVG: 2.0000\\n' after bad input to ensure connection didn't drop, got {repr(resp)}"


def test_randomized_averages_and_rounding():
    rng = random.SystemRandom()
    for _ in range(10):
        count = rng.randint(2, 8)
        values = [Decimal(rng.randint(1, 9000)) / Decimal(100) for _ in range(count)]
        label = "M" + secrets.token_hex(4)
        s, f = authenticated_connection()
        try:
            payload = " ".join(format(v, "f") for v in values)
            f.write(f"METRIC {label} {payload}\n")
            f.flush()
            assert f.readline() == expected_average(values)
        finally:
            f.close()
            s.close()

    s, f = authenticated_connection()
    try:
        f.write("METRIC ROUNDING 1 2 2\n")
        f.flush()
        assert f.readline() == "AVG: 1.6667\n"
    finally:
        f.close()
        s.close()


def test_arbitrary_bad_values_do_not_kill_connection():
    random_bad = "bad" + secrets.token_hex(10)
    malformed = ["NaN", random_bad, "12oops", "1..2", "++7", "@not_a_number@"]
    rng = random.SystemRandom()
    rng.shuffle(malformed)

    s, f = authenticated_connection()
    try:
        for bad in malformed:
            f.write(f"METRIC CPU {rng.randint(1, 50)} {bad} {rng.randint(51, 99)}\n")
            f.flush()
            assert f.readline() == "ERROR: BAD INPUT\n", f"Malformed value {bad!r} was not rejected"

            a = Decimal(rng.randint(10, 90))
            b = Decimal(rng.randint(10, 90))
            f.write(f"METRIC HEALTH {a} {b}\n")
            f.flush()
            assert f.readline() == expected_average([a, b]), "Connection did not remain usable after bad input"

        f.write("METRIC CPU\n")
        f.flush()
        assert f.readline() == "ERROR: BAD INPUT\n"
        f.write("METRIC HEALTH 4 6\n")
        f.flush()
        assert f.readline() == "AVG: 5.0000\n"
    finally:
        f.close()
        s.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
