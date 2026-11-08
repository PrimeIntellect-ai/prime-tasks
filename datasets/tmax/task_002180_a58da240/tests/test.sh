#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import time
import urllib.request
import urllib.error
import uuid
import pytest


def run_filter(path):
    return subprocess.run(
        ["python3", "/home/user/filter.py", path],
        capture_output=True,
        timeout=5,
    ).returncode


def test_filter_script_exists():
    assert os.path.isfile("/home/user/filter.py"), "/home/user/filter.py does not exist."


def test_corpora_validation():
    clean_dir = "/home/user/corpora/clean"
    evil_dir = "/home/user/corpora/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} missing."
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} missing."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_modified = []
    for f in clean_files:
        res = subprocess.run(["python3", "/home/user/filter.py", f], capture_output=True)
        if res.returncode != 0:
            clean_modified.append(os.path.basename(f))

    evil_bypassed = []
    for f in evil_files:
        res = subprocess.run(["python3", "/home/user/filter.py", f], capture_output=True)
        if res.returncode != 1:
            evil_bypassed.append(os.path.basename(f))

    errors = []
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")

    assert not errors, " | ".join(errors)


def test_generated_filter_semantics():
    token = uuid.uuid4().hex
    probe_dir = f"/home/user/.probe_{uuid.uuid4().hex}"
    os.makedirs(probe_dir)

    cases = [
        (0, f"# {token}\nOrdinary documentation.\n"),
        (0, f"# Safe includes\n!INCLUDE[./{token}.md]\n!INCLUDE[images/{token}.png]\n"),
        (0, f'---\n{{"title":"{token}","enabled":true,"count":3}}\n---\n# Document\n'),
        (0, f"# Not frontmatter\n---\n{{ invalid: {token} }}\n---\n"),
        (1, f"# Absolute include\n!INCLUDE[/etc/{token}]\n"),
        (1, f"# Traversal include\n!INCLUDE[chapters/../{token}.md]\n"),
        (1, f'---\n{{"title":"{token}",}}\n---\n# Invalid JSON\n'),
    ]
    random.SystemRandom().shuffle(cases)

    failures = []
    for expected, content in cases:
        path = os.path.join(probe_dir, f"{uuid.uuid4().hex}.md")
        with open(path, "w") as f:
            f.write(content)
        actual = run_filter(path)
        if actual != expected:
            failures.append(f"{os.path.basename(path)}: expected {expected}, got {actual}")

    assert not failures, "Generated semantic cases failed: " + "; ".join(failures)


def test_end_to_end_flow():
    safe_path = "/home/user/docs_src/test_safe.md"
    evil_path = "/home/user/docs_src/test_evil.md"

    with open(safe_path, "w") as f:
        f.write("# Safe Document\nThis is a safe file.\n")

    with open(evil_path, "w") as f:
        f.write("# Evil Document\n!INCLUDE[/etc/shadow]\n")

    # Wait for the watcher and builder to process
    time.sleep(4)

    # Check safe file is served
    try:
        resp = urllib.request.urlopen("http://localhost:8080/test_safe.html")
        assert resp.status == 200, f"Expected safe file to be served with 200 OK, got {resp.status}"
    except urllib.error.HTTPError as e:
        pytest.fail(f"Safe file fetch failed with HTTP Error: {e.code}")
    except urllib.error.URLError as e:
        pytest.fail(f"Safe file fetch failed: {e.reason}")

    # Check evil file is NOT served
    try:
        resp = urllib.request.urlopen("http://localhost:8080/test_evil.html")
        pytest.fail("Evil file was served (200 OK) but should have been blocked (expected 404).")
    except urllib.error.HTTPError as e:
        assert e.code == 404, f"Expected 404 for evil file, got {e.code}"
    except urllib.error.URLError as e:
        pass # Connection refused or similar is also acceptable if nginx drops it, but 404 is standard

    # Check quarantine log
    quarantine_log = "/home/user/quarantine.log"
    assert os.path.exists(quarantine_log), f"{quarantine_log} does not exist. Evil file was not logged."

    with open(quarantine_log, "r") as f:
        log_content = f.read()

    assert "test_evil.md" in log_content, "test_evil.md was not found in /home/user/quarantine.log."


def http_status(url):
    try:
        with urllib.request.urlopen(url, timeout=2) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code
    except urllib.error.URLError:
        return None


def test_randomized_end_to_end_semantics():
    token = uuid.uuid4().hex
    names = [f"{uuid.uuid4().hex}.md" for _ in range(3)]
    safe_name, absolute_name, traversal_name = names

    documents = {
        safe_name: f'---\n{{"title":"{token}","published":true}}\n---\n# Safe {token}\n!INCLUDE[images/{token}.png]\n',
        absolute_name: f"# Unsafe {token}\n!INCLUDE[/etc/{token}]\n",
        traversal_name: f"# Unsafe {token}\n!INCLUDE[assets/../{token}.txt]\n",
    }

    for name, content in documents.items():
        with open(os.path.join("/home/user/docs_src", name), "w") as f:
            f.write(content)

    safe_html = os.path.splitext(safe_name)[0] + ".html"
    evil_html = [
        os.path.splitext(absolute_name)[0] + ".html",
        os.path.splitext(traversal_name)[0] + ".html",
    ]
    evil_names = [absolute_name, traversal_name]
    deadline = time.time() + 12

    safe_ready = False
    quarantined = False
    while time.time() < deadline:
        safe_ready = http_status(f"http://localhost:8080/{safe_html}") == 200
        if os.path.exists("/home/user/quarantine.log"):
            with open("/home/user/quarantine.log", "r") as f:
                log_content = f.read()
            quarantined = all(name in log_content for name in evil_names)
        if safe_ready and quarantined:
            break
        time.sleep(0.25)

    assert safe_ready, f"Randomly named safe document {safe_name} was not built and served."
    assert quarantined, "Randomly named malicious documents were not both written to quarantine.log."

    for html_name in evil_html:
        output_path = os.path.join("/home/user/www", html_name)
        assert not os.path.exists(output_path), f"Malicious document was built as {output_path}."
        status = http_status(f"http://localhost:8080/{html_name}")
        assert status == 404, f"Expected 404 for malicious document {html_name}, got {status}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
