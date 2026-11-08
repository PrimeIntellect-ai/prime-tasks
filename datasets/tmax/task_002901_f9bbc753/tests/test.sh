#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import random
import re
import shutil
import string
import subprocess
import time
import uuid
import pytest


def _strip_nginx_comments(content):
    lines = []
    for line in content.splitlines():
        out = []
        quote = None
        escaped = False
        for ch in line:
            if escaped:
                out.append(ch)
                escaped = False
                continue
            if ch == "\\":
                out.append(ch)
                escaped = True
                continue
            if quote:
                out.append(ch)
                if ch == quote:
                    quote = None
            elif ch in ("'", '"'):
                out.append(ch)
                quote = ch
            elif ch == '#':
                break
            else:
                out.append(ch)
        lines.append(''.join(out))
    return '\n'.join(lines)


def _server_blocks(content):
    blocks = []
    for match in re.finditer(r'(?<![A-Za-z0-9_])server\s*\{', content):
        brace = content.find('{', match.start())
        depth = 0
        for pos in range(brace, len(content)):
            if content[pos] == '{':
                depth += 1
            elif content[pos] == '}':
                depth -= 1
                if depth == 0:
                    blocks.append(content[brace + 1:pos])
                    break
    return blocks


def test_nginx_configuration():
    """Check that nginx.conf is valid and actively configures the required server."""
    conf_path = '/app/nginx.conf'
    assert os.path.isfile(conf_path), f"{conf_path} does not exist."

    with open(conf_path, 'r') as f:
        content = f.read()

    # Preserve the original assertions.
    assert "8080" in content, "Nginx is not configured to listen on port 8080."
    assert "/app/docs" in content, "Nginx is not configured to serve /app/docs/."
    assert "disable_symlinks off;" in content, "Nginx is not configured with 'disable_symlinks off;'."

    checked = subprocess.run(
        ['nginx', '-t', '-c', conf_path],
        text=True,
        capture_output=True
    )
    assert checked.returncode == 0, (
        "nginx.conf is not a valid Nginx configuration:\n"
        + checked.stdout + checked.stderr
    )

    active = _strip_nginx_comments(content)
    blocks = _server_blocks(active)
    assert blocks, "nginx.conf has no active server block."

    found = False
    for block in blocks:
        has_listen = re.search(
            r'(?:^|[;{}])\s*listen\s+[^;]*(?<!\d)8080(?!\d)[^;]*;',
            block,
            re.MULTILINE
        )
        has_root = re.search(
            r'(?:^|[;{}])\s*root\s+/app/docs/?\s*;',
            block,
            re.MULTILINE
        )
        has_symlinks = re.search(
            r'(?:^|[;{}])\s*disable_symlinks\s+off\s*;',
            block,
            re.MULTILINE
        )
        if has_listen and has_root and has_symlinks:
            found = True
            break

    assert found, (
        "A single active server block must listen on port 8080, use root "
        "/app/docs/, and set disable_symlinks off."
    )


def test_watcher_configuration():
    """Check that watcher.conf actively sets the correct process script."""
    conf_path = '/app/watcher.conf'
    assert os.path.isfile(conf_path), f"{conf_path} does not exist."

    with open(conf_path, 'r') as f:
        content = f.read()

    # Preserve the original assertion.
    assert "PROCESS_SCRIPT=/home/user/parse_docs.sh" in content, \
        "watcher.conf does not point to /home/user/parse_docs.sh."

    proc = subprocess.run(
        [
            'bash', '-c',
            'unset PROCESS_SCRIPT; source "$1" >/dev/null; '
            'status=$?; printf "%s" "${PROCESS_SCRIPT-}"; exit "$status"',
            'watcher-check', conf_path
        ],
        text=True,
        capture_output=True
    )
    assert proc.returncode == 0, f"watcher.conf is not a valid sourceable configuration: {proc.stderr}"
    assert proc.stdout == '/home/user/parse_docs.sh', \
        "watcher.conf does not actively set PROCESS_SCRIPT to /home/user/parse_docs.sh."


def test_script_exists_and_executable():
    """Check that the parsing script exists and is executable."""
    script_path = '/home/user/parse_docs.sh'
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_lock_is_acquired_before_file_operations():
    """A competing exclusive lock must prevent documentation updates."""
    script_path = '/home/user/parse_docs.sh'
    lock_path = '/app/docs/.lock'
    os.makedirs('/app/docs/by-tag', exist_ok=True)
    open(lock_path, 'a').close()

    token = uuid.uuid4().hex
    tag = f'locktest_{token}'
    source = f'/tmp/locktest_{token}.md'
    link = f'/app/docs/by-tag/{tag}/{os.path.basename(source)}'
    metadata = f'PATH: {source}\nAUTHOR: Lock Tester\nTAGS: {tag}\n'

    lock_fd = os.open(lock_path, os.O_RDWR)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    proc = subprocess.Popen(
        [script_path],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    assert proc.stdin is not None
    proc.stdin.write(metadata)
    proc.stdin.close()
    proc.stdin = None

    try:
        time.sleep(0.5)
        assert proc.poll() is None, \
            "The parsing script completed while /app/docs/.lock was held by another process."
        assert not os.path.lexists(link), \
            "The parsing script modified tag links before acquiring /app/docs/.lock."
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)

    stdout, stderr = proc.communicate(timeout=8)
    assert proc.returncode == 0, f"Parsing script failed after the lock was released: {stderr}"
    assert stdout == f'[Lock Tester] processed [{os.path.basename(source)}] with [1] tags\n'
    assert os.path.islink(link), "Parsing script did not create the required symlink after acquiring the lock."
    assert os.readlink(link) == source, "Created symlink does not point to the PATH value."


def generate_random_record():
    path_len = random.randint(5, 20)
    path = "/tmp/" + "".join(random.choices(string.ascii_lowercase, k=path_len)) + ".md"

    author_len = random.randint(5, 15)
    author = "".join(random.choices(string.ascii_letters + " ", k=author_len)).strip()
    if not author:
        author = "Default Author"

    num_tags = random.randint(1, 10)
    tags = []
    for _ in range(num_tags):
        tags.append("".join(random.choices(string.ascii_lowercase, k=random.randint(3, 8))))

    ws1 = " " * random.randint(0, 3)
    ws2 = " " * random.randint(0, 3)
    ws3 = " " * random.randint(0, 3)

    tags_str = ("," + " " * random.randint(0, 2)).join(tags)
    record = f"PATH:{ws1}{path}\nAUTHOR:{ws2}{author}\nTAGS:{ws3}{tags_str}"
    return record, path, tags


def test_fuzz_equivalence():
    """Check exact output and all required directories and symlinks."""
    oracle_path = '/app/oracle.py'
    agent_script = '/home/user/parse_docs.sh'

    assert os.path.isfile(oracle_path), f"Oracle program {oracle_path} missing."

    random.seed(42)

    for i in range(100):
        tag_root = '/app/docs/by-tag'
        shutil.rmtree(tag_root, ignore_errors=True)
        os.makedirs(tag_root, exist_ok=True)

        num_records = random.randint(1, 50)
        generated = [generate_random_record() for _ in range(num_records)]
        records = [item[0] for item in generated]

        sep = "\n" + "\n" * random.randint(1, 2)
        fuzz_input = sep.join(records) + "\n"

        try:
            oracle_proc = subprocess.run(
                [oracle_path],
                input=fuzz_input,
                text=True,
                capture_output=True,
                check=True
            )
            oracle_out = oracle_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input:\n{fuzz_input}\nError: {e.stderr}")

        try:
            agent_proc = subprocess.run(
                [agent_script],
                input=fuzz_input,
                text=True,
                capture_output=True,
                check=True,
                timeout=15
            )
            agent_out = agent_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on input:\n{fuzz_input}\nError: {e.stderr}")

        assert agent_out == oracle_out, (
            f"Output mismatch on fuzz iteration {i}.\n"
            f"Input:\n{fuzz_input}\n"
            f"Expected (Oracle):\n{oracle_out}\n"
            f"Got (Agent):\n{agent_out}"
        )

        for _, target, tags in generated:
            filename = os.path.basename(target)
            for tag in tags:
                tag_dir = os.path.join(tag_root, tag)
                link_path = os.path.join(tag_dir, filename)
                assert os.path.isdir(tag_dir), f"Missing tag directory {tag_dir} on fuzz iteration {i}."
                assert os.path.islink(link_path), f"Missing symbolic link {link_path} on fuzz iteration {i}."
                assert os.readlink(link_path) == target, (
                    f"Symlink {link_path} points to {os.readlink(link_path)!r}, expected {target!r}."
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
