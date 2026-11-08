#!/bin/bash
set +e
mkdir -p /logs/verifier

run_checks() {
    python3 <<'PY' || return 1
import io
import os
import shutil
import tarfile
import time
import zipfile

incoming = "/home/user/incoming"
shutil.rmtree(incoming, ignore_errors=True)
os.makedirs(incoming, exist_ok=True)

with open(os.path.join(incoming, "submissions.log"), "w") as f:
    f.write("""ID: sub_001
Status: APPROVED
File: proj1.tar.gz

ID: sub_002
Status: REJECTED
File: proj2.zip

ID: sub_003
Status: APPROVED
File: proj3.zip

ID: sub_004
Status: APPROVED
File: proj4.tar.gz

ID: sub_005
Status: APPROVED
File: proj5.zip
""")

now = time.time()
with tarfile.open(os.path.join(incoming, "proj1.tar.gz"), "w:gz") as tf:
    for name, data, mtime in [
        ("proj1/main.py", b"print('hello')\n", now - 2*86400),
        ("proj1/README.md", b"readme\n", now - 10*86400),
    ]:
        ti = tarfile.TarInfo(name)
        ti.size = len(data)
        ti.mtime = mtime
        tf.addfile(ti, io.BytesIO(data))

with zipfile.ZipFile(os.path.join(incoming, "proj2.zip"), "w") as zf:
    zf.writestr("proj2/ignore.txt", "ignored\n")

with zipfile.ZipFile(os.path.join(incoming, "proj3.zip"), "w") as zf:
    zf.writestr("../../../evil.sh", "echo malicious\n")
    zf.writestr("normal.txt", "normal\n")

with tarfile.open(os.path.join(incoming, "proj4.tar.gz"), "w:gz") as tf:
    data = b"evil"
    ti = tarfile.TarInfo("../../etc/passwd_fake")
    ti.size = len(data)
    ti.mtime = now
    tf.addfile(ti, io.BytesIO(data))

with zipfile.ZipFile(os.path.join(incoming, "proj5.zip"), "w") as zf:
    for name, data, age in [
        ("proj5/old.py", b"print('old')\n", 20),
        ("proj5/new.py", b"print('new')\n", 1),
    ]:
        zi = zipfile.ZipInfo(name, time.localtime(now - age*86400)[:6])
        zf.writestr(zi, data)
PY

    rm -rf /home/user/projects /home/user/recent_code /home/user/summary.txt
    mkdir -p /home/user/projects /home/user/recent_code
    rm -f /home/evil.sh /etc/passwd_fake

    cat <<'PY' > /tmp/test_original_state.py
import os

def test_script_exists_and_executable():
    script_path = "/home/user/organize_projects.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

def test_extracted_projects():
    sub_001_dir = "/home/user/projects/sub_001"
    sub_005_dir = "/home/user/projects/sub_005"
    assert os.path.isdir(sub_001_dir), f"Safe project sub_001 was not extracted to {sub_001_dir}."
    assert os.path.isdir(sub_005_dir), f"Safe project sub_005 was not extracted to {sub_005_dir}."
    sub_001_files = []
    for root, _, files in os.walk(sub_001_dir):
        sub_001_files.extend(files)
    assert "main.py" in sub_001_files, "main.py not found in extracted sub_001."
    sub_005_files = []
    for root, _, files in os.walk(sub_005_dir):
        sub_005_files.extend(files)
    assert "new.py" in sub_005_files, "new.py not found in extracted sub_005."
    assert "old.py" in sub_005_files, "old.py not found in extracted sub_005."

def test_malicious_and_rejected_not_extracted():
    not_expected_dirs = [
        "/home/user/projects/sub_002",
        "/home/user/projects/sub_003",
        "/home/user/projects/sub_004",
    ]
    for d in not_expected_dirs:
        assert not os.path.exists(d), f"Directory {d} should not exist (it was malicious or rejected)."

def test_recent_code_copied():
    recent_dir = "/home/user/recent_code"
    assert os.path.isdir(recent_dir), f"Directory {recent_dir} does not exist."
    expected_files = ["main.py", "new.py"]
    actual_files = os.listdir(recent_dir)
    for ef in expected_files:
        assert ef in actual_files, f"Recent python file {ef} was not copied to {recent_dir}."
    assert "old.py" not in actual_files, "old.py was copied, but it is older than 7 days."

def test_summary_report():
    summary_path = "/home/user/summary.txt"
    assert os.path.isfile(summary_path), f"Summary report {summary_path} does not exist."
    with open(summary_path, "r") as f:
        content = f.read().strip()
    expected_lines = [
        "Safe Extracted: 2",
        "Malicious Found: 2",
        "Recent Python Files: 2",
    ]
    for line in expected_lines:
        assert line in content, f"Expected line '{line}' not found in summary report."
PY

    test -f /home/user/organize_projects.sh || return 1
    test -x /home/user/organize_projects.sh || return 1
    timeout 30s /home/user/organize_projects.sh >/tmp/organize-original.out 2>/tmp/organize-original.err || return 1
    python3 -m pytest /tmp/test_original_state.py -x --tb=short || return 1
    test ! -e /home/evil.sh || return 1
    test ! -e /etc/passwd_fake || return 1

    python3 <<'PY' || return 1
import io
import json
import os
import secrets
import shutil
import tarfile
import time
import zipfile

incoming = "/home/user/incoming"
shutil.rmtree(incoming, ignore_errors=True)
os.makedirs(incoming, exist_ok=True)

token = secrets.token_hex(6)
now = time.time()
safe_count = 1 + secrets.randbelow(3)
malicious_count = 1 + secrets.randbelow(3)
records = []
expected_projects = []
recent = {}
old_names = []
markers = []

def zip_write(zf, name, data, when):
    zi = zipfile.ZipInfo(name, time.localtime(when)[:6])
    zf.writestr(zi, data)

for i in range(safe_count):
    sid = f"safe_{token}_{i}"
    ext = ".tar.gz" if i % 2 == 0 else ".zip"
    archive = f"bundle_{token}_{i}{ext}"
    recent_name = f"recent_{token}_{i}.py"
    old_name = f"old_{token}_{i}.py"
    recent_data = f"print('recent-{token}-{i}')\n".encode()
    old_data = f"print('old-{token}-{i}')\n".encode()
    path = os.path.join(incoming, archive)
    if ext == ".tar.gz":
        with tarfile.open(path, "w:gz") as tf:
            for name, data, mtime in [
                (f"src{i}/{recent_name}", recent_data, now - 86400),
                (f"src{i}/{old_name}", old_data, now - 20*86400),
                (f"src{i}/note.txt", b"safe\n", now - 86400),
            ]:
                ti = tarfile.TarInfo(name)
                ti.size = len(data)
                ti.mtime = mtime
                tf.addfile(ti, io.BytesIO(data))
    else:
        with zipfile.ZipFile(path, "w") as zf:
            zip_write(zf, f"src{i}/{recent_name}", recent_data, now - 86400)
            zip_write(zf, f"src{i}/{old_name}", old_data, now - 20*86400)
            zip_write(zf, f"src{i}/note.txt", b"safe\n", now - 86400)
    records.append((sid, "APPROVED", archive))
    expected_projects.append(sid)
    recent[recent_name] = recent_data.decode()
    old_names.append(old_name)

for i in range(malicious_count):
    sid = f"mal_{token}_{i}"
    ext = ".zip" if i % 2 == 0 else ".tar.gz"
    archive = f"malicious_{token}_{i}{ext}"
    traversal_marker = f"/tmp/traversal_{token}_{i}"
    absolute_marker = f"/tmp/absolute_{token}_{i}"
    markers.extend([traversal_marker, absolute_marker])
    for marker in (traversal_marker, absolute_marker):
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass
    path = os.path.join(incoming, archive)
    traversal_name = f"../../../../tmp/traversal_{token}_{i}"
    if ext == ".zip":
        with zipfile.ZipFile(path, "w") as zf:
            zf.writestr(traversal_name, "escape\n")
            zf.writestr(absolute_marker, "absolute\n")
            zf.writestr("normal.txt", "normal\n")
    else:
        with tarfile.open(path, "w:gz") as tf:
            for name in (traversal_name, absolute_marker):
                data = b"escape\n"
                ti = tarfile.TarInfo(name)
                ti.size = len(data)
                ti.mtime = now
                tf.addfile(ti, io.BytesIO(data))
    records.append((sid, "APPROVED", archive))

corrupt_id = f"corrupt_{token}"
corrupt_archive = f"corrupt_{token}.zip"
with open(os.path.join(incoming, corrupt_archive), "wb") as f:
    f.write(secrets.token_bytes(37))
records.append((corrupt_id, "APPROVED", corrupt_archive))

rejected_id = f"rejected_{token}"
rejected_archive = f"rejected_{token}.zip"
with zipfile.ZipFile(os.path.join(incoming, rejected_archive), "w") as zf:
    zf.writestr(f"rejected_{token}.py", "print('must not extract')\n")
records.append((rejected_id, "REJECTED", rejected_archive))

with open(os.path.join(incoming, "submissions.log"), "w") as f:
    for index, (sid, status, archive) in enumerate(records):
        if index:
            f.write("\n")
        f.write(f"ID: {sid}\nStatus: {status}\nFile: {archive}\n")

with open("/tmp/dynamic_expect.json", "w") as f:
    json.dump({
        "safe_count": safe_count,
        "malicious_count": malicious_count,
        "expected_projects": expected_projects,
        "recent": recent,
        "old_names": old_names,
        "markers": markers,
        "forbidden_projects": [corrupt_id, rejected_id] + [f"mal_{token}_{i}" for i in range(malicious_count)],
    }, f)
PY

    rm -rf /home/user/projects /home/user/recent_code /home/user/summary.txt
    mkdir -p /home/user/projects /home/user/recent_code
    timeout 30s /home/user/organize_projects.sh >/tmp/organize-dynamic.out 2>/tmp/organize-dynamic.err || return 1

    python3 <<'PY' || return 1
import json
import os

with open('/tmp/dynamic_expect.json') as f:
    e = json.load(f)

project_root = '/home/user/projects'
actual_projects = set(os.listdir(project_root))
assert actual_projects == set(e['expected_projects']), (actual_projects, e['expected_projects'])

for sid in e['expected_projects']:
    root = os.path.join(project_root, sid)
    assert os.path.isdir(root)
    found = {}
    for base, _, files in os.walk(root):
        for name in files:
            with open(os.path.join(base, name), errors='replace') as f:
                found[name] = f.read()
    expected_recent = [name for name in e['recent'] if name in found]
    assert len(expected_recent) == 1
    name = expected_recent[0]
    assert found[name] == e['recent'][name]

for sid in e['forbidden_projects']:
    assert not os.path.exists(os.path.join(project_root, sid))
for marker in e['markers']:
    assert not os.path.exists(marker), f"Archive escaped extraction directory: {marker}"

recent_root = '/home/user/recent_code'
assert os.path.isdir(recent_root)
actual_recent = set(os.listdir(recent_root))
assert actual_recent == set(e['recent']), (actual_recent, set(e['recent']))
for name, content in e['recent'].items():
    path = os.path.join(recent_root, name)
    assert os.path.isfile(path)
    with open(path) as f:
        assert f.read() == content
for name in e['old_names']:
    assert not os.path.exists(os.path.join(recent_root, name))

with open('/home/user/summary.txt') as f:
    summary = f.read()
expected_summary = (
    f"Safe Extracted: {e['safe_count']}\n"
    f"Malicious Found: {e['malicious_count']}\n"
    f"Recent Python Files: {len(e['recent'])}\n"
)
assert summary == expected_summary, (summary, expected_summary)
PY
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
