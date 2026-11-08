#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_extracted_logs_directory():
    dir_path = "/home/user/extracted_logs"
    assert os.path.isdir(dir_path), f"Directory {dir_path} does not exist or is not a directory."

def test_extracted_files_content():
    expected_files = {
        "startup.log": "System initialized normally.",
        "authorized_keys": "Warning: Disk usage high.",
        "status.txt": "All services running."
    }

    for filename, expected_content in expected_files.items():
        filepath = os.path.join("/home/user/extracted_logs", filename)
        assert os.path.exists(filepath), f"File {filepath} was not extracted (path traversal might not be mitigated properly)."

        try:
            with open(filepath, "r", encoding="utf-8") as f:
                content = f.read().strip()
        except UnicodeDecodeError:
            pytest.fail(f"File {filepath} is not valid UTF-8. Encoding conversion failed.")

        assert content == expected_content, f"Content of {filename} does not match expected. Got: {content}"

def test_audit_log_contents():
    audit_path = "/home/user/extraction_audit.log"
    assert os.path.exists(audit_path), f"Audit log {audit_path} does not exist."

    with open(audit_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = {
        "EXTRACTED: startup.log",
        "EXTRACTED: authorized_keys",
        "EXTRACTED: status.txt"
    }

    assert set(lines) == expected_lines, f"Audit log contents do not match expected. Expected exactly {expected_lines}, but got: {set(lines)}"

def test_script_logic():
    found_flock = False
    found_iconv = False
    found_mv = False

    for root, dirs, files in os.walk("/home/user"):
        if "extracted_logs" in root:
            continue
        for file in files:
            if file in ["backup_archive.txt", "extraction_audit.log", ".bash_history", ".bashrc", ".profile", ".bash_logout"]:
                continue

            filepath = os.path.join(root, file)
            if not os.path.isfile(filepath):
                continue

            try:
                with open(filepath, "r", encoding="utf-8") as f:
                    content = f.read()
                    if "flock" in content:
                        found_flock = True
                    if "iconv" in content:
                        found_iconv = True
                    if "mv " in content:
                        found_mv = True
            except Exception:
                pass

    assert found_flock, "Could not find 'flock' command in any script in /home/user/ (required for concurrent audit logging)."
    assert found_iconv, "Could not find 'iconv' command in any script in /home/user/ (required for encoding conversion)."
    assert found_mv, "Could not find 'mv' command in any script in /home/user/ (required for atomic writes)."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_extraction.py
import fcntl
import os
import re
import secrets
import shlex
import shutil
import subprocess
import time

HOME = "/home/user"
ARCHIVE = os.path.join(HOME, "backup_archive.txt")
OUTDIR = os.path.join(HOME, "extracted_logs")
AUDIT = os.path.join(HOME, "extraction_audit.log")


def script_candidates():
    result = []
    excluded = {ARCHIVE, AUDIT}
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if os.path.join(root, d) != OUTDIR]
        for name in files:
            path = os.path.join(root, name)
            if path in excluded or not os.path.isfile(path):
                continue
            try:
                with open(path, "rb") as f:
                    head = f.read(4096)
            except OSError:
                continue
            first = head.splitlines()[0] if head.splitlines() else b""
            if name.endswith((".sh", ".bash")) or (first.startswith(b"#!") and b"bash" in first):
                result.append(path)
    return sorted(result, key=lambda p: (p != "/home/user/extract.sh", len(p), p))


def make_archive(entries):
    with open(ARCHIVE, "wb") as f:
        for path, encoding, text in entries:
            f.write(b"[BEGIN_FILE]\n")
            f.write(("Path: " + path + "\n").encode("ascii"))
            f.write(("Encoding: " + encoding + "\n").encode("ascii"))
            f.write(b"[DATA]\n")
            f.write(text.encode(encoding))
            f.write(b"\n[END_FILE]\n")
    os.chmod(ARCHIVE, 0o644)


def command_lines(trace, command):
    pattern = re.compile(r"(?:^|\s)(?:/[^\s]*/)?" + re.escape(command) + r"(?:\s|$)")
    return [line for line in trace.splitlines() if line.startswith("+") and pattern.search(line)]


def mv_covers_file(lines, filename):
    for line in lines:
        try:
            words = shlex.split(line.lstrip("+ "))
        except ValueError:
            continue
        index = next((i for i, word in enumerate(words) if os.path.basename(word) == "mv"), None)
        if index is None:
            continue
        operands = [w for w in words[index + 1:] if w != "--" and not w.startswith("-")]
        if len(operands) >= 2:
            source, destination = operands[-2], operands[-1]
            if os.path.basename(destination.rstrip("/")) == filename and source != destination:
                return True
    return False


def try_script(script):
    token = secrets.token_hex(8)
    names = [f"boot_{token}.log", f"auth_{token}.txt", f"state_{token}.txt"]
    texts = [
        f"UTF16 payload {token}",
        f"Latin-1 café {token}",
        f"Windows € quote “{token}”",
    ]
    encodings = ["UTF-16LE", "ISO-8859-1", "WINDOWS-1252"]
    escape = f"escape_{token}.txt"
    escape_path = os.path.join("/tmp", escape)
    entries = [
        (f"var/log/{names[0]}", encodings[0], texts[0]),
        (f"../../../tmp/{names[1]}", encodings[1], texts[1]),
        (f"/var/spool/mail/admin/{names[2]}", encodings[2], texts[2]),
    ]

    shutil.rmtree(OUTDIR, ignore_errors=True)
    os.makedirs(OUTDIR, mode=0o777)
    try:
        os.unlink(escape_path)
    except FileNotFoundError:
        pass
    make_archive(entries)

    trace_path = f"/tmp/extract_trace_{token}.txt"
    with open(AUDIT, "w+", encoding="utf-8") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        env = os.environ.copy()
        env["PS4"] = "+ "
        with open(trace_path, "wb") as trace_file:
            proc = subprocess.Popen(
                ["bash", "-x", script],
                cwd=HOME,
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=trace_file,
            )
            time.sleep(1.0)
            lock_file.seek(0)
            if lock_file.read() != "" or proc.poll() is not None:
                if proc.poll() is None:
                    proc.kill()
                    proc.wait()
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
                return False
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            try:
                rc = proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
                return False

    if rc != 0 or os.path.exists(escape_path):
        return False

    try:
        actual_names = set(os.listdir(OUTDIR))
    except OSError:
        return False
    if actual_names != set(names):
        return False

    for name, expected in zip(names, texts):
        path = os.path.join(OUTDIR, name)
        if not os.path.isfile(path):
            return False
        try:
            with open(path, "r", encoding="utf-8") as f:
                if f.read().strip() != expected:
                    return False
        except (OSError, UnicodeDecodeError):
            return False

    try:
        with open(AUDIT, "r", encoding="utf-8") as f:
            audit_lines = [line.strip() for line in f if line.strip()]
    except (OSError, UnicodeDecodeError):
        return False
    if set(audit_lines) != {f"EXTRACTED: {name}" for name in names} or len(audit_lines) != 3:
        return False

    try:
        with open(trace_path, "r", encoding="utf-8", errors="replace") as f:
            trace = f.read()
    except OSError:
        return False

    iconv_lines = command_lines(trace, "iconv")
    mv_lines = command_lines(trace, "mv")
    flock_lines = command_lines(trace, "flock")
    if not flock_lines or len(iconv_lines) < 3 or len(mv_lines) < 3:
        return False
    if not all(any(enc.lower() in line.lower() for line in iconv_lines) for enc in encodings):
        return False
    if not all(mv_covers_file(mv_lines, name) for name in names):
        return False
    return True


candidates = script_candidates()
assert candidates, "No Bash extraction script was found under /home/user."
assert any(try_script(candidate) for candidate in candidates), (
    "No Bash script correctly extracted a freshly generated archive while using "
    "iconv, temporary-file renames, and flock-protected audit logging."
)
DYNAMIC_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 /tmp/test_dynamic_extraction.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
