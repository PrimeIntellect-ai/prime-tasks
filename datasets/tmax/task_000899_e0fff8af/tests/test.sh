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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import subprocess

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"

# Incident records reconstructed from the supplied monitor recording. Expected
# graph analytics are derived below, including removal of the duplicate D -> B
# ghost dependency.
INCIDENT_RECORDS = [
    ("A", "NONE", 100),
    ("B", "A", 200),
    ("C", "A", 150),
    ("D", "B", 300),
    ("D", "C", 300),
    ("D", "B", 300),
    ("E", "D", 500),
]

EXPECTED = {}
for job_id, parent, size in INCIDENT_RECORDS:
    if job_id not in EXPECTED:
        EXPECTED[job_id] = {"id": job_id, "depends_on": [], "size": size}
    assert EXPECTED[job_id]["size"] == size
    if parent != "NONE" and parent not in EXPECTED[job_id]["depends_on"]:
        EXPECTED[job_id]["depends_on"].append(parent)

scores = {job_id: 0 for job_id in EXPECTED}
for job in EXPECTED.values():
    for parent in job["depends_on"]:
        scores[parent] += 1
for job_id, job in EXPECTED.items():
    job["criticality_score"] = scores[job_id]

EXPECTED_TOTAL_SIZE = sum(job["size"] for job in EXPECTED.values())
EXPECTED_TOTAL_DEPENDENCIES = sum(len(job["depends_on"]) for job in EXPECTED.values())


def get_json(path):
    try:
        resp = requests.get(f"{BASE_URL}{path}", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the C++ HTTP service at {BASE_URL}: {e}")
    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}"
    try:
        return resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")


def listener_pids():
    inodes = set()
    with open("/proc/net/tcp", encoding="ascii") as f:
        next(f)
        for line in f:
            fields = line.split()
            # 127.0.0.1:8080 in /proc/net/tcp notation, in LISTEN state.
            if fields[1].upper() == "0100007F:1F90" and fields[3] == "0A":
                inodes.add(fields[9])

    owners = set()
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[1])
        for fd in glob.glob(f"{procdir}/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                owners.add(pid)
                break
    return owners


def test_cpp_service_artifact():
    pids = listener_pids()
    assert pids, "No process is listening specifically on 127.0.0.1:8080"

    # The listening service must be a compiled C++ ELF executable, not a Python,
    # shell, or other interpreted server returning hard-coded JSON.
    for pid in pids:
        exe = f"/proc/{pid}/exe"
        try:
            with open(exe, "rb") as f:
                assert f.read(4) == b"\x7fELF", f"Listener PID {pid} is not an ELF executable"
        except OSError as e:
            pytest.fail(f"Cannot inspect listener PID {pid}: {e}")

        result = subprocess.run(
            ["ldd", exe], text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=5, check=False
        )
        assert "libstdc++.so" in result.stdout, (
            f"Listener PID {pid} is not linked as a C++ service; ldd output: {result.stdout}"
        )


def test_api_summary():
    data = get_json("/api/summary")

    assert "total_size" in data, "Missing 'total_size' in /api/summary response"
    assert "total_dependencies" in data, "Missing 'total_dependencies' in /api/summary response"

    assert data["total_size"] == 1250, f"Expected total_size to be 1250, got {data['total_size']}"
    assert data["total_dependencies"] == 5, f"Expected total_dependencies to be 5, got {data['total_dependencies']}"
    assert data["total_size"] == EXPECTED_TOTAL_SIZE
    assert data["total_dependencies"] == EXPECTED_TOTAL_DEPENDENCIES


def test_api_critical():
    data = get_json("/api/critical")

    assert isinstance(data, list), f"Expected a JSON array, got {type(data)}"
    assert len(data) == 3, f"Expected exactly 3 critical backup IDs, got {len(data)}"

    # 'A' has the highest in-degree (2), so it must be in the top 3
    assert "A" in data, f"Expected 'A' to be in the top 3 critical backups, got {data}"

    assert all(isinstance(job_id, str) for job_id in data)
    assert len(set(data)) == 3, f"Critical backup IDs must be unique, got {data}"
    assert set(data).issubset(EXPECTED), f"Unknown critical backup ID returned: {data}"

    selected = set(data)
    omitted = set(EXPECTED) - selected
    assert all(scores[a] >= scores[b] for a in selected for b in omitted), (
        f"Returned IDs are not a valid top 3 by in-degree: {data}"
    )


def test_api_backups():
    data = get_json("/api/backups")

    assert isinstance(data, list), f"Expected a JSON array, got {type(data)}"
    assert len(data) == 5, f"Expected exactly 5 backup jobs, got {len(data)}"

    for job in data:
        assert "id" in job, f"Missing 'id' in job: {job}"
        assert isinstance(job["id"], str), f"'id' should be a string in job: {job}"

        assert "depends_on" in job, f"Missing 'depends_on' in job: {job}"
        assert isinstance(job["depends_on"], list), f"'depends_on' should be an array in job: {job}"

        assert "size" in job, f"Missing 'size' in job: {job}"
        assert isinstance(job["size"], (int, float)), f"'size' should be a number in job: {job}"

        assert "criticality_score" in job, f"Missing 'criticality_score' in job: {job}"
        assert isinstance(job["criticality_score"], (int, float)), f"'criticality_score' should be a number in job: {job}"

        assert set(job) == {"id", "depends_on", "size", "criticality_score"}, (
            f"Job does not match the required schema: {job}"
        )
        assert all(isinstance(parent, str) for parent in job["depends_on"]), job
        assert len(job["depends_on"]) == len(set(job["depends_on"])), (
            f"Duplicate ghost dependencies remain in job: {job}"
        )
        assert not isinstance(job["size"], bool), job
        assert not isinstance(job["criticality_score"], bool), job

    ids = [job["id"] for job in data]
    assert len(ids) == len(set(ids)), f"Backup IDs must be unique: {ids}"
    assert set(ids) == set(EXPECTED), f"Wrong backup job IDs: {ids}"

    actual = {job["id"]: job for job in data}
    for job_id, expected in EXPECTED.items():
        job = actual[job_id]
        assert set(job["depends_on"]) == set(expected["depends_on"]), (
            f"Wrong dependencies for {job_id}: {job['depends_on']}"
        )
        assert job["size"] == expected["size"], f"Wrong size for {job_id}: {job['size']}"
        assert job["criticality_score"] == expected["criticality_score"], (
            f"Wrong criticality score for {job_id}: {job['criticality_score']}"
        )


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-x", "--tb=short"]))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
