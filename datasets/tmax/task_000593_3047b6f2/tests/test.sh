#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_ingest.py
import hashlib
import json
import os
import shutil
import stat
import subprocess
import tempfile
import uuid
import zipfile

SOURCE = "/home/user/config_manager/ingest.go"
MODULE = "/home/user/config_manager/go.mod"
MANIFEST = "/home/user/manifest.json"
ORIGINAL_ZIP = "/home/user/incoming/update.zip"
ORIGINAL_TARGET = "/home/user/config_target"
PWNED = "/home/user/pwned.txt"


def assert_regular_file(path):
    st = os.lstat(path)
    assert stat.S_ISREG(st.st_mode), f"Expected a regular file: {path}"


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def run_tool(binary, archive, target):
    result = subprocess.run(
        [binary, archive, target],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"ingest tool failed for {archive}:\nstdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def load_manifest():
    assert os.path.exists(MANIFEST), f"Manifest file missing: {MANIFEST}"
    with open(MANIFEST, "r", encoding="utf-8") as f:
        return json.load(f)


assert os.path.exists(SOURCE), f"Missing required source file: {SOURCE}"
assert_regular_file(SOURCE)
assert os.path.exists(MODULE), f"Go module was not initialized: {MODULE}"
assert_regular_file(MODULE)

with tempfile.TemporaryDirectory(prefix="ingest-verifier-") as work:
    binary = os.path.join(work, "ingest")
    build = subprocess.run(
        ["go", "build", "-o", binary, SOURCE],
        cwd="/home/user/config_manager",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert build.returncode == 0, (
        f"ingest.go does not build:\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )
    assert_regular_file(binary)

    # Re-run the submitted program from a clean state against the supplied archive.
    remove_path(ORIGINAL_TARGET)
    os.makedirs(ORIGINAL_TARGET)
    remove_path(MANIFEST)
    remove_path(PWNED)
    run_tool(binary, ORIGINAL_ZIP, ORIGINAL_TARGET)

    # Preserve the original verifier's assertions.
    assert not os.path.exists(PWNED), (
        f"Security failure: {PWNED} was extracted! Zip slip vulnerability detected."
    )

    server_conf_path = os.path.join(ORIGINAL_TARGET, "server.conf")
    settings_txt_path = os.path.join(ORIGINAL_TARGET, "app", "settings.txt")
    assert os.path.exists(server_conf_path), f"File missing: {server_conf_path}"
    assert os.path.exists(settings_txt_path), f"File missing: {settings_txt_path}"

    with open(server_conf_path, "rb") as f:
        server_conf_content = f.read()
    with open(settings_txt_path, "rb") as f:
        settings_txt_content = f.read()

    expected_server_conf = "port=8080\nnaïve=true".encode("utf-8")
    expected_settings_txt = "café=open\n".encode("utf-8")
    assert server_conf_content == expected_server_conf, (
        f"Content mismatch or encoding error in {server_conf_path}"
    )
    assert settings_txt_content == expected_settings_txt, (
        f"Content mismatch or encoding error in {settings_txt_path}"
    )

    expected_manifest = {
        "server.conf": hashlib.sha256(expected_server_conf).hexdigest(),
        "app/settings.txt": hashlib.sha256(expected_settings_txt).hexdigest(),
    }
    manifest = load_manifest()
    assert manifest == expected_manifest, (
        f"Manifest contents do not match expected values. Got: {manifest}"
    )

    # Exercise the built artifact on an independently generated archive and target.
    case = os.path.join(work, "case-" + uuid.uuid4().hex)
    os.makedirs(case)
    archive = os.path.join(case, "random-input.zip")
    target = os.path.join(case, "random-target")
    os.makedirs(target)

    token = uuid.uuid4().hex
    top_name = f"config-{token}.txt"
    nested_name = f"deep-{token}/settings-{token}.cfg"
    existing_name = f"existing-{token}.txt"

    source_values = {
        top_name: f"name=André\nprice=10€\nid={token}\n",
        nested_name: f"city=Zürich\nquote=“legacy”\nid={token}\n",
        existing_name: f"preexisting=façade\nid={token}\n",
    }

    with open(os.path.join(target, existing_name), "wb") as f:
        f.write(source_values[existing_name].encode("cp1252"))

    escaped = os.path.join(case, "escaped-" + token + ".txt")
    absolute_escape = os.path.join(case, "absolute-" + token + ".txt")
    traversal_entry = "../" + os.path.basename(escaped)

    with zipfile.ZipFile(archive, "w") as zf:
        # Malicious entries precede valid entries to verify they are skipped without aborting.
        zf.writestr(traversal_entry, b"traversal payload")
        zf.writestr(absolute_escape, b"absolute payload")
        zf.writestr(top_name, source_values[top_name].encode("cp1252"))
        zf.writestr(nested_name, source_values[nested_name].encode("cp1252"))

    remove_path(MANIFEST)
    run_tool(binary, archive, target)

    assert not os.path.exists(escaped), f"Zip slip wrote outside target: {escaped}"
    assert not os.path.exists(absolute_escape), (
        f"Absolute zip path wrote outside target: {absolute_escape}"
    )

    dynamic_expected_manifest = {}
    for relative, text in source_values.items():
        expected_bytes = text.encode("utf-8")
        output_path = os.path.join(target, *relative.split("/"))
        assert os.path.isfile(output_path), f"Extracted/processed file missing: {output_path}"
        with open(output_path, "rb") as f:
            actual = f.read()
        assert actual == expected_bytes, f"Incorrect Windows-1252 conversion: {relative}"
        dynamic_expected_manifest[relative] = hashlib.sha256(expected_bytes).hexdigest()

    dynamic_manifest = load_manifest()
    assert dynamic_manifest == dynamic_expected_manifest, (
        f"Dynamic manifest mismatch. Expected {dynamic_expected_manifest}, got {dynamic_manifest}"
    )

assert_regular_file(SOURCE)
print("All ingest checks passed")
TEST_EOF

if python3 /tmp/test_ingest.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
