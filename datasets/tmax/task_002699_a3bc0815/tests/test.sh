#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import gzip
import io
import os
import random
import secrets
import subprocess
import tarfile
import time
import zipfile

import pytest

SCRIPT_PATH = "/home/user/process_archive.sh"
EVIL_CORPUS_DIR = "/home/user/corpora/evil"
CLEAN_CORPUS_DIR = "/home/user/corpora/clean"


def test_process_archive_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Directory {EVIL_CORPUS_DIR} missing."
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.tar')]
    assert len(evil_files) > 0, "No files found in evil corpus."

    bypassed_files = []
    for f in evil_files:
        result = subprocess.run(["bash", SCRIPT_PATH, f], capture_output=True)
        if result.returncode != 1:
            bypassed_files.append(os.path.basename(f))

    if bypassed_files:
        pytest.fail(f"{len(bypassed_files)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed_files[:5])}")


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Directory {CLEAN_CORPUS_DIR} missing."
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.tar')]
    assert len(clean_files) > 0, "No files found in clean corpus."

    failed_files = []
    untransformed_files = []
    for f in clean_files:
        result = subprocess.run(["bash", SCRIPT_PATH, f], capture_output=True, text=True)
        if result.returncode != 0:
            failed_files.append(os.path.basename(f))
        else:
            stdout = result.stdout
            if "[CONFIDENTIAL]" in stdout or "[REDACTED]" not in stdout:
                untransformed_files.append(os.path.basename(f))

    if failed_files or untransformed_files:
        msg = []
        if failed_files:
            msg.append(f"{len(failed_files)} of {len(clean_files)} clean failed to process (exit code != 0). Offending: {', '.join(failed_files[:5])}")
        if untransformed_files:
            msg.append(f"{len(untransformed_files)} of {len(clean_files)} clean modified incorrectly (missing REDACTED or kept CONFIDENTIAL). Offending: {', '.join(untransformed_files[:5])}")
        pytest.fail("; ".join(msg))


def _make_bundle(path, documents):
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, content in documents.items():
            zf.writestr(name, content)

    compressed = gzip.compress(zip_buffer.getvalue())
    with tarfile.open(path, "w") as tf:
        info = tarfile.TarInfo("payload.gz")
        info.size = len(compressed)
        tf.addfile(info, io.BytesIO(compressed))


def test_generated_archives_are_actually_processed(tmp_path):
    token = secrets.token_hex(12)
    cases = []

    for index in range(3):
        marker = f"{token}-clean-{index}"
        documents = {
            "first.md": f"{marker} alpha [CONFIDENTIAL] and [CONFIDENTIAL]\n",
            "nested/second.md": f"{marker} beta remains unchanged\n",
            "nested/third.md": f"{marker} harmless <SCRIPT> and < script> text\n",
        }
        expected = [
            f"{marker} alpha [REDACTED] and [REDACTED]",
            f"{marker} beta remains unchanged",
            f"{marker} harmless <SCRIPT> and < script> text",
        ]
        cases.append((documents, 0, expected))

    forbidden = ["<script>", "<iframe", "<!-- SYSTEM_EXEC:"]
    for index, bad_text in enumerate(forbidden):
        marker = f"{token}-blocked-{index}"
        documents = {
            "ordinary.md": f"{marker} ordinary text\n",
            "nested/target.md": f"{marker} contains {bad_text} randomized payload\n",
        }
        cases.append((documents, 1, None))

    random.SystemRandom().shuffle(cases)
    for documents, expected_code, expected_lines in cases:
        bundle = tmp_path / f"{secrets.token_hex(16)}.tar"
        _make_bundle(bundle, documents)
        result = subprocess.run(
            ["bash", SCRIPT_PATH, str(bundle)],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == expected_code, (
            f"Generated bundle returned {result.returncode}, expected {expected_code}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        if expected_code == 0:
            assert "[CONFIDENTIAL]" not in result.stdout
            assert collections.Counter(result.stdout.splitlines()) == collections.Counter(expected_lines), (
                f"Clean generated bundle output was incorrect: {result.stdout!r}"
            )


def test_nginx_config_fixed():
    nginx_conf = "/app/doc_stack/nginx.conf"
    assert os.path.isfile(nginx_conf), f"{nginx_conf} missing."
    with open(nginx_conf, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:5000" in content or "proxy_pass http://localhost:5000" in content, "Nginx config not updated to proxy to 127.0.0.1:5000."


def test_flask_env_fixed():
    env_file = "/app/doc_stack/.env"
    assert os.path.isfile(env_file), f"{env_file} missing."
    with open(env_file, "r") as f:
        content = f.read()
    assert "REDIS_HOST=127.0.0.1" in content or "REDIS_HOST=localhost" in content, "Flask .env not updated to set REDIS_HOST=127.0.0.1."


def test_end_to_end_api():
    subprocess.run(["pkill", "-f", "nginx"], capture_output=True)
    subprocess.run(["pkill", "-f", "/app/doc_stack/app.py"], capture_output=True)
    subprocess.run(["pkill", "-f", "flask"], capture_output=True)
    subprocess.run(["pkill", "-f", "redis-server"], capture_output=True)

    start_script = "/app/doc_stack/start.sh"
    assert os.path.isfile(start_script), f"{start_script} missing."

    subprocess.Popen(["bash", start_script], cwd="/app/doc_stack", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(3)

    result = subprocess.run(
        ["curl", "-s", "-X", "POST", "http://127.0.0.1:8080/api/render", "--data-binary", "# Test"],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, "curl command failed to execute."
    assert '<h1>Test</h1>' in result.stdout, f"Expected rendered HTML, got: {result.stdout}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
