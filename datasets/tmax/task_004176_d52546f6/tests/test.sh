#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_doc_extractor.py
import ctypes
import glob
import hashlib
import io
import json
import os
import shutil
import struct
import subprocess
import tarfile
import uuid

PROJECT = "/home/user/doc_extractor"
ARCHIVE = "/home/user/docs_incoming/docs.tar.gz"
OUTPUT = "/home/user/docs_safe"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def build_tool():
    manifest = os.path.join(PROJECT, "Cargo.toml")
    assert os.path.isdir(PROJECT), f"Rust project {PROJECT} does not exist."
    assert os.path.isfile(manifest), f"{manifest} does not exist."
    assert glob.glob(os.path.join(PROJECT, "src", "**", "*.rs"), recursive=True), "Rust source files are missing."

    proc = subprocess.run(
        ["cargo", "build", "--manifest-path", manifest, "--message-format=json"],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert proc.returncode == 0, f"Cargo build failed:\n{proc.stderr}\n{proc.stdout}"

    executables = []
    for line in proc.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get("reason") == "compiler-artifact" and "bin" in message.get("target", {}).get("kind", []):
            executable = message.get("executable")
            if executable:
                executables.append(executable)

    assert executables, "Cargo did not produce a Rust binary executable."
    executable = executables[-1]
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), f"Built binary {executable} is not executable."
    return executable


def run_tool(executable):
    return subprocess.run(
        [executable],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def assert_warning(stderr, path):
    expected = f"WARNING: Zip Slip detected in {path}"
    lines = stderr.splitlines()
    assert lines.count(expected) == 1, f"Expected exactly one stderr line {expected!r}; got:\n{stderr}"


def manifest_lines():
    manifest_path = os.path.join(OUTPUT, "manifest.txt")
    assert os.path.isfile(manifest_path), f"Manifest file {manifest_path} does not exist."
    with open(manifest_path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def check_original(executable):
    escaped_path = "/home/user/escaped.txt"
    passwd_override = "/etc/passwd.override.md"
    assert not os.path.exists(escaped_path), f"{escaped_path} exists! Zip Slip vulnerability triggered."
    assert not os.path.exists(passwd_override), f"{passwd_override} exists! Zip Slip vulnerability triggered."

    shutil.rmtree(OUTPUT, ignore_errors=True)
    proc = run_tool(executable)
    assert proc.returncode == 0, f"Extractor failed on the supplied archive:\n{proc.stderr}"

    intro_path = os.path.join(OUTPUT, "intro.md")
    api_path = os.path.join(OUTPUT, "api/reference.txt")
    assert os.path.isfile(intro_path), f"{intro_path} was not extracted."
    with open(intro_path, "r", encoding="utf-8") as f:
        assert f.read() == "Introduction\n", f"Content of {intro_path} is incorrect."
    assert os.path.isfile(api_path), f"{api_path} was not extracted."
    with open(api_path, "r", encoding="utf-8") as f:
        assert f.read() == "API Reference\n", f"Content of {api_path} is incorrect."

    logo_path = os.path.join(OUTPUT, "images/logo.png")
    assert not os.path.exists(logo_path), f"{logo_path} should not have been extracted (not .md or .txt)."
    assert not os.path.exists(escaped_path), f"{escaped_path} exists! Zip Slip vulnerability triggered."
    assert not os.path.exists(passwd_override), f"{passwd_override} exists! Zip Slip vulnerability triggered."

    expected = [
        f"{sha256(b'API Reference\n')}  api/reference.txt",
        f"{sha256(b'Introduction\n')}  intro.md",
    ]
    assert manifest_lines() == expected, f"Manifest contents are incorrect or not properly sorted. Expected:\n{expected}\nGot:\n{manifest_lines()}"

    assert_warning(proc.stderr, "../../../../home/user/escaped.txt")
    assert_warning(proc.stderr, "/etc/passwd.override.md")


def make_dynamic_archive(token, root_name, nested_rel, root_data, nested_data, traversal, absolute):
    with tarfile.open(ARCHIVE, "w:gz") as tar:
        def add(name, data):
            info = tarfile.TarInfo(name=name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))

        add(root_name, root_data)
        add(nested_rel, nested_data)
        add(f"ignored_{token}.bin", b"not documentation\n")
        add(traversal, b"traversal succeeded\n")
        add(absolute, b"absolute path succeeded\n")


def check_dynamic_and_atomic(executable):
    token = uuid.uuid4().hex
    root_name = f"note_{token}.md"
    nested_dir = f"section_{token}/deep"
    nested_rel = f"{nested_dir}/reference_{token}.txt"
    root_data = os.urandom(47)
    nested_data = os.urandom(61)
    traversal_target = f"doc_extractor_escape_{token}.txt"
    traversal = f"../../../../tmp/{traversal_target}"
    traversal_result = f"/tmp/{traversal_target}"
    absolute = f"/tmp/doc_extractor_absolute_{token}.md"

    for path in (traversal_result, absolute):
        if os.path.lexists(path):
            os.unlink(path)

    make_dynamic_archive(token, root_name, nested_rel, root_data, nested_data, traversal, absolute)
    shutil.rmtree(OUTPUT, ignore_errors=True)
    os.makedirs(os.path.join(OUTPUT, nested_dir), exist_ok=True)

    libc = ctypes.CDLL(None, use_errno=True)
    libc.inotify_init1.argtypes = [ctypes.c_int]
    libc.inotify_init1.restype = ctypes.c_int
    libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
    libc.inotify_add_watch.restype = ctypes.c_int

    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100
    mask = IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, "Could not initialize filesystem event monitoring."

    watches = {}
    for directory, rel_parent in ((OUTPUT, ""), (os.path.join(OUTPUT, nested_dir), nested_dir)):
        wd = libc.inotify_add_watch(fd, directory.encode(), mask)
        assert wd >= 0, f"Could not monitor {directory} for atomic writes."
        watches[wd] = rel_parent

    try:
        proc = run_tool(executable)
        assert proc.returncode == 0, f"Extractor failed on a generated archive:\n{proc.stderr}"

        raw = bytearray()
        while True:
            try:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                raw.extend(chunk)
            except BlockingIOError:
                break
    finally:
        os.close(fd)

    events = []
    offset = 0
    header = struct.Struct("iIII")
    while offset + header.size <= len(raw):
        wd, event_mask, cookie, name_len = header.unpack_from(raw, offset)
        offset += header.size
        name_bytes = bytes(raw[offset:offset + name_len])
        offset += name_len
        name = name_bytes.split(b"\0", 1)[0].decode("utf-8", "surrogateescape")
        events.append((watches.get(wd, "?"), event_mask, cookie, name))

    def assert_atomic(rel_path):
        parent, final_name = os.path.split(rel_path)
        tmp_name = final_name + ".tmp"
        assert any(p == parent and n == tmp_name and m & IN_CREATE for p, m, c, n in events), f"No creation of atomic temporary file {rel_path}.tmp was observed."
        assert any(p == parent and n == tmp_name and m & IN_CLOSE_WRITE for p, m, c, n in events), f"Temporary file {rel_path}.tmp was not written and closed."
        from_events = [(c, p) for p, m, c, n in events if p == parent and n == tmp_name and m & IN_MOVED_FROM]
        to_events = [(c, p) for p, m, c, n in events if p == parent and n == final_name and m & IN_MOVED_TO]
        assert from_events and to_events and any(fc != 0 and fc == tc for fc, _ in from_events for tc, _ in to_events), f"No atomic rename from {rel_path}.tmp to {rel_path} was observed."

    assert_atomic(root_name)
    assert_atomic(nested_rel)

    root_path = os.path.join(OUTPUT, root_name)
    nested_path = os.path.join(OUTPUT, nested_rel)
    assert os.path.isfile(root_path) and open(root_path, "rb").read() == root_data, "Generated Markdown file was not correctly extracted."
    assert os.path.isfile(nested_path) and open(nested_path, "rb").read() == nested_data, "Generated text file was not correctly extracted."
    assert not os.path.exists(os.path.join(OUTPUT, f"ignored_{token}.bin")), "A generated non-documentation file was extracted."
    assert not os.path.exists(traversal_result), "Generated traversal path escaped the output directory."
    assert not os.path.exists(absolute), "Generated absolute path was extracted."
    assert not glob.glob(os.path.join(OUTPUT, "**", "*.tmp"), recursive=True), "Temporary files were left behind."

    expected = sorted([
        f"{sha256(root_data)}  {root_name}",
        f"{sha256(nested_data)}  {nested_rel}",
    ], key=lambda line: line.split("  ", 1)[1])
    actual = manifest_lines()
    assert actual == expected, f"Generated manifest is incorrect. Expected {expected}, got {actual}"
    assert_warning(proc.stderr, traversal)
    assert_warning(proc.stderr, absolute)


def main():
    assert os.path.isfile(ARCHIVE), f"Input archive {ARCHIVE} is missing."
    with open(ARCHIVE, "rb") as f:
        original_archive = f.read()
    try:
        executable = build_tool()
        check_original(executable)
        check_dynamic_and_atomic(executable)
    finally:
        with open(ARCHIVE, "wb") as f:
            f.write(original_archive)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_doc_extractor.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
