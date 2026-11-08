#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import secrets
import shutil
import subprocess
import tempfile
import time

import pytest
import requests

BINARY = "/home/user/doc_filter"
BACKUP_APP = "/home/user/services/backup/app.py"
BACKUP_HITS = "/tmp/doc_backup_hits"


def stop_test_services():
    if shutil.which("fuser"):
        for port in (5000, 5001, 8080):
            subprocess.run(["fuser", "-k", f"{port}/tcp"], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.3)


@pytest.fixture(scope="session", autouse=True)
def running_pipeline():
    stop_test_services()
    with open(BACKUP_APP, "rb") as f:
        original_backup = f.read()

    recorder = b'''from flask import Flask, request\napp = Flask(__name__)\n@app.route("/health")\ndef health():\n    return "ok", 200\n@app.route("/backup", methods=["POST"])\ndef backup():\n    with open("/tmp/doc_backup_hits", "ab") as f:\n        f.write(request.get_data() + b"\\n")\n    return "Backed up", 200\nif __name__ == "__main__":\n    app.run(host="127.0.0.1", port=5001)\n'''

    proc = None
    restored = False
    try:
        with open(BACKUP_APP, "wb") as f:
            f.write(recorder)
        try:
            os.unlink(BACKUP_HITS)
        except FileNotFoundError:
            pass

        proc = subprocess.Popen(
            ["/home/user/services/start_all.sh"],
            stdout=open("/tmp/doc_services.log", "wb"),
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )

        uploader_ready = backup_ready = nginx_ready = False
        deadline = time.time() + 15
        while time.time() < deadline:
            try:
                uploader_ready = requests.get("http://127.0.0.1:5000/upload", timeout=0.4).status_code in (400, 405)
            except requests.RequestException:
                pass
            try:
                backup_ready = requests.get("http://127.0.0.1:5001/health", timeout=0.4).status_code == 200
            except requests.RequestException:
                pass
            try:
                nginx_ready = requests.get("http://127.0.0.1:8080/", timeout=0.4).status_code in (200, 403, 404)
            except requests.RequestException:
                pass
            if uploader_ready and backup_ready and nginx_ready:
                break
            if proc.poll() is not None:
                break
            time.sleep(0.2)

        with open(BACKUP_APP, "wb") as f:
            f.write(original_backup)
        restored = True

        assert uploader_ready, "Uploader did not start on port 5000 via start_all.sh"
        assert backup_ready, "Backup service did not start on port 5001 via start_all.sh"
        assert nginx_ready, "Nginx did not start on port 8080 via start_all.sh"
        yield
    finally:
        if not restored:
            with open(BACKUP_APP, "wb") as f:
                f.write(original_backup)
        if proc is not None:
            try:
                os.killpg(proc.pid, 15)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, 9)
                except ProcessLookupError:
                    pass
        stop_test_services()


def generated_cases():
    token = secrets.token_hex(10)
    clean = [
        f"[label](file-{token}.md)\n",
        f"prefix [one](images/{token}.png) suffix\n",
        f"[one](a/{token}.md) and [two](b/c-{token}.md)\n",
        f"dangerous text /etc/{token} and ../{token} is not a link\n[ok](safe/{token})\n",
        f"[not a link] (/absolute/{token})\n[ok](dir/{token}.md)\n",
        f"[ok](name..x/{token})\n",
        f"[ok](a/..)\n",
    ]
    evil_targets = [
        f"/{token}/secret",
        f"../{token}.md",
        f"safe/../{token}.md",
        f"a/b/../../{token}",
        f"prefix../suffix-{token}",
        "/",
    ]
    evil = []
    for i, target in enumerate(evil_targets):
        evil.append(f"[safe](ordinary-{token}-{i}.md)\n[text-{i}]({target})\n")
    return clean, evil


DYNAMIC_CLEAN, DYNAMIC_EVIL = generated_cases()


def exercise_filter(executable, clean_cases=DYNAMIC_CLEAN, evil_cases=DYNAMIC_EVIL):
    failures = []
    with tempfile.TemporaryDirectory(prefix="filter-cases-") as td:
        for expected, cases in ((0, clean_cases), (1, evil_cases)):
            for i, content in enumerate(cases):
                path = os.path.join(td, f"case-{expected}-{i}-{secrets.token_hex(4)}.md")
                with open(path, "w", encoding="utf-8") as f:
                    f.write(content)
                try:
                    result = subprocess.run([executable, path], stdout=subprocess.PIPE,
                                            stderr=subprocess.PIPE, timeout=3)
                except Exception as exc:
                    failures.append(f"case {expected}/{i} could not run: {exc}")
                    continue
                if result.returncode != expected:
                    failures.append(
                        f"case {expected}/{i} returned {result.returncode}; expected {expected}"
                    )
    return failures


def test_doc_filter_binary_exists():
    binary_path = "/home/user/doc_filter"
    assert os.path.isfile(binary_path), f"Document filter binary missing: {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Document filter binary is not executable: {binary_path}"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Document filter must be a compiled native executable"


def test_doc_filter_corpus():
    binary_path = "/home/user/doc_filter"
    clean_dir = "/home/user/corpora/clean"
    evil_dir = "/home/user/corpora/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    for f in clean_files:
        filepath = os.path.join(clean_dir, f)
        result = subprocess.run([binary_path, filepath], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(f)

    evil_bypassed = []
    for f in evil_files:
        filepath = os.path.join(evil_dir, f)
        result = subprocess.run([binary_path, filepath], capture_output=True)
        if result.returncode != 1:
            evil_bypassed.append(f)

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")

    assert not errors, "Corpus verification failed:\n" + "\n".join(errors)


def test_doc_filter_generated_inputs():
    failures = exercise_filter(BINARY)
    assert not failures, "Generated filter cases failed:\n" + "\n".join(failures)


def test_filter_has_working_c_source():
    candidates = []
    for path in glob.glob("/home/user/**/*.c", recursive=True):
        if os.path.isfile(path):
            candidates.append(path)
    assert candidates, "No C source file for the document filter was found under /home/user"

    compile_errors = []
    with tempfile.TemporaryDirectory(prefix="rebuild-filter-") as td:
        for i, source in enumerate(candidates):
            rebuilt = os.path.join(td, f"filter-{i}")
            result = subprocess.run(["gcc", "-O2", source, "-o", rebuilt], capture_output=True,
                                    text=True, timeout=15)
            if result.returncode != 0:
                compile_errors.append(f"{source}: did not compile")
                continue
            if not exercise_filter(rebuilt):
                return
            compile_errors.append(f"{source}: rebuilt program failed generated cases")
    pytest.fail("No supplied C source rebuilt into a working document filter: " + "; ".join(compile_errors))


def test_uploader_config():
    config_path = "/home/user/services/uploader/config.json"
    assert os.path.isfile(config_path), f"Uploader config missing: {config_path}"

    with open(config_path, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Uploader config is not valid JSON: {config_path}")

    assert config.get("FILTER_BIN") == "/home/user/doc_filter", "FILTER_BIN not set correctly"
    assert config.get("PUBLISH_DIR") == "/home/user/docs_published", "PUBLISH_DIR not set correctly"
    assert config.get("BACKUP_URL") == "http://127.0.0.1:5001/backup", "BACKUP_URL not set correctly"


def test_nginx_config():
    config_path = "/home/user/services/nginx/nginx.conf"
    assert os.path.isfile(config_path), f"Nginx config missing: {config_path}"

    with open(config_path, "r") as f:
        content = f.read()

    server_8080_pattern = re.compile(r'listen\s+8080\s*;.*?root\s+/home/user/docs_published\s*;', re.DOTALL)
    assert "/home/user/docs_published" in content, "Nginx config does not contain the correct root path"
    syntax = subprocess.run(["nginx", "-t", "-c", config_path], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Invalid Nginx configuration: {syntax.stderr}"


def test_file_operations_and_linking():
    publish_dir = "/home/user/docs_published"
    assert os.path.isdir(publish_dir), f"Publish directory missing: {publish_dir}"

    symlink_path = os.path.join(publish_dir, "index.md")
    assert os.path.islink(symlink_path), f"Symlink missing or not a symlink: {symlink_path}"

    target = os.readlink(symlink_path)
    expected_target = "/home/user/docs_published/home.md"

    if not os.path.isabs(target):
        target = os.path.normpath(os.path.join(publish_dir, target))

    assert target == expected_target, f"Symlink points to {target}, expected {expected_target}"


def test_end_to_end_upload_serving_rejection_and_backup():
    token = secrets.token_hex(12)
    clean_body = f"Documentation {token}\n[asset](images/{token}.png)\n"
    evil_name = f"evil-{token}.md"
    evil_body = f"Attack {token}\n[secret](safe/../private-{token})\n"

    try:
        os.unlink(BACKUP_HITS)
    except FileNotFoundError:
        pass

    response = requests.post(
        "http://127.0.0.1:5000/upload",
        files={"file": ("home.md", clean_body.encode(), "text/markdown")},
        timeout=5,
    )
    assert response.status_code == 200, f"Clean upload failed: {response.status_code} {response.text}"

    published = "/home/user/docs_published/home.md"
    assert os.path.isfile(published), "Uploader did not publish the approved file"
    with open(published, "r", encoding="utf-8") as f:
        assert f.read() == clean_body, "Published file content differs from the upload"

    served = requests.get("http://127.0.0.1:8080/home.md", timeout=5)
    assert served.status_code == 200, f"Nginx did not serve the approved file: {served.status_code}"
    assert served.text == clean_body

    via_link = requests.get("http://127.0.0.1:8080/index.md", timeout=5)
    assert via_link.status_code == 200, "Nginx did not serve index.md through the required symlink"
    assert via_link.text == clean_body

    deadline = time.time() + 5
    while time.time() < deadline and not os.path.exists(BACKUP_HITS):
        time.sleep(0.1)
    assert os.path.isfile(BACKUP_HITS), "Successful upload did not make a request to the backup service"
    with open(BACKUP_HITS, "rb") as f:
        assert b"backup" in f.read(), "Backup endpoint received no expected backup payload"

    evil_response = requests.post(
        "http://127.0.0.1:5000/upload",
        files={"file": (evil_name, evil_body.encode(), "text/markdown")},
        timeout=5,
    )
    assert evil_response.status_code == 403, f"Malicious upload was not rejected: {evil_response.status_code}"
    assert not os.path.exists(os.path.join("/home/user/docs_published", evil_name)), \
        "Rejected upload was nevertheless published"
    not_served = requests.get(f"http://127.0.0.1:8080/{evil_name}", timeout=5)
    assert not_served.status_code == 404, "Rejected upload is accessible through Nginx"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
