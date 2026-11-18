#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import bz2
import configparser
import ctypes
import filecmp
import io
import os
import re
import secrets
import select
import shutil
import struct
import subprocess
import tarfile
import time
import zipfile
from pathlib import Path

IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100


def test_01_curated_art_001():
    incoming_path = "/home/user/incoming/art_001.tar.gz"
    curated_path = "/home/user/curated/art_001.tar.gz"
    assert os.path.isfile(curated_path), f"Expected file {curated_path} was not found."
    assert filecmp.cmp(incoming_path, curated_path, shallow=False), f"File {curated_path} does not match the original {incoming_path}."


def _assert_log_archive(path, artifact):
    assert os.path.isfile(path), f"Expected file {path} was not found."
    try:
        with tarfile.open(path, "r:bz2") as tar:
            member = tar.getmember("logs/info.log")
            f = tar.extractfile(member)
            content = f.read().decode("utf-8").strip()
            assert f"Log data for {artifact}" in content, f"Incorrect content in logs/info.log for {artifact}: {content}"
    except Exception as e:
        assert False, f"Failed to read {path} as a valid bzip2 tarball: {e}"


def test_02_curated_art_002_logs():
    _assert_log_archive("/home/user/curated/art_002_logs.tar.bz2", "art_002")


def test_03_curated_art_004_logs():
    _assert_log_archive("/home/user/curated/art_004_logs.tar.bz2", "art_004")


def test_04_curated_no_art_003():
    for filename in os.listdir("/home/user/curated"):
        assert "art_003" not in filename, f"Artifact art_003 should have been dropped, but found: {filename}"


def test_05_curation_log():
    log_path = "/home/user/curation.log"
    assert os.path.isfile(log_path), f"Log file {log_path} was not found."
    with open(log_path) as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_lines = {
        "[keep] Processed art_001.tar.gz",
        "[extract_logs] Processed art_002.tar.gz",
        "[extract_logs] Processed art_004.tar.gz",
    }
    actual_lines = set(lines)
    missing = expected_lines - actual_lines
    extra = actual_lines - expected_lines
    assert not missing, f"Log file is missing expected entries: {missing}"
    assert not extra, f"Log file contains unexpected entries: {extra}"


def test_06_no_temp_files():
    for filename in os.listdir("/home/user/curated"):
        assert not filename.endswith(".tmp"), f"Found a temporary file {filename} in /home/user/curated. Atomic writes should rename these."


def _candidate_scripts():
    excluded = {
        "/tmp/test_final_state.py",
        "/home/user/rules.ini",
        "/home/user/curation.log",
    }
    candidates = []
    for root in (Path("/home/user"), Path("/root"), Path("/tmp")):
        if not root.exists():
            continue
        for p in root.rglob("*"):
            try:
                sp = str(p)
                if (not p.is_file() or sp in excluded or
                    sp.startswith("/home/user/incoming/") or
                    sp.startswith("/home/user/curated/") or
                    sp.startswith("/tmp/pytest-") or
                    "__pycache__" in p.parts or p.stat().st_size > 2_000_000):
                    continue
                data = p.read_bytes()
            except (OSError, ValueError):
                continue
            text = data.decode("utf-8", "ignore")
            is_script = p.suffix.lower() in {".py", ".sh", ".bash", ".pl", ".rb"} or text.startswith("#!")
            if not is_script:
                continue
            low = text.lower()
            score = sum(token in low for token in ("/home/user/incoming", "/home/user/curated", "rules.ini", "payload.zip", "meta.txt", "tar.gz", "extract_logs"))
            if score >= 3:
                candidates.append((score, p.stat().st_mtime, p, text))
    candidates.sort(reverse=True, key=lambda x: (x[0], x[1]))
    return candidates


def _command_for(path, text):
    suffix = path.suffix.lower()
    if suffix == ".py":
        return ["python3", str(path)]
    if suffix in {".sh", ".bash"}:
        return ["bash", str(path)]
    if suffix == ".pl":
        return ["perl", str(path)]
    if suffix == ".rb":
        return ["ruby", str(path)]
    first = text.splitlines()[0] if text.splitlines() else ""
    if "python" in first:
        return ["python3", str(path)]
    if "bash" in first or "sh" in first:
        return ["bash", str(path)]
    return [str(path)]


def _logs_archive(message):
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w") as tf:
        payload = message.encode()
        info = tarfile.TarInfo("logs/info.log")
        info.size = len(payload)
        info.mode = 0o644
        tf.addfile(info, io.BytesIO(payload))
    return bz2.compress(raw.getvalue())


def _make_artifact(path, project, message):
    logs = _logs_archive(message)
    zbuf = io.BytesIO()
    with zipfile.ZipFile(zbuf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("data.bin", secrets.token_bytes(257))
        zf.writestr("logs.tar.bz2", logs)
        zf.writestr("unrelated/decoy.txt", secrets.token_hex(64))
    with tarfile.open(path, "w:gz") as tf:
        meta = f"project={project}\n".encode()
        mi = tarfile.TarInfo("meta.txt")
        mi.size = len(meta)
        tf.addfile(mi, io.BytesIO(meta))
        zi = tarfile.TarInfo("payload.zip")
        zi.size = len(zbuf.getvalue())
        tf.addfile(zi, io.BytesIO(zbuf.getvalue()))
        decoy = secrets.token_bytes(4096)
        di = tarfile.TarInfo("must_not_be_extracted.bin")
        di.size = len(decoy)
        tf.addfile(di, io.BytesIO(decoy))
    return logs


def _read_inotify(fd, events):
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            return
        if not data:
            return
        pos = 0
        while pos < len(data):
            wd, mask, cookie, length = struct.unpack_from("iIII", data, pos)
            pos += 16
            name = data[pos:pos + length].split(b"\0", 1)[0].decode("utf-8", "replace")
            pos += length
            events.append((mask, cookie, name))


def test_07_execute_script_on_derived_inputs_and_require_atomic_moves():
    candidates = _candidate_scripts()
    assert candidates, "No retained curation script was found; the task requires writing and executing a script."
    _, _, script, source = candidates[0]

    low = source.lower()
    python_stream = "extractfile" in low and "meta.txt" in low
    tar_stream = bool(re.search(r"(?:^|[;&|\n])\s*(?:[a-z0-9_./-]*tar)\s+[^\n]*(?:--to-stdout|-[a-z]*o[a-z]*)", low)) and "meta.txt" in low
    generic_stream = "meta.txt" in low and any(token in low for token in ("get_input_stream", "entry.open", "readentry", "entry.read", "tar_stream"))
    assert python_stream or tar_stream or generic_stream, "The script does not read meta.txt as a stream from the compressed tar archive."
    assert "extractall(" not in low and ".extractall(" not in low, "The script extracts the entire outer archive instead of streaming meta.txt."

    incoming = Path("/home/user/incoming")
    curated = Path("/home/user/curated")
    for p in incoming.iterdir():
        if p.is_dir():
            shutil.rmtree(p)
        else:
            p.unlink()
    for p in curated.iterdir():
        if p.is_dir():
            shutil.rmtree(p)
        else:
            p.unlink()
    Path("/home/user/curation.log").unlink(missing_ok=True)

    token = secrets.token_hex(6)
    projects = {
        "keep": "keep_" + secrets.token_hex(5),
        "extract": "extract_" + secrets.token_hex(5),
        "drop": "drop_" + secrets.token_hex(5),
        "unknown": "unknown_" + secrets.token_hex(5),
    }
    names = {
        "keep": f"dynamic_keep_{token}",
        "extract1": f"dynamic_logs_a_{token}",
        "extract2": f"dynamic_logs_b_{token}",
        "drop": f"dynamic_drop_{token}",
        "unknown": f"dynamic_unknown_{token}",
    }
    Path("/home/user/rules.ini").write_text(
        "[Rules]\n"
        f"{projects['keep']} = keep\n"
        f"{projects['extract']} = extract_logs\n"
        f"{projects['drop']} = drop\n"
    )

    expected_logs = {}
    _make_artifact(incoming / f"{names['keep']}.tar.gz", projects["keep"], "keep payload")
    expected_logs[names["extract1"]] = _make_artifact(incoming / f"{names['extract1']}.tar.gz", projects["extract"], "dynamic first " + secrets.token_hex(20))
    expected_logs[names["extract2"]] = _make_artifact(incoming / f"{names['extract2']}.tar.gz", projects["extract"], "dynamic second " + secrets.token_hex(20))
    _make_artifact(incoming / f"{names['drop']}.tar.gz", projects["drop"], "drop payload")
    _make_artifact(incoming / f"{names['unknown']}.tar.gz", projects["unknown"], "unknown payload")

    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, f"inotify_init1 failed: errno {ctypes.get_errno()}"
    wd = libc.inotify_add_watch(fd, os.fsencode(str(curated)), IN_CREATE | IN_MOVED_FROM | IN_MOVED_TO)
    assert wd >= 0, f"inotify_add_watch failed: errno {ctypes.get_errno()}"
    events = []
    try:
        proc = subprocess.Popen(_command_for(script, source), cwd="/home/user", stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        deadline = time.time() + 30
        while proc.poll() is None and time.time() < deadline:
            select.select([fd], [], [], 0.05)
            _read_inotify(fd, events)
        if proc.poll() is None:
            proc.kill()
            proc.wait()
            assert False, f"Curation script {script} timed out"
        for _ in range(3):
            select.select([fd], [], [], 0.05)
            _read_inotify(fd, events)
        stderr = proc.stderr.read()
        assert proc.returncode == 0, f"Curation script {script} failed with status {proc.returncode}: {stderr}"
    finally:
        os.close(fd)

    expected_files = {
        f"{names['keep']}.tar.gz",
        f"{names['extract1']}_logs.tar.bz2",
        f"{names['extract2']}_logs.tar.bz2",
    }
    actual_files = {p.name for p in curated.iterdir() if p.is_file()}
    assert actual_files == expected_files, f"Incorrect dynamically curated files: expected {expected_files}, got {actual_files}"
    assert (curated / f"{names['keep']}.tar.gz").read_bytes() == (incoming / f"{names['keep']}.tar.gz").read_bytes()
    for name, expected in expected_logs.items():
        output = curated / f"{name}_logs.tar.bz2"
        assert output.read_bytes() == expected, f"{output} was not the exact logs.tar.bz2 stored in payload.zip"

    created = {name for mask, cookie, name in events if mask & IN_CREATE}
    moved_from = {cookie: name for mask, cookie, name in events if mask & IN_MOVED_FROM}
    moved_to = {name: cookie for mask, cookie, name in events if mask & IN_MOVED_TO}
    for final_name in expected_files:
        assert final_name not in created, f"{final_name} was opened as a direct new write rather than installed atomically"
        assert final_name in moved_to, f"{final_name} was not installed using a rename/mv into the curated directory"
        cookie = moved_to[final_name]
        assert cookie in moved_from, f"No same-directory temporary source was observed for atomic move to {final_name}"
        assert moved_from[cookie] != final_name, f"Atomic move for {final_name} did not originate from a temporary filename"

    with open("/home/user/curation.log") as f:
        lines = {line.strip() for line in f if line.strip()}
    expected_lines = {
        f"[keep] Processed {names['keep']}.tar.gz",
        f"[extract_logs] Processed {names['extract1']}.tar.gz",
        f"[extract_logs] Processed {names['extract2']}.tar.gz",
    }
    assert lines == expected_lines, f"Incorrect dynamic curation log: expected {expected_lines}, got {lines}"
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
