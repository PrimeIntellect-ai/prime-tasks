#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'RUN_EOF' > /tmp/run_submission.py
import hashlib
import json
import os
import secrets
import shlex
import shutil
import stat
import subprocess
import tarfile
import uuid

ROOT = "/home/user/project_data"
MANIFEST = "/home/user/backup_manifest.json"
ARCHIVE = "/home/user/project_backup.tar.gz"

# Add unpredictable cases after the agent has acted, then rerun its script.
tag = uuid.uuid4().hex
extra_dir = os.path.join(ROOT, "generated_" + tag, "nested")
os.makedirs(extra_dir, exist_ok=True)
with open(os.path.join(extra_dir, "payload.bin"), "wb") as f:
    f.write(secrets.token_bytes(193) + tag.encode())
os.symlink(os.path.relpath(os.path.join(extra_dir, "payload.bin"), os.path.join(ROOT, "links")),
           os.path.join(ROOT, "links", "valid_" + tag))
a = os.path.join(ROOT, "links", "cycle_a_" + tag)
b = os.path.join(ROOT, "links", "cycle_b_" + tag)
c = os.path.join(ROOT, "links", "cycle_c_" + tag)
os.symlink(os.path.basename(b), a)
os.symlink(os.path.basename(c), b)
os.symlink(os.path.basename(a), c)
self_link = os.path.join(ROOT, "links", "self_" + tag)
os.symlink(os.path.basename(self_link), self_link)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def expected_state():
    files = {}
    seen = set()
    symlinks = []
    for base, dirs, names in os.walk(ROOT, followlinks=False):
        for name in dirs + names:
            path = os.path.join(base, name)
            try:
                mode = os.lstat(path).st_mode
            except OSError:
                continue
            if stat.S_ISLNK(mode):
                symlinks.append(path)
            elif stat.S_ISREG(mode):
                st = os.stat(path, follow_symlinks=False)
                ident = (st.st_dev, st.st_ino)
                if ident not in seen:
                    seen.add(ident)
                    rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
                    with open(path, "rb") as f:
                        files[rel] = sha(f.read())

    cycle_members = set()
    for start in symlinks:
        chain = []
        positions = {}
        current = os.path.normpath(start)
        while os.path.islink(current):
            if current in positions:
                cycle_members.update(chain[positions[current]:])
                break
            positions[current] = len(chain)
            chain.append(current)
            try:
                target = os.readlink(current)
            except OSError:
                break
            if os.path.isabs(target):
                current = os.path.normpath(target)
            else:
                current = os.path.normpath(os.path.join(os.path.dirname(current), target))
    circular = sorted(os.path.relpath(p, ROOT).replace(os.sep, "/") for p in cycle_members)
    return files, circular


def valid_outputs():
    expected_files, expected_circular = expected_state()
    try:
        with open(MANIFEST, "r", encoding="utf-8") as f:
            manifest = json.load(f)
        if not isinstance(manifest, dict) or set(manifest) != {"files", "circular_links"}:
            return False
        if manifest["files"] != expected_files or manifest["circular_links"] != expected_circular:
            return False
        with tarfile.open(ARCHIVE, "r:gz") as tar:
            members = tar.getmembers()
            if any(not m.isfile() for m in members):
                return False
            names = [m.name for m in members]
            if len(names) != len(set(names)) or set(names) != set(expected_files):
                return False
            for member in members:
                extracted = tar.extractfile(member)
                if extracted is None or sha(extracted.read()) != expected_files[member.name]:
                    return False
        return True
    except Exception:
        return False


def command_for(path, data):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".py":
        return ["python3", path]
    if ext in (".sh", ".bash"):
        return ["bash", path]
    if ext == ".rb" and shutil.which("ruby"):
        return ["ruby", path]
    first = data.splitlines()[0].decode("utf-8", "ignore") if data.splitlines() else ""
    if first.startswith("#!"):
        parts = shlex.split(first[2:].strip())
        if parts and os.path.basename(parts[0]) == "env":
            parts = parts[1:]
        return parts + [path] if parts else None
    if os.access(path, os.X_OK):
        return [path]
    return None

candidates = []
for top in ("/home/user", "/root", "/tmp", "/workspace"):
    if not os.path.isdir(top):
        continue
    for base, dirs, names in os.walk(top):
        dirs[:] = [d for d in dirs if d not in {".cache", ".git", "__pycache__"}]
        for name in names:
            path = os.path.join(base, name)
            if path in {MANIFEST, ARCHIVE, "/tmp/run_submission.py", "/tmp/test_final_state.py"}:
                continue
            try:
                if not os.path.isfile(path) or os.path.getsize(path) > 2_000_000:
                    continue
                with open(path, "rb") as f:
                    data = f.read()
            except OSError:
                continue
            lower = data.lower()
            if b"project_data" not in lower or b"backup_manifest" not in lower or b"project_backup" not in lower:
                continue
            cmd = command_for(path, data)
            if cmd:
                candidates.append((path, cmd))

for path, cmd in sorted(candidates):
    for output in (MANIFEST, ARCHIVE):
        try:
            os.remove(output)
        except FileNotFoundError:
            pass
    try:
        subprocess.run(cmd, cwd=os.path.dirname(path) or "/", timeout=30,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    except Exception:
        continue
    if valid_outputs():
        raise SystemExit(0)

raise SystemExit("No submitted script produced correct outputs for the augmented fixture")
RUN_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import stat
import tarfile

MANIFEST_PATH = "/home/user/backup_manifest.json"
ARCHIVE_PATH = "/home/user/project_backup.tar.gz"
PROJECT_DATA_DIR = "/home/user/project_data"


def compute_sha256(file_path):
    hasher = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def derive_expected():
    files = {}
    seen = set()
    links = []
    for base, dirs, names in os.walk(PROJECT_DATA_DIR, followlinks=False):
        for name in dirs + names:
            path = os.path.join(base, name)
            mode = os.lstat(path).st_mode
            if stat.S_ISLNK(mode):
                links.append(path)
            elif stat.S_ISREG(mode):
                st = os.stat(path, follow_symlinks=False)
                ident = (st.st_dev, st.st_ino)
                if ident not in seen:
                    seen.add(ident)
                    rel = os.path.relpath(path, PROJECT_DATA_DIR).replace(os.sep, "/")
                    files[rel] = compute_sha256(path)

    members = set()
    for start in links:
        chain, positions = [], {}
        current = os.path.normpath(start)
        while os.path.islink(current):
            if current in positions:
                members.update(chain[positions[current]:])
                break
            positions[current] = len(chain)
            chain.append(current)
            target = os.readlink(current)
            current = os.path.normpath(target if os.path.isabs(target) else
                                       os.path.join(os.path.dirname(current), target))
    circular = sorted(os.path.relpath(p, PROJECT_DATA_DIR).replace(os.sep, "/") for p in members)
    return files, circular


def load_manifest():
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def test_manifest_exists_and_valid_json():
    assert os.path.isfile(MANIFEST_PATH)
    manifest = load_manifest()
    assert isinstance(manifest, dict)
    assert "files" in manifest
    assert "circular_links" in manifest
    assert set(manifest) == {"files", "circular_links"}


def test_manifest_files_content():
    manifest = load_manifest()
    expected, _ = derive_expected()
    assert isinstance(manifest["files"], dict)
    assert manifest["files"] == expected
    for rel_path in ("src/hello.txt", "src/config.txt", "assets/blob.bin"):
        assert rel_path in manifest["files"]
        assert manifest["files"][rel_path] == compute_sha256(os.path.join(PROJECT_DATA_DIR, rel_path))


def test_manifest_circular_links_content():
    manifest = load_manifest()
    _, expected = derive_expected()
    circular = manifest["circular_links"]
    assert isinstance(circular, list)
    assert circular == sorted(circular)
    assert circular == expected
    for rel_path in ("links/loop_a", "links/loop_b", "links/loop_c", "links/self_loop"):
        assert rel_path in circular


def test_archive_exists_and_valid():
    assert os.path.isfile(ARCHIVE_PATH)
    assert tarfile.is_tarfile(ARCHIVE_PATH)
    with open(ARCHIVE_PATH, "rb") as f:
        assert f.read(2) == b"\x1f\x8b"


def test_archive_contents_and_bytes():
    expected, _ = derive_expected()
    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getmembers()
        assert all(member.isfile() for member in members)
        names = [member.name for member in members]
        assert len(names) == len(set(names))
        assert set(names) == set(expected)
        for baseline in ("src/hello.txt", "src/config.txt", "assets/blob.bin"):
            assert baseline in names
        for member in members:
            stream = tar.extractfile(member)
            assert stream is not None
            assert hashlib.sha256(stream.read()).hexdigest() == expected[member.name]
TEST_EOF

if python3 /tmp/run_submission.py 2>&1 && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
