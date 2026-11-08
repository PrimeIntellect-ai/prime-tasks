#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt
export TZ=UTC

SCRIPT=/home/user/organize_docs.sh
if [ ! -f "$SCRIPT" ] || [ -L "$SCRIPT" ]; then
    exit 0
fi

python3 <<'PY' || exit 0
import base64
import io
import json
import os
import secrets
import shutil
import tarfile
import zipfile
from datetime import datetime, timezone

home = "/home/user"
incoming = os.path.join(home, "incoming_docs")
for path in [
    incoming,
    os.path.join(home, "quarantine"),
    os.path.join(home, "extracted"),
    os.path.join(home, "recent_docs"),
]:
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
if os.path.lexists(os.path.join(home, "summary.log")):
    os.unlink(os.path.join(home, "summary.log"))
os.makedirs(incoming, mode=0o777)

token = secrets.token_hex(8)
contents = {
    "docset1/old.md": f"Old documentation {token}\n".encode(),
    "docset1/new1.md": f"New documentation one {token}\n".encode(),
    "docset2/new2.md": f"New documentation two {token}\n".encode(),
    "docset3/old2.md": f"Old zipped documentation {token}\n".encode(),
    "docset3/new3.md": f"New zipped documentation {token}\n".encode(),
}
mtimes = {
    "docset1/old.md": int(datetime(2021, 5, 5, 12, 0, 0, tzinfo=timezone.utc).timestamp()),
    "docset1/new1.md": int(datetime(2023, 5, 5, 12, 0, 0, tzinfo=timezone.utc).timestamp()),
    "docset2/new2.md": int(datetime(2024, 1, 1, 10, 0, 0, tzinfo=timezone.utc).timestamp()),
    "docset3/old2.md": int(datetime(2022, 12, 31, 23, 59, 58, tzinfo=timezone.utc).timestamp()),
    "docset3/new3.md": int(datetime(2023, 1, 1, 0, 0, 2, tzinfo=timezone.utc).timestamp()),
}

def make_tar(path, members):
    with tarfile.open(path, "w:gz") as tf:
        for name in members:
            info = tarfile.TarInfo(name)
            info.size = len(contents[name])
            info.mtime = mtimes[name]
            info.mode = 0o644
            tf.addfile(info, io.BytesIO(contents[name]))

valid_archives = [
    f"manuals-{token}.tar.gz",
    f"guides-{token}.tar.gz",
    f"notes-{token}.zip",
]
make_tar(os.path.join(incoming, valid_archives[0]), ["docset1/old.md", "docset1/new1.md"])
make_tar(os.path.join(incoming, valid_archives[1]), ["docset2/new2.md"])
with zipfile.ZipFile(os.path.join(incoming, valid_archives[2]), "w", zipfile.ZIP_DEFLATED) as zf:
    for name in ["docset3/old2.md", "docset3/new3.md"]:
        dt = datetime.fromtimestamp(mtimes[name], timezone.utc)
        info = zipfile.ZipInfo(name, (dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        zf.writestr(info, contents[name])

corrupt_archives = [
    f"damaged-{token}-a.tar.gz",
    f"damaged-{token}-b.tar.gz",
    f"damaged-{token}-c.zip",
]
with open(os.path.join(incoming, corrupt_archives[0]), "wb") as f:
    f.write(("not a tar archive " + token).encode())
with open(os.path.join(incoming, corrupt_archives[1]), "wb") as f:
    f.write(os.urandom(1537))
with open(os.path.join(incoming, corrupt_archives[2]), "wb") as f:
    f.write(("not a zip archive " + token).encode())

manifest = {
    "valid_archives": valid_archives,
    "corrupt_archives": corrupt_archives,
    "files": {
        name: {
            "content": base64.b64encode(data).decode(),
            "mtime": mtimes[name],
        }
        for name, data in contents.items()
    },
    "recent": {
        "new1.md": "/home/user/extracted/docset1/new1.md",
        "new2.md": "/home/user/extracted/docset2/new2.md",
        "new3.md": "/home/user/extracted/docset3/new3.md",
    },
}
with open("/tmp/organize_expected.json", "w") as f:
    json.dump(manifest, f)
os.chmod("/tmp/organize_expected.json", 0o600)
PY

chown -R user:user /home/user/incoming_docs || exit 0
chmod 777 /home/user/incoming_docs || exit 0

if ! timeout 30s runuser -u user -- bash -c 'cd /home/user/incoming_docs && bash /home/user/organize_docs.sh' >/tmp/organize_docs.stdout 2>/tmp/organize_docs.stderr; then
    exit 0
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import stat

with open("/tmp/organize_expected.json") as f:
    EXPECTED = json.load(f)


def regular_file(path):
    return os.path.isfile(path) and not os.path.islink(path) and stat.S_ISREG(os.lstat(path).st_mode)


def test_quarantine_directory():
    quarantine_dir = "/home/user/quarantine"
    assert os.path.isdir(quarantine_dir), f"Directory {quarantine_dir} does not exist."
    expected_files = set(EXPECTED["corrupt_archives"])
    actual_files = set(os.listdir(quarantine_dir))
    assert expected_files.issubset(actual_files), f"Quarantine directory is missing files. Expected {expected_files}, found {actual_files}"
    assert actual_files == expected_files, f"Quarantine directory contains unexpected files. Expected {expected_files}, found {actual_files}"
    for filename in expected_files:
        assert regular_file(os.path.join(quarantine_dir, filename))


def test_incoming_archive_outcomes():
    incoming_dir = "/home/user/incoming_docs"
    assert os.path.isdir(incoming_dir)
    assert set(os.listdir(incoming_dir)) == set(EXPECTED["valid_archives"])


def test_extracted_directory():
    extracted_dir = "/home/user/extracted"
    assert os.path.isdir(extracted_dir), f"Directory {extracted_dir} does not exist."

    expected_files = [
        "docset1/old.md",
        "docset1/new1.md",
        "docset2/new2.md",
        "docset3/old2.md",
        "docset3/new3.md",
    ]
    actual_files = set()
    for root, dirs, files in os.walk(extracted_dir, followlinks=False):
        for filename in files:
            actual_files.add(os.path.relpath(os.path.join(root, filename), extracted_dir))
    assert actual_files == set(expected_files), f"Extracted files differ: expected {set(expected_files)}, found {actual_files}"

    for rel_path in expected_files:
        full_path = os.path.join(extracted_dir, rel_path)
        assert regular_file(full_path), f"Extracted file {full_path} is missing or is not a regular file."
        expected = EXPECTED["files"][rel_path]
        with open(full_path, "rb") as f:
            assert f.read() == base64.b64decode(expected["content"]), f"Incorrect content in {full_path}"
        assert int(os.stat(full_path).st_mtime) == expected["mtime"], f"Incorrect modification time for {full_path}"


def test_hardlinks():
    hardlinks_dir = "/home/user/recent_docs/hardlinks"
    assert os.path.isdir(hardlinks_dir), f"Directory {hardlinks_dir} does not exist."
    expected_links = EXPECTED["recent"]
    actual_files = set(os.listdir(hardlinks_dir))
    assert actual_files == set(expected_links), f"Hardlinks directory contains incorrect files. Expected {set(expected_links)}, found {actual_files}"

    for filename, target_path in expected_links.items():
        link_path = os.path.join(hardlinks_dir, filename)
        assert regular_file(link_path), f"Hard link {link_path} is missing."
        link_stat = os.stat(link_path)
        target_stat = os.stat(target_path)
        assert (link_stat.st_dev, link_stat.st_ino) == (target_stat.st_dev, target_stat.st_ino), f"File {link_path} is not a hardlink to {target_path}."


def test_symlinks():
    symlinks_dir = "/home/user/recent_docs/symlinks"
    assert os.path.isdir(symlinks_dir), f"Directory {symlinks_dir} does not exist."
    expected_links = EXPECTED["recent"]
    actual_files = set(os.listdir(symlinks_dir))
    assert actual_files == set(expected_links), f"Symlinks directory contains incorrect files. Expected {set(expected_links)}, found {actual_files}"

    for filename, target_path in expected_links.items():
        link_path = os.path.join(symlinks_dir, filename)
        assert os.path.islink(link_path), f"File {link_path} is not a symlink."
        actual_target = os.readlink(link_path)
        assert actual_target == target_path, f"Symlink {link_path} points to {actual_target}, expected {target_path}."


def test_summary_log():
    log_path = "/home/user/summary.log"
    assert regular_file(log_path), f"Log file {log_path} is missing."
    with open(log_path, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == 3, f"Summary log must contain exactly 3 lines, found {len(lines)}."
    assert lines[0] == "3", f"Line 1 of summary log should be '3', found '{lines[0]}'."
    assert lines[1] == "3", f"Line 2 of summary log should be '3', found '{lines[1]}'."
    assert lines[2] == "3", f"Line 3 of summary log should be '3', found '{lines[2]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
