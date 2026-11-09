#!/bin/bash
set -u
mkdir -p /logs/verifier

echo "0" > /logs/verifier/reward.txt

# The submitted Go project itself must compile.
if ! (cd /app/patch-api && go build -o /tmp/patch-api-verifier .); then
    exit 0
fi

# Stop any server the agent left on port 8080 so the tests exercise the binary
# built from the submitted project rather than an unrelated process.
python3 - <<'PY'
import glob
import os
import signal

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[1].endswith(":1F90") and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

pids = set()
for fd in glob.glob("/proc/[0-9]*/fd/*"):
    try:
        target = os.readlink(fd)
    except OSError:
        continue
    if target.startswith("socket:[") and target[8:-1] in inodes:
        try:
            pids.add(int(fd.split("/")[2]))
        except (ValueError, IndexError):
            pass

for pid in pids:
    if pid != os.getpid():
        try:
            os.kill(pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
PY
sleep 1

(cd /app/patch-api && /tmp/patch-api-verifier >/tmp/patch-api-verifier.log 2>&1) &
SERVER_PID=$!
cleanup() {
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

ready=0
for _ in $(seq 1 50); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        break
    fi
    if curl -sS -o /dev/null --max-time 1 http://127.0.0.1:8080/ 2>/dev/null; then
        ready=1
        break
    fi
    # Any HTTP response also proves the listener is ready; curl returns success
    # for ordinary 404 responses from net/http.
    sleep 0.1
done
if [ "$ready" -ne 1 ] || ! kill -0 "$SERVER_PID" 2>/dev/null; then
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import subprocess
import urllib.error
import urllib.request
import pytest

URL = "http://127.0.0.1:8080/api/v1/patch"


def post_patch(data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    req = urllib.request.Request(URL, data=data, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.getcode()
    except urllib.error.HTTPError as exc:
        return exc.code
    except Exception as exc:
        pytest.fail(f"API request failed (is the submitted server running?): {exc}")


def expected_frame_count():
    try:
        cmd = [
            "ffprobe", "-v", "error", "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1", "/app/incident.mp4"
        ]
        return int(float(subprocess.check_output(cmd, text=True).strip()))
    except Exception:
        return 45


def test_frame_count():
    """Preserve the original count assertion and verify extracted frames exist."""
    assert os.path.exists("/app/frame_count.txt"), "/app/frame_count.txt is missing"
    with open("/app/frame_count.txt", "r") as f:
        content = f.read().strip()
    assert content.isdigit(), f"frame_count.txt does not contain a valid integer: {content}"
    actual_count = int(content)
    expected_frames = expected_frame_count()
    assert abs(actual_count - expected_frames) <= 2, \
        f"Expected around {expected_frames} frames, but got {actual_count}"

    # Find actual, independently decodable, single-frame image artefacts. The
    # extraction directory may be chosen freely, so inspect regular files under
    # /app and group valid frames by their containing directory.
    by_directory = {}
    ignored = {"/app/incident.mp4", "/app/frame_count.txt"}
    for root, dirs, files in os.walk("/app"):
        dirs[:] = [d for d in dirs if d not in {".git", "vendor"}]
        for name in files:
            path = os.path.join(root, name)
            if path in ignored or os.path.islink(path):
                continue
            try:
                output = subprocess.check_output(
                    ["ffprobe", "-v", "error", "-count_frames",
                     "-select_streams", "v:0",
                     "-show_entries", "stream=codec_type,width,height,nb_read_frames",
                     "-of", "json", path],
                    text=True, stderr=subprocess.DEVNULL, timeout=3
                )
                streams = json.loads(output).get("streams", [])
            except Exception:
                continue
            if len(streams) != 1:
                continue
            stream = streams[0]
            try:
                one_frame = int(stream.get("nb_read_frames", 0)) == 1
                dimensions_ok = int(stream.get("width", 0)) > 0 and int(stream.get("height", 0)) > 0
            except (TypeError, ValueError):
                continue
            if stream.get("codec_type") == "video" and one_frame and dimensions_ok:
                by_directory.setdefault(root, []).append(path)

    matching = {directory: paths for directory, paths in by_directory.items()
                if len(paths) == actual_count}
    assert actual_count > 0 and matching, (
        f"frame_count.txt claims {actual_count}, but no directory under /app "
        "contains that many decodable single-frame image artefacts"
    )


def test_api_corpus():
    """Preserve checks against the supplied evil and clean corpora."""
    evil_dir = "/app/tests/evil"
    clean_dir = "/app/tests/clean"
    evil_files = glob.glob(os.path.join(evil_dir, "*"))
    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}"
    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}"

    evil_bypassed = []
    for fpath in evil_files:
        with open(fpath, "rb") as f:
            data = f.read()
        if post_patch(data) != 400:
            evil_bypassed.append(os.path.basename(fpath))

    clean_modified = []
    for fpath in clean_files:
        with open(fpath, "rb") as f:
            data = f.read()
        if post_patch(data) != 200:
            clean_modified.append(os.path.basename(fpath))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_api_generated_cases():
    """Exercise randomized paths and diff-format variants not present in /app/tests."""
    token = secrets.token_hex(12)
    clean = [
        f"--- a/src/{token}.go\n+++ b/src/{token}.go\n@@ -1 +1 @@\n-old\n+new\n",
        f"diff --git a/{token}.txt b/{token}.txt\nindex 1..2 100644\n--- a/{token}.txt\t2026-01-01 00:00:00 +0000\n+++ b/{token}.txt\t2026-01-02 00:00:00 +0000\n@@ -1 +1 @@\n-a\n+b\n",
        f"--- a/pkg/.../{token}\n+++ b/pkg/.../{token}\n@@ -0,0 +1 @@\n+safe\n",
        f"--- a/dir..name/{token}\n+++ b/dir..name/{token}\n@@ -1 +1 @@\n---- /etc/passwd\n++++ b/../../not-a-header\n",
    ]
    evil = [
        f"--- a/{token}\n+++ b/../private/{token}\n@@ -1 +1 @@\n-a\n+b\n",
        f"--- /etc/{token}\n+++ b/{token}\n@@ -1 +1 @@\n-a\n+b\n",
        f"--- a/safe/{token}\r\n+++ b/safe/../../escape/{token}\r\n@@ -1 +1 @@\r\n-a\r\n+b\r\n",
        f"diff --git a/{token} b/{token}\n--- a/{token}\t2026-01-01 00:00:00 +0000\n+++ /var/tmp/{token}\t2026-01-01 00:00:01 +0000\n@@ -1 +1 @@\n-a\n+b\n",
        f"--- a/first/{token}\n+++ b/first/{token}\n@@ -1 +1 @@\n-a\n+b\n--- a/second/{token}\n+++ b/second/../../../escape/{token}\n@@ -1 +1 @@\n-c\n+d\n",
        f"preamble for {token}\n--- ../outside/{token}\n+++ b/local/{token}\n@@ -0,0 +1 @@\n+x\n",
    ]

    for index, patch in enumerate(clean):
        assert post_patch(patch) == 200, f"generated clean patch {index} was rejected"
    for index, patch in enumerate(evil):
        assert post_patch(patch) == 400, f"generated malicious patch {index} was accepted"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
fi
