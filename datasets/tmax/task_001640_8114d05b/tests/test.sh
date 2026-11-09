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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import locale
import os
import random
import re
import signal
import subprocess
import time

import pytest
import requests

VIDEO = "/app/edge_feed.mp4"
SOURCE = "/home/user/edge_daemon.c"
BINARY = "/home/user/edge_daemon"
DEPLOY = "/home/user/deploy.sh"
WIDTH = 16
HEIGHT = 16


def make_video(black_count, total_frames):
    rng = random.SystemRandom()
    frames = [bytes(WIDTH * HEIGHT * 3) for _ in range(black_count)]
    for _ in range(total_frames - black_count):
        color = (rng.randrange(1, 256), rng.randrange(1, 256), rng.randrange(1, 256))
        frames.append(bytes(color) * (WIDTH * HEIGHT))
    rng.shuffle(frames)

    os.makedirs(os.path.dirname(VIDEO), exist_ok=True)
    proc = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "rawvideo", "-pixel_format", "rgb24",
            "-video_size", f"{WIDTH}x{HEIGHT}", "-framerate", "10",
            "-i", "pipe:0", "-an", "-c:v", "libx264rgb", "-crf", "0",
            "-preset", "ultrafast", "-pix_fmt", "rgb24", VIDEO,
        ],
        input=b"".join(frames), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=20,
    )
    assert proc.returncode == 0, proc.stderr.decode(errors="replace")


def independently_count_black_frames():
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x", VIDEO],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=True,
    )
    width, height = map(int, probe.stdout.decode().strip().split("x"))
    decoded = subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", VIDEO,
         "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20, check=True,
    ).stdout
    frame_size = width * height * 3
    assert frame_size > 0 and len(decoded) % frame_size == 0
    return sum(
        all(value == 0 for value in decoded[offset:offset + frame_size])
        for offset in range(0, len(decoded), frame_size)
    )


def stop_daemon():
    subprocess.run(["pkill", "-TERM", "-x", "edge_daemon"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 5
    while time.time() < deadline:
        found = False
        for name in os.listdir("/proc"):
            if not name.isdigit():
                continue
            try:
                with open(f"/proc/{name}/comm") as f:
                    if f.read().strip() == "edge_daemon":
                        found = True
                        break
            except (FileNotFoundError, PermissionError, ProcessLookupError):
                pass
        if not found:
            return
        time.sleep(0.1)
    subprocess.run(["pkill", "-KILL", "-x", "edge_daemon"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def start_with_deploy():
    stop_daemon()
    result = subprocess.run(
        ["bash", DEPLOY], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20,
    )
    assert result.returncode == 0, f"deploy.sh failed:\n{result.stdout}\n{result.stderr}"
    deadline = time.time() + 10
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get("http://127.0.0.1:8080/health", timeout=0.5)
            if response.status_code == 200:
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.1)
    pytest.fail(f"edge_daemon did not become ready on port 8080: {last_error}")


def daemon_environments():
    environments = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/comm") as f:
                if f.read().strip() != "edge_daemon":
                    continue
            with open(f"/proc/{name}/environ", "rb") as f:
                entries = f.read().split(b"\0")
            environments.append({
                item.split(b"=", 1)[0].decode(errors="replace"):
                item.split(b"=", 1)[1].decode(errors="replace")
                for item in entries if b"=" in item
            })
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return environments


@pytest.fixture(scope="module", autouse=True)
def prepared_service():
    make_video(42, 50)
    assert independently_count_black_frames() == 42
    start_with_deploy()
    yield
    stop_daemon()


def test_files_exist():
    assert os.path.isfile(DEPLOY), "/home/user/deploy.sh is missing"
    assert os.path.isfile(SOURCE), "/home/user/edge_daemon.c is missing"
    assert os.path.isfile(BINARY), "/home/user/edge_daemon executable is missing"
    assert os.access(BINARY, os.X_OK), "/home/user/edge_daemon is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "edge_daemon is not a compiled ELF executable"


def test_c_program_invokes_ffmpeg_and_deploy_sets_environment():
    source = open(SOURCE, encoding="utf-8", errors="replace").read()
    deploy = open(DEPLOY, encoding="utf-8", errors="replace").read()
    assert re.search(r"\bffmpeg\b", source), "C source does not reference ffmpeg"
    assert re.search(r"\b(system|popen|execl|execlp|execle|execv|execvp|execve|posix_spawn|posix_spawnp)\s*\(", source), \
        "C source does not use a process-execution API to invoke ffmpeg"
    assert re.search(r"\bTZ\s*=\s*['\"]?Asia/Tokyo", deploy), "deploy.sh does not set TZ=Asia/Tokyo"
    assert re.search(r"\b(?:LANG|LC_ALL|LC_TIME)\s*=\s*['\"]?ja_JP\.UTF-8", deploy, re.I), \
        "deploy.sh does not set the ja_JP.UTF-8 locale"

    envs = daemon_environments()
    assert envs, "No running edge_daemon process found"
    assert any(env.get("TZ") == "Asia/Tokyo" for env in envs), "edge_daemon is not running with TZ=Asia/Tokyo"
    assert any(any(env.get(key, "").lower() == "ja_jp.utf-8" for key in ("LC_ALL", "LC_TIME", "LANG")) for env in envs), \
        "edge_daemon is not running with the ja_JP.UTF-8 locale"


def test_health_endpoint():
    try:
        locale.setlocale(locale.LC_TIME, "ja_JP.UTF-8")
    except locale.Error as exc:
        pytest.fail(f"ja_JP.UTF-8 locale is unavailable: {exc}")
    old_tz = os.environ.get("TZ")
    os.environ["TZ"] = "Asia/Tokyo"
    time.tzset()
    try:
        before = time.time()
        response = requests.get("http://127.0.0.1:8080/health", timeout=5)
        after = time.time()
        assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
        body = response.text.strip()
        has_jp_chars = any(char in body for char in ['年', '月', '日', '時', '分', '秒', 'JST'])
        assert has_jp_chars, f"Response body does not appear Japanese/Tokyo formatted. Body: {body}"
        valid = {
            time.strftime("%c", time.localtime(second))
            for second in range(int(before) - 2, int(after) + 3)
        }
        assert body in valid, f"/health is not the current Asia/Tokyo ja_JP.UTF-8 %c time. Body: {body}"
    finally:
        if old_tz is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = old_tz
        time.tzset()


def test_metrics_endpoint():
    response = requests.get("http://127.0.0.1:8080/metrics", timeout=5)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    body = response.text.strip()
    match = re.search(r'black_frames:\s*(\d+)', body)
    assert match is not None, f"Response body does not match expected format 'black_frames: <COUNT>'. Body: {body}"
    count = int(match.group(1))
    assert count == 42, f"Expected 42 black frames, got {count}"
    assert body == "black_frames: 42", f"Metrics body contains extra or malformed text: {body!r}"


def test_metrics_are_recomputed_from_changed_video():
    new_count = random.SystemRandom().randrange(5, 36)
    make_video(new_count, 47)
    expected = independently_count_black_frames()
    assert expected == new_count
    start_with_deploy()
    response = requests.get("http://127.0.0.1:8080/metrics", timeout=5)
    assert response.status_code == 200
    assert response.text.strip() == f"black_frames: {expected}", \
        "edge_daemon did not recompute the exact black-frame count from /app/edge_feed.mp4"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
