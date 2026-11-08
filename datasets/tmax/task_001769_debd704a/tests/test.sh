#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import gzip
import io
import os
import re
import shutil
import subprocess
import tarfile
import threading
import time
import uuid
import zipfile

import pytest

LOG = "/home/user/unified_index.log"
SUBMISSIONS = "/home/user/submissions"


def read_lines():
    with open(LOG, "r") as f:
        return set(line.strip() for line in f if line.strip())


def test_unified_index_log_exists():
    path = "/home/user/unified_index.log"
    assert os.path.isfile(path), f"File {path} does not exist. The script must create this file."


def test_unified_index_log_contents():
    path = "/home/user/unified_index.log"
    assert os.path.isfile(path), f"File {path} does not exist."

    expected_lines = {
        "team_alpha.tar.gz::docs/api.md -> 3",
        "team_alpha.tar.gz::legacy.zip/v1.md -> 5",
        "team_beta.zip::readme.md -> 2",
        "team_gamma.stream.gz::team_gamma.stream -> 4"
    }

    with open(path, "r") as f:
        actual_lines = set(line.strip() for line in f if line.strip())

    missing = expected_lines - actual_lines
    unexpected = actual_lines - expected_lines

    error_msg = []
    if missing:
        error_msg.append(f"Missing expected lines: {missing}")
    if unexpected:
        error_msg.append(f"Unexpected lines found: {unexpected}")

    assert not missing and not unexpected, " | ".join(error_msg)


def source_without_comments(text):
    return "\n".join(line for line in text.splitlines()
                     if not line.lstrip().startswith(("#", "//")))


def has_explicit_lock(path, text):
    suffix = os.path.splitext(path)[1].lower()
    if suffix == ".py" or "python" in text.splitlines()[0:1][0].lower() if text.splitlines() else False:
        try:
            tree = ast.parse(text)
        except SyntaxError:
            return False
        imported_flock = any(
            isinstance(n, ast.ImportFrom) and n.module == "fcntl" and
            any(a.name == "flock" for a in n.names)
            for n in ast.walk(tree)
        )
        for n in ast.walk(tree):
            if not isinstance(n, ast.Call):
                continue
            if isinstance(n.func, ast.Attribute) and n.func.attr == "flock":
                return True
            if imported_flock and isinstance(n.func, ast.Name) and n.func.id == "flock":
                return True
        return False
    code = source_without_comments(text)
    if suffix == ".sh" or "bash" in text[:100] or "sh" in text[:100]:
        return re.search(r"(^|[;&|()\s])flock(?:\s|$)", code, re.M) is not None
    return re.search(r"(?:\.flock\s*\(|\bflock\s*\()", code) is not None


def has_streaming_gzip(path, text):
    code = source_without_comments(text)
    patterns = [
        r"\bgzip\.open\s*\(", r"\bGzipFile\s*\(",
        r"GzipReader", r"IO::Uncompress::Gunzip", r"gunzip\s*\(",
        r"\bzcat\b", r"\bgzip\b[^\n]*(?:-[^\n]*[cd]|--stdout|--decompress)",
    ]
    return any(re.search(p, code, re.I) for p in patterns)


def command_for(path, text):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".py":
        return ["python3", path]
    if ext == ".sh":
        return ["bash", path]
    if ext == ".rb" and shutil.which("ruby"):
        return ["ruby", path]
    if ext == ".pl" and shutil.which("perl"):
        return ["perl", path]
    first = text.splitlines()[0] if text.splitlines() else ""
    if "python" in first:
        return ["python3", path]
    if "bash" in first or re.search(r"/sh\b", first):
        return ["bash", path]
    if "ruby" in first and shutil.which("ruby"):
        return ["ruby", path]
    if "perl" in first and shutil.which("perl"):
        return ["perl", path]
    if os.access(path, os.X_OK) and first.startswith("#!"):
        return [path]
    return None


def candidate_scripts():
    result = []
    excluded = {LOG, "/tmp/test_final_state.py", "/tmp/setup.py"}
    for root in ("/home/user", "/tmp"):
        for directory, dirs, files in os.walk(root):
            if directory.startswith(SUBMISSIONS):
                dirs[:] = []
                continue
            dirs[:] = [d for d in dirs if d not in {".cache", "__pycache__"}]
            for name in files:
                path = os.path.join(directory, name)
                if path in excluded:
                    continue
                try:
                    if not os.path.isfile(path) or os.path.getsize(path) > 2_000_000:
                        continue
                    raw = open(path, "rb").read()
                    if b"\x00" in raw:
                        continue
                    text = raw.decode("utf-8")
                except (OSError, UnicodeDecodeError):
                    continue
                cmd = command_for(path, text)
                if cmd and has_explicit_lock(path, text) and has_streaming_gzip(path, text):
                    result.append((path, cmd, text))
    return result


def reset_log():
    with open(LOG, "w"):
        pass
    os.chmod(LOG, 0o666)


def run_one(cmd, item, cwd, env=None, timeout=30):
    return subprocess.run(cmd + [item], cwd=cwd, env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=timeout)


def test_script_artifact_recursive_streaming_locking_and_concurrency():
    token = "verify_" + uuid.uuid4().hex
    work = os.path.join("/tmp", token)
    os.makedirs(work)

    probe_name = token + "_probe.zip"
    probe = os.path.join(SUBMISSIONS, probe_name)
    with zipfile.ZipFile(probe, "w") as zf:
        zf.writestr("unpredictable.md", "one\ntwo\nthree\n")
    probe_expected = {f"{probe_name}::unpredictable.md -> 3"}

    viable = []
    for path, cmd, text in candidate_scripts():
        reset_log()
        try:
            result = run_one(cmd, probe, work, timeout=15)
            if result.returncode == 0 and read_lines() == probe_expected:
                viable.append((path, cmd, text))
        except (subprocess.TimeoutExpired, OSError):
            pass

    assert viable, "No submitted single-argument script with explicit locking and streaming gzip processing could be executed successfully."
    script_path, cmd, script_text = viable[0]
    assert os.path.isfile(script_path), "The required processing script does not exist."
    assert has_explicit_lock(script_path, script_text), "The processing script does not make an explicit file-locking call."
    assert has_streaming_gzip(script_path, script_text), "The processing script does not use streaming gzip processing."

    expected = {
        "team_alpha.tar.gz::docs/api.md -> 3",
        "team_alpha.tar.gz::legacy.zip/v1.md -> 5",
        "team_beta.zip::readme.md -> 2",
        "team_gamma.stream.gz::team_gamma.stream -> 4",
    }
    items = [
        os.path.join(SUBMISSIONS, "team_alpha.tar.gz"),
        os.path.join(SUBMISSIONS, "team_beta.zip"),
        os.path.join(SUBMISSIONS, "team_gamma.stream.gz"),
    ]

    # Many independently processed archives exercise concurrent writes and locking.
    for i in range(10):
        name = f"{token}_bulk_{i}.zip"
        path = os.path.join(SUBMISSIONS, name)
        with zipfile.ZipFile(path, "w") as zf:
            for j in range(35):
                count = 1 + ((i * 11 + j * 7) % 19)
                internal = f"docs/group_{j % 4}/page_{j}.md"
                zf.writestr(internal, "".join(f"{token}-{i}-{j}-{k}\n" for k in range(count)))
                expected.add(f"{name}::{internal} -> {count}")
            zf.writestr("ignore.txt", "not markdown\n")
        items.append(path)

    # Outer archive -> first nested archive -> second nested archive -> Markdown.
    deep_zip = io.BytesIO()
    with zipfile.ZipFile(deep_zip, "w") as zf:
        zf.writestr("deep/path/result.md", "a\nb\nc\nd\ne\nf\ng\n")
    middle_tar = io.BytesIO()
    with tarfile.open(fileobj=middle_tar, mode="w:gz") as tf:
        payload = deep_zip.getvalue()
        info = tarfile.TarInfo("level2.zip")
        info.size = len(payload)
        tf.addfile(info, io.BytesIO(payload))
    nested_name = token + "_nested.zip"
    nested_path = os.path.join(SUBMISSIONS, nested_name)
    with zipfile.ZipFile(nested_path, "w") as zf:
        zf.writestr("top.md", "x\ny\n")
        zf.writestr("level1.tar.gz", middle_tar.getvalue())
    items.append(nested_path)
    expected.add(f"{nested_name}::top.md -> 2")
    expected.add(f"{nested_name}::level1.tar.gz/level2.zip/deep/path/result.md -> 7")

    stream_name = token + "_large.stream.gz"
    stream_path = os.path.join(SUBMISSIONS, stream_name)
    stream_count = 200000
    with gzip.open(stream_path, "wt") as f:
        for i in range(stream_count):
            f.write(f"{token}-{i}\n")
    expected.add(f"{stream_name}::{stream_name[:-3]} -> {stream_count}")
    items.append(stream_path)

    # Run the stream by itself while watching its private working/TMP directory.
    stream_work = os.path.join(work, "stream")
    os.makedirs(stream_work)
    env = os.environ.copy()
    env["TMPDIR"] = stream_work
    reset_log()
    proc = subprocess.Popen(cmd + [stream_path], cwd=stream_work, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    observed_disk_file = False
    while proc.poll() is None:
        for _, _, files in os.walk(stream_work):
            if files:
                observed_disk_file = True
                break
        time.sleep(0.001)
    out, err = proc.communicate(timeout=5)
    assert proc.returncode == 0, f"Standalone stream processing failed: {err or out}"
    assert not observed_disk_file and not any(files for _, _, files in os.walk(stream_work)), \
        "The standalone .stream.gz was materialized in the processing/TMP directory instead of being streamed."
    assert read_lines() == {f"{stream_name}::{stream_name[:-3]} -> {stream_count}"}

    # Invoke one process per top-level item at the same time, sharing one index.
    reset_log()
    processes = [subprocess.Popen(cmd + [item], cwd=work,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True) for item in items]
    failures = []
    for item, proc in zip(items, processes):
        try:
            out, err = proc.communicate(timeout=45)
        except subprocess.TimeoutExpired:
            proc.kill()
            out, err = proc.communicate()
            failures.append(f"{os.path.basename(item)} timed out")
            continue
        if proc.returncode != 0:
            failures.append(f"{os.path.basename(item)} exited {proc.returncode}: {err or out}")
    assert not failures, " | ".join(failures)

    actual = read_lines()
    missing = expected - actual
    unexpected = actual - expected
    assert not missing and not unexpected, \
        f"Concurrent recursive execution produced an incorrect index. Missing: {missing}; unexpected: {unexpected}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
