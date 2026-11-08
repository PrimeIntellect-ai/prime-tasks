#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import shutil
import struct
import subprocess
import tarfile
import tempfile
import io


def test_01_script_exists_and_uses_rename():
    script_path = "/home/user/process_artifacts.py"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    with open(script_path, 'r') as f:
        content = f.read()

    assert "rename(" in content or "replace(" in content, "Script does not appear to use atomic rename (e.g. os.rename, Path.rename) as required."


def test_02_release_archive_exists():
    archive_path = "/home/user/outgoing/release.tar.gz"
    assert os.path.isfile(archive_path), f"Output archive {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"Output file {archive_path} is not a valid tar archive."


def test_03_release_archive_contents():
    archive_path = "/home/user/outgoing/release.tar.gz"

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(archive_path, 'r:gz') as tar:
            tar.extractall(path=tmpdir)

        metadata_path = os.path.join(tmpdir, "release", "metadata.txt")
        assert os.path.isfile(metadata_path), "release/metadata.txt is missing from the archive."
        with open(metadata_path, 'r') as f:
            metadata_content = f.read()
        expected_metadata = "Release Version: 2.4.1\nDate: 2023-10-15\nTarget: production\n"
        assert metadata_content == expected_metadata, f"metadata.txt content is incorrect. Got:\n{metadata_content}"

        bin_meta_path = os.path.join(tmpdir, "release", "artifacts", "bin1.meta")
        assert os.path.isfile(bin_meta_path), "release/artifacts/bin1.meta is missing from the archive."
        with open(bin_meta_path, 'r') as f:
            bin_meta_content = f.read()
        expected_bin_meta = "Binary: bin1\nVersion: 2.4.1\nEnv: production\n"
        assert bin_meta_content == expected_bin_meta, f"bin1.meta content is incorrect. Got:\n{bin_meta_content}"

        bin_dat_path = os.path.join(tmpdir, "release", "artifacts", "bin1.dat")
        assert os.path.isfile(bin_dat_path), "release/artifacts/bin1.dat is missing from the archive."
        with open(bin_dat_path, 'rb') as f:
            bin_dat_content = f.read()
        expected_bin_dat = b'\x00\x01\x02\x03\x04'
        assert bin_dat_content == expected_bin_dat, f"bin1.dat content is corrupted. Expected {expected_bin_dat}, got {bin_dat_content}"


def _add_tar_file(tar, name, data):
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))


def _directory_snapshot():
    result = set()
    for root in ("/tmp", "/home/user"):
        for current, dirs, _ in os.walk(root):
            dirs[:] = [d for d in dirs if d != "__pycache__"]
            result.update(os.path.join(current, d) for d in dirs)
    return result


def test_04_execute_script_on_derived_archive_and_observe_atomic_rename():
    token = secrets.token_hex(8)
    root = f"nightly-{token}"
    input_files = {
        f"{root}/docs/readme.txt": (
            f"token={token}\nversion=${{VERSION}}\ndate=${{BUILD_DATE}}\n"
            f"environment=${{ENVIRONMENT}}\nagain=${{VERSION}}\nunknown=${{UNSET}}\n"
        ).encode(),
        f"{root}/packages/deep/component.meta": (
            f"component={token}\n${{ENVIRONMENT}}/${{BUILD_DATE}}/${{VERSION}}\n"
        ).encode(),
        f"{root}/packages/payload-{token}.bin": bytes(range(256)) + token.encode() + b"\x00\xff",
        f"{root}/literal.cfg": b"${VERSION} must remain in non-txt/meta files\n",
    }
    expected_files = {
        name: (data.replace(b"${VERSION}", b"2.4.1")
                   .replace(b"${BUILD_DATE}", b"2023-10-15")
                   .replace(b"${ENVIRONMENT}", b"production")
               if name.endswith((".txt", ".meta")) else data)
        for name, data in input_files.items()
    }

    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w:gz") as tar:
        for name, data in input_files.items():
            _add_tar_file(tar, name, data)
    encoded = bytes(byte ^ 0x5A for byte in stream.getvalue())
    with open("/home/user/incoming/repository.dat", "wb") as f:
        f.write(encoded)

    outgoing = "/home/user/outgoing"
    for entry in os.listdir(outgoing):
        path = os.path.join(outgoing, entry)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    verifier_tmp = f"/tmp/verifier-agent-tmp-{token}"
    os.mkdir(verifier_tmp)
    dirs_before = _directory_snapshot()

    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK)
    assert fd >= 0, os.strerror(ctypes.get_errno())
    IN_CLOSE_WRITE = 0x00000008
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    IN_CREATE = 0x00000100
    watch_mask = IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE
    wd = libc.inotify_add_watch(fd, outgoing.encode(), watch_mask)
    assert wd >= 0, os.strerror(ctypes.get_errno())

    env = os.environ.copy()
    env["TMPDIR"] = verifier_tmp
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    try:
        result = subprocess.run(
            ["python3", "/home/user/process_artifacts.py"],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )

        raw_events = bytearray()
        while True:
            try:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                raw_events.extend(chunk)
            except BlockingIOError:
                break
    finally:
        os.close(fd)

    assert result.returncode == 0, (
        f"process_artifacts.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    events = []
    offset = 0
    header = struct.Struct("iIII")
    while offset + header.size <= len(raw_events):
        event_wd, mask, cookie, name_len = header.unpack_from(raw_events, offset)
        offset += header.size
        name_bytes = raw_events[offset:offset + name_len]
        offset += name_len
        name = bytes(name_bytes).split(b"\0", 1)[0].decode(errors="replace")
        events.append((mask, cookie, name))

    moves_from = {(cookie, name) for mask, cookie, name in events if mask & IN_MOVED_FROM}
    moves_to_release = [cookie for mask, cookie, name in events
                        if mask & IN_MOVED_TO and name == "release.tar.gz"]
    matching_sources = [name for cookie, name in moves_from
                        if cookie in moves_to_release and name != "release.tar.gz"]
    assert matching_sources, (
        "No atomic rename from a temporary file in /home/user/outgoing/ to "
        "release.tar.gz was observed."
    )
    created_names = {name for mask, _, name in events if mask & IN_CREATE}
    assert any(name in created_names for name in matching_sources), (
        "The atomically renamed source was not created as a temporary file in "
        "/home/user/outgoing/."
    )

    archive_path = os.path.join(outgoing, "release.tar.gz")
    assert os.path.isfile(archive_path), f"Output archive {archive_path} does not exist after executing the script."
    assert tarfile.is_tarfile(archive_path), f"Output file {archive_path} is not a valid tar archive."
    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()
        assert all(member.isdir() or member.isfile() for member in members), "Output contains unexpected special archive members."
        actual_names = {member.name.rstrip("./") for member in members if member.isfile()}
        assert actual_names == set(expected_files), (
            f"Archive layout was not preserved. Expected files {set(expected_files)}, got {actual_names}"
        )
        for name, expected in expected_files.items():
            extracted = tar.extractfile(name)
            assert extracted is not None, f"Could not read {name} from output archive."
            actual = extracted.read()
            assert actual == expected, f"Incorrect output content for {name}."

    assert os.listdir(outgoing) == ["release.tar.gz"], "Temporary files were not cleaned from /home/user/outgoing/."
    assert os.listdir(verifier_tmp) == [], "Temporary extraction files or directories were not cleaned up."
    dirs_after = _directory_snapshot()
    assert dirs_after == dirs_before, f"Temporary directories were not cleaned up: {sorted(dirs_after - dirs_before)}"
    os.rmdir(verifier_tmp)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
