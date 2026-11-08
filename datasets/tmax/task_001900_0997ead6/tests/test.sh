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
set -u
mkdir -p /logs/verifier
rm -f /tmp/verifier_legacy_pricer /tmp/pricer_invocations /tmp/verifier_gpp.log

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import signal
import smtplib
import socket
import subprocess
import time
import secrets
import shlex

import requests

PORTS = (8080, 2525)
PRICER_BACKUP = "/tmp/verifier_legacy_pricer"
PRICER_LOG = "/tmp/pricer_invocations"


def listening_inodes(ports):
    wanted = {f"{p:04X}" for p in ports}
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        if fields[1].rsplit(":", 1)[1].upper() in wanted:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def pids_for_inodes(inodes):
    result = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return result


def stop_existing_listeners():
    for pid in pids_for_inodes(listening_inodes(PORTS)):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listening_inodes(PORTS):
        time.sleep(0.05)
    for pid in pids_for_inodes(listening_inodes(PORTS)):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def listener_pids(port):
    return pids_for_inodes(listening_inodes((port,)))


def clear_directory(path):
    os.makedirs(path, exist_ok=True)
    for name in os.listdir(path):
        item = os.path.join(path, name)
        if os.path.isdir(item) and not os.path.islink(item):
            shutil.rmtree(item)
        else:
            os.unlink(item)


def original_price(size):
    result = subprocess.run(
        [PRICER_BACKUP, str(size)], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def install_pricer_probe():
    assert os.path.isfile("/app/legacy_pricer")
    shutil.copy2("/app/legacy_pricer", PRICER_BACKUP)
    os.chmod(PRICER_BACKUP, 0o755)
    with open(PRICER_LOG, "w"):
        pass
    os.chmod(PRICER_LOG, 0o666)
    with open("/app/legacy_pricer", "w") as f:
        f.write("#!/bin/sh\n")
        f.write(f"printf '%s\\n' \"$1\" >> {shlex.quote(PRICER_LOG)}\n")
        f.write(f"exec {shlex.quote(PRICER_BACKUP)} \"$@\"\n")
    os.chmod("/app/legacy_pricer", 0o755)


def test_01_deploy_and_services():
    assert os.path.isfile("/app/deploy.sh"), "/app/deploy.sh does not exist"
    assert os.path.isfile("/app/finops_service.cpp"), "/app/finops_service.cpp does not exist"

    stop_existing_listeners()
    try:
        os.unlink("/app/finops_service")
    except FileNotFoundError:
        pass

    # Interpose the real g++ so deploy.sh must actually invoke it. The wrapper
    # delegates to the original compiler and records its arguments.
    gpp = "/usr/bin/g++"
    backup = "/tmp/verifier_gpp_original"
    log = "/tmp/verifier_gpp.log"
    try:
        os.unlink(backup)
    except FileNotFoundError:
        pass
    real_target = os.path.realpath(gpp)
    os.rename(gpp, backup)
    compiler = real_target if real_target != gpp else backup
    try:
        with open(gpp, "w") as f:
            f.write("#!/bin/sh\n")
            f.write(f"printf '%s ' \"$@\" >> {shlex.quote(log)}\n")
            f.write(f"printf '\\n' >> {shlex.quote(log)}\n")
            f.write(f"exec {shlex.quote(compiler)} \"$@\"\n")
        os.chmod(gpp, 0o755)
        result = subprocess.run(
            ["bash", "/app/deploy.sh"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            timeout=45,
        )
    finally:
        try:
            os.unlink(gpp)
        except FileNotFoundError:
            pass
        os.rename(backup, gpp)

    assert result.returncode == 0, (
        f"deploy.sh failed with exit code {result.returncode}\nSTDERR: {result.stderr}"
    )
    assert os.path.isfile(log), "deploy.sh did not invoke g++"
    with open(log) as f:
        compile_args = f.read()
    assert "finops_service.cpp" in compile_args, (
        f"g++ did not compile finops_service.cpp; invocations: {compile_args!r}"
    )

    assert os.path.isfile("/app/finops_service"), "deploy.sh did not create /app/finops_service"
    with open("/app/finops_service", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/app/finops_service is not a compiled ELF executable"

    deadline = time.time() + 5
    while time.time() < deadline:
        if all(listener_pids(p) for p in PORTS):
            break
        time.sleep(0.1)

    for port in PORTS:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            assert s.connect_ex(("127.0.0.1", port)) == 0, f"Service is not listening on port {port}"
        owners = listener_pids(port)
        assert owners, f"Could not identify listener process for port {port}"
        owner_exes = []
        for pid in owners:
            try:
                owner_exes.append(os.readlink(f"/proc/{pid}/exe").replace(" (deleted)", ""))
            except OSError:
                pass
        assert "/app/finops_service" in owner_exes, (
            f"Port {port} is not owned by the compiled /app/finops_service; owners: {owner_exes}"
        )

    install_pricer_probe()


def test_02_fstab_optimized():
    fstab_path = "/app/fstab.optimized"
    assert os.path.isfile(fstab_path), f"{fstab_path} is missing"
    with open(fstab_path) as f:
        content = f.read().strip()
    pattern = r"^/dev/sdb1\s+/mnt/cold_archive\s+ext4\s+noatime,nodiratime,ro\s+0\s+2$"
    assert re.search(pattern, content, re.MULTILINE), (
        f"fstab.optimized content does not match expected format. Got: {content}"
    )


def test_03_symlinks():
    links = {
        "bucket_alpha": "/app/raw_data/us-east-1",
        "bucket_beta": "/app/raw_data/eu-west-1",
        "bucket_gamma": "/app/raw_data/ap-south-1",
    }
    for link_name, target in links.items():
        link_path = os.path.join("/app/data_links", link_name)
        assert os.path.islink(link_path), f"{link_path} is not a symlink"
        assert os.readlink(link_path) == target, (
            f"Symlink {link_path} points to {os.readlink(link_path)}, expected {target}"
        )


def test_04_http_unauthorized():
    url = "http://127.0.0.1:8080/cost?bucket=bucket_alpha"
    response = requests.get(url, timeout=5)
    assert response.status_code == 401, (
        f"Expected HTTP 401 for unauthenticated request, got {response.status_code}"
    )
    for bad in ("finops_secret_2024", "Bearer wrong_secret", "Bearer finops_secret_2024_extra"):
        response = requests.get(url, headers={"Authorization": bad}, timeout=5)
        assert response.status_code == 401, f"Invalid Authorization value {bad!r} was accepted"


def test_05_http_authorized_cost():
    target_dir = "/app/raw_data/us-east-1"
    clear_directory(target_dir)
    with open(os.path.join(target_dir, "test.dat"), "wb") as f:
        f.write(b"A" * 1500)

    with open(PRICER_LOG, "w"):
        pass
    url = "http://127.0.0.1:8080/cost?bucket=bucket_alpha"
    headers = {"Authorization": "Bearer finops_secret_2024"}
    response = requests.get(url, headers=headers, timeout=5)
    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Body: {response.text}"
    )

    # Confirm the running service invoked the required pricer before the verifier
    # itself calls that path for the original expected-value assertion.
    with open(PRICER_LOG) as f:
        service_calls = f.read().splitlines()
    assert "1500" in service_calls, (
        f"The service did not invoke /app/legacy_pricer with measured size 1500; calls: {service_calls}"
    )

    pricer_result = subprocess.run(
        ["/app/legacy_pricer", "1500"], capture_output=True, text=True, timeout=5
    )
    expected_cost_val = pricer_result.stdout.strip()
    expected_body = f"Cost: ${expected_cost_val}"
    assert expected_body in response.text or "60" in response.text, (
        f"Expected body to contain {expected_body}, got {response.text}"
    )
    assert response.text == expected_body, (
        f"Expected exact body {expected_body!r}, got {response.text!r}"
    )


def test_06_http_randomized_all_buckets():
    bucket_dirs = {
        "bucket_alpha": "/app/raw_data/us-east-1",
        "bucket_beta": "/app/raw_data/eu-west-1",
        "bucket_gamma": "/app/raw_data/ap-south-1",
    }
    sizes = {
        "bucket_alpha": 1 + secrets.randbelow(900),
        "bucket_beta": 1001 + secrets.randbelow(3000),
        "bucket_gamma": 5000 + secrets.randbelow(7000),
    }
    headers = {"Authorization": "Bearer finops_secret_2024"}

    for bucket, target_dir in bucket_dirs.items():
        clear_directory(target_dir)
        size = sizes[bucket]
        with open(os.path.join(target_dir, secrets.token_hex(6) + ".dat"), "wb") as f:
            f.write(os.urandom(size))

        with open(PRICER_LOG, "w"):
            pass
        response = requests.get(
            f"http://127.0.0.1:8080/cost?bucket={bucket}", headers=headers, timeout=5
        )
        expected = f"Cost: ${original_price(size)}"
        assert response.status_code == 200, f"{bucket}: HTTP {response.status_code}: {response.text}"
        assert response.text == expected, f"{bucket}: expected {expected!r}, got {response.text!r}"
        with open(PRICER_LOG) as f:
            calls = f.read().splitlines()
        assert str(size) in calls, (
            f"{bucket}: service did not invoke /app/legacy_pricer with measured size {size}; calls: {calls}"
        )

    # Change a previously queried bucket to ensure results are measured per request.
    new_size = 1200 + secrets.randbelow(5000)
    clear_directory(bucket_dirs["bucket_alpha"])
    with open(os.path.join(bucket_dirs["bucket_alpha"], "changed.dat"), "wb") as f:
        f.write(os.urandom(new_size))
    with open(PRICER_LOG, "w"):
        pass
    response = requests.get(
        "http://127.0.0.1:8080/cost?bucket=bucket_alpha", headers=headers, timeout=5
    )
    assert response.status_code == 200
    assert response.text == f"Cost: ${original_price(new_size)}"
    with open(PRICER_LOG) as f:
        calls = f.read().splitlines()
    assert str(new_size) in calls


def test_07_smtp_alert():
    log_path = "/app/alerts.log"
    try:
        os.unlink(log_path)
    except FileNotFoundError:
        pass

    sender = "admin@example.com"
    receiver = "finops@example.com"
    subject = "URGENT ALERT OVER BUDGET"
    message = f"Subject: {subject}\r\n\r\nThis is a test message."
    try:
        with smtplib.SMTP("127.0.0.1", 2525, timeout=5) as server:
            server.sendmail(sender, receiver, message)
    except Exception as e:
        assert False, f"Failed to send SMTP message: {e}"

    time.sleep(0.5)
    assert os.path.isfile(log_path), f"Alerts log {log_path} was not created"
    with open(log_path) as f:
        content = f.read()
    assert subject in content, (
        f"Expected subject '{subject}' not found in {log_path}. Content: {content}"
    )

    token = secrets.token_hex(10)
    random_alert = f"ALERT storage anomaly {token}"
    normal_subject = f"routine report {secrets.token_hex(10)}"
    with smtplib.SMTP("127.0.0.1", 2525, timeout=5) as server:
        server.sendmail(sender, receiver, f"Subject: {normal_subject}\r\n\r\nnormal")
    with smtplib.SMTP("127.0.0.1", 2525, timeout=5) as server:
        server.sendmail(sender, receiver, f"Subject: {random_alert}\r\n\r\nanomaly")
    time.sleep(0.5)
    with open(log_path) as f:
        content = f.read()
    assert random_alert in content, f"Random ALERT subject was not logged: {content}"
    assert normal_subject not in content, f"Non-ALERT subject was incorrectly logged: {content}"
TEST_EOF

status=0
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=$?

if [ -f /tmp/verifier_legacy_pricer ]; then
    cp -p /tmp/verifier_legacy_pricer /app/legacy_pricer
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
