#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess
import tempfile
from pathlib import Path


def run_classifier(classifier, request_file):
    return subprocess.run(
        ["python3", str(classifier), str(request_file)],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_incident_frame():
    """Verify the correct frame number is written to incident_frame.txt."""
    frame_txt = Path("/home/user/incident_frame.txt")
    assert frame_txt.is_file(), f"File not found: {frame_txt}"
    content = frame_txt.read_text().strip()
    assert content == "142", f"Expected frame '142', but got '{content}'"


def test_nginx_config():
    """Verify nginx.conf is syntactically coherent and all proxy_pass directives use the fixed upstream."""
    conf_path = Path("/home/user/gateway/nginx.conf")
    assert conf_path.is_file(), f"File not found: {conf_path}"
    content = conf_path.read_text()
    assert "proxy_pass http://127.0.0.1:8081;" in content, \
        "nginx.conf does not contain the corrected proxy_pass directive"

    # Parse the supplied Nginx configuration fragment sufficiently to reject
    # unbalanced blocks, unterminated directives, and active stale proxy_pass
    # directives. The image intentionally contains a server fragment rather
    # than a complete nginx.conf with an events section.
    uncommented = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    tokens = re.findall(r"[{};]|[^\s{};]+", uncommented)
    stack = []
    pending = []
    proxies = []

    for token in tokens:
        if token == "{":
            assert pending, "Invalid Nginx syntax: block has no directive header"
            stack.append(tuple(pending))
            pending = []
        elif token == ";":
            assert pending, "Invalid Nginx syntax: empty directive"
            if pending[0] == "proxy_pass":
                assert len(pending) == 2, "Invalid proxy_pass directive"
                proxies.append((pending[1], tuple(stack)))
            pending = []
        elif token == "}":
            assert not pending, "Invalid Nginx syntax: directive is missing a semicolon"
            assert stack, "Invalid Nginx syntax: unmatched closing brace"
            stack.pop()
        else:
            pending.append(token)

    assert not pending, "Invalid Nginx syntax: unterminated directive"
    assert not stack, "Invalid Nginx syntax: unclosed block"
    assert proxies, "No active proxy_pass directive found"
    assert all(value == "http://127.0.0.1:8081" for value, _ in proxies), \
        f"Found an incorrect active proxy_pass directive: {[value for value, _ in proxies]}"
    for _, contexts in proxies:
        assert any(ctx and ctx[0] == "server" for ctx in contexts), \
            "proxy_pass is not inside a server block"
        assert any(ctx and ctx[0] == "location" for ctx in contexts), \
            "proxy_pass is not inside a location block"


def test_classifier_adversarial_corpus():
    """Preserve the original corpus checks."""
    classifier_path = Path("/home/user/classifier.py")
    assert classifier_path.is_file(), f"Classifier not found at {classifier_path}"

    clean_dir = Path("/app/corpus/clean")
    evil_dir = Path("/app/corpus/evil")
    clean_files = list(clean_dir.iterdir()) if clean_dir.is_dir() else []
    evil_files = list(evil_dir.iterdir()) if evil_dir.is_dir() else []
    clean_failed = []
    evil_failed = []

    for request_file in clean_files:
        if request_file.is_file():
            result = run_classifier(classifier_path, request_file)
            if result.returncode != 0 or "CLEAN" not in result.stdout:
                clean_failed.append(request_file.name)

    for request_file in evil_files:
        if request_file.is_file():
            result = run_classifier(classifier_path, request_file)
            if result.returncode != 1 or "EVIL" not in result.stdout:
                evil_failed.append(request_file.name)

    errors = []
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    assert not errors, " | ".join(errors)


def test_classifier_randomized_requests():
    """Exercise request parsing with unpredictable filenames and request data."""
    classifier = Path("/home/user/classifier.py")
    assert classifier.is_file(), f"Classifier not found at {classifier}"

    token = secrets.token_hex(10)
    host = f"{secrets.token_hex(6)}.example"
    cases = [
        (f"GET /{token}/index.html HTTP/1.1\r\nHost: {host}\r\n\r\n", "CLEAN", 0),
        (f"POST /submit/{token} HTTP/1.1\r\nHost: {host}\r\nX-Note: ../not-the-path\r\nContent-Length: 3\r\n\r\n../", "CLEAN", 0),
        (f"GET /archive/..hidden/{token} HTTP/1.1\r\nHost: {host}\r\n\r\n", "CLEAN", 0),
        (f"GET /api/{token}/../private HTTP/1.1\r\nHost: {host}\r\n\r\n", "EVIL", 1),
        (f"GET /assets/%2e%2E/{token} HTTP/1.1\r\nHost: {host}\r\n\r\n", "EVIL", 1),
        (f"HEAD /%2E%2e/secrets/{token} HTTP/1.1\r\nHost: {host}\r\n\r\n", "EVIL", 1),
    ]
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="classifier-check-") as temp_dir:
        temp = Path(temp_dir)
        for request, expected_output, expected_code in cases:
            request_path = temp / f"request-{secrets.token_hex(12)}.dat"
            request_path.write_text(request)
            result = run_classifier(classifier, request_path)
            assert result.returncode == expected_code, \
                f"Classifier returned {result.returncode}, expected {expected_code}, for request {request!r}"
            assert result.stdout.strip() == expected_output, \
                f"Classifier printed {result.stdout!r}, expected exactly {expected_output!r}"

    no_arg = subprocess.run(["python3", str(classifier)], capture_output=True, text=True, timeout=10)
    two_args = subprocess.run(
        ["python3", str(classifier), "/dev/null", "/dev/null"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert no_arg.returncode != 0, "Classifier accepted zero request-file arguments"
    assert two_args.returncode != 0, "Classifier accepted more than one request-file argument"


def test_git_pre_commit_hook():
    """Verify the hook handles dynamically named staged request files."""
    repo_dir = Path("/home/user/gateway")
    hook_path = repo_dir / ".git" / "hooks" / "pre-commit"

    assert hook_path.is_file(), "pre-commit hook does not exist"
    assert os.access(hook_path, os.X_OK), "pre-commit hook is not executable"

    # Unstage unrelated agent files without changing their working-tree contents,
    # so only the generated requests participate in these commits.
    subprocess.run(["git", "reset", "--mixed", "HEAD"], cwd=repo_dir, check=True, capture_output=True)

    evil_name = f"request-{secrets.token_hex(12)}.req"
    evil_file = repo_dir / evil_name
    evil_file.write_text(
        f"GET /{secrets.token_hex(8)}/%2e%2E/private HTTP/1.1\n"
        f"Host: {secrets.token_hex(5)}.example\n"
    )
    subprocess.run(["git", "add", "--", evil_name], cwd=repo_dir, check=True)
    evil_result = subprocess.run(
        ["git", "commit", "-m", f"dynamic evil {secrets.token_hex(4)}"],
        cwd=repo_dir,
        capture_output=True,
        text=True,
    )
    assert evil_result.returncode != 0, \
        "Git commit succeeded for a dynamically named EVIL .req file"

    subprocess.run(["git", "reset", "--mixed", "HEAD", "--", evil_name], cwd=repo_dir, check=True)
    evil_file.unlink(missing_ok=True)

    # An unstaged evil request must not cause a staged clean request to fail.
    unstaged_name = f"request-{secrets.token_hex(12)}.req"
    unstaged_file = repo_dir / unstaged_name
    unstaged_file.write_text("GET /random/../private HTTP/1.1\n")

    clean_name = f"request-{secrets.token_hex(12)}.req"
    clean_file = repo_dir / clean_name
    clean_file.write_text(
        f"GET /public/{secrets.token_hex(10)}.html HTTP/1.1\n"
        f"Host: {secrets.token_hex(5)}.example\n"
    )
    subprocess.run(["git", "add", "--", clean_name], cwd=repo_dir, check=True)
    clean_result = subprocess.run(
        ["git", "commit", "-m", f"dynamic clean {secrets.token_hex(4)}"],
        cwd=repo_dir,
        capture_output=True,
        text=True,
    )
    assert clean_result.returncode == 0, \
        f"Git commit failed for a dynamically named staged CLEAN .req file: {clean_result.stderr}"
    unstaged_file.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
