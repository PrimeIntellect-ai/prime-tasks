#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import gzip
import hashlib
import io
import os
import posixpath
import shutil
import stat
import subprocess
import tarfile
import tempfile
import uuid
import glob
import pytest

SCRIPT = "/home/user/sanitize_backup.sh"
PIGZ = "/home/user/bin/pigz"
SOURCE = "/app/vendored/pigz-2.8"


def safe_extract(archive, destination):
    with tarfile.open(archive, "r:gz") as tf:
        members = tf.getmembers()
        for member in members:
            name = member.name
            normalized = posixpath.normpath(name)
            assert not name.startswith("/"), f"absolute output member: {name}"
            assert normalized != ".." and not normalized.startswith("../"), f"traversing output member: {name}"
            if member.issym():
                target = member.linkname
                assert not target.startswith("/"), f"absolute symlink survived: {name} -> {target}"
                resolved = posixpath.normpath(posixpath.join(posixpath.dirname(normalized), target))
                assert resolved != ".." and not resolved.startswith("../"), f"escaping symlink survived: {name} -> {target}"
            if member.islnk():
                target = posixpath.normpath(member.linkname)
                assert not member.linkname.startswith("/")
                assert target != ".." and not target.startswith("../")
        tf.extractall(destination)


def test_pigz_compiled_and_installed():
    assert os.path.isfile(PIGZ), f"pigz binary not found at {PIGZ}"
    assert os.access(PIGZ, os.X_OK), f"pigz binary at {PIGZ} is not executable"
    with open(PIGZ, "rb") as f:
        assert f.read(4) == b"\x7fELF", "installed pigz is not a compiled ELF binary"

    result = subprocess.run([PIGZ, "--version"], capture_output=True, text=True)
    assert result.returncode == 0
    assert "pigz 2.8" in result.stdout or "pigz 2.8" in result.stderr

    payload = os.urandom(131071) + b"pigz-functional-test"
    compressed = subprocess.run([PIGZ, "-c", "-6"], input=payload, capture_output=True)
    assert compressed.returncode == 0, compressed.stderr.decode(errors="replace")
    assert gzip.decompress(compressed.stdout) == payload
    decompressed = subprocess.run([PIGZ, "-dc"], input=compressed.stdout, capture_output=True)
    assert decompressed.returncode == 0
    assert decompressed.stdout == payload

    clean = subprocess.run(["make", "clean"], cwd=SOURCE, capture_output=True, text=True)
    assert clean.returncode == 0, clean.stdout + clean.stderr
    built = subprocess.run(["make", "-j2"], cwd=SOURCE, capture_output=True, text=True)
    assert built.returncode == 0, "provided pigz source still does not compile:\n" + built.stdout + built.stderr
    source_binary = os.path.join(SOURCE, "pigz")
    assert os.path.isfile(source_binary) and os.access(source_binary, os.X_OK)
    with open(source_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF"
    source_test = subprocess.run([source_binary, "-c"], input=payload, capture_output=True)
    assert source_test.returncode == 0
    assert gzip.decompress(source_test.stdout) == payload


def test_script_exists():
    assert os.path.isfile(SCRIPT), f"Script not found at {SCRIPT}"


def test_clean_corpus():
    clean_files = glob.glob("/app/corpora/clean/*.tar.gz")
    assert len(clean_files) > 0, "No clean corpus files found."
    modified_clean = []
    for input_file in clean_files:
        basename = os.path.basename(input_file)
        with tempfile.TemporaryDirectory() as tmpdir:
            output_file = os.path.join(tmpdir, "output.tar.gz")
            res = subprocess.run(["bash", SCRIPT, input_file, output_file], capture_output=True)
            if res.returncode != 0 or not os.path.isfile(output_file):
                modified_clean.append(f"{basename} (script failed or no output)")
                continue
            extract_dir = os.path.join(tmpdir, "extracted")
            os.makedirs(extract_dir)
            safe_extract(output_file, extract_dir)
            safe_txt = os.path.join(extract_dir, "docs", "safe.txt")
            safe_link = os.path.join(extract_dir, "docs", "safelink")
            nested_internal_dir = os.path.join(extract_dir, "docs", "nested", "internal")
            nested_safe_txt = os.path.join(nested_internal_dir, "docs", "safe.txt")
            nested_tar = os.path.join(extract_dir, "docs", "nested", "internal.tar.gz")
            if not (os.path.isfile(safe_txt) and os.path.islink(safe_link) and
                    os.path.isdir(nested_internal_dir) and os.path.isfile(nested_safe_txt) and
                    not os.path.exists(nested_tar)):
                modified_clean.append(basename)
    if modified_clean:
        pytest.fail(f"{len(modified_clean)} of {len(clean_files)} clean modified: {', '.join(modified_clean)}")


def test_evil_corpus():
    evil_files = glob.glob("/app/corpora/evil/*.tar.gz")
    assert len(evil_files) > 0, "No evil corpus files found."
    bypassed_evil = []
    for input_file in evil_files:
        basename = os.path.basename(input_file)
        with tempfile.TemporaryDirectory() as tmpdir:
            output_file = os.path.join(tmpdir, "output.tar.gz")
            res = subprocess.run(["bash", SCRIPT, input_file, output_file], capture_output=True)
            if res.returncode != 0 or not os.path.isfile(output_file):
                bypassed_evil.append(f"{basename} (script failed or no output)")
                continue
            extract_dir = os.path.join(tmpdir, "extracted")
            os.makedirs(extract_dir)
            safe_extract(output_file, extract_dir)
            bad_txt = os.path.join(extract_dir, "payload", "bad.txt")
            abs_link = os.path.join(extract_dir, "payload", "abs_link")
            rel_link = os.path.join(extract_dir, "payload", "rel_link")
            nested_bomb_dir = os.path.join(extract_dir, "payload", "deep", "hidden_evil")
            root_link = os.path.join(nested_bomb_dir, "payload", "nested_bomb", "root_link")
            nested_tar = os.path.join(extract_dir, "payload", "deep", "hidden_evil.tar.gz")
            bypassed = (not os.path.isfile(bad_txt) or os.path.lexists(abs_link) or
                        os.path.lexists(rel_link) or os.path.lexists(root_link) or
                        os.path.exists(nested_tar))
            if bypassed:
                bypassed_evil.append(basename)
    if bypassed_evil:
        pytest.fail(f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed: {', '.join(bypassed_evil)}")


def make_tar(entries, gz=False):
    buf = io.BytesIO()
    mode = "w:gz" if gz else "w"
    with tarfile.open(fileobj=buf, mode=mode) as tf:
        for kind, name, value in entries:
            info = tarfile.TarInfo(name)
            info.mtime = 1700000000
            if kind == "file":
                info.mode = 0o640
                info.size = len(value)
                tf.addfile(info, io.BytesIO(value))
            elif kind == "symlink":
                info.type = tarfile.SYMTYPE
                info.mode = 0o777
                info.linkname = value
                tf.addfile(info)
            elif kind == "hardlink":
                info.type = tarfile.LNKTYPE
                info.linkname = value
                tf.addfile(info)
            else:
                raise AssertionError(kind)
    return buf.getvalue()


def create_random_fixture(path):
    nonce = uuid.uuid4().hex
    top_data = os.urandom(4097) + nonce.encode()
    note_data = ("nested-" + nonce).encode()
    leaf_data = hashlib.sha256(nonce.encode()).digest() * 7

    deepest = make_tar([
        ("file", f"leaf_{nonce}.bin", leaf_data),
        ("symlink", "safe_leaf_link", f"leaf_{nonce}.bin"),
        ("symlink", "absolute_bad", "/root/.ssh/id_rsa"),
        ("symlink", "relative_bad", "../../../../outside"),
    ], gz=False)
    middle = make_tar([
        ("file", "middle.txt", note_data),
        ("file", f"layer/deep_{nonce}.tar", deepest),
        ("symlink", "middle_safe", "middle.txt"),
        ("symlink", "middle_bad", "../../../etc/shadow"),
    ], gz=True)
    bundle = make_tar([
        ("file", "inner/note.txt", note_data),
        ("file", f"inner/more_{nonce}.tar.gz", middle),
        ("symlink", "inner/note_link", "note.txt"),
        ("symlink", "inner/evil_link", "/etc/passwd"),
    ], gz=False)
    outer = make_tar([
        ("file", f"alpha/random_{nonce}.bin", top_data),
        ("hardlink", f"alpha/random_hard_{nonce}.bin", f"alpha/random_{nonce}.bin"),
        ("file", "targetdir/note.txt", b"target directory\n"),
        ("symlink", "alpha/file_link", f"random_{nonce}.bin"),
        ("symlink", "alpha/dir_link", "../targetdir"),
        ("symlink", "alpha/absolute_bad", "/etc/shadow"),
        ("symlink", "alpha/traversal_bad", "../../../var/log"),
        ("file", f"zone/bundle_{nonce}.tar", bundle),
    ], gz=True)
    with open(path, "wb") as f:
        f.write(outer)
    return nonce, top_data, note_data, leaf_data


def collect_tree(root):
    files = {}
    links = {}
    for current, dirs, names in os.walk(root, followlinks=False):
        for name in list(dirs) + names:
            full = os.path.join(current, name)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            if os.path.islink(full):
                links[rel] = os.readlink(full)
            elif os.path.isfile(full):
                with open(full, "rb") as f:
                    files[rel] = f.read()
    return files, links


def test_random_recursive_preservation_sanitization_pigz_and_atomic_write():
    backup = PIGZ + ".verifier-real"
    marker = os.path.join(tempfile.gettempdir(), "pigz-marker-" + uuid.uuid4().hex)
    assert not os.path.lexists(backup)
    os.rename(PIGZ, backup)
    wrapper = f'''#!/bin/bash
printf '%s\\n' "$*" >> "${{VERIFIER_PIGZ_MARKER}}"
if [[ -n "${{VERIFIER_EXPECT_OUTPUT:-}}" && -e "${{VERIFIER_EXPECT_OUTPUT}}.tmp" ]]; then
    echo tmp-seen >> "${{VERIFIER_PIGZ_MARKER}}"
fi
if [[ "${{VERIFIER_PIGZ_FAIL:-0}}" = 1 ]]; then
    exit 73
fi
exec {backup} "$@"
'''
    try:
        with open(PIGZ, "w") as f:
            f.write(wrapper)
        os.chmod(PIGZ, 0o755)
        with tempfile.TemporaryDirectory() as td:
            input_path = os.path.join(td, "unseen-input.tar.gz")
            nonce, top_data, note_data, leaf_data = create_random_fixture(input_path)
            output_path = os.path.join(td, "sanitized.tar.gz")
            env = os.environ.copy()
            env["PATH"] = "/home/user/bin:" + env.get("PATH", "")
            env["VERIFIER_PIGZ_MARKER"] = marker
            env["VERIFIER_EXPECT_OUTPUT"] = output_path
            result = subprocess.run(["bash", SCRIPT, input_path, output_path], env=env,
                                    capture_output=True, timeout=45)
            assert result.returncode == 0, result.stderr.decode(errors="replace")
            assert os.path.isfile(output_path)
            assert os.path.isfile(marker), "sanitizer did not invoke /home/user/bin/pigz"
            marker_text = open(marker).read()
            assert "tmp-seen" in marker_text, "pigz was not writing the required <output>.tmp file"

            extracted = os.path.join(td, "extracted")
            os.mkdir(extracted)
            safe_extract(output_path, extracted)
            files, links = collect_tree(extracted)
            expected_files = {
                f"alpha/random_{nonce}.bin": top_data,
                f"alpha/random_hard_{nonce}.bin": top_data,
                "targetdir/note.txt": b"target directory\n",
                f"zone/bundle_{nonce}/inner/note.txt": note_data,
                f"zone/bundle_{nonce}/inner/more_{nonce}/middle.txt": note_data,
                f"zone/bundle_{nonce}/inner/more_{nonce}/layer/deep_{nonce}/leaf_{nonce}.bin": leaf_data,
            }
            expected_links = {
                "alpha/file_link": f"random_{nonce}.bin",
                "alpha/dir_link": "../targetdir",
                f"zone/bundle_{nonce}/inner/note_link": "note.txt",
                f"zone/bundle_{nonce}/inner/more_{nonce}/middle_safe": "middle.txt",
                f"zone/bundle_{nonce}/inner/more_{nonce}/layer/deep_{nonce}/safe_leaf_link": f"leaf_{nonce}.bin",
            }
            assert files == expected_files, f"legitimate file set/content changed: {sorted(files)}"
            assert links == expected_links, f"safe links changed or malicious links survived: {links}"
            assert not any(p.endswith(".tar") or p.endswith(".tar.gz") for p in files), "nested archive survived"

            os.remove(marker)
            failed_output = os.path.join(td, "must-not-appear.tar.gz")
            fail_env = env.copy()
            fail_env["VERIFIER_EXPECT_OUTPUT"] = failed_output
            fail_env["VERIFIER_PIGZ_FAIL"] = "1"
            failed = subprocess.run(["bash", SCRIPT, input_path, failed_output], env=fail_env,
                                    capture_output=True, timeout=45)
            assert failed.returncode != 0, "sanitizer reported success after pigz failed"
            assert not os.path.exists(failed_output), "failed compression was promoted to the final output"
            assert os.path.isfile(marker), "failure test did not reach pigz"
    finally:
        if os.path.lexists(PIGZ):
            os.unlink(PIGZ)
        if os.path.lexists(backup):
            os.rename(backup, PIGZ)
        if os.path.exists(marker):
            os.unlink(marker)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
