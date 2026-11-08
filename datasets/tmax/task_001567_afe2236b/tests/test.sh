#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import datetime
import hashlib
import hmac
import os
import pathlib
import random
import shutil
import signal
import struct
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

import pytest

FILTER_BIN = "/home/user/filter"
FILTER_SRC = "/home/user/filter.go"
SERVER_SRC = "/home/user/app/server.go"
CLEAN_DIR = "/app/corpus/clean"
EVIL_DIR = "/app/corpus/evil"
UPLOAD_URL = "http://127.0.0.1:8080/upload"
MINIO_URL = "http://127.0.0.1:9000"
MINIO_USER = "admin"
MINIO_PASSWORD = "password"
FILTER_LOG = "/tmp/verifier-filter-invocations.log"
REAL_FILTER = "/home/user/filter.verifier-real"


def kill_port(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10:
                local = fields[1]
                state = fields[3]
                try:
                    local_port = int(local.rsplit(":", 1)[1], 16)
                except (ValueError, IndexError):
                    continue
                if local_port == port and state == "0A":
                    inodes.add(fields[9])

    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        os.kill(int(proc.name), signal.SIGTERM)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except OSError:
            pass
    time.sleep(1)


def wait_http(url, timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            urllib.request.urlopen(url, timeout=1).close()
            return
        except urllib.error.HTTPError:
            return
        except Exception:
            time.sleep(0.25)
    raise AssertionError(f"Service did not become available: {url}")


def wait_redis(timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = subprocess.run(["redis-cli", "PING"], capture_output=True)
        if result.returncode == 0 and result.stdout.strip() == b"PONG":
            return
        time.sleep(0.25)
    raise AssertionError("Redis did not become available")


@pytest.fixture(scope="session", autouse=True)
def controlled_services():
    assert os.path.isfile(SERVER_SRC), f"Tracker source missing at {SERVER_SRC}"

    # Test against freshly launched, known service instances rather than any
    # process the submission may have left listening on the requested ports.
    for port in (8080, 9000, 6379):
        kill_port(port)

    data_dir = pathlib.Path("/data")
    data_dir.mkdir(parents=True, exist_ok=True)
    for child in data_dir.iterdir():
        if child.is_dir() and not child.is_symlink():
            shutil.rmtree(child)
        else:
            child.unlink()

    redis = subprocess.run(["redis-server", "--daemonize", "yes"], capture_output=True, text=True)
    assert redis.returncode == 0, redis.stderr
    wait_redis()
    subprocess.run(["redis-cli", "FLUSHALL"], check=True, capture_output=True)

    minio_log = open("/tmp/verifier-minio.log", "wb")
    minio_env = os.environ.copy()
    minio_env.update({"MINIO_ROOT_USER": MINIO_USER, "MINIO_ROOT_PASSWORD": MINIO_PASSWORD})
    minio = subprocess.Popen(
        ["minio", "server", "/data"], env=minio_env,
        stdout=minio_log, stderr=subprocess.STDOUT
    )
    wait_http(MINIO_URL + "/minio/health/live")

    build = subprocess.run(
        ["go", "build", "-o", "/tmp/tracker-under-test", SERVER_SRC],
        cwd="/home/user/app", capture_output=True, text=True, timeout=90
    )
    assert build.returncode == 0, f"server.go did not build:\n{build.stdout}\n{build.stderr}"

    tracker_log = open("/tmp/verifier-tracker.log", "wb")
    tracker = subprocess.Popen(
        ["/tmp/tracker-under-test"], cwd="/home/user/app",
        stdout=tracker_log, stderr=subprocess.STDOUT
    )
    wait_http(UPLOAD_URL)

    yield

    for proc in (tracker, minio):
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
    subprocess.run(["redis-cli", "SHUTDOWN", "NOSAVE"], capture_output=True)
    tracker_log.close()
    minio_log.close()


def make_backup(path, encoding, text):
    payload = text.encode(encoding)
    enc = encoding.encode("ascii")
    path.write_bytes(b"BKP1" + bytes([len(enc)]) + enc + struct.pack("<I", len(payload)) + payload)
    return path.read_bytes()


def run_filter(data, encoding, text):
    with tempfile.TemporaryDirectory(prefix="filter-dynamic-") as td:
        path = pathlib.Path(td) / ("input-" + os.urandom(6).hex() + ".bin")
        make_backup(path, encoding, text)
        return subprocess.run([FILTER_BIN, str(path)], capture_output=True, timeout=5).returncode


def test_filter_executable_corpus():
    """Retain the original corpus assertions and require the requested binary artifact."""
    assert os.path.isfile(FILTER_SRC), f"Filter source not found at {FILTER_SRC}"
    assert os.path.isfile(FILTER_BIN), f"Filter binary not found at {FILTER_BIN}"
    assert os.access(FILTER_BIN, os.X_OK), f"Filter binary is not executable at {FILTER_BIN}"
    with open(FILTER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Filter must be a compiled executable, not a script"

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert clean_files, "No clean corpus files found."
    assert evil_files, "No evil corpus files found."

    clean_failed = []
    evil_failed = []
    for cf in clean_files:
        if subprocess.run([FILTER_BIN, cf], capture_output=True, timeout=5).returncode != 0:
            clean_failed.append(os.path.basename(cf))
    for ef in evil_files:
        if subprocess.run([FILTER_BIN, ef], capture_output=True, timeout=5).returncode != 1:
            evil_failed.append(os.path.basename(ef))

    errors = []
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_filter_generated_inputs():
    """Exercise parsing and decoding on unpredictable valid backup files."""
    token = os.urandom(12).hex()
    cases = [
        ("UTF-8", f"clean differential setting={token} /DEV/TCP/ EXEC-bash", 0),
        ("UTF-16LE", f"snowman config Ω {token} then EXEC_BASH --now", 1),
        ("Windows-1252", f"café={token}; endpoint=/dev/tcp/203.0.113.7/4444", 1),
        ("UTF-16LE", f"ordinary UTF16 configuration {token}", 0),
        ("Windows-1252", f"price=£12; clean={token}", 0),
        ("UTF-8", f"prefix{token}EXEC_BASHsuffix", 1),
    ]
    random.shuffle(cases)
    for encoding, text, expected in cases:
        assert run_filter(None, encoding, text) == expected, (
            f"Filter returned the wrong status for generated {encoding} input"
        )


def aws_request(method, path, query=""):
    now = datetime.datetime.now(datetime.timezone.utc)
    amzdate = now.strftime("%Y%m%dT%H%M%SZ")
    datestamp = now.strftime("%Y%m%d")
    payload_hash = hashlib.sha256(b"").hexdigest()
    canonical_uri = urllib.parse.quote(path, safe="/-_.~")
    pairs = urllib.parse.parse_qsl(query, keep_blank_values=True)
    canonical_query = urllib.parse.urlencode(sorted(pairs), quote_via=urllib.parse.quote, safe="-_.~")
    canonical_headers = f"host:127.0.0.1:9000\nx-amz-content-sha256:{payload_hash}\nx-amz-date:{amzdate}\n"
    signed_headers = "host;x-amz-content-sha256;x-amz-date"
    canonical_request = "\n".join([method, canonical_uri, canonical_query, canonical_headers, signed_headers, payload_hash])
    scope = f"{datestamp}/us-east-1/s3/aws4_request"
    string_to_sign = "AWS4-HMAC-SHA256\n" + amzdate + "\n" + scope + "\n" + hashlib.sha256(canonical_request.encode()).hexdigest()

    def sign(key, msg):
        return hmac.new(key, msg.encode(), hashlib.sha256).digest()

    key = sign(("AWS4" + MINIO_PASSWORD).encode(), datestamp)
    key = sign(key, "us-east-1")
    key = sign(key, "s3")
    key = sign(key, "aws4_request")
    signature = hmac.new(key, string_to_sign.encode(), hashlib.sha256).hexdigest()
    authorization = f"AWS4-HMAC-SHA256 Credential={MINIO_USER}/{scope}, SignedHeaders={signed_headers}, Signature={signature}"
    url = MINIO_URL + canonical_uri + (("?" + canonical_query) if canonical_query else "")
    req = urllib.request.Request(url, method=method, headers={
        "Host": "127.0.0.1:9000",
        "x-amz-date": amzdate,
        "x-amz-content-sha256": payload_hash,
        "Authorization": authorization,
    })
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.read()


def xml_values(data, local_name):
    root = ET.fromstring(data)
    return [elem.text or "" for elem in root.iter() if elem.tag.rsplit("}", 1)[-1] == local_name]


def minio_objects():
    result = {}
    for bucket in xml_values(aws_request("GET", "/"), "Name"):
        listing = aws_request("GET", "/" + bucket, "list-type=2")
        for key in xml_values(listing, "Key"):
            result[(bucket, key)] = aws_request("GET", "/" + bucket + "/" + key)
    return result


def minio_contains(data):
    return any(value == data for value in minio_objects().values())


def redis_snapshot():
    snapshot = {}
    for db in range(16):
        keys = subprocess.run(
            ["redis-cli", "-n", str(db), "--scan"], capture_output=True, check=True
        ).stdout.splitlines()
        for key in keys:
            dumped = subprocess.run(
                ["redis-cli", "-n", str(db), "--raw", "DUMP", key],
                capture_output=True, check=True
            ).stdout
            snapshot[(db, key)] = dumped
    return snapshot


def upload(data):
    req = urllib.request.Request(UPLOAD_URL, data=data, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=8) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code


def wait_for_storage(data, redis_before, timeout=8):
    deadline = time.time() + timeout
    last_redis = redis_before
    while time.time() < deadline:
        last_redis = redis_snapshot()
        if last_redis != redis_before and minio_contains(data):
            return
        time.sleep(0.25)
    assert last_redis != redis_before, "Accepted upload did not create or update Redis metadata"
    assert minio_contains(data), "Accepted upload was not stored as an object in MinIO"


def install_filter_wrapper():
    if os.path.exists(REAL_FILTER):
        os.unlink(REAL_FILTER)
    os.rename(FILTER_BIN, REAL_FILTER)
    wrapper = f'''#!/bin/sh
p="$1"
if [ -f "$p" ]; then
  hash=$(sha256sum "$p" | cut -d' ' -f1)
  printf '%s %s\\n' "$hash" "$p" >> {FILTER_LOG}
else
  printf 'MISSING %s\\n' "$p" >> {FILTER_LOG}
fi
if [ -f /tmp/verifier-force-filter-code ]; then
  exit "$(cat /tmp/verifier-force-filter-code)"
fi
exec {REAL_FILTER} "$@"
'''
    pathlib.Path(FILTER_BIN).write_text(wrapper)
    os.chmod(FILTER_BIN, 0o755)


def restore_filter():
    try:
        os.unlink(FILTER_BIN)
    except FileNotFoundError:
        pass
    if os.path.exists(REAL_FILTER):
        os.rename(REAL_FILTER, FILTER_BIN)
    try:
        os.unlink("/tmp/verifier-force-filter-code")
    except FileNotFoundError:
        pass


def logged_hashes():
    if not os.path.exists(FILTER_LOG):
        return []
    return [line.split()[0] for line in pathlib.Path(FILTER_LOG).read_text().splitlines() if line.strip()]


def test_server_integration():
    """Retain fixed HTTP checks, then verify invocation and both backing stores with fresh inputs."""
    clean_files = sorted(os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f)))
    evil_files = sorted(os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f)))
    assert clean_files and evil_files, "Corpus files missing, cannot test server integration."

    pathlib.Path(FILTER_LOG).write_text("")
    install_filter_wrapper()
    try:
        # Original fixed clean and evil status assertions, now also checking storage effects.
        clean_data = pathlib.Path(clean_files[0]).read_bytes()
        before = redis_snapshot()
        assert upload(clean_data) == 200, "Clean file upload expected HTTP 200"
        wait_for_storage(clean_data, before)

        evil_data = pathlib.Path(evil_files[0]).read_bytes()
        before = redis_snapshot()
        assert upload(evil_data) == 403, "Evil file upload expected HTTP 403"
        time.sleep(0.3)
        assert redis_snapshot() == before, "Rejected upload modified Redis metadata"
        assert not minio_contains(evil_data), "Rejected upload was stored in MinIO"

        # Unpredictable bodies prevent path/content-specific server behavior.
        token = os.urandom(16).hex()
        with tempfile.TemporaryDirectory() as td:
            clean_path = pathlib.Path(td) / "generated-clean.bin"
            evil_path = pathlib.Path(td) / "generated-evil.bin"
            clean_dynamic = make_backup(clean_path, "UTF-16LE", f"dynamic clean configuration {token} café")
            evil_dynamic = make_backup(evil_path, "Windows-1252", f"dynamic {token} /dev/tcp/198.51.100.9/9001")

        before = redis_snapshot()
        assert upload(clean_dynamic) == 200, "Generated clean upload expected HTTP 200"
        wait_for_storage(clean_dynamic, before)

        before = redis_snapshot()
        assert upload(evil_dynamic) == 403, "Generated evil upload expected HTTP 403"
        time.sleep(0.3)
        assert redis_snapshot() == before, "Generated rejected upload modified Redis metadata"
        assert not minio_contains(evil_dynamic), "Generated rejected upload was stored in MinIO"

        expected_hashes = {
            hashlib.sha256(clean_data).hexdigest(),
            hashlib.sha256(evil_data).hexdigest(),
            hashlib.sha256(clean_dynamic).hexdigest(),
            hashlib.sha256(evil_dynamic).hexdigest(),
        }
        seen = set(logged_hashes())
        assert expected_hashes <= seen, "Tracker did not invoke /home/user/filter on every uploaded temporary file"
        assert "MISSING" not in seen, "Tracker invoked the filter before writing a temporary file"

        # Ensure the HTTP decision actually follows the filter's exit status.
        forced_token = os.urandom(12).hex()
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td) / "forced-clean.bin"
            forced_clean = make_backup(p, "UTF-8", f"otherwise clean {forced_token}")
        pathlib.Path("/tmp/verifier-force-filter-code").write_text("1")
        before = redis_snapshot()
        assert upload(forced_clean) == 403, "Tracker ignored the filter's rejection exit status"
        time.sleep(0.3)
        assert redis_snapshot() == before, "Filter-rejected upload modified Redis metadata"
        assert not minio_contains(forced_clean), "Filter-rejected upload was stored in MinIO"
        assert hashlib.sha256(forced_clean).hexdigest() in set(logged_hashes())
    finally:
        restore_filter()
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
