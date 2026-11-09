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
import os
import secrets
import shutil
import subprocess
import tempfile
import requests
import xml.etree.ElementTree as ET

BASE_URL = "http://127.0.0.1:8080"


def get_storage_results():
    url = BASE_URL + "/storage-scan"
    try:
        resp = requests.get(url, timeout=5)
    except requests.RequestException as e:
        assert False, f"Failed to connect to {url}: {e}"

    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}"
    try:
        return resp.json()
    except ValueError:
        assert False, f"Response is not valid JSON: {resp.text}"


def expected_storage_results():
    expected = []
    base_dir = "/home/user/storage_dump"
    for root, dirs, files in os.walk(base_dir):
        for f in files:
            if f.endswith(".dat"):
                path = os.path.join(root, f)
                with open(path, "rb") as fp:
                    header = fp.read(4).hex().lower()
                expected.append({"path": path, "header": header})
    return sorted(expected, key=lambda x: x["path"])


def test_video_analysis():
    url = BASE_URL + "/video-analysis"
    try:
        resp = requests.get(url, timeout=5)
    except requests.RequestException as e:
        assert False, f"Failed to connect to {url}: {e}"

    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}"

    try:
        data = resp.json()
    except ValueError:
        assert False, f"Response is not valid JSON: {resp.text}"

    assert "black_frames_count" in data, "Key 'black_frames_count' missing in response"
    assert data["black_frames_count"] == 5, f"Expected 5 black frames, got {data['black_frames_count']}"


def count_pure_black_frames(path):
    width, height = 320, 240
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path,
        "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"
    ])
    frame_size = width * height * 3
    assert len(raw) % frame_size == 0, "Could not decode complete video frames"
    return sum(
        1 for offset in range(0, len(raw), frame_size)
        if not any(raw[offset:offset + frame_size])
    )


def test_video_analysis_uses_recording():
    video = "/app/disk_monitor.mp4"
    token = secrets.token_hex(8)
    alternate = f"/tmp/alternate-{token}.mp4"
    saved = f"/tmp/original-{token}.mp4"
    requested_black_frames = 8 + secrets.randbelow(10)

    subprocess.run([
        "ffmpeg", "-v", "error", "-y",
        "-f", "lavfi", "-i", "color=c=red:s=320x240:r=10:d=0.6",
        "-f", "lavfi", "-i",
        f"color=c=black:s=320x240:r=10:d={requested_black_frames / 10.0}",
        "-f", "lavfi", "-i", "color=c=green:s=320x240:r=10:d=0.4",
        "-filter_complex", "[0:v][1:v][2:v]concat=n=3:v=1:a=0[outv]",
        "-map", "[outv]", "-r", "10", alternate
    ], check=True)
    expected = count_pure_black_frames(alternate)
    assert expected != 5 and expected > 0

    os.replace(video, saved)
    try:
        shutil.copy2(alternate, video)
        resp = requests.get(BASE_URL + "/video-analysis", timeout=10)
        assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}"
        try:
            data = resp.json()
        except ValueError:
            assert False, f"Response is not valid JSON: {resp.text}"
        assert "black_frames_count" in data, "Key 'black_frames_count' missing in response"
        assert data["black_frames_count"] == expected, (
            f"Video analysis did not reflect the supplied recording: expected {expected}, got {data['black_frames_count']}"
        )
    finally:
        if os.path.exists(video):
            os.unlink(video)
        os.replace(saved, video)
        if os.path.exists(alternate):
            os.unlink(alternate)


def test_storage_scan():
    data = get_storage_results()
    expected = expected_storage_results()

    assert isinstance(data, list), "Expected response to be a JSON array"
    data_sorted = sorted(data, key=lambda x: x.get("path", ""))
    assert data == data_sorted, "The JSON array is not sorted alphabetically by file path"
    assert data == expected, f"Storage scan results mismatch.\nExpected: {expected}\nGot: {data}"


def test_storage_scan_discovers_current_files():
    token = secrets.token_hex(12)
    dynamic_dir = os.path.join("/home/user/storage_dump", "dynamic_" + token)
    dynamic_path = os.path.join(dynamic_dir, "sample_" + token + ".dat")
    header = secrets.token_bytes(4)
    os.makedirs(dynamic_dir)
    with open(dynamic_path, "wb") as fp:
        fp.write(header + secrets.token_bytes(19))

    try:
        data = get_storage_results()
        expected = expected_storage_results()
        assert isinstance(data, list), "Expected response to be a JSON array"
        assert data == sorted(data, key=lambda x: x.get("path", "")), (
            "The JSON array is not sorted alphabetically by file path"
        )
        assert data == expected, f"Storage scan did not discover current files.\nExpected: {expected}\nGot: {data}"
        assert {"path": dynamic_path, "header": header.hex()} in data
    finally:
        shutil.rmtree(dynamic_dir, ignore_errors=True)


def test_clean_config():
    url = BASE_URL + "/clean-config"
    test_xml = """<backup>
  <target>/mnt/data</target>
  <loop_detected/><loop_detected/>
  <retention>7</retention>
</backup>"""

    try:
        resp = requests.post(url, data=test_xml, timeout=5)
    except requests.RequestException as e:
        assert False, f"Failed to connect to {url}: {e}"

    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}"

    output = resp.text
    assert "<loop_detected" not in output, "The <loop_detected/> tags were not completely removed"
    assert "<target>/mnt/data</target>" in output, "The <target> tag is missing or altered"
    assert "<retention>7</retention>" in output, "The <retention> tag is missing or altered"

    try:
        root = ET.fromstring(output)
        assert root.tag == "backup", "Root element should be <backup>"
        assert root.find("target") is not None and root.find("target").text == "/mnt/data"
        assert root.find("retention") is not None and root.find("retention").text == "7"
    except ET.ParseError as e:
        assert False, f"Returned XML is invalid or malformed: {e}\nOutput was:\n{output}"


def tree_without_loops(element):
    assert element.tag != "loop_detected"
    return (
        element.tag,
        tuple(sorted(element.attrib.items())),
        (element.text or "").strip(),
        tuple(tree_without_loops(child) for child in element if child.tag != "loop_detected")
    )


def test_clean_config_handles_arbitrary_large_input():
    token = secrets.token_hex(16)
    loops = "\n    <loop_detected/>" * (1200 + secrets.randbelow(400))
    test_xml = f"""<backup id="{token}">
  <target>/mnt/{token}</target>
  <settings mode="incremental">
    <owner>{token}-owner</owner>{loops}
    <retention unit="days">{17 + secrets.randbelow(70)}</retention>
    <loop_detected></loop_detected>
    <note>preserve-{token}</note>
  </settings>
  <loop_detected />
  <destination enabled="true">host-{token}</destination>
</backup>"""

    input_root = ET.fromstring(test_xml)
    expected = tree_without_loops(input_root)
    try:
        resp = requests.post(
            BASE_URL + "/clean-config",
            data=test_xml.encode("utf-8"),
            headers={"Content-Type": "application/xml"},
            timeout=10
        )
    except requests.RequestException as e:
        assert False, f"Failed to connect to clean-config: {e}"

    assert resp.status_code == 200, f"Expected status 200, got {resp.status_code}"
    assert "loop_detected" not in resp.text, "Not all loop_detected elements were removed"
    try:
        output_root = ET.fromstring(resp.text)
    except ET.ParseError as e:
        assert False, f"Returned XML is invalid or malformed: {e}"
    assert tree_without_loops(output_root) == expected, (
        "Cleaning changed non-loop elements, attributes, or text"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
