#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_drift_tracker.py
import json
import os
import random
import signal
import subprocess
import time
from pathlib import Path

import requests
from PIL import Image, ImageDraw, ImageFont

URL = "http://127.0.0.1:8080/api/v1/drift"
HEADERS = {"Authorization": "Bearer devops-secret-token"}
BINARY = "/tmp/drift_tracker_submission"


def listening_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                inodes.add(fields[9])

    owners = set()
    if not inodes:
        return owners
    for proc_dir in Path("/proc").glob("[0-9]*"):
        try:
            for fd in (proc_dir / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(proc_dir.name))
        except OSError:
            continue
    return owners


def clear_port():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        for _ in range(20):
            pids = listening_pids()
            if not pids:
                return
            for pid in pids:
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
            time.sleep(0.1)
    assert not listening_pids(), "Could not clear port 8080"


def start_submission():
    proc = subprocess.Popen(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 12
    while time.time() < deadline:
        if proc.poll() is not None:
            raise AssertionError("Compiled Go submission exited before serving requests")
        if proc.pid in listening_pids():
            try:
                requests.get("http://127.0.0.1:8080/", timeout=0.5)
                return proc
            except requests.RequestException:
                pass
        time.sleep(0.15)
    stop_submission(proc)
    raise AssertionError("Compiled Go submission did not listen on 127.0.0.1:8080")


def stop_submission(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=2)
    clear_port()


def post(payload, headers=HEADERS):
    return requests.post(URL, json=payload, headers=headers, timeout=3)


def check_original_assertions():
    payload = {"hostname": "core-db-primary", "cores": 64, "memory_gb": 256, "storage": "NVMe"}
    response = requests.post(URL, json=payload, timeout=3)
    assert response.status_code == 401, f"Expected HTTP 401 for missing auth, got {response.status_code}"

    payload = {"hostname": "core-db-primary", "cores": 0, "memory_gb": 256, "storage": "NVMe"}
    response = post(payload)
    assert response.status_code == 400, f"Expected HTTP 400 for invalid payload, got {response.status_code}"
    data = response.json()
    assert data.get("status") == "invalid", f"Expected status 'invalid', got {data.get('status')}"

    payload = {"hostname": "core-db-primary", "cores": 64, "memory_gb": 256, "storage": "nvme"}
    response = post(payload)
    assert response.status_code == 200, f"Expected HTTP 200 for zero drift, got {response.status_code}"
    data = response.json()
    assert data.get("status") == "valid", f"Expected status 'valid', got {data.get('status')}"
    assert data.get("total_drift") == 0, f"Expected total_drift 0, got {data.get('total_drift')}"

    payload = {"hostname": "core-db-replica", "cores": 32, "memory_gb": 128, "storage": "SSD"}
    response = post(payload)
    assert response.status_code == 200, f"Expected HTTP 200 for calculated drift, got {response.status_code}"
    data = response.json()
    assert data.get("status") == "valid", f"Expected status 'valid', got {data.get('status')}"
    assert data.get("total_drift") == 217, f"Expected total_drift 217, got {data.get('total_drift')}"


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(current[-1] + 1, previous[j] + 1, previous[j - 1] + (ca != cb)))
        previous = current
    return previous[-1]


def write_random_baseline(rng):
    words = [
        "atlas", "cinder", "maple", "falcon", "harbor", "juniper", "kernel",
        "lunar", "matrix", "nebula", "opal", "quartz", "raven", "summit",
        "timber", "velvet", "willow", "zenith",
    ]
    hostname = "-".join(rng.sample(words, 3))
    cores = rng.randint(11, 119)
    memory = rng.randint(73, 731)
    storage = rng.choice(["NVMe", "SSD", "HDD"])

    image = Image.new("RGB", (1100, 500), color=(255, 255, 255))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 36)
    text = (
        "BASELINE CONFIGURATION\n"
        f"Hostname: {hostname}\n"
        f"Cores: {cores}\n"
        f"Memory: {memory}\n"
        f"Storage: {storage}"
    )
    draw.multiline_text((25, 25), text, fill=(0, 0, 0), font=font, spacing=14)
    image.save("/app/config_baseline.png")
    return hostname, cores, memory, storage


def check_randomized_baseline(baseline, rng):
    hostname, cores, memory, storage = baseline

    response = requests.post(
        URL,
        json={"hostname": hostname, "cores": cores, "memory_gb": memory, "storage": storage},
        headers={"Authorization": "Bearer wrong-token"},
        timeout=3,
    )
    assert response.status_code == 401, f"Expected HTTP 401 for incorrect auth, got {response.status_code}"

    for bad_cores, bad_memory in ((0, memory), (-rng.randint(1, 20), memory), (cores, 0), (cores, -rng.randint(1, 20))):
        response = post({"hostname": hostname, "cores": bad_cores, "memory_gb": bad_memory, "storage": storage})
        assert response.status_code == 400, f"Expected HTTP 400 for invalid resources, got {response.status_code}"
        assert response.json().get("status") == "invalid"

    cases = [(hostname, cores, memory, storage.swapcase())]
    alphabet = "acdefhkmnprstuvwx"
    other_storages = [value for value in ("NVMe", "SSD", "HDD", "SATA") if value.lower() != storage.lower()]
    for _ in range(16):
        submitted_host = "".join(rng.choice(alphabet) for _ in range(rng.randint(3, 24)))
        submitted_cores = rng.randint(1, 150)
        submitted_memory = rng.randint(1, 900)
        if rng.choice((True, False)):
            submitted_storage = storage.swapcase()
        else:
            submitted_storage = rng.choice(other_storages)
        cases.append((submitted_host, submitted_cores, submitted_memory, submitted_storage))

    for submitted_host, submitted_cores, submitted_memory, submitted_storage in cases:
        expected = (
            levenshtein(hostname, submitted_host)
            + abs(cores - submitted_cores)
            + abs(memory - submitted_memory)
            + (0 if storage.lower() == submitted_storage.lower() else 50)
        )
        response = post({
            "hostname": submitted_host,
            "cores": submitted_cores,
            "memory_gb": submitted_memory,
            "storage": submitted_storage,
        })
        assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
        data = response.json()
        assert data.get("status") == "valid", f"Expected status 'valid', got {data.get('status')}"
        assert isinstance(data.get("total_drift"), int) and not isinstance(data.get("total_drift"), bool)
        assert data.get("total_drift") == expected, (
            f"Expected total_drift {expected} for randomized payload, got {data.get('total_drift')}"
        )


def main():
    rng = random.SystemRandom()
    clear_port()

    proc = start_submission()
    try:
        check_original_assertions()
    finally:
        stop_submission(proc)

    baseline = write_random_baseline(rng)
    proc = start_submission()
    try:
        check_randomized_baseline(baseline, rng)
    finally:
        stop_submission(proc)


if __name__ == "__main__":
    main()
PY_EOF

status=1
if [ -f /home/user/drift_tracker.go ] && [ ! -L /home/user/drift_tracker.go ]; then
    timeout 30s go build -o /tmp/drift_tracker_submission /home/user/drift_tracker.go
    if [ $? -eq 0 ] && [ -x /tmp/drift_tracker_submission ]; then
        timeout 90s python3 /tmp/verify_drift_tracker.py
        status=$?
    fi
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
