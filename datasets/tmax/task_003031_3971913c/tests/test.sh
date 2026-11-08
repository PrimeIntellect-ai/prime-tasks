#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import tempfile
import time

import requests


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def service_container(service):
    ids = run(
        "docker", "ps",
        "--filter", f"label=com.docker.compose.service={service}",
        "--format", "{{.ID}}",
    ).splitlines()
    assert ids, f"Docker Compose service {service} is not running."
    return ids[0]


def expected_count(path):
    with open(path, "rb") as f:
        return sum(b"GET /api/v1/data" in line for line in f)


def test_done_file():
    done_path = "/app/done.txt"
    assert os.path.isfile(done_path), f"{done_path} is missing."
    with open(done_path, "r") as f:
        content = f.read().strip()
    assert content == "SUCCESS", f"Expected 'SUCCESS' in {done_path}, got '{content}'."


def test_squashfuse_mount():
    output = run("findmnt", "-T", "/app/data", "-n", "-o", "TARGET,SOURCE,FSTYPE")
    fields = output.split()
    assert len(fields) >= 3, f"Could not parse mount information: {output!r}"
    target, source, fstype = fields[0], fields[1], fields[2]
    assert os.path.realpath(target) == "/app/data", f"/app/data is not a mount point: {output}"
    assert os.path.realpath(source) == "/app/backup.sqsh", f"Unexpected mount source: {source}"
    assert "squashfuse" in fstype.lower(), f"Expected a squashfuse filesystem, got {fstype}"
    assert os.path.isfile("/app/data/access.log"), "Mounted archive does not contain access.log."

    found_process = False
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode(errors="replace")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if exe.startswith("squashfuse") and "/app/backup.sqsh" in cmd and "/app/data" in cmd:
            found_process = True
            break
    assert found_process, "No real squashfuse process owns the documented image mount."


def test_fstab_entry():
    fstab_path = "/app/restore-env/fstab"
    assert os.path.isfile(fstab_path), f"{fstab_path} is missing."
    with open(fstab_path, "r") as f:
        content = f.read()
    expected_line = "/app/backup.sqsh /app/data squashfs defaults 0 0"
    assert expected_line in content, f"Expected fstab entry '{expected_line}' not found in {fstab_path}."


def test_compose_services_running():
    for service in ("nginx", "go-app", "ssh-bastion"):
        cid = service_container(service)
        running = run("docker", "inspect", "-f", "{{.State.Running}}", cid)
        assert running == "true", f"Compose service {service} is not running."


def test_nginx_and_go_performance():
    url = "http://127.0.0.1:8080/stats"
    expected = expected_count("/app/data/access.log")
    start = time.monotonic()
    try:
        response = requests.get(url, timeout=2.0)
        elapsed = time.monotonic() - start
    except requests.RequestException as exc:
        assert False, f"Request to {url} failed: {exc}"

    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text[:100]}"
    )
    try:
        body = response.json()
    except ValueError as exc:
        assert False, f"/stats did not return valid JSON: {exc}; body={response.text[:100]!r}"
    assert isinstance(body, dict) and body.get("count") == expected, (
        f"Expected /stats count {expected}, got {body!r}."
    )
    assert elapsed <= 0.250, (
        f"Latency threshold failed: {elapsed:.3f}s > 0.250s. "
        "The Go application needs further optimization."
    )


def test_compiled_app_on_derived_input():
    # Run the submitted go-app image against a verifier-generated log so a
    # constant response cannot pass merely because the restored image has 10,000 matches.
    go_cid = service_container("go-app")
    image = run("docker", "inspect", "-f", "{{.Image}}", go_cid)
    wanted = random.SystemRandom().randint(31, 97)
    container = None

    with tempfile.TemporaryDirectory(prefix="verifier-log-") as data_dir:
        log_path = os.path.join(data_dir, "access.log")
        with open(log_path, "w") as f:
            for i in range(wanted):
                f.write(f'10.0.0.{i % 255} - - [test] "GET /api/v1/data HTTP/1.1" 200 1\n')
            for i in range(23):
                f.write(f'10.1.0.{i} - - [test] "POST /api/v1/data HTTP/1.1" 200 1\n')
                f.write(f'10.2.0.{i} - - [test] "GET /api/v1/other HTTP/1.1" 200 1\n')

        try:
            container = run(
                "docker", "run", "-d", "--rm",
                "-p", "127.0.0.1::9090",
                "-v", f"{data_dir}:/app/data:ro",
                "--tmpfs", "/var/run/go-app",
                image,
            )
            mapping = run("docker", "port", container, "9090/tcp").splitlines()[0]
            port = int(mapping.rsplit(":", 1)[1])
            url = f"http://127.0.0.1:{port}/stats"

            response = None
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                try:
                    response = requests.get(url, timeout=1.0)
                    break
                except requests.RequestException:
                    time.sleep(0.1)
            assert response is not None, "Verifier-generated go-app container did not become reachable."
            assert response.status_code == 200, (
                f"Submitted go-app returned HTTP {response.status_code} on generated input."
            )
            try:
                body = response.json()
            except ValueError:
                assert False, f"Submitted go-app returned invalid JSON: {response.text[:100]!r}"
            assert body.get("count") == wanted, (
                f"Submitted go-app did not parse generated input: expected {wanted}, got {body!r}."
            )
        finally:
            if container:
                subprocess.run(
                    ["docker", "rm", "-f", container],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )


def socket_table():
    rows = []
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except FileNotFoundError:
            continue
        for line in lines:
            parts = line.split()
            local_port = int(parts[1].split(":")[1], 16)
            remote_port = int(parts[2].split(":")[1], 16)
            rows.append((local_port, remote_port, parts[3], parts[9]))
    return rows


def test_ssh_tunnel():
    rows = socket_table()
    listening_9090 = {inode for local, remote, state, inode in rows if local == 9090 and state == "0A"}
    established_2222 = {inode for local, remote, state, inode in rows if remote == 2222 and state == "01"}
    assert listening_9090, "Nothing is listening on local port 9090."

    valid_ssh = False
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode(errors="replace")
            owned = set()
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    link = os.readlink(f"/proc/{pid}/fd/{fd}")
                except OSError:
                    continue
                if link.startswith("socket:["):
                    owned.add(link[8:-1])
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue

        if (
            os.path.basename(exe) == "ssh"
            and "9090:go-app:9090" in cmd
            and "2222" in cmd
            and owned.intersection(listening_9090)
            and owned.intersection(established_2222)
        ):
            valid_ssh = True
            break
    assert valid_ssh, "Port 9090 is not owned by an active SSH forward through localhost:2222."

    url = "http://127.0.0.1:9090/stats"
    try:
        response = requests.get(url, timeout=2.0)
    except requests.RequestException as exc:
        assert False, f"SSH tunnel check failed. Could not reach {url}: {exc}"
    assert response.status_code == 200, (
        f"Expected HTTP 200 from the internal endpoint through SSH, got {response.status_code}."
    )
    try:
        body = response.json()
    except ValueError:
        assert False, f"Internal endpoint returned invalid JSON: {response.text[:100]!r}"
    expected = expected_count("/app/data/access.log")
    assert body.get("count") == expected, (
        f"SSH-forwarded go-app returned count {body.get('count')!r}; expected {expected}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
