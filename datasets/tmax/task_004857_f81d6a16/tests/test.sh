#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import subprocess
import tarfile


def test_nginx_conf_content():
    conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(conf_path), f"{conf_path} does not exist."

    with open(conf_path, "r") as f:
        content = f.read()

    # Preserve the original required-directive assertions.
    assert "pid /home/user/nginx.pid;" in content or "pid" in content and "/home/user/nginx.pid" in content, "Missing or incorrect pid directive."
    assert "error_log /home/user/error.log;" in content or "error_log" in content and "/home/user/error.log" in content, "Missing or incorrect error_log directive."
    assert "access_log" in content and "/home/user/access.log" in content, "Missing or incorrect access_log directive."
    assert "events" in content, "Missing events block."
    assert "http" in content, "Missing http block."
    assert "listen 8080;" in content or "listen" in content and "8080" in content, "Missing or incorrect listen directive."
    assert "proxy_pass http://backend;" in content or "proxy_pass" in content and "http://backend" in content, "Missing or incorrect proxy_pass directive."
    assert "upstream backend" in content, "Missing upstream backend block."
    assert "127.0.0.1:8081" in content, "Missing backend server 127.0.0.1:8081."
    assert "127.0.0.1:8082" in content, "Missing backend server 127.0.0.1:8082."


def _lex_nginx(text):
    tokens = []
    buf = []
    quote = None
    escaped = False
    i = 0

    def flush():
        if buf:
            tokens.append("".join(buf))
            buf.clear()

    while i < len(text):
        ch = text[i]
        if quote is not None:
            if escaped:
                buf.append(ch)
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = None
            else:
                buf.append(ch)
            i += 1
            continue

        if ch == "#":
            flush()
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            i += 1
            continue
        if ch.isspace():
            flush()
            i += 1
            continue
        if ch in "{};":
            flush()
            tokens.append(ch)
            i += 1
            continue
        buf.append(ch)
        i += 1

    assert quote is None, "Unterminated quote in nginx configuration"
    flush()
    return tokens


def _parse_nginx(tokens):
    def parse_block(pos, nested):
        nodes = []
        while pos < len(tokens):
            if tokens[pos] == "}":
                assert nested, "Unexpected closing brace"
                return nodes, pos + 1

            head = []
            while pos < len(tokens) and tokens[pos] not in (";", "{", "}"):
                head.append(tokens[pos])
                pos += 1
            assert head, "Empty or malformed nginx directive"
            assert pos < len(tokens), "Unterminated nginx directive"
            assert tokens[pos] != "}", "Directive missing semicolon or block"

            if tokens[pos] == ";":
                nodes.append((tuple(head), None))
                pos += 1
            else:
                children, pos = parse_block(pos + 1, True)
                nodes.append((tuple(head), children))

        assert not nested, "Unclosed nginx block"
        return nodes, pos

    nodes, end = parse_block(0, False)
    assert end == len(tokens)
    return nodes


def _directives(nodes, name, block=None):
    result = []
    for args, children in nodes:
        if args and args[0] == name and (block is None or (children is not None) == block):
            result.append((args, children))
    return result


def test_nginx_configuration_is_valid_and_active():
    conf_path = "/home/user/nginx.conf"
    result = subprocess.run(
        ["nginx", "-t", "-c", conf_path, "-p", "/home/user/"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, result.stdout + result.stderr

    with open(conf_path, "r") as f:
        nodes = _parse_nginx(_lex_nginx(f.read()))

    assert any(args[1:] == ("/home/user/nginx.pid",) for args, _ in _directives(nodes, "pid", False)), "Missing active root-level pid directive"
    assert any(len(args) >= 2 and args[1] == "/home/user/error.log" for args, _ in _directives(nodes, "error_log", False)), "Missing active root-level error_log directive"
    assert _directives(nodes, "events", True), "Missing active root-level events block"

    http_blocks = _directives(nodes, "http", True)
    assert http_blocks, "Missing active root-level http block"
    assert any(
        len(args) >= 2 and args[1] == "/home/user/access.log"
        for _, http in http_blocks
        for args, _ in _directives(http, "access_log", False)
    ), "Missing active access_log directive in the http block"

    for _, http in http_blocks:
        upstreams = [children for args, children in _directives(http, "upstream", True) if args[1:] == ("backend",)]
        for upstream in upstreams:
            backend_servers = {args[1] for args, _ in _directives(upstream, "server", False) if len(args) >= 2}
            if not {"127.0.0.1:8081", "127.0.0.1:8082"}.issubset(backend_servers):
                continue

            for _, server in _directives(http, "server", True):
                listens = [arg for args, _ in _directives(server, "listen", False) for arg in args[1:]]
                if not any(re.search(r"(^|:)8080$", value) for value in listens):
                    continue
                locations = [children for args, children in _directives(server, "location", True) if args[1:] == ("/",)]
                if any(
                    any(args[1:] == ("http://backend",) for args, _ in _directives(location, "proxy_pass", False))
                    for location in locations
                ):
                    return

    raise AssertionError("No active port-8080 server proxies location / to the required backend upstream")


def test_storage_and_backups_dirs():
    storage_dir = "/home/user/storage"
    backups_dir = "/home/user/backups"
    dummy_file = os.path.join(storage_dir, "dummy.txt")

    assert os.path.isdir(storage_dir), f"{storage_dir} does not exist."
    assert os.path.isdir(backups_dir), f"{backups_dir} does not exist."
    assert os.path.isfile(dummy_file), f"{dummy_file} does not exist."

    size_mb = os.path.getsize(dummy_file) / (1024 * 1024)
    assert 9 <= size_mb <= 11, f"{dummy_file} is not approximately 10MB (found {size_mb:.2f} MB)."


def test_backup_archive():
    archive_path = "/home/user/backups/storage_backup.tar.gz"
    assert os.path.isfile(archive_path), f"{archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar archive."

    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()
        assert any("dummy.txt" in name for name in names), "dummy.txt not found in the backup archive."


def test_setup_proxy_idempotency():
    script_path = "/home/user/setup_proxy.py"
    conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    before = os.stat(conf_path)
    result = subprocess.run(["python3", script_path], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, result.stdout + result.stderr
    assert "CONFIG_UNCHANGED" in result.stdout, "Script did not output CONFIG_UNCHANGED when no changes were needed."
    after = os.stat(conf_path)
    assert after.st_mtime_ns == before.st_mtime_ns, "setup_proxy.py rewrote an already-correct configuration"

    with open(conf_path, "a") as f:
        f.write("\n# test modification\n")

    result2 = subprocess.run(["python3", script_path], capture_output=True, text=True, timeout=20)
    assert result2.returncode == 0, result2.stdout + result2.stderr
    assert "CONFIG_UPDATED" in result2.stdout, "Script did not output CONFIG_UPDATED after the config was modified."


def _storage_snapshot(storage_dir):
    result = {}
    for root, _, files in os.walk(storage_dir):
        for filename in files:
            path = os.path.join(root, filename)
            if os.path.isfile(path):
                rel = os.path.relpath(path, storage_dir).replace(os.sep, "/")
                with open(path, "rb") as f:
                    result[rel] = f.read()
    return result


def _archive_snapshot(archive_path):
    result = {}
    with tarfile.open(archive_path, "r:gz") as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            name = member.name.lstrip("/")
            while name.startswith("./"):
                name = name[2:]
            for prefix in ("home/user/storage/", "storage/"):
                if name.startswith(prefix):
                    name = name[len(prefix):]
                    break
            extracted = tar.extractfile(member)
            assert extracted is not None
            assert name not in result, f"Duplicate archive member for {name}"
            result[name] = extracted.read()
    return result


def test_backup_logic():
    script_path = "/home/user/backup.py"
    log_path = "/home/user/backup.log"
    storage_dir = "/home/user/storage"
    archive_path = "/home/user/backups/storage_backup.tar.gz"

    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.path.isfile(log_path), f"{log_path} does not exist."

    with open(log_path, "r") as f:
        log_content = f.read().strip()
    assert log_content == "BACKUP_SUCCESS", f"Expected BACKUP_SUCCESS in {log_path}, got {log_content}"

    challenge_name = f"verifier_{secrets.token_hex(8)}.bin"
    challenge_path = os.path.join(storage_dir, challenge_name)
    large_file = os.path.join(storage_dir, "large_test.txt")

    try:
        with open(challenge_path, "wb") as f:
            f.write(os.urandom(131071))
        expected = _storage_snapshot(storage_dir)

        if os.path.exists(archive_path):
            os.remove(archive_path)
        if os.path.exists(log_path):
            os.remove(log_path)

        under = subprocess.run(["python3", script_path], capture_output=True, text=True, timeout=60)
        assert under.returncode == 0, under.stdout + under.stderr
        assert os.path.isfile(log_path), "backup.py did not create backup.log"
        with open(log_path, "r") as f:
            assert f.read().strip() == "BACKUP_SUCCESS", "Under-quota run did not log BACKUP_SUCCESS"
        assert os.path.isfile(archive_path), "Under-quota run did not create the archive"
        assert tarfile.is_tarfile(archive_path), "Under-quota run produced an invalid tar archive"
        assert _archive_snapshot(archive_path) == expected, "Archive contents do not exactly match the storage files"

        with open(archive_path, "rb") as f:
            archive_hash = hashlib.sha256(f.read()).digest()

        # Preserve the original over-quota exercise.
        with open(large_file, "wb") as f:
            f.write(b"0" * (60 * 1024 * 1024))

        over = subprocess.run(["python3", script_path], capture_output=True, text=True, timeout=60)
        assert over.returncode == 0, over.stdout + over.stderr
        with open(log_path, "r") as f:
            log_content2 = f.read().strip()
        assert log_content2 == "QUOTA_EXCEEDED", f"Expected QUOTA_EXCEEDED in {log_path}, got {log_content2}"
        with open(archive_path, "rb") as f:
            assert hashlib.sha256(f.read()).digest() == archive_hash, "Over-quota run modified the existing backup archive"
    finally:
        for path in (large_file, challenge_path):
            if os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
