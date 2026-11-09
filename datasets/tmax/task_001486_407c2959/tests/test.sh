#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import io
import json
import os
import posixpath
import shlex
import shutil
import stat
import subprocess
import tarfile
import tempfile
import uuid
import xml.etree.ElementTree as ET

import pytest

SCRIPT = "/home/user/pipeline/sanitizer.sh"


def run_sanitizer(archive, output_dir):
    return subprocess.run(
        [SCRIPT, archive, output_dir],
        capture_output=True,
        text=True,
        timeout=20,
    )


def normalized(name):
    while name.startswith("./"):
        name = name[2:]
    return posixpath.normpath(name)


def expected_json_configs(archive):
    expected = {}
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar.getmembers():
            path = normalized(member.name)
            if member.isfile() and posixpath.basename(path) == "app_config.json":
                stream = tar.extractfile(member)
                assert stream is not None
                data = json.loads(stream.read().decode("utf-8"))
                assert isinstance(data, dict)
                xml_path = posixpath.join(posixpath.dirname(path), "app_config.xml")
                expected[xml_path] = data
    return expected


def validate_transformed_archive(input_archive, output_archive):
    expected = expected_json_configs(input_archive)
    assert expected, "Input archive did not contain an app_config.json"

    with tarfile.open(output_archive, "r:gz") as tar:
        members = tar.getmembers()
        by_name = {normalized(member.name): member for member in members}

        assert not any(posixpath.basename(name) == "app_config.json" for name in by_name)
        assert not any(member.issym() or member.islnk() for member in members)

        for xml_path, source_data in expected.items():
            assert xml_path in by_name, f"Missing converted file {xml_path}"
            member = by_name[xml_path]
            assert member.isfile(), f"{xml_path} is not a regular file"
            stream = tar.extractfile(member)
            assert stream is not None
            root = ET.fromstring(stream.read())
            assert root.tag == "config"
            actual = {}
            for child in list(root):
                assert len(list(child)) == 0
                assert child.tag not in actual
                actual[child.tag] = child.text or ""
            wanted = {str(key): str(value) for key, value in source_data.items()}
            assert actual == wanted, f"Incorrect XML contents in {xml_path}: {actual!r} != {wanted!r}"


def add_bytes(tar, name, payload):
    data = payload if isinstance(payload, bytes) else payload.encode("utf-8")
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(data))


def make_clean_archive(path):
    token = uuid.uuid4().hex
    with tarfile.open(path, "w:gz") as tar:
        add_bytes(tar, "app_config.json", json.dumps({
            "service": "frontend-" + token,
            "workers": 7,
            "note": "a < b & c",
        }))
        add_bytes(tar, "regions/east/app_config.json", json.dumps({
            "service": "worker-" + token,
            "workers": 3,
        }))
        add_bytes(tar, "regions/east/readme.txt", "preserve me")
    return token


def make_evil_archive(path, kind):
    with tarfile.open(path, "w:gz") as tar:
        if kind == "absolute_symlink":
            info = tarfile.TarInfo("links/shadow")
            info.type = tarfile.SYMTYPE
            info.linkname = "/etc/shadow"
            tar.addfile(info)
        elif kind == "escaping_symlink":
            info = tarfile.TarInfo("nested/link")
            info.type = tarfile.SYMTYPE
            info.linkname = "../../outside"
            tar.addfile(info)
        elif kind == "hardlink":
            info = tarfile.TarInfo("shadow-copy")
            info.type = tarfile.LNKTYPE
            info.linkname = "/etc/shadow"
            tar.addfile(info)
        elif kind == "shell":
            add_bytes(tar, "nested/payload.sh", "#!/bin/sh\necho pwned\n")
        elif kind == "traversal":
            add_bytes(tar, "../escape-" + uuid.uuid4().hex, "bad")
        else:
            raise AssertionError(kind)


def upload(path):
    return subprocess.run([
        "curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}",
        "-F", f"file=@{path}", "http://127.0.0.1:8080/upload",
    ], capture_output=True, text=True, timeout=30)


def redis(*args):
    return subprocess.run(["redis-cli", *args], capture_output=True, text=True, timeout=10)


def test_sanitizer_executable_and_argument_count():
    assert os.path.isfile(SCRIPT), f"Sanitizer script missing at {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"Sanitizer script {SCRIPT} is not executable"
    assert subprocess.run([SCRIPT], capture_output=True, text=True, timeout=10).returncode != 0
    assert subprocess.run([SCRIPT, "a", "b", "c"], capture_output=True, text=True, timeout=10).returncode != 0


def test_evil_corpus_rejected():
    evil_files = glob.glob("/home/user/corpora/evil/*.tar.gz")
    assert evil_files, "No evil corpus files found"

    bypassed = []
    for evil_file in evil_files:
        with tempfile.TemporaryDirectory() as tmpdir:
            result = run_sanitizer(evil_file, tmpdir)
            if result.returncode == 0 or "REJECTED" not in result.stdout:
                bypassed.append(os.path.basename(evil_file))

    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}"


@pytest.mark.parametrize("kind", [
    "absolute_symlink", "escaping_symlink", "hardlink", "shell", "traversal"
])
def test_generated_malicious_archives_rejected(kind):
    with tempfile.TemporaryDirectory() as tmpdir:
        archive = os.path.join(tmpdir, uuid.uuid4().hex + ".tar.gz")
        output = os.path.join(tmpdir, "out")
        os.mkdir(output)
        make_evil_archive(archive, kind)
        result = run_sanitizer(archive, output)
        assert result.returncode == 1, f"{kind} returned {result.returncode}: {result.stdout} {result.stderr}"
        assert "REJECTED" in result.stdout
        assert not os.path.exists(os.path.join(output, "sanitized_bundle.tar.gz"))


def test_clean_corpus_accepted_and_transformed():
    clean_files = glob.glob("/home/user/corpora/clean/*.tar.gz")
    assert clean_files, "No clean corpus files found"

    modified_or_failed = []
    for clean_file in clean_files:
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                result = run_sanitizer(clean_file, tmpdir)
                if result.returncode != 0 or "ACCEPTED" not in result.stdout:
                    modified_or_failed.append(f"{os.path.basename(clean_file)} (rejected)")
                    continue
                out_tar = os.path.join(tmpdir, "sanitized_bundle.tar.gz")
                if not os.path.isfile(out_tar):
                    modified_or_failed.append(f"{os.path.basename(clean_file)} (missing output tar)")
                    continue
                validate_transformed_archive(clean_file, out_tar)
        except Exception as exc:
            modified_or_failed.append(f"{os.path.basename(clean_file)} ({exc})")

    assert not modified_or_failed, f"{len(modified_or_failed)} of {len(clean_files)} clean failed/modified: {', '.join(modified_or_failed)}"


def test_generated_clean_archive_xml_contents_and_locations():
    with tempfile.TemporaryDirectory() as tmpdir:
        archive = os.path.join(tmpdir, uuid.uuid4().hex + ".tar.gz")
        output = os.path.join(tmpdir, "out")
        os.mkdir(output)
        make_clean_archive(archive)
        result = run_sanitizer(archive, output)
        assert result.returncode == 0, result.stderr
        assert "ACCEPTED" in result.stdout
        out_tar = os.path.join(output, "sanitized_bundle.tar.gz")
        assert os.path.isfile(out_tar)
        validate_transformed_archive(archive, out_tar)


def test_end_to_end_invokes_sanitizer_and_parses_its_xml():
    with tempfile.TemporaryDirectory() as tmpdir:
        clean_archive = os.path.join(tmpdir, uuid.uuid4().hex + ".tar.gz")
        make_clean_archive(clean_archive)

        malformed_archive = os.path.join(tmpdir, "malformed.tar.gz")
        with tarfile.open(malformed_archive, "w:gz") as tar:
            add_bytes(tar, "app_config.xml", "<config><service>broken</config>")

        backup = os.path.join(tmpdir, "sanitizer.original")
        log_path = os.path.join(tmpdir, "calls.log")
        mode_path = os.path.join(tmpdir, "mode")
        shutil.copy2(SCRIPT, backup)
        original_mode = stat.S_IMODE(os.stat(SCRIPT).st_mode)

        wrapper = f'''#!/bin/bash
in_ok=0
out_ok=0
[ -f "$1" ] && in_ok=1
[ -d "$2" ] && out_ok=1
printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "$#" "$1" "$2" "$in_ok" "$out_ok" >> {shlex.quote(log_path)}
if [ "$(cat {shlex.quote(mode_path)} 2>/dev/null)" = "malformed" ]; then
    mkdir -p "$2"
    cp {shlex.quote(malformed_archive)} "$2/sanitized_bundle.tar.gz"
    echo ACCEPTED
    exit 0
fi
exec {shlex.quote(backup)} "$@"
'''

        try:
            with open(SCRIPT, "w", encoding="utf-8") as handle:
                handle.write(wrapper)
            os.chmod(SCRIPT, 0o755)

            with open(mode_path, "w", encoding="utf-8") as handle:
                handle.write("valid")
            assert redis("del", "config_status").returncode == 0
            result = upload(clean_archive)
            assert result.stdout.strip() in ["200", "201"], f"Upload to Nginx failed, HTTP code: {result.stdout}; {result.stderr}"
            status = redis("get", "config_status")
            assert status.returncode == 0
            assert status.stdout.strip() == "SECURE_UPDATE_APPLIED"

            with open(log_path, encoding="utf-8") as handle:
                calls = [line.rstrip("\n").split("\t") for line in handle if line.strip()]
            assert calls, "Flask did not invoke /home/user/pipeline/sanitizer.sh"
            count, input_arg, output_arg, input_ok, output_ok = calls[-1]
            assert count == "2", f"Sanitizer was called with {count} arguments"
            assert input_ok == "1", "Sanitizer input argument was not an uploaded file"
            assert output_ok == "1", "Sanitizer output argument was not an existing temporary directory"
            assert os.path.abspath(input_arg) != os.path.abspath(clean_archive), "Flask did not save the upload to a temporary file"

            assert redis("del", "config_status").returncode == 0
            with open(mode_path, "w", encoding="utf-8") as handle:
                handle.write("malformed")
            upload(clean_archive)
            status = redis("get", "config_status")
            assert status.returncode == 0
            assert status.stdout.strip() == "", "Flask set config_status without successfully parsing sanitizer XML output"

            with open(log_path, encoding="utf-8") as handle:
                later_calls = [line for line in handle if line.strip()]
            assert len(later_calls) > len(calls), "Malformed-output upload did not invoke the sanitizer"
        finally:
            shutil.copy2(backup, SCRIPT)
            os.chmod(SCRIPT, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
