#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import socket
import subprocess
import tempfile
import time
import uuid
import zipfile

import pytest
import requests


def wait_for_archive(zip_path, timeout=15):
    start_time = time.time()
    while time.time() - start_time < timeout:
        if not os.path.exists(zip_path):
            return
        time.sleep(0.25)
    pytest.fail(f"Zip file {zip_path} was not deleted after processing")


def create_malicious_zip(zip_path):
    manifest = [
        {
            "source": "content/intro.md",
            "published_path": "manual/intro.md",
            "version": "v3.14",
        }
    ]
    with zipfile.ZipFile(zip_path, "w") as zf:
        zf.writestr("manifest.json", json.dumps(manifest))
        zf.writestr("content/intro.md", "# Introduction\n\nVersion: __VERSION__\n")
        zf.writestr("../../home/user/canary.txt", "You have been hacked!")


@pytest.fixture(scope="module", autouse=True)
def trigger_processing():
    zip_path = "/home/user/incoming/docs.zip"
    create_malicious_zip(zip_path)
    wait_for_archive(zip_path)
    time.sleep(2)


def test_zip_slip_mitigated():
    canary_path = "/home/user/canary.txt"
    assert not os.path.exists(canary_path), "Zip Slip vulnerability still present: canary file was extracted outside the destination directory."


def test_zip_file_deleted():
    zip_path = "/home/user/incoming/docs.zip"
    assert not os.path.exists(zip_path), f"Zip file {zip_path} was not deleted after processing."


def test_http_server_serves_transformed_content():
    url = "http://127.0.0.1:8080/docs/manual/intro.md"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    content = response.text
    assert "Version: v3.14" in content, "The markdown content was not properly transformed. Expected 'Version: v3.14' to be present."
    assert "__VERSION__" not in content, "The literal string '__VERSION__' was not replaced in the markdown content."


def test_symlink_created_correctly():
    symlink_path = "/home/user/www/manual/intro.md"
    assert os.path.islink(symlink_path), f"Expected {symlink_path} to be a symbolic link."
    target_path = os.readlink(symlink_path)
    expected_target_suffix = "content/intro.md"
    assert target_path.endswith(expected_target_suffix), f"Symlink target {target_path} does not point to the expected extracted file."


def test_randomized_archive_is_processed_and_traversal_is_blocked():
    nonce = uuid.uuid4().hex
    source = f"raw-{nonce}/document-{nonce}.md"
    published = f"generated-{nonce}/page-{nonce}.md"
    version = f"release-{nonce}"
    marker = f"body-{nonce}"
    zip_path = f"/home/user/incoming/job-{nonce}.zip"
    canary_home = f"/home/user/canary-{nonce}.txt"
    canary_tmp = f"/tmp/zip-slip-{nonce}.txt"

    for path in (canary_home, canary_tmp):
        if os.path.lexists(path):
            os.unlink(path)

    manifest = [{"source": source, "published_path": published, "version": version}]
    with zipfile.ZipFile(zip_path, "w") as zf:
        zf.writestr("manifest.json", json.dumps(manifest))
        zf.writestr(source, f"# {marker}\nVersion: __VERSION__\nAgain: __VERSION__\n")
        zf.writestr(f"../canary-{nonce}.txt", "escaped")
        zf.writestr(f"../../../tmp/zip-slip-{nonce}.txt", "escaped")

    wait_for_archive(zip_path)

    url = f"http://127.0.0.1:8080/docs/{published}"
    deadline = time.time() + 5
    response = None
    while time.time() < deadline:
        try:
            response = requests.get(url, timeout=2)
            if response.status_code == 200:
                break
        except requests.exceptions.RequestException:
            pass
        time.sleep(0.2)

    assert response is not None and response.status_code == 200, f"Randomized published path was not served at {url}"
    assert marker in response.text
    assert response.text.count(version) == 2
    assert "__VERSION__" not in response.text
    assert not os.path.exists(canary_home), "A ../ archive entry escaped the extraction directory"
    assert not os.path.exists(canary_tmp), "A ../../ archive entry escaped the extraction directory"

    link_path = os.path.join("/home/user/www", published)
    assert os.path.islink(link_path), f"Expected {link_path} to be a symbolic link"
    assert os.readlink(link_path).endswith(source), "Randomized symlink does not target the transformed source file"
    extracted_path = os.path.join("/home/user/extracted", source)
    with open(extracted_path, encoding="utf-8") as f:
        transformed = f.read()
    assert transformed.count(version) == 2 and "__VERSION__" not in transformed


def test_vendored_ziputil_is_importable_and_secure_when_called_directly():
    package_dir = "/app/vendored/ziputil"
    assert os.path.isfile(os.path.join(package_dir, "go.mod"))
    assert os.path.isfile(os.path.join(package_dir, "ziputil.go"))

    module_info = subprocess.run(
        ["go", "list", "-m", "-json"], cwd=package_dir,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert module_info.returncode == 0, f"Vendored go.mod is not valid: {module_info.stderr}"
    module_path = json.loads(module_info.stdout).get("Path", "")
    assert re.fullmatch(r"[A-Za-z0-9._~+/:-]+", module_path), "Vendored module has an invalid module path"

    nonce = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="ziputil-check-") as td:
        archive = os.path.join(td, "probe.zip")
        destination = os.path.join(td, "destination")
        outside = os.path.join(td, "outside.txt")
        with zipfile.ZipFile(archive, "w") as zf:
            zf.writestr("nested/safe.txt", f"safe-{nonce}")
            zf.writestr("../outside.txt", "escaped")

        probe_dir = os.path.join(td, "probe")
        os.mkdir(probe_dir)
        with open(os.path.join(probe_dir, "go.mod"), "w", encoding="utf-8") as f:
            f.write(f"module verifierprobe\n\ngo 1.20\n\nrequire {module_path} v0.0.0\nreplace {module_path} => {package_dir}\n")
        with open(os.path.join(probe_dir, "main.go"), "w", encoding="utf-8") as f:
            f.write(
                'package main\n'
                'import (\n'
                '  "fmt"\n'
                '  "os"\n'
                f'  ziputil {json.dumps(module_path)}\n'
                ')\n'
                'func main() {\n'
                '  if len(os.Args) != 3 { panic("arguments") }\n'
                '  if err := ziputil.Extract(os.Args[1], os.Args[2]); err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(1) }\n'
                '}\n'
            )
        run = subprocess.run(
            ["go", "run", ".", archive, destination], cwd=probe_dir,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30,
            env={**os.environ, "GO111MODULE": "on"}
        )
        assert run.returncode == 0, f"Calling ziputil.Extract failed: {run.stderr}"
        with open(os.path.join(destination, "nested", "safe.txt"), encoding="utf-8") as f:
            assert f.read() == f"safe-{nonce}"
        assert not os.path.exists(outside), "Vendored ziputil.Extract remains vulnerable to Zip Slip"

    go_sources = glob.glob("/home/user/docserver/**/*.go", recursive=True)
    assert go_sources, "No Go service source exists under /home/user/docserver"
    assert any(module_path in open(path, encoding="utf-8", errors="ignore").read() for path in go_sources), \
        "The Go service source does not import the vendored ziputil module"


def test_port_8080_is_owned_by_a_compiled_go_program():
    listener_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, encoding="ascii") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_address, state, inode = fields[1], fields[3], fields[9]
                    if local_address.rsplit(":", 1)[1].upper() == "1F90" and state == "0A":
                        listener_inodes.add(inode)
        except FileNotFoundError:
            pass
    assert listener_inodes, "No process is listening on port 8080"

    owning_pids = set()
    for proc_path in glob.glob("/proc/[0-9]*"):
        pid = os.path.basename(proc_path)
        for fd in glob.glob(os.path.join(proc_path, "fd", "*")):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in listener_inodes:
                owning_pids.add(pid)
                break

    assert owning_pids, "Could not identify the process listening on port 8080"
    go_owners = []
    diagnostics = []
    for pid in owning_pids:
        result = subprocess.run(
            ["go", "version", "-m", f"/proc/{pid}/exe"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        diagnostics.append(result.stdout + result.stderr)
        if result.returncode == 0 and re.search(r"\bgo1\d+\.", result.stdout):
            go_owners.append(pid)
    assert go_owners, "The service listening on port 8080 is not a compiled Go program: " + " | ".join(diagnostics)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
