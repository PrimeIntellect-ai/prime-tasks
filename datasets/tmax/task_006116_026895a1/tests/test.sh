#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import io
import os
import re
import shutil
import signal
import struct
import subprocess
import tarfile
import time
import uuid
import zipfile


def test_organizer_cpp_exists_and_uses_rename():
    """Preserve the source-level checks for the required atomic rename operation."""
    cpp_file = "/home/user/organizer.cpp"
    assert os.path.exists(cpp_file), f"File {cpp_file} does not exist."

    with open(cpp_file, "r") as f:
        content = f.read()

    assert re.search(r'rename\s*\(', content), "organizer.cpp does not use the rename() function for atomic updates."
    assert re.search(r'inotify_(?:init|init1)\s*\(', content), "organizer.cpp does not initialize inotify."
    assert "IN_CLOSE_WRITE" in content or "IN_MOVED_TO" in content, "organizer.cpp does not request the required inotify events."


def make_nested_zip(files):
    """Return a zip containing deeply nested tar.gz files with the supplied CSVs."""
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for index, (name, data) in enumerate(files.items()):
            tar_buffer = io.BytesIO()
            with tarfile.open(fileobj=tar_buffer, mode="w:gz") as tf:
                info = tarfile.TarInfo(name=f"inside/level_{index}/{name}")
                encoded = data.encode("utf-8")
                info.size = len(encoded)
                tf.addfile(info, io.BytesIO(encoded))
            zf.writestr(f"outer/deep/archive_{index}/part_{index}.tar.gz", tar_buffer.getvalue())
    return zip_buffer.getvalue()


def organizer_pids():
    expected = os.path.realpath("/home/user/organizer")
    result = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            if os.path.realpath(f"/proc/{entry}/exe") == expected:
                result.append(int(entry))
        except OSError:
            pass
    return result


def has_inotify_fd(pid):
    fd_dir = f"/proc/{pid}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                if os.readlink(os.path.join(fd_dir, fd)) == "anon_inode:inotify":
                    return True
            except OSError:
                pass
    except OSError:
        pass
    return False


def wait_until(predicate, timeout=15, message="condition was not met"):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            if predicate():
                return
        except (OSError, AssertionError) as exc:
            last_error = exc
        time.sleep(0.1)
    if last_error:
        raise AssertionError(f"{message}: {last_error}")
    raise AssertionError(message)


IN_CLOSE_WRITE = 0x00000008
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100


def open_manifest_monitor():
    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, f"inotify_init1 failed: errno {ctypes.get_errno()}"
    wd = libc.inotify_add_watch(fd, b"/home/user/dataset_links", IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE)
    assert wd >= 0, f"inotify_add_watch failed: errno {ctypes.get_errno()}"
    return fd


def collect_events(fd):
    events = []
    while True:
        try:
            block = os.read(fd, 65536)
        except BlockingIOError:
            break
        if not block:
            break
        offset = 0
        while offset + 16 <= len(block):
            wd, mask, cookie, length = struct.unpack_from("iIII", block, offset)
            offset += 16
            raw_name = block[offset:offset + length]
            offset += length
            name = raw_name.split(b"\0", 1)[0].decode("utf-8", "replace")
            events.append((name, mask))
    return events


def assert_final_state(expected):
    manifest = "/home/user/dataset_links/manifest.log"
    assert os.path.isfile(manifest) and not os.path.islink(manifest), "manifest.log is not a regular file"
    with open(manifest, "r") as f:
        lines = f.read().splitlines()
    assert lines == sorted(expected), f"Manifest mismatch: expected {sorted(expected)!r}, got {lines!r}"

    for name, wanted_content in expected.items():
        link = os.path.join("/home/user/dataset_links", name)
        assert os.path.islink(link), f"{link} is not a symbolic link"
        raw_target = os.readlink(link)
        assert os.path.isabs(raw_target), f"{link} does not contain an absolute target: {raw_target!r}"
        target = os.path.realpath(link)
        assert os.path.isfile(target), f"Symlink target does not exist as a file: {target}"
        assert os.path.basename(target) == name, f"Symlink target has the wrong basename: {target}"
        assert not target.startswith("/home/user/dataset_links/"), "Symlink points back into dataset_links"
        assert not target.startswith("/home/user/incoming/"), "Symlink points into the incoming directory"
        with open(target, "r") as f:
            actual_content = f.read()
        assert actual_content == wanted_content, f"Wrong extracted content for {name}"


def assert_atomic_manifest_events(events):
    manifest_events = [mask for name, mask in events if name == "manifest.log"]
    assert any(mask & IN_MOVED_TO for mask in manifest_events), \
        f"No runtime rename into manifest.log was observed; events were {events!r}"
    assert not any(mask & IN_CLOSE_WRITE for mask in manifest_events), \
        f"manifest.log was written directly instead of being replaced atomically; events were {events!r}"


def test_pipeline_execution():
    start_sh = "/home/user/start.sh"
    assert os.path.exists(start_sh), f"File {start_sh} does not exist."
    os.chmod(start_sh, 0o755)

    # Eliminate all prior output so a submission must create the directories and process these archives.
    shutil.rmtree("/home/user/incoming", ignore_errors=True)
    shutil.rmtree("/home/user/dataset_links", ignore_errors=True)
    try:
        os.remove("/home/user/organizer")
    except FileNotFoundError:
        pass

    proc = subprocess.Popen(["/bin/bash", start_sh], cwd="/home/user", start_new_session=True)
    monitors = []
    try:
        wait_until(lambda: os.path.isdir("/home/user/incoming") and os.path.isdir("/home/user/dataset_links"),
                   timeout=20, message="start.sh did not create the required directories")
        wait_until(lambda: os.path.isfile("/home/user/organizer"), timeout=20,
                   message="start.sh did not compile /home/user/organizer")
        with open("/home/user/organizer", "rb") as f:
            assert f.read(4) == b"\x7fELF", "/home/user/organizer is not a compiled ELF executable"
        wait_until(lambda: any(has_inotify_fd(pid) for pid in organizer_pids()), timeout=15,
                   message="No running /home/user/organizer process with an active inotify descriptor was found")

        # Preserve the original alpha/zeta case, but validate targets and contents and observe atomic replacement.
        first = {
            "alpha.csv": "id,value\n1,10\n",
            "zeta.csv": "id,value\n2,20\n",
        }
        monitor1 = open_manifest_monitor()
        monitors.append(monitor1)
        first_bytes = make_nested_zip(first)
        with open("/home/user/incoming/dataset_001.zip", "wb") as f:
            for offset in range(0, len(first_bytes), 97):
                f.write(first_bytes[offset:offset + 97])
                f.flush()
        wait_until(lambda: _state_matches(first), timeout=15,
                   message="The close-written archive was not processed correctly")
        time.sleep(0.5)
        assert_final_state(first)
        assert_atomic_manifest_events(collect_events(monitor1))

        # Add unpredictable filenames and contents through IN_MOVED_TO, requiring cumulative behavior.
        token = uuid.uuid4().hex
        second = {
            f"sample_{token[:9]}.csv": f"key,payload\nA,{uuid.uuid4().hex}\n",
            f"measure_{token[9:18]}.csv": f"x,y\n{uuid.uuid4().int % 100000},{uuid.uuid4().int % 100000}\n",
            f"result_{token[18:27]}.csv": f"name,value\n{token},{uuid.uuid4().hex}\n",
        }
        expected = dict(first)
        expected.update(second)
        monitor2 = open_manifest_monitor()
        monitors.append(monitor2)
        staged = f"/tmp/{uuid.uuid4().hex}.zip"
        with open(staged, "wb") as f:
            f.write(make_nested_zip(second))
        destination = f"/home/user/incoming/batch_{uuid.uuid4().hex}.zip"
        os.rename(staged, destination)

        wait_until(lambda: _state_matches(expected), timeout=15,
                   message="The randomly generated moved-in archive was not processed correctly")
        time.sleep(0.5)
        assert_final_state(expected)
        assert_atomic_manifest_events(collect_events(monitor2))
    finally:
        for fd in monitors:
            try:
                os.close(fd)
            except OSError:
                pass
        for pid in organizer_pids():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def _state_matches(expected):
    manifest = "/home/user/dataset_links/manifest.log"
    try:
        with open(manifest, "r") as f:
            if f.read().splitlines() != sorted(expected):
                return False
        for name, content in expected.items():
            link = os.path.join("/home/user/dataset_links", name)
            if not os.path.islink(link):
                return False
            with open(link, "r") as f:
                if f.read() != content:
                    return False
        return True
    except OSError:
        return False
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
