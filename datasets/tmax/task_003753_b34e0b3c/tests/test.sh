#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import random
import secrets
import socket
import string
import subprocess
import threading

import pytest

AGENT_SCRIPT = "/home/user/aggregator.sh"
HOST = "127.0.0.1"
PORTS = (9001, 9002, 9003)


def serve_data(port, data, ready_event):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((HOST, port))
    s.listen(1)
    ready_event.set()
    try:
        s.settimeout(10.0)
        conn, _ = s.accept()
        with conn:
            conn.sendall(data.encode("utf-8"))
    finally:
        s.close()


def new_order_id(used, rng):
    alphabet = string.ascii_letters + string.digits
    while True:
        oid = "".join(rng.choice(alphabet) for _ in range(12))
        if oid not in used:
            used.add(oid)
            return oid


def generate_case():
    rng = secrets.SystemRandom()
    used = set()
    orders = []
    payments = []
    shipping = []
    expected_rows = []

    def timestamp():
        return rng.randint(1400000000, 1893455999)

    def add_order(oid, ts=None):
        if ts is None:
            ts = timestamp()
        dt = datetime.datetime.fromtimestamp(ts, datetime.timezone.utc)
        amount = f"{rng.randint(5, 500)}.{rng.randint(0, 99):02d}"
        orders.append(f"{dt.strftime('%Y-%m-%d %H:%M:%S')}, {oid}, {amount}")
        return ts, amount

    def add_payment(oid):
        ts = timestamp()
        status = rng.choice(("SUCCESS", "FAILED", "PENDING"))
        payments.append(f"{ts}\t{oid}\t{status}")
        return status

    def add_shipping(oid):
        ts = timestamp()
        dt = datetime.datetime.fromtimestamp(ts, datetime.timezone.utc)
        warehouse = rng.choice(("EAST", "WEST", "CENTRAL"))
        shipping.append(f"{dt.strftime('%Y-%m-%dT%H:%M:%SZ')} | {oid} | {warehouse}")
        return warehouse

    # Guaranteed nonempty inner join, with enough rows to exercise sorting.
    for _ in range(rng.randint(300, 450)):
        oid = new_order_id(used, rng)
        order_ts, amount = add_order(oid)
        status = add_payment(oid)
        warehouse = add_shipping(oid)
        expected_rows.append((order_ts, oid, amount, status, warehouse))

    # Add records absent from one or two streams so non-inner joins cannot pass.
    for streams in (("o",), ("p",), ("s",), ("o", "p"),
                    ("o", "s"), ("p", "s")):
        for _ in range(rng.randint(35, 70)):
            oid = new_order_id(used, rng)
            if "o" in streams:
                add_order(oid)
            if "p" in streams:
                add_payment(oid)
            if "s" in streams:
                add_shipping(oid)

    rng.shuffle(orders)
    rng.shuffle(payments)
    rng.shuffle(shipping)

    expected_rows.sort(key=lambda row: (row[0], row[1]))
    expected = "".join(
        f"{oid},{ts},{amount},{status},{warehouse}\n"
        for ts, oid, amount, status, warehouse in expected_rows
    )
    return (
        "\n".join(orders) + "\n",
        "\n".join(payments) + "\n",
        "\n".join(shipping) + "\n",
        expected,
    )


def run_script_with_services(orders, payments, shipping):
    ready_events = [threading.Event() for _ in PORTS]
    threads = [
        threading.Thread(target=serve_data, args=(port, data, event))
        for port, data, event in zip(
            PORTS, (orders, payments, shipping), ready_events
        )
    ]
    for thread in threads:
        thread.start()
    for event in ready_events:
        assert event.wait(5), "A mock service failed to start"

    env = os.environ.copy()
    env["TZ"] = "UTC"
    try:
        result = subprocess.run(
            ["/bin/bash", AGENT_SCRIPT],
            capture_output=True,
            text=True,
            timeout=30,
            env=env,
        )
    finally:
        for thread in threads:
            thread.join(timeout=12)

    assert all(not thread.is_alive() for thread in threads), \
        "The script failed to connect to every service"
    return result


def test_agent_exists_and_executable():
    assert os.path.exists(AGENT_SCRIPT), \
        f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), \
        f"Agent script {AGENT_SCRIPT} is not a regular file."
    assert os.access(AGENT_SCRIPT, os.X_OK), \
        f"Agent script {AGENT_SCRIPT} is not executable."


def test_fuzz_equivalence():
    for iteration in range(10):
        orders, payments, shipping, expected = generate_case()
        result = run_script_with_services(orders, payments, shipping)
        assert result.stdout == expected, (
            f"Mismatch on fuzz iteration {iteration + 1}!\n\n"
            f"--- Expected Output ---\n{expected[:2000]}\n\n"
            f"--- Agent Output ---\n{result.stdout[:2000]}\n\n"
            f"--- Agent Stderr ---\n{result.stderr[:2000]}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
