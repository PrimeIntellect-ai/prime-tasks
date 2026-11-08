#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import signal
import socket
import string
import subprocess
import time
from pathlib import Path

import requests
from PIL import Image, ImageDraw, ImageFont

BASE_URL = "http://127.0.0.1:8080"
ENDPOINT = "/dept-top-earners"
PROJECT = Path("/home/user/app-service")


def request(dept, token=None, timeout=5):
    headers = {}
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    return requests.get(
        f"{BASE_URL}{ENDPOINT}",
        params={"dept_id": dept},
        headers=headers,
        timeout=timeout,
    )


def assert_response(response, dept, expected):
    assert response.status_code == 200, (
        f"Expected 200 for department {dept}, got {response.status_code}: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        raise AssertionError(f"Response is not valid JSON: {response.text}")

    assert set(data.keys()) == {"department", "top_earners"}, data
    assert data["department"] == dept
    assert isinstance(data["top_earners"], list)
    assert len(data["top_earners"]) == len(expected)

    for index, (actual, wanted) in enumerate(zip(data["top_earners"], expected), 1):
        assert isinstance(actual, dict), f"Rank {index} is not an object"
        assert set(actual.keys()) == {"emp_id", "team_volume"}, actual
        assert actual["emp_id"] == wanted["emp_id"], (
            f"Rank {index}: expected {wanted['emp_id']}, got {actual.get('emp_id')}"
        )
        assert isinstance(actual["team_volume"], (int, float)) and not isinstance(actual["team_volume"], bool)
        assert abs(float(actual["team_volume"]) - wanted["team_volume"]) < 1e-5, (
            f"Rank {index}: expected volume {wanted['team_volume']}, "
            f"got {actual['team_volume']}"
        )


def check_original_service():
    try:
        response = request("D1")
    except requests.exceptions.ConnectionError:
        raise AssertionError("The service is not running on 127.0.0.1:8080")
    assert response.status_code == 401, (
        f"Expected 401 Unauthorized without token, got {response.status_code}"
    )

    response = request("D1", "WrongToken!")
    assert response.status_code == 401, (
        f"Expected 401 Unauthorized with wrong token, got {response.status_code}"
    )

    expected = [
        {"emp_id": "E1", "team_volume": 1550.0},
        {"emp_id": "E2", "team_volume": 900.0},
        {"emp_id": "E3", "team_volume": 650.0},
    ]
    assert_response(request("D1", "SuperSecret123!"), "D1", expected)


def rust_project_exists():
    manifest = PROJECT / "Cargo.toml"
    assert manifest.is_file(), "Missing /home/user/app-service/Cargo.toml"
    rust_sources = list((PROJECT / "src").rglob("*.rs"))
    assert rust_sources, "No Rust source files found under /home/user/app-service/src"
    assert any(path.stat().st_size > 0 for path in rust_sources), "Rust source files are empty"


def kill_port_8080():
    target_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if int(local.rsplit(":", 1)[1], 16) == 8080 and state == "0A":
                target_inodes.add(fields[9])

    victims = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    link = os.readlink(fd)
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in target_inodes:
                    victims.add(int(proc.name))
                    break
        except OSError:
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(1)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def make_id():
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "X" + "".join(secrets.choice(alphabet) for _ in range(9))


def install_dynamic_inputs():
    ids = {role: make_id() for role in "ABCDEFGH"}
    while len(set(ids.values())) != len(ids):
        ids = {role: make_id() for role in "ABCDEFGH"}

    dept_one = "DEPT-" + secrets.token_hex(5).upper()
    dept_two = "DEPT-" + secrets.token_hex(5).upper()
    token = "TOK" + "".join(secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(25))
    threshold = float(random.SystemRandom().randint(121, 389))

    managers = {
        "A": "",
        "B": "A",
        "C": "A",
        "D": "B",
        "E": "B",
        "F": "C",
        "G": "C",
        "H": "E",
    }
    departments = {
        "A": dept_one,
        "B": dept_one,
        "C": dept_one,
        "D": dept_one,
        "E": dept_two,
        "F": dept_one,
        "G": dept_two,
        "H": dept_two,
    }

    employee_rows = []
    for role in "ABCDEFGH":
        employee_rows.append({
            "emp_id": ids[role],
            "manager_id": ids[managers[role]] if managers[role] else "",
            "dept_id": departments[role],
            "name": "Employee-" + secrets.token_hex(3),
        })

    # B and C have equal recursively aggregated volume despite different subtree
    # shapes. E and G also tie, exercising emp_id ascending tie-breaking.
    amounts = {
        "A": threshold + 25.25,
        "B": threshold + 20.25,
        "C": threshold + 20.25,
        "D": threshold + 30.25,
        "E": threshold + 40.25,
        "F": threshold + 30.25,
        "G": 2 * threshold + 50.50,
        "H": threshold + 10.25,
    }
    transaction_rows = []
    for role in "ABCDEFGH":
        transaction_rows.append({
            "tx_id": "TX-" + secrets.token_hex(5),
            "emp_id": ids[role],
            "amount": f"{amounts[role]:.2f}",
            "timestamp": "2026-01-01T00:00:00Z",
        })
    # These verify that the threshold comparison is strictly greater-than.
    transaction_rows.extend([
        {
            "tx_id": "TX-" + secrets.token_hex(5),
            "emp_id": ids["A"],
            "amount": f"{threshold:.2f}",
            "timestamp": "2026-01-02T00:00:00Z",
        },
        {
            "tx_id": "TX-" + secrets.token_hex(5),
            "emp_id": ids["H"],
            "amount": f"{threshold - 0.01:.2f}",
            "timestamp": "2026-01-02T00:00:00Z",
        },
    ])

    with open("/app/employees.csv", "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["emp_id", "manager_id", "dept_id", "name"])
        writer.writeheader()
        writer.writerows(employee_rows)
    with open("/app/transactions.csv", "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["tx_id", "emp_id", "amount", "timestamp"])
        writer.writeheader()
        writer.writerows(transaction_rows)

    image = Image.new("RGB", (1100, 230), "white")
    draw = ImageDraw.Draw(image)
    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
    font = ImageFont.truetype(font_path, 38) if Path(font_path).exists() else ImageFont.load_default()
    draw.text((25, 30), f"API_TOKEN={token}", fill="black", font=font)
    draw.text((25, 125), f"MIN_TX_THRESHOLD={threshold:.1f}", fill="black", font=font)
    image.save("/app/system_config.png")

    return token, threshold, dept_one, dept_two


def derive_expected(dept, threshold):
    with open("/app/employees.csv", newline="") as handle:
        employees = list(csv.DictReader(handle))
    with open("/app/transactions.csv", newline="") as handle:
        transactions = list(csv.DictReader(handle))

    children = {row["emp_id"]: [] for row in employees}
    for row in employees:
        manager = row["manager_id"]
        if manager in children:
            children[manager].append(row["emp_id"])

    own = {row["emp_id"]: 0.0 for row in employees}
    for tx in transactions:
        amount = float(tx["amount"])
        if amount > threshold and tx["emp_id"] in own:
            own[tx["emp_id"]] += amount

    def total(emp_id, path=None):
        path = set() if path is None else path
        assert emp_id not in path, "Generated employee graph unexpectedly contains a cycle"
        next_path = path | {emp_id}
        return own[emp_id] + sum(total(child, next_path) for child in children[emp_id])

    ranked = [
        {"emp_id": row["emp_id"], "team_volume": total(row["emp_id"])}
        for row in employees
        if row["dept_id"] == dept
    ]
    ranked.sort(key=lambda item: (-item["team_volume"], item["emp_id"]))
    return ranked[:3]


def wait_for_service(process):
    deadline = time.time() + 120
    last_error = None
    while time.time() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"cargo run exited with status {process.returncode}")
        try:
            requests.get(BASE_URL + ENDPOINT, params={"dept_id": "probe"}, timeout=1)
            return
        except requests.RequestException as exc:
            last_error = exc
            time.sleep(0.5)
    raise AssertionError(f"Rust service did not start within 120 seconds: {last_error}")


def check_dynamic_service():
    token, threshold, dept_one, dept_two = install_dynamic_inputs()
    kill_port_8080()

    log = open("/tmp/app-service-verifier.log", "w")
    process = subprocess.Popen(
        ["cargo", "run", "--offline", "--quiet"],
        cwd=str(PROJECT),
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        wait_for_service(process)

        assert request(dept_one).status_code == 401
        assert request(dept_one, "incorrect-" + token).status_code == 401
        response = requests.get(
            BASE_URL + ENDPOINT,
            params={"dept_id": dept_one},
            headers={"Authorization": f"bearer {token}"},
            timeout=5,
        )
        assert response.status_code == 401, "Authentication scheme must strictly be 'Bearer'"

        assert_response(request(dept_one, token), dept_one, derive_expected(dept_one, threshold))
        assert_response(request(dept_two, token), dept_two, derive_expected(dept_two, threshold))
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
        log.close()


def main():
    check_original_service()
    rust_project_exists()
    check_dynamic_service()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
