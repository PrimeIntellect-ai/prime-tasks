#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import secrets
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request

import pytest

DEPLOY = "/home/user/edge_deploy"
FRAMES = "/home/user/frames"
EXTRACT = os.path.join(DEPLOY, "extract.sh")
SANITIZER = os.path.join(DEPLOY, "sanitizer.py")
LB_CONF = os.path.join(DEPLOY, "lb.conf")


def run_as_user(command, **kwargs):
    account = pwd.getpwnam("user")

    def demote():
        os.initgroups(account.pw_name, account.pw_gid)
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    env = {
        "HOME": account.pw_dir,
        "USER": account.pw_name,
        "LOGNAME": account.pw_name,
        "SHELL": account.pw_shell,
        "PATH": "/usr/bin:/bin",
    }
    return subprocess.run(command, preexec_fn=demote, env=env, **kwargs)


def decoded_thumbnail(path):
    result = subprocess.run(
        ["/usr/bin/ffmpeg", "-v", "error", "-i", path,
         "-vf", "scale=64:64", "-frames:v", "1", "-f", "rawvideo",
         "-pix_fmt", "rgb24", "-"],
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Not a decodable image: {path}: {result.stderr.decode(errors='replace')}"
    assert len(result.stdout) == 64 * 64 * 3, f"Unexpected decoded image size for {path}"
    return result.stdout


def test_frames_extracted():
    """Execute the extractor in a cron-like environment and validate its output."""
    assert os.path.isfile(EXTRACT), f"Extractor script is missing at {EXTRACT}."
    assert os.access(EXTRACT, os.X_OK), f"Extractor script is not executable: {EXTRACT}."
    assert os.path.isdir(FRAMES), f"Frames directory {FRAMES}/ does not exist."

    cron = subprocess.run(["crontab", "-u", "user", "-l"], capture_output=True, text=True)
    assert cron.returncode == 0, "The user crontab is missing."
    active_lines = [line.strip() for line in cron.stdout.splitlines()
                    if line.strip() and not line.lstrip().startswith("#")]
    assert any(EXTRACT in line for line in active_lines), "The user crontab does not schedule extract.sh."

    reference_dir = tempfile.mkdtemp(prefix="expected-frames-")
    try:
        reference_pattern = os.path.join(reference_dir, "frame_%06d.jpg")
        reference = subprocess.run(
            ["/usr/bin/ffmpeg", "-v", "error", "-i", "/app/video.mp4",
             "-vf", "fps=1", "-q:v", "2", reference_pattern],
            capture_output=True,
            timeout=30,
        )
        assert reference.returncode == 0, reference.stderr.decode(errors="replace")
        expected = sorted(os.path.join(reference_dir, f) for f in os.listdir(reference_dir)
                          if f.lower().endswith(".jpg"))
        assert expected, "Reference extraction unexpectedly produced no frames."

        for name in os.listdir(FRAMES):
            if name.lower().endswith(".jpg"):
                path = os.path.join(FRAMES, name)
                if os.path.isfile(path) or os.path.islink(path):
                    os.unlink(path)

        result = run_as_user(
            [EXTRACT], cwd="/tmp", capture_output=True, timeout=45
        )
        assert result.returncode == 0, (
            f"extract.sh failed in a cron-like environment: "
            f"{result.stderr.decode(errors='replace')}"
        )

        jpg_names = [f for f in os.listdir(FRAMES) if f.endswith(".jpg")]
        assert len(jpg_names) == len(expected), (
            f"Expected exactly {len(expected)} .jpg files in {FRAMES}/, found {len(jpg_names)}."
        )
        actual = sorted(os.path.join(FRAMES, f) for f in jpg_names)

        for produced, wanted in zip(actual, expected):
            got_pixels = decoded_thumbnail(produced)
            expected_pixels = decoded_thumbnail(wanted)
            mean_error = sum(abs(a - b) for a, b in zip(got_pixels, expected_pixels)) / len(got_pixels)
            assert mean_error < 18.0, (
                f"{produced} does not correspond to the expected frame (mean pixel error {mean_error:.2f})."
            )
    finally:
        shutil.rmtree(reference_dir, ignore_errors=True)


def invoke_sanitizer(path):
    return subprocess.run(["python3", SANITIZER, path], capture_output=True, timeout=10)


def test_sanitizer_corpus():
    """Verify the sanitizer against both the supplied and generated adversarial cases."""
    assert os.path.isfile(SANITIZER), f"Sanitizer script is missing at {SANITIZER}."
    clean_dir = "/app/corpus/clean/"
    evil_dir = "/app/corpus/evil/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} is missing."
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} is missing."

    clean_failed = []
    evil_failed = []
    for name in os.listdir(clean_dir):
        result = invoke_sanitizer(os.path.join(clean_dir, name))
        if result.returncode != 0:
            clean_failed.append(name)
        assert result.stdout == b"", f"Sanitizer wrote to stdout for clean corpus file {name}."
    for name in os.listdir(evil_dir):
        result = invoke_sanitizer(os.path.join(evil_dir, name))
        if result.returncode == 0:
            evil_failed.append(name)
        assert result.returncode == 1, f"Sanitizer must exit 1 for evil corpus file {name}."
        assert result.stdout == b"", f"Sanitizer wrote to stdout for evil corpus file {name}."

    errors = []
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(os.listdir(evil_dir))} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(os.listdir(clean_dir))} clean rejected: {', '.join(clean_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))

    token = secrets.token_hex(12)
    clean_objects = [
        {"sensor_id": "CAM-" + token, "timestamp": secrets.randbelow(10**12), "status": "OK"},
        {"status": "OK", "timestamp": -secrets.randbelow(100000), "sensor_id": "CAM-Ω-" + token},
    ]
    evil_payloads = [
        json.dumps({"sensor_id": "CAM-" + token, "timestamp": 1, "status": "OK", token: 1}),
        json.dumps({"sensor_id": "cam-" + token, "timestamp": 1, "status": "OK"}),
        json.dumps({"sensor_id": "CAM-" + token, "timestamp": True, "status": "OK"}),
        json.dumps({"sensor_id": "CAM-" + token, "timestamp": 1.5, "status": "OK"}),
        json.dumps({"sensor_id": "CAM-" + token, "timestamp": 1, "status": "ok"}),
        json.dumps({"sensor_id": "CAM-" + token, "timestamp": 1}),
        json.dumps([{"sensor_id": "CAM-" + token, "timestamp": 1, "status": "OK"}]),
        "{\"sensor_id\": \"CAM-" + token + "\",",
        "null",
    ]

    with tempfile.TemporaryDirectory(prefix="sanitizer-cases-") as case_dir:
        for index, obj in enumerate(clean_objects):
            path = os.path.join(case_dir, f"random-clean-{token}-{index}.dat")
            with open(path, "w", encoding="utf-8") as stream:
                json.dump(obj, stream, ensure_ascii=False, indent=2)
            result = invoke_sanitizer(path)
            assert result.returncode == 0, f"Generated valid telemetry was rejected: {index}"
            assert result.stdout == b"", "Sanitizer must not write valid telemetry to stdout."

        for index, payload in enumerate(evil_payloads):
            path = os.path.join(case_dir, f"random-evil-{token}-{index}.dat")
            with open(path, "w", encoding="utf-8") as stream:
                stream.write(payload)
            result = invoke_sanitizer(path)
            assert result.returncode == 1, f"Generated evil telemetry bypassed sanitizer: {index}"
            assert result.stdout == b"", "Sanitizer must not write evil telemetry to stdout."


def listener_pids(port):
    wanted = f"{port:04X}"
    inodes = set()
    with open("/proc/net/tcp", encoding="ascii") as stream:
        next(stream)
        for line in stream:
            fields = line.split()
            address, state, inode = fields[1], fields[3], fields[9]
            host, found_port = address.split(":")
            if host == "0100007F" and found_port == wanted and state == "0A":
                inodes.add(inode)
    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(entry))
        except OSError:
            continue
    return pids


def process_uid(pid):
    with open(f"/proc/{pid}/status", encoding="utf-8") as stream:
        for line in stream:
            if line.startswith("Uid:"):
                return int(line.split()[1])
    raise AssertionError(f"Could not determine uid for pid {pid}")


def process_name(pid):
    return os.path.basename(os.readlink(f"/proc/{pid}/exe"))


def fetch(url, timeout=5):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        assert response.status == 200, f"Expected HTTP 200 from {url}, got {response.status}."
        return response.read()


def test_load_balancer():
    """Verify both backends, the active proxy configuration, and proxy routing."""
    assert os.path.isfile(LB_CONF), f"Load-balancer configuration is missing at {LB_CONF}."
    user_uid = pwd.getpwnam("user").pw_uid

    listeners = {}
    for port in (9001, 9002, 8080):
        pids = listener_pids(port)
        assert pids, f"No process is listening on 127.0.0.1:{port}."
        assert all(process_uid(pid) == user_uid for pid in pids), (
            f"The service on port {port} is not running as the standard user."
        )
        listeners[port] = pids

    lb_names = {process_name(pid) for pid in listeners[8080]}
    assert lb_names & {"haproxy", "nginx"}, (
        f"Port 8080 is not served by haproxy or nginx (found {sorted(lb_names)})."
    )
    proxy_kind = "haproxy" if "haproxy" in lb_names else "nginx"

    active_conf = False
    for pid_entry in os.listdir("/proc"):
        if not pid_entry.isdigit():
            continue
        try:
            if process_uid(int(pid_entry)) != user_uid:
                continue
            cmdline = open(f"/proc/{pid_entry}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
            if LB_CONF in cmdline and process_name(int(pid_entry)) in {"haproxy", "nginx"}:
                active_conf = True
                break
        except (OSError, ProcessLookupError):
            continue
    assert active_conf, "The running proxy was not started with /home/user/edge_deploy/lb.conf."

    with open(LB_CONF, encoding="utf-8", errors="replace") as stream:
        config = stream.read()
    uncommented = "\n".join(line.split("#", 1)[0] for line in config.splitlines())
    assert re.search(r"127\.0\.0\.1\s*:\s*9001", uncommented), "lb.conf does not configure backend 9001."
    assert re.search(r"127\.0\.0\.1\s*:\s*9002", uncommented), "lb.conf does not configure backend 9002."
    assert re.search(r"(?:127\.0\.0\.1\s*)?:\s*8080|127\.0\.0\.1\s+8080", uncommented), (
        "lb.conf does not configure the port 8080 listener."
    )
    if proxy_kind == "haproxy":
        validation = subprocess.run(["haproxy", "-c", "-f", LB_CONF], capture_output=True, timeout=10)
        assert validation.returncode == 0, "Invalid HAProxy configuration."
        balance_modes = re.findall(r"(?im)^\s*balance\s+(\S+)", uncommented)
        assert all(mode.lower() == "roundrobin" for mode in balance_modes), "HAProxy is not using round-robin balancing."
    else:
        assert re.search(r"\bproxy_pass\b", uncommented), "nginx configuration has no proxy_pass."
        assert not re.search(r"(?m)^\s*(?:ip_hash|least_conn|hash|random)\b", uncommented), (
            "nginx upstream is configured with a non-round-robin method."
        )

    marker_name = f"backend-check-{secrets.token_hex(10)}.txt"
    marker_data = secrets.token_bytes(64)
    marker_path = os.path.join(FRAMES, marker_name)
    with open(marker_path, "wb") as stream:
        stream.write(marker_data)
    os.chmod(marker_path, 0o644)
    try:
        assert fetch(f"http://127.0.0.1:9001/{marker_name}") == marker_data
        assert fetch(f"http://127.0.0.1:9002/{marker_name}") == marker_data
        for _ in range(8):
            assert fetch(f"http://127.0.0.1:8080/{marker_name}") == marker_data

        content = fetch("http://127.0.0.1:8080/frame_1.jpg")
        assert len(content) > 0, "The response content is empty."
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to fetch through a required service: {exc}")
    finally:
        try:
            os.unlink(marker_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
