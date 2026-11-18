#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import hashlib
import json
import os
import pathlib
import posixpath
import pwd
import random
import shutil
import signal
import string
import subprocess
import tempfile

MANIFEST = "/home/user/manifest.json"
REPO = "/home/user/repo"
CONFIG = "/home/user/curator.json"
README = "/home/user/repo/docs/readme.txt"
SETTINGS = "/home/user/repo/config/settings.conf"
IGNORE = "/home/user/repo/docs/ignore.log"


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


# Preserve the original final-state assertions.
assert os.path.exists(README), f"Missing {README}"
with open(README, "rb") as f:
    readme_content = f.read()
assert readme_content in (
    "Documentation for v1.0\nIt “works” well.".encode("utf-8"),
    "Documentation for v1.0\nIt “works” well.\n".encode("utf-8"),
), "readme.txt was not properly converted to UTF-8"

assert os.path.exists(SETTINGS), f"Missing {SETTINGS}"
with open(SETTINGS, "rb") as f:
    settings_content = f.read()
assert settings_content in (
    "System configuration\nMax connections: 100\nAuthor: René".encode("utf-8"),
    "System configuration\nMax connections: 100\nAuthor: René\n".encode("utf-8"),
), "settings.conf was not properly converted to UTF-8"

assert os.path.exists(MANIFEST), f"Manifest file {MANIFEST} is missing"
with open(MANIFEST, "r") as f:
    manifest = json.load(f)
assert isinstance(manifest, dict), "Manifest should be a JSON dictionary"
assert "docs/readme.txt" in manifest, "docs/readme.txt missing from manifest"
assert manifest["docs/readme.txt"] == sha256(README), "Incorrect SHA-256 hash for docs/readme.txt"
found_settings = False
for key, value in manifest.items():
    if "settings.conf" in key:
        assert value == sha256(SETTINGS), f"Incorrect SHA-256 hash for {key}"
        found_settings = True
assert found_settings, "settings.conf missing from manifest"

assert os.path.exists(IGNORE), f"Missing {IGNORE}"
with open(IGNORE, "rb") as f:
    ignored = f.read()
assert ignored in (b"Ignore this file\n", b"Ignore this file"), "ignore.log was modified but should have been ignored"

# Locate the Python artifact the agent was required to write.
candidates = []
for root, dirs, files in os.walk("/home/user", followlinks=False):
    rel = os.path.relpath(root, "/home/user")
    depth = 0 if rel == "." else len(pathlib.Path(rel).parts)
    dirs[:] = [d for d in dirs if not d.startswith(".") and depth < 4]
    for name in files:
        path = os.path.join(root, name)
        if not os.path.isfile(path) or os.path.islink(path):
            continue
        is_python = name.endswith(".py")
        if not is_python:
            try:
                with open(path, "rb") as f:
                    is_python = b"python" in f.readline(256).lower() and f.readline(256) is not None
            except OSError:
                pass
        if is_python:
            candidates.append(path)
assert candidates, "No Python curation script was written under /home/user"

suffix = "." + "q" + "".join(random.SystemRandom().choices(string.ascii_lowercase, k=12))
token = "".join(random.SystemRandom().choices(string.ascii_lowercase, k=12))
direct_dir = os.path.join(REPO, "dynamic_" + token)
external_dir = os.path.join("/home/user", "external_" + token)
alias1 = os.path.join(REPO, "alias_a_" + token)
alias2 = os.path.join(REPO, "alias_b_" + token)
direct_file = os.path.join(direct_dir, "direct" + suffix)
external_file = os.path.join(external_dir, "linked" + suffix)
ignored_file = os.path.join(direct_dir, "untouched.bin")
direct_source = b"Direct Ren\xe9 and \x93quotes\x94\n"
linked_source = b"Linked Andr\xe9: \x91unique\x92\n"
direct_expected = direct_source.decode("windows-1252").encode("utf-8")
linked_expected = linked_source.decode("windows-1252").encode("utf-8")
original_config = open(CONFIG, "rb").read()
user = pwd.getpwnam("user")


def remove(path):
    try:
        if os.path.islink(path) or os.path.isfile(path):
            os.unlink(path)
        elif os.path.isdir(path):
            shutil.rmtree(path)
    except FileNotFoundError:
        pass


def chown_tree(path):
    if os.path.islink(path):
        os.chown(path, user.pw_uid, user.pw_gid, follow_symlinks=False)
        return
    for root, dirs, files in os.walk(path, followlinks=False):
        os.chown(root, user.pw_uid, user.pw_gid)
        for name in dirs + files:
            p = os.path.join(root, name)
            os.chown(p, user.pw_uid, user.pw_gid, follow_symlinks=False)


def reset_fixture():
    for p in (direct_dir, alias1, alias2, external_dir):
        remove(p)
    os.makedirs(direct_dir)
    os.makedirs(external_dir)
    with open(direct_file, "wb") as f:
        f.write(direct_source)
    with open(external_file, "wb") as f:
        f.write(linked_source)
    with open(ignored_file, "wb") as f:
        f.write(b"must remain unchanged")
    os.symlink(external_dir, alias1)
    os.symlink(external_dir, alias2)
    # Following either linked directory reaches this cycle and must terminate.
    os.symlink(REPO, os.path.join(external_dir, "cycle_to_repo"))
    chown_tree(direct_dir)
    chown_tree(external_dir)
    os.chown(alias1, user.pw_uid, user.pw_gid, follow_symlinks=False)
    os.chown(alias2, user.pw_uid, user.pw_gid, follow_symlinks=False)
    with open(CONFIG, "w") as f:
        json.dump({"extensions": [suffix], "source_encoding": "windows-1252", "target_encoding": "utf-8"}, f)
    os.chown(CONFIG, user.pw_uid, user.pw_gid)
    remove(MANIFEST)


site_dir = tempfile.mkdtemp(prefix="curator_audit_")
audit_log = os.path.join(site_dir, "rename.jsonl")
open(audit_log, "w").close()
os.chmod(audit_log, 0o666)
sitecustomize = r'''
import json, os, sys
log = os.environ.get("CURATOR_AUDIT_LOG")
def resolve(path, fd):
    path = os.fsdecode(path)
    if os.path.isabs(path):
        return os.path.abspath(path)
    if isinstance(fd, int) and fd >= 0:
        try:
            return os.path.abspath(os.path.join(os.readlink("/proc/self/fd/%d" % fd), path))
        except OSError:
            pass
    return os.path.abspath(path)
def audit(event, args):
    if event != "os.rename" or not log:
        return
    try:
        src, dst, srcfd, dstfd = args
        src = resolve(src, srcfd)
        dst = resolve(dst, dstfd)
        rec = {
            "src": src,
            "dst": dst,
            "src_dir": os.path.realpath(os.path.dirname(src)),
            "dst_dir": os.path.realpath(os.path.dirname(dst)),
            "dst_real": os.path.realpath(dst),
        }
        with open(log, "a") as f:
            f.write(json.dumps(rec) + "\n")
    except Exception:
        pass
sys.addaudithook(audit)
'''
with open(os.path.join(site_dir, "sitecustomize.py"), "w") as f:
    f.write(sitecustomize)
os.chmod(site_dir, 0o755)
os.chmod(os.path.join(site_dir, "sitecustomize.py"), 0o644)


def validate_run():
    assert open(direct_file, "rb").read() == direct_expected, "dynamically named direct file was not converted"
    assert open(external_file, "rb").read() == linked_expected, "file reachable only through directory symlinks was not converted exactly once"
    assert open(ignored_file, "rb").read() == b"must remain unchanged", "nonmatching dynamic file was modified"
    assert os.stat(direct_file).st_ino != direct_inode, "direct file was rewritten in place rather than replaced atomically"
    assert os.stat(external_file).st_ino != linked_inode, "symlink-reached file was rewritten in place rather than replaced atomically"

    with open(MANIFEST, "r", encoding="utf-8") as f:
        m = json.load(f)
    assert isinstance(m, dict), "Dynamic manifest is not a JSON dictionary"
    assert len(m) == 2, "Manifest must contain each unique processed physical file exactly once"
    for key, value in m.items():
        assert isinstance(key, str) and isinstance(value, str)
        assert not key.startswith("/") and "\\" not in key
        assert key == posixpath.normpath(key) and ".." not in pathlib.PurePosixPath(key).parts
        assert len(value) == 64 and value == value.lower() and all(c in "0123456789abcdef" for c in value)
    direct_key = "dynamic_" + token + "/direct" + suffix
    linked_keys = {"alias_a_" + token + "/linked" + suffix, "alias_b_" + token + "/linked" + suffix}
    assert direct_key in m, "Manifest lacks the valid relative path for the direct file"
    present_linked = linked_keys.intersection(m)
    assert len(present_linked) == 1, "Symlink aliases must yield one valid relative manifest path"
    assert m[direct_key] == hashlib.sha256(direct_expected).hexdigest()
    linked_key = next(iter(present_linked))
    assert m[linked_key] == hashlib.sha256(linked_expected).hexdigest()

    events = []
    with open(audit_log) as f:
        for line in f:
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    for target in (os.path.realpath(direct_file), os.path.realpath(external_file)):
        matching = [e for e in events if e.get("dst_real") == target and e.get("src_dir") == e.get("dst_dir")]
        assert matching, f"No same-directory atomic rename/replace was used for {target}"


passed = False
errors = []
try:
    for candidate in sorted(set(candidates)):
        reset_fixture()
        direct_inode = os.stat(direct_file).st_ino
        linked_inode = os.stat(external_file).st_ino
        open(audit_log, "w").close()
        env = os.environ.copy()
        env["PYTHONPATH"] = site_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        env["CURATOR_AUDIT_LOG"] = audit_log
        try:
            proc = subprocess.Popen(
                ["python3", candidate], cwd="/home/user", env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                start_new_session=True,
                preexec_fn=lambda: (os.setgid(user.pw_gid), os.setuid(user.pw_uid)),
            )
            try:
                _, stderr = proc.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.communicate()
                raise AssertionError("script did not terminate while traversing symlink cycles")
            assert proc.returncode == 0, stderr.decode("utf-8", "replace")
            validate_run()
            passed = True
            break
        except Exception as exc:
            errors.append(f"{candidate}: {exc}")
    assert passed, "No submitted Python script passed execution tests: " + "; ".join(errors)
finally:
    with open(CONFIG, "wb") as f:
        f.write(original_config)
    os.chown(CONFIG, user.pw_uid, user.pw_gid)
    for p in (direct_dir, alias1, alias2, external_dir):
        remove(p)
    shutil.rmtree(site_dir, ignore_errors=True)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
