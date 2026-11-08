#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import stat
import shutil
import subprocess
import tarfile
import tempfile
import uuid
import zipfile

from PIL import Image

SCRIPT_PATH = "/home/user/secure_extract.py"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
VIDEO_PATH = "/app/incident_record.mp4"
PASSWORD = "42"


def run_tool(archive, dest, password=PASSWORD):
    return subprocess.run(
        ["python3", SCRIPT_PATH, str(archive), str(dest), str(password)],
        capture_output=True,
        text=True,
        timeout=30,
    )


def assert_accept(result):
    assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
    assert result.stdout.strip() == "ACCEPT", (result.stdout, result.stderr)


def assert_reject(result):
    assert result.returncode == 1, (result.returncode, result.stdout, result.stderr)
    assert result.stdout.strip() == "REJECT", (result.stdout, result.stderr)


def regular_files(root):
    found = []
    for base, dirs, files in os.walk(root, followlinks=False):
        for name in files:
            path = os.path.join(base, name)
            if os.path.isfile(path) and not os.path.islink(path):
                found.append(path)
    return found


def tar_bytes(entries, gz=True):
    output = io.BytesIO()
    mode = "w:gz" if gz else "w"
    with tarfile.open(fileobj=output, mode=mode) as tf:
        for entry in entries:
            kind = entry[0]
            if kind == "file":
                _, name, data = entry
                info = tarfile.TarInfo(name)
                info.size = len(data)
                info.mode = 0o640
                tf.addfile(info, io.BytesIO(data))
            elif kind == "dir":
                _, name = entry
                info = tarfile.TarInfo(name)
                info.type = tarfile.DIRTYPE
                info.mode = 0o750
                tf.addfile(info)
            elif kind == "symlink":
                _, name, target = entry
                info = tarfile.TarInfo(name)
                info.type = tarfile.SYMTYPE
                info.linkname = target
                tf.addfile(info)
            elif kind == "hardlink":
                _, name, target = entry
                info = tarfile.TarInfo(name)
                info.type = tarfile.LNKTYPE
                info.linkname = target
                tf.addfile(info)
    return output.getvalue()


def zip_bytes(entries):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as zf:
        for entry in entries:
            kind = entry[0]
            if kind == "file":
                _, name, data = entry
                zf.writestr(name, data)
            elif kind == "symlink":
                _, name, target = entry
                info = zipfile.ZipInfo(name)
                info.create_system = 3
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                zf.writestr(info, target)
    return output.getvalue()


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_video_password_is_derived_from_extracted_frames():
    assert os.path.isfile(VIDEO_PATH)
    frame_dir = tempfile.mkdtemp(prefix="decoded_frames_")
    try:
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", VIDEO_PATH,
             "-vsync", "0", os.path.join(frame_dir, "frame_%05d.png")],
            check=True,
            timeout=60,
        )
        names = sorted(os.listdir(frame_dir))
        assert names, "ffmpeg extracted no frames"
        red_frames = 0
        for name in names:
            with Image.open(os.path.join(frame_dir, name)).convert("RGB") as image:
                r, g, b = image.getpixel((320, 240))
                # H.264/YUV conversion can move 255 by a few values after decoding.
                if r >= 240 and g <= 20 and b <= 20:
                    red_frames += 1
        assert str(red_frames) == PASSWORD
    finally:
        shutil.rmtree(frame_dir)


def test_adversarial_corpus():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Clean corpus missing at {CLEAN_CORPUS_DIR}"
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Evil corpus missing at {EVIL_CORPUS_DIR}"

    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR)
                   if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR)
                  if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]

    assert len(clean_files) > 0, "No files found in clean corpus."
    assert len(evil_files) > 0, "No files found in evil corpus."

    failed_clean = []
    failed_evil = []

    for clean_file in clean_files:
        dest_dir = tempfile.mkdtemp()
        try:
            result = run_tool(clean_file, dest_dir)
            if result.returncode != 0 or result.stdout.strip() != "ACCEPT":
                failed_clean.append((os.path.basename(clean_file), result.returncode, result.stdout.strip()))
            else:
                contents = [open(p, "rb").read() for p in regular_files(dest_dir)]
                if b"clean data\n" not in contents:
                    failed_clean.append((os.path.basename(clean_file), result.returncode, "missing extracted data"))
        finally:
            shutil.rmtree(dest_dir)

    for evil_file in evil_files:
        dest_dir = tempfile.mkdtemp()
        try:
            result = run_tool(evil_file, dest_dir)
            if result.returncode != 1 or result.stdout.strip() != "REJECT" or os.listdir(dest_dir):
                failed_evil.append((os.path.basename(evil_file), result.returncode, result.stdout.strip()))
        finally:
            shutil.rmtree(dest_dir)

    error_messages = []
    if failed_clean:
        error_messages.append(f"{len(failed_clean)} of {len(clean_files)} clean archives rejected or failed:")
        for f, rc, out in failed_clean:
            error_messages.append(f"  - {f} (exit code: {rc}, stdout: '{out}')")
    if failed_evil:
        error_messages.append(f"{len(failed_evil)} of {len(evil_files)} evil archives bypassed or failed to reject properly:")
        for f, rc, out in failed_evil:
            error_messages.append(f"  - {f} (exit code: {rc}, stdout: '{out}')")
    assert not failed_clean and not failed_evil, "\n".join(error_messages)


def test_randomized_clean_tar_preserves_safe_links():
    root = tempfile.mkdtemp(prefix="case_")
    try:
        archive = os.path.join(root, uuid.uuid4().hex + ".tar.gz")
        payload = ("payload-" + uuid.uuid4().hex).encode()
        data = tar_bytes([
            ("dir", "tree"),
            ("file", "tree/value.bin", payload),
            ("symlink", "tree/safe_alias", "value.bin"),
            ("hardlink", "tree/safe_hard", "tree/value.bin"),
        ])
        open(archive, "wb").write(data)
        dest = os.path.join(root, "out_" + uuid.uuid4().hex)
        os.mkdir(dest)
        assert_accept(run_tool(archive, dest))
        value = os.path.join(dest, "tree", "value.bin")
        alias = os.path.join(dest, "tree", "safe_alias")
        hard = os.path.join(dest, "tree", "safe_hard")
        assert open(value, "rb").read() == payload
        assert os.path.islink(alias)
        assert open(alias, "rb").read() == payload
        assert os.path.commonpath([os.path.realpath(alias), os.path.realpath(dest)]) == os.path.realpath(dest)
        assert os.stat(value).st_ino == os.stat(hard).st_ino
    finally:
        shutil.rmtree(root)


def test_randomized_clean_zip_and_three_level_recursive_encrypted_extraction():
    root = tempfile.mkdtemp(prefix="case_")
    try:
        token = uuid.uuid4().hex.encode()
        deep_name = uuid.uuid4().hex + ".tar.gz"
        middle_name = uuid.uuid4().hex + ".zip"
        deep = tar_bytes([("file", "deep/path/value.dat", token)])
        middle = zip_bytes([("file", deep_name, deep), ("file", "middle-note", b"middle")])
        source = os.path.join(root, "src_" + uuid.uuid4().hex)
        os.mkdir(source)
        open(os.path.join(source, middle_name), "wb").write(middle)
        outer = os.path.join(root, uuid.uuid4().hex + ".zip")
        subprocess.run(
            ["7z", "a", "-tzip", "-p" + PASSWORD, outer, middle_name],
            cwd=source,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
            timeout=30,
        )
        dest = os.path.join(root, "out_" + uuid.uuid4().hex)
        os.mkdir(dest)
        assert_accept(run_tool(outer, dest))
        assert token in [open(p, "rb").read() for p in regular_files(dest)]
    finally:
        shutil.rmtree(root)


def test_randomized_safe_zip_symlink():
    root = tempfile.mkdtemp(prefix="case_")
    try:
        archive = os.path.join(root, uuid.uuid4().hex + ".zip")
        payload = uuid.uuid4().hex.encode()
        open(archive, "wb").write(zip_bytes([
            ("file", "folder/value", payload),
            ("symlink", "folder/alias", "value"),
        ]))
        dest = os.path.join(root, "out_" + uuid.uuid4().hex)
        os.mkdir(dest)
        assert_accept(run_tool(archive, dest))
        alias = os.path.join(dest, "folder", "alias")
        assert os.path.islink(alias)
        assert open(alias, "rb").read() == payload
        assert os.path.commonpath([os.path.realpath(alias), os.path.realpath(dest)]) == os.path.realpath(dest)
    finally:
        shutil.rmtree(root)


def reject_archive_and_require_atomicity(archive, root, outside_checks=()):
    dest = os.path.join(root, "out_" + uuid.uuid4().hex)
    os.mkdir(dest)
    result = run_tool(archive, dest)
    assert_reject(result)
    assert os.listdir(dest) == [], "a rejected archive extracted destination entries"
    for path, expected in outside_checks:
        if expected is None:
            assert not os.path.lexists(path), f"archive wrote outside destination: {path}"
        else:
            assert open(path, "rb").read() == expected


def test_randomized_zip_traversal_and_absolute_paths_are_atomic():
    root = tempfile.mkdtemp(prefix="case_")
    absolute = os.path.join("/tmp", "escape_" + uuid.uuid4().hex)
    try:
        archive = os.path.join(root, uuid.uuid4().hex + ".zip")
        open(archive, "wb").write(zip_bytes([
            ("file", "ordinary-first", b"must-not-appear"),
            ("file", "../escaped", b"bad"),
            ("file", absolute, b"bad"),
        ]))
        reject_archive_and_require_atomicity(archive, root, [(absolute, None)])
    finally:
        if os.path.lexists(absolute):
            os.unlink(absolute)
        shutil.rmtree(root)


def test_randomized_tar_symlink_pivot_is_rejected_atomically():
    root = tempfile.mkdtemp(prefix="case_")
    outside_dir = os.path.join(root, "outside_" + uuid.uuid4().hex)
    os.mkdir(outside_dir)
    outside_file = os.path.join(outside_dir, "pwned")
    try:
        archive = os.path.join(root, uuid.uuid4().hex + ".tar.gz")
        relative_target = os.path.relpath(outside_dir, os.path.join(root, "placeholder"))
        data = tar_bytes([
            ("file", "ordinary-first", b"must-not-appear"),
            ("symlink", "pivot", relative_target),
            ("file", "pivot/pwned", b"bad"),
        ])
        open(archive, "wb").write(data)
        reject_archive_and_require_atomicity(archive, root, [(outside_file, None)])
    finally:
        shutil.rmtree(root)


def test_randomized_tar_external_symlink_and_hardlink_are_rejected():
    root = tempfile.mkdtemp(prefix="case_")
    outside = os.path.join(root, "protected_" + uuid.uuid4().hex)
    protected = b"unchanged-" + uuid.uuid4().hex.encode()
    open(outside, "wb").write(protected)
    try:
        for entries in [
            [("file", "safe", b"x"), ("symlink", "bad", outside)],
            [("file", "safe", b"x"), ("hardlink", "bad", "../" + os.path.basename(outside))],
        ]:
            archive = os.path.join(root, uuid.uuid4().hex + ".tar.gz")
            open(archive, "wb").write(tar_bytes(entries))
            reject_archive_and_require_atomicity(archive, root, [(outside, protected)])
    finally:
        shutil.rmtree(root)


def test_randomized_nested_malicious_archive_is_rejected_atomically():
    root = tempfile.mkdtemp(prefix="case_")
    escaped = os.path.join(root, "escaped_" + uuid.uuid4().hex)
    try:
        inner_name = uuid.uuid4().hex + ".zip"
        inner = zip_bytes([
            ("file", "normal", b"normal"),
            ("file", "../../" + os.path.basename(escaped), b"bad"),
        ])
        outer = os.path.join(root, uuid.uuid4().hex + ".zip")
        open(outer, "wb").write(zip_bytes([
            ("file", "ordinary-first", b"must-not-appear"),
            ("file", inner_name, inner),
        ]))
        reject_archive_and_require_atomicity(outer, root, [(escaped, None)])
    finally:
        shutil.rmtree(root)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
