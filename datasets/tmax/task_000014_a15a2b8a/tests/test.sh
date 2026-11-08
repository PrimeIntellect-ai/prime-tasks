#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import stat
import subprocess


def assert_regular_file(path):
    assert os.path.exists(path), f"{path} does not exist."
    assert stat.S_ISREG(os.lstat(path).st_mode), f"{path} must be a regular file."


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30, **kwargs)


def test_auth_exp_behavior():
    path = "/home/user/auth.exp"
    assert_regular_file(path)
    assert os.access(path, os.X_OK), f"Expect script {path} is not executable."

    result = run([path])
    output = result.stdout.strip()
    assert "TOKEN_99AABBCC" in output, f"auth.exp did not output the correct token. Output was: {output}"

    vault = "/app/legacy_vault"
    original = open(vault, "rb").read()
    original_mode = stat.S_IMODE(os.stat(vault).st_mode)
    token = "TOKEN_" + secrets.token_hex(12).upper()
    replacement = f'''#!/bin/bash
IFS= read -r -p "Username: " user
IFS= read -r -p "Migration Pin: " pin
IFS= read -r -p "Action: " action
if [ "$user" = "cloud_admin" ] && [ "$pin" = "8821" ] && [ "$action" = "GET_TOKEN" ]; then
    printf '%s\\n' '{token}'
else
    printf '%s\\n' 'AUTH_FAILED'
fi
'''.encode()

    try:
        with open(vault, "wb") as f:
            f.write(replacement)
        os.chmod(vault, 0o755)
        challenged = run([path])
        assert challenged.returncode == 0, f"auth.exp failed against the authentication CLI: {challenged.stderr}"
        assert challenged.stdout.strip() == token, (
            "auth.exp must interact with /app/legacy_vault and print only the returned token; "
            f"stdout was {challenged.stdout!r}."
        )
    finally:
        with open(vault, "wb") as f:
            f.write(original)
        os.chmod(vault, original_mode)


def test_fstab_staged_content():
    path = "/home/user/fstab.staged"
    assert_regular_file(path)

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]

    assert len(lines) == 1, f"Expected exactly 1 active line in {path}, found {len(lines)}."
    parts = lines[0].split()
    assert len(parts) == 6, f"Expected 6 fields in fstab line, found {len(parts)}."
    assert parts[0] == "10.0.5.50:/var/video_archive", f"Incorrect device/share: {parts[0]}"
    assert parts[1] == "/mnt/video_staged", f"Incorrect mount point: {parts[1]}"
    assert parts[2] == "nfs4", f"Incorrect filesystem type: {parts[2]}"

    opts = parts[3].split(",")
    expected_opts = ["rw", "soft", "intr", "noatime", "x-systemd.automount"]
    for opt in expected_opts:
        assert opt in opts, f"Missing mount option '{opt}' in {parts[3]}."
    assert len(opts) == len(expected_opts) and set(opts) == set(expected_opts), (
        f"Mount options must be exactly {','.join(expected_opts)}; found {parts[3]}."
    )
    assert parts[4] == "0", f"Incorrect dump value: {parts[4]}"
    assert parts[5] == "0", f"Incorrect pass value: {parts[5]}"


def test_optimize_stream_script_exists_and_runs():
    path = "/home/user/optimize_stream.sh"
    auth = "/home/user/auth.exp"
    output = "/home/user/migrated_stream.mp4"
    assert_regular_file(path)
    assert os.access(path, os.X_OK), f"Script {path} is not executable."

    with open(path, "r") as f:
        content = f.read()
    assert "AUTH_TOKEN" in content, "Variable AUTH_TOKEN not assigned in optimize_stream.sh."
    assignment = re.compile(
        r'(?m)^\s*AUTH_TOKEN\s*=\s*(?:["\']?\$\([^\n)]*/home/user/auth\.exp[^\n)]*\)["\']?|["\']?`[^\n`]*/home/user/auth\.exp[^\n`]*`["\']?)'
    )
    assert assignment.search(content), "AUTH_TOKEN must be assigned from executing /home/user/auth.exp."

    auth_original = open(auth, "rb").read()
    auth_mode = stat.S_IMODE(os.stat(auth).st_mode)
    marker = "/tmp/auth-called-" + secrets.token_hex(12)
    mock = f'''#!/bin/sh
printf called > '{marker}'
printf '%s\\n' 'TOKEN_{secrets.token_hex(10).upper()}'
'''.encode()

    try:
        with open(auth, "wb") as f:
            f.write(mock)
        os.chmod(auth, 0o755)
        if os.path.exists(output):
            os.remove(output)
        result = run(["runuser", "-u", "user", "--", path])
        assert result.returncode == 0, f"optimize_stream.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
        assert os.path.exists(marker), "optimize_stream.sh did not execute /home/user/auth.exp."
        assert_regular_file(output)
        assert os.path.getsize(output) > 0, f"Output video {output} is empty (0 bytes)."
    finally:
        with open(auth, "wb") as f:
            f.write(auth_original)
        os.chmod(auth, auth_mode)
        if os.path.exists(marker):
            os.remove(marker)


def video_info(path):
    probe = run([
        "ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
        "-show_entries", "stream=width,height,nb_read_frames,duration",
        "-of", "json", path
    ])
    assert probe.returncode == 0, f"ffprobe failed for {path}: {probe.stderr}"
    streams = json.loads(probe.stdout).get("streams", [])
    assert streams, f"No video stream found in {path}."
    stream = streams[0]

    packets = run([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "packet=size", "-of", "csv=p=0", path
    ])
    assert packets.returncode == 0, f"Could not inspect video packets in {path}: {packets.stderr}"
    payload = sum(int(line.strip().rstrip(",")) for line in packets.stdout.splitlines() if line.strip())
    return {
        "width": int(stream["width"]),
        "height": int(stream["height"]),
        "frames": int(stream["nb_read_frames"]),
        "duration": float(stream["duration"]),
        "payload": payload,
    }


def test_video_ssim_metric():
    source = "/app/traffic_cam.mp4"
    output = "/home/user/migrated_stream.mp4"
    assert_regular_file(output)
    assert os.path.getsize(output) > 0, f"Output video {output} is empty (0 bytes)."

    src = video_info(source)
    dst = video_info(output)
    assert dst["frames"] == src["frames"], "Optimized video must retain all source frames."
    assert abs(dst["duration"] - src["duration"]) <= 0.15, "Optimized video duration differs from the source."
    assert os.path.getsize(output) < os.path.getsize(source), "Optimized video must be smaller than the source."
    reduced_resolution = dst["width"] * dst["height"] < src["width"] * src["height"]
    reduced_video_payload = dst["payload"] < src["payload"]
    assert reduced_resolution or reduced_video_payload, (
        "The output must reduce resolution or encoded video payload/bitrate; copying or merely remuxing the source is not sufficient."
    )

    cmd = ["ffmpeg", "-i", source, "-i", output, "-lavfi", "ssim", "-f", "null", "-"]
    result = subprocess.run(cmd, stderr=subprocess.PIPE, text=True, timeout=30)
    match = re.search(r"All:([0-9.]+)", result.stderr)
    assert match is not None, "Could not parse SSIM metric from ffmpeg output."
    ssim_val = float(match.group(1))
    assert ssim_val >= 0.90, f"SSIM value {ssim_val} is less than the required threshold of 0.90."


def test_systemd_service_content():
    path = "/home/user/.config/systemd/user/video-migrator.service"
    assert_regular_file(path)
    with open(path, "r") as f:
        content = f.read()

    assert "ExecStart=/home/user/optimize_stream.sh" in content, "ExecStart is incorrect or missing in service file."
    assert "Type=oneshot" in content, "Type=oneshot is missing in service file."
    assert "WantedBy=default.target" in content, "WantedBy=default.target is missing in service file."
    assert re.search(r"(?m)^Description=Staged Video Migrator\s*$", content), "Required service description is missing."
    assert re.search(r"(?ms)^\[Unit\].*?^Description=Staged Video Migrator\s*$", content), "Description must be in [Unit]."
    assert re.search(r"(?ms)^\[Service\].*?^Type=oneshot\s*$", content), "Type=oneshot must be in [Service]."
    assert re.search(r"(?ms)^\[Service\].*?^ExecStart=/home/user/optimize_stream\.sh\s*$", content), "ExecStart must be in [Service]."
    assert re.search(r"(?ms)^\[Install\].*?^WantedBy=default\.target\s*$", content), "WantedBy must be in [Install]."

    verified = run(["systemd-analyze", "verify", path])
    assert verified.returncode == 0, f"Invalid systemd unit syntax: {verified.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
