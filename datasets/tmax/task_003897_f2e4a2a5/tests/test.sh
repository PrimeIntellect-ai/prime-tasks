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
import json
import os
import random
import shutil
import subprocess
import tempfile
import time

import requests


def test_config_json_exists():
    config_path = "/home/user/config.json"
    assert os.path.isfile(config_path), f"{config_path} does not exist"
    with open(config_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{config_path} does not contain valid JSON"
    assert "DASH-99" in str(data), "config.json does not seem to contain DASH-99"


def _find_expect_script():
    candidates = []
    for root in ("/home/user", "/root"):
        if not os.path.isdir(root):
            continue
        for directory, _, files in os.walk(root):
            for name in files:
                path = os.path.join(directory, name)
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    with open(path, "r", errors="ignore") as f:
                        content = f.read()
                except OSError:
                    continue
                lowered = content.lower()
                if ("/app/legacy_configurator" in content and
                        "spawn" in lowered and "expect" in lowered and
                        "send" in lowered and "admin" in content and
                        "observability2024" in content and "DASH-99" in content):
                    candidates.append((path, content))
    assert candidates, "No expect automation script for /app/legacy_configurator was found"
    return candidates


def test_expect_script_runs_configurator_and_generates_config():
    config_path = "/home/user/config.json"
    configurator = "/app/legacy_configurator"
    real_configurator = "/app/legacy_configurator.verifier-real"
    marker = "/tmp/verifier_legacy_configurator_invoked"
    candidates = _find_expect_script()

    with open(config_path, "rb") as f:
        original_config = f.read()

    assert not os.path.exists(real_configurator), f"Unexpected path already exists: {real_configurator}"
    if os.path.exists(marker):
        os.unlink(marker)

    os.rename(configurator, real_configurator)
    with open(configurator, "w") as f:
        f.write("#!/bin/sh\necho invoked > /tmp/verifier_legacy_configurator_invoked\nexec /app/legacy_configurator.verifier-real \"$@\"\n")
    os.chmod(configurator, 0o755)

    succeeded = False
    errors = []
    try:
        for path, content in candidates:
            try:
                if content.startswith("#!") and "expect" in content.splitlines()[0].lower():
                    command = ["expect", path]
                elif path.lower().endswith((".exp", ".expect")):
                    command = ["expect", path]
                elif os.access(path, os.X_OK):
                    command = [path]
                else:
                    command = ["bash", path]

                if os.path.exists(marker):
                    os.unlink(marker)
                result = subprocess.run(
                    command,
                    cwd=os.path.dirname(path) or "/home/user",
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
                if result.returncode != 0 or not os.path.isfile(marker):
                    errors.append(f"{path}: rc={result.returncode}, stdout={result.stdout}, stderr={result.stderr}")
                    continue

                with open(config_path, "r") as f:
                    generated = json.load(f)
                if generated == {
                    "dashboard_id": "DASH-99",
                    "username": "admin",
                    "password": "observability2024",
                }:
                    succeeded = True
                    break
                errors.append(f"{path}: generated unexpected config {generated!r}")
            except Exception as exc:
                errors.append(f"{path}: {exc}")
    finally:
        if os.path.exists(configurator):
            os.unlink(configurator)
        os.rename(real_configurator, configurator)
        with open(config_path, "wb") as f:
            f.write(original_config)
        if os.path.exists(marker):
            os.unlink(marker)

    assert succeeded, "Expect automation did not invoke the configurator and generate the required config: " + "; ".join(errors)


def test_systemd_service_file():
    service_path = os.path.expanduser("~/.config/systemd/user/video-metrics.service")
    assert os.path.isfile(service_path), f"Systemd service file {service_path} does not exist"

    with open(service_path, "r") as f:
        content = f.read()

    assert "After=network.target" in content, "Service file does not contain 'After=network.target'"


def test_systemd_service_active():
    try:
        result = subprocess.run(
            ["systemctl", "--user", "is-active", "video-metrics.service"],
            capture_output=True,
            text=True,
            check=True
        )
        assert result.stdout.strip() == "active", "video-metrics.service is not active"
    except subprocess.CalledProcessError as e:
        assert False, f"Failed to check service status, output: {e.stdout}, err: {e.stderr}"


def test_http_metrics_endpoint():
    url = "http://127.0.0.1:9090/metrics"
    headers = {"Authorization": "Bearer DASH-99"}

    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.RequestException as e:
        assert False, f"Failed to connect to {url}: {e}"

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        assert False, f"Response is not valid JSON: {response.text}"

    assert data.get("dashboard_id") == "DASH-99", f"Expected dashboard_id 'DASH-99', got {data.get('dashboard_id')}"
    assert data.get("red_alerts_count") == 12, f"Expected red_alerts_count 12, got {data.get('red_alerts_count')}"


def _write_ppm(path, width, height, center_red):
    if center_red:
        background = (17, 41, 83)
        center = (255, 0, 0)
    else:
        # Most of this frame is red, but its exact center is not. This detects
        # implementations that inspect the whole frame instead of the center.
        background = (255, 0, 0)
        center = (0, 0, 255)

    pixels = bytearray(background * (width * height))
    x, y = width // 2, height // 2
    offset = (y * width + x) * 3
    pixels[offset:offset + 3] = bytes(center)
    with open(path, "wb") as f:
        f.write(f"P6\n{width} {height}\n255\n".encode("ascii"))
        f.write(pixels)


def _wait_for_dynamic_metrics(dashboard_id, expected_count):
    url = "http://127.0.0.1:9090/metrics"
    headers = {"Authorization": f"Bearer {dashboard_id}"}
    last_error = None
    deadline = time.time() + 20
    while time.time() < deadline:
        try:
            response = requests.get(url, headers=headers, timeout=2)
            if response.status_code == 200:
                data = response.json()
                if data.get("dashboard_id") == dashboard_id and data.get("red_alerts_count") == expected_count:
                    return data
                last_error = f"unexpected payload {data!r}"
            else:
                last_error = f"HTTP {response.status_code}: {response.text}"
        except Exception as exc:
            last_error = str(exc)
        time.sleep(0.5)
    assert False, f"Service did not report metrics derived from the replacement config/video: {last_error}"


def test_service_reads_config_invokes_ffmpeg_and_checks_center_pixels():
    config_path = "/home/user/config.json"
    video_path = "/app/dashboard_recording.mp4"
    ffmpeg_path = os.path.realpath(shutil.which("ffmpeg") or "/usr/bin/ffmpeg")
    real_ffmpeg = ffmpeg_path + ".verifier-real"
    marker = "/tmp/verifier_ffmpeg_invoked"

    with open(config_path, "rb") as f:
        original_config = f.read()
    with open(video_path, "rb") as f:
        original_video = f.read()

    rng = random.SystemRandom()
    dashboard_id = "VERIFY-" + os.urandom(6).hex().upper()
    frame_count = 9
    expected_count = rng.randint(2, 6)
    alert_indexes = set(rng.sample(range(frame_count), expected_count))

    wrapper_installed = False
    with tempfile.TemporaryDirectory() as frames_dir:
        for index in range(frame_count):
            _write_ppm(
                os.path.join(frames_dir, f"frame{index:03d}.ppm"),
                64,
                64,
                index in alert_indexes,
            )

        generated_video = os.path.join(frames_dir, "dashboard_recording.mp4")
        subprocess.run([
            ffmpeg_path, "-hide_banner", "-loglevel", "error", "-y",
            "-framerate", "5", "-i", os.path.join(frames_dir, "frame%03d.ppm"),
            "-c:v", "libx264rgb", "-crf", "0", "-preset", "ultrafast",
            "-pix_fmt", "rgb24", "-frames:v", str(frame_count), generated_video,
        ], check=True, timeout=30)

        assert not os.path.exists(real_ffmpeg), f"Unexpected path already exists: {real_ffmpeg}"
        if os.path.exists(marker):
            os.unlink(marker)

        try:
            with open(config_path, "w") as f:
                json.dump({
                    "dashboard_id": dashboard_id,
                    "username": "admin",
                    "password": "observability2024",
                }, f)
            shutil.copyfile(generated_video, video_path)

            os.rename(ffmpeg_path, real_ffmpeg)
            with open(ffmpeg_path, "w") as f:
                f.write(
                    "#!/bin/sh\n"
                    "echo \"$@\" >> /tmp/verifier_ffmpeg_invoked\n"
                    f"exec {real_ffmpeg} \"$@\"\n"
                )
            os.chmod(ffmpeg_path, 0o755)
            wrapper_installed = True

            restart = subprocess.run(
                ["systemctl", "--user", "restart", "video-metrics.service"],
                capture_output=True,
                text=True,
                timeout=20,
            )
            assert restart.returncode == 0, f"Failed to restart service: {restart.stdout} {restart.stderr}"

            data = _wait_for_dynamic_metrics(dashboard_id, expected_count)
            assert data == {
                "dashboard_id": dashboard_id,
                "red_alerts_count": expected_count,
            }, f"Unexpected dynamic metrics payload: {data!r}"
            assert os.path.isfile(marker) and os.path.getsize(marker) > 0, "The service did not invoke ffmpeg while processing the replacement video"
        finally:
            with open(config_path, "wb") as f:
                f.write(original_config)
            with open(video_path, "wb") as f:
                f.write(original_video)

            if wrapper_installed:
                if os.path.exists(ffmpeg_path):
                    os.unlink(ffmpeg_path)
                os.rename(real_ffmpeg, ffmpeg_path)
            if os.path.exists(marker):
                os.unlink(marker)

            subprocess.run(
                ["systemctl", "--user", "restart", "video-metrics.service"],
                capture_output=True,
                text=True,
                timeout=20,
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
