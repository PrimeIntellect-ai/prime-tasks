#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

WORKDIR=$(mktemp -d /tmp/etl-verifier.XXXXXX)
EMBED_TOOL=/app/bin/get_embedding
BACKUP="$WORKDIR/get_embedding.original"
LOGFILE="$WORKDIR/get_embedding.calls"

cleanup() {
    if [ -f "$BACKUP" ]; then
        cp "$BACKUP" "$EMBED_TOOL"
        chmod +x "$EMBED_TOOL"
    fi
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

cp "$EMBED_TOOL" "$BACKUP"
: > "$LOGFILE"
cat > "$EMBED_TOOL" <<WRAPPER_EOF
#!/bin/bash
if [ -z "\$1" ] || [ ! -f "\$1" ]; then
    echo "Error: missing file"
    exit 1
fi
p=\$(readlink -f "\$1")
printf '%s\n' "\$p" >> '$LOGFILE'
HASH=\$(md5sum "\$1" | awk '{print \$1}')
echo "[0.\${HASH:0:4}, 0.\${HASH:4:4}, 0.\${HASH:8:4}]"
WRAPPER_EOF
chmod +x "$EMBED_TOOL"

export VERIFIER_WORKDIR="$WORKDIR"
export VERIFIER_LOGFILE="$LOGFILE"

if python3 <<'PY_EOF'
import collections
import glob
import hashlib
import os
import signal
import socket
import subprocess
import tempfile
import time

workdir = os.environ["VERIFIER_WORKDIR"]
logfile = os.environ["VERIFIER_LOGFILE"]
etl_script = "/home/user/run_etl.sh"
serve_script = "/home/user/serve.sh"
processed = "/home/user/processed"
frames_dir = os.path.join(processed, "frames")
csv_path = os.path.join(processed, "embeddings.csv")

assert os.path.isfile(etl_script), f"ETL script not found at {etl_script}"
assert os.path.isfile(serve_script), f"Retrieval script not found at {serve_script}"

# Independently extract the expected one-frame-per-second sequence.
reference_dir = os.path.join(workdir, "reference")
os.makedirs(reference_dir)
subprocess.run([
    "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
    "-i", "/app/data/source.mp4", "-vf", "fps=1",
    os.path.join(reference_dir, "frame_%04d.jpg")
], check=True, timeout=60)
reference_files = sorted(glob.glob(os.path.join(reference_dir, "frame_*.jpg")))
assert len(reference_files) >= 5, "Reference extraction unexpectedly produced fewer than five frames"
reference_names = [os.path.basename(p) for p in reference_files]
assert "frame_0005.jpg" in reference_names

# Remove any pre-existing self-reported output, then execute the submitted ETL script.
subprocess.run(["rm", "-rf", processed], check=True)
subprocess.run(["/bin/bash", etl_script], check=True, timeout=90)

assert os.path.isdir(frames_dir), f"Frames directory not found at {frames_dir}"
assert os.path.isfile(csv_path), f"Embeddings CSV not found at {csv_path}"

actual_files = sorted(glob.glob(os.path.join(frames_dir, "frame_*.jpg")))
actual_names = [os.path.basename(p) for p in actual_files]
assert actual_names == reference_names, (
    f"Extracted frame sequence differs from the expected 1-fps sequence: {actual_names}"
)

# Decode both image sequences and verify each submitted frame corresponds to the
# same-position source frame. This permits ordinary JPEG encoder variation while
# rejecting arbitrary fabricated images.
def decoded_rgb(path):
    return subprocess.check_output([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", path,
        "-vf", "scale=160:120", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
    ], timeout=20)

reference_rgb = [decoded_rgb(p) for p in reference_files]
for index, actual_path in enumerate(actual_files):
    actual_rgb = decoded_rgb(actual_path)
    assert len(actual_rgb) == len(reference_rgb[index])
    errors = [
        sum(abs(a - b) for a, b in zip(actual_rgb, candidate)) / len(actual_rgb)
        for candidate in reference_rgb
    ]
    assert errors[index] == min(errors), (
        f"{os.path.basename(actual_path)} does not match its expected source-video frame"
    )
    assert errors[index] < 25.0, (
        f"{os.path.basename(actual_path)} differs too much from the source-video frame"
    )

# Keep the original CSV existence, population, and line-format assertions.
with open(csv_path, "r", encoding="utf-8") as f:
    lines = f.readlines()
assert len(lines) >= 5, f"Expected at least 5 lines in embeddings.csv, found {len(lines)}"

entries = {}
for line in lines:
    parts = line.strip().split(',', 1)
    assert len(parts) == 2, f"Invalid format in embeddings.csv line: {line.strip()}"
    assert parts[0].startswith("frame_") and parts[0].endswith(".jpg"), (
        f"Invalid frame name format: {parts[0]}"
    )
    assert line.endswith("\n"), "Every CSV record must end with a newline"
    name, embedding = parts[0], parts[1].strip()
    assert line.rstrip("\n") == f"{name}, {embedding}", (
        f"CSV line is not formatted as 'frame_XXXX.jpg, <embedding_output>': {line.rstrip()}"
    )
    assert name not in entries, f"Duplicate CSV entry for {name}"
    entries[name] = embedding

assert list(entries.keys()) == reference_names, "CSV frame names/order do not match extracted frames"

# Validate embeddings independently from the actual extracted files.
def expected_embedding(path):
    digest = hashlib.md5(open(path, "rb").read()).hexdigest()
    return f"[0.{digest[0:4]}, 0.{digest[4:8]}, 0.{digest[8:12]}]"

for path in actual_files:
    name = os.path.basename(path)
    assert entries[name] == expected_embedding(path), f"Incorrect embedding for {name}"

# Confirm the ETL actually invoked the provided absolute tool for every frame.
with open(logfile, "r", encoding="utf-8") as f:
    calls = [line.strip() for line in f if line.strip()]
expected_paths = [os.path.realpath(p) for p in actual_files]
counts = collections.Counter(calls)
assert all(path in expected_paths for path in calls), "get_embedding was invoked on an unexpected file"
for path in expected_paths:
    assert counts[path] >= 1, f"get_embedding was not invoked for {path}"

# Find and stop all pre-existing port-8888 listeners so only the submitted
# serve.sh launched below can satisfy the service checks.
def listener_inodes():
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            rows = open(table, encoding="ascii").read().splitlines()[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            local = fields[1]
            state = fields[3]
            if state == "0A" and int(local.rsplit(":", 1)[1], 16) == 8888:
                result.add(fields[9])
    return result

def listener_pids():
    inodes = listener_inodes()
    result = set()
    if not inodes:
        return result
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[1])
        for fd in glob.glob(procdir + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                result.add(pid)
                break
    return result

for pid in listener_pids():
    if pid != os.getpid():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
time.sleep(0.5)
for pid in listener_pids():
    if pid != os.getpid():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
time.sleep(0.3)
assert not listener_inodes(), "Could not clear the pre-existing listener on port 8888"

subprocess.Popen(
    ["/bin/bash", serve_script],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    start_new_session=True,
)

def request(number):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        s.connect(("127.0.0.1", 8888))
        s.sendall((number + "\n").encode("ascii"))
        response = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            response += chunk
        return response

# Wait for startup using a real request, then exercise multiple sequential
# connections. Exact bytes enforce embedding-only output plus one newline.
first_number = reference_names[0][6:10]
last_error = None
for _ in range(50):
    try:
        response = request(first_number)
        assert response == (entries[reference_names[0]] + "\n").encode("utf-8")
        break
    except (ConnectionRefusedError, socket.timeout, OSError) as exc:
        last_error = exc
        time.sleep(0.1)
else:
    raise AssertionError(f"Could not connect to TCP server at 127.0.0.1:8888: {last_error}")

# Includes the original frame-0005 response assertion and several sequential requests.
for name in reference_names[1:]:
    number = name[6:10]
    actual = request(number)
    expected = (entries[name] + "\n").encode("utf-8")
    assert actual == expected, (
        f"Server response for {number} was {actual!r}, expected {expected!r}"
    )

# The service must still be listening after handling all requests.
for _ in range(30):
    if listener_inodes():
        break
    time.sleep(0.1)
assert listener_inodes(), "Retrieval service is not still listening after sequential requests"
PY_EOF
then
    echo "1" > /logs/verifier/reward.txt
fi
