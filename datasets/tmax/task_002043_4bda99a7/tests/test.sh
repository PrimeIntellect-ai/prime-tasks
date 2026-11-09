#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shlex
import stat
import subprocess
import tempfile


def test_version_log():
    log_path = "/home/user/version.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "1.2.3", f"Expected version.log to contain '1.2.3', but got '{content}'."


def test_symlink_created():
    symlink_path = "/home/user/libs/libcatalan.so"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."

    target = os.readlink(symlink_path)
    resolved_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), target))
    expected_target = "/home/user/libs/libcatalan.so.1.2.3"

    assert resolved_target == expected_target, f"Symlink points to {resolved_target}, expected {expected_target}."


def test_fix_link_script_semantic_selection():
    script_path = "/home/user/fix_link.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert not os.path.islink(script_path), f"{script_path} must be an actual script, not a symlink."

    libs = "/home/user/libs"
    link = os.path.join(libs, "libcatalan.so")
    log = "/home/user/version.log"
    rng = random.SystemRandom()
    major = rng.randint(20, 80)
    minor = rng.randint(2, 30)
    patch = rng.randint(1, 90)
    versions = [
        f"{major}.{minor}.{patch}",
        f"{major}.{minor + 1}.0",
        f"{major + 1}.99.99-rc1",
        f"{major + 2}.0.0-alpha",
    ]
    expected = versions[1]
    created = []

    try:
        for version in versions:
            path = os.path.join(libs, "libcatalan.so." + version)
            with open(path, "x"):
                pass
            created.append(path)

        if os.path.lexists(link):
            os.unlink(link)
        if os.path.exists(log):
            os.unlink(log)

        result = subprocess.run(
            ["bash", script_path], capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, f"fix_link.sh failed: {result.stderr}"
        assert os.path.islink(link), "fix_link.sh did not create libcatalan.so as a symbolic link."
        resolved = os.path.realpath(link)
        assert resolved == os.path.join(libs, "libcatalan.so." + expected), (
            f"Dynamic semantic-version test selected {resolved}; expected stable version {expected}."
        )
        assert os.path.isfile(log), "fix_link.sh did not create version.log."
        with open(log) as f:
            assert f.read().strip() == expected, "version.log does not contain the dynamically selected version."
    finally:
        for path in created:
            if os.path.exists(path):
                os.unlink(path)
        if os.path.lexists(link):
            os.unlink(link)
        os.symlink("libcatalan.so.1.2.3", link)
        with open(log, "w") as f:
            f.write("1.2.3\n")


def catalan_expected(n):
    if n <= 1:
        return 1
    values = [1, 1]
    for k in range(2, n + 1):
        values.append(sum(values[i] * values[k - i - 1] for i in range(k)))
    return values[n]


def test_catalan_script():
    script_path = "/home/user/catalan.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    result_5 = subprocess.run(["bash", script_path, "5"], capture_output=True, text=True)
    assert result_5.returncode == 0, f"Running catalan.sh 5 failed with error: {result_5.stderr}"
    assert result_5.stdout.strip() == "42", f"Expected output '42' for n=5, got '{result_5.stdout.strip()}'"

    result_6 = subprocess.run(["bash", script_path, "6"], capture_output=True, text=True)
    assert result_6.returncode == 0, f"Running catalan.sh 6 failed with error: {result_6.stderr}"
    assert result_6.stdout.strip() == "132", f"Expected output '132' for n=6, got '{result_6.stdout.strip()}'"

    assert not os.path.islink(script_path), f"{script_path} must be an actual Bash script."
    with open(script_path) as f:
        source = f.read()
    assert not re.search(r"\b(?:python(?:3)?|perl)\b", source, re.IGNORECASE), (
        "catalan.sh must use Bash arithmetic, not Python or Perl."
    )

    rng = random.SystemRandom()
    inputs = [-rng.randint(1, 10), 0, 1, 2, 4]
    inputs.extend(rng.sample(range(7, 19), 5))
    for n in inputs:
        result = subprocess.run(
            ["bash", script_path, str(n)], capture_output=True, text=True, timeout=15
        )
        expected = str(catalan_expected(n))
        assert result.returncode == 0, f"Running catalan.sh {n} failed: {result.stderr}"
        assert result.stdout.strip() == expected, (
            f"Expected Catalan({n})={expected}, got {result.stdout.strip()!r}."
        )


def tokenize_nginx(text):
    cleaned = "\n".join(line.split("#", 1)[0] for line in text.splitlines())
    pattern = r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{};]|[^\s{};]+'
    tokens = re.findall(pattern, cleaned)
    return [t[1:-1] if len(t) >= 2 and t[0] == t[-1] and t[0] in "\"'" else t for t in tokens]


def parse_nginx(text):
    tokens = tokenize_nginx(text)
    pos = 0

    def sequence(expect_close=False):
        nonlocal pos
        nodes = []
        while pos < len(tokens):
            if tokens[pos] == "}":
                assert expect_close, "Unexpected closing brace in nginx.conf"
                pos += 1
                return nodes
            name = tokens[pos]
            pos += 1
            args = []
            while pos < len(tokens) and tokens[pos] not in (";", "{", "}"):
                args.append(tokens[pos])
                pos += 1
            assert pos < len(tokens), f"Unterminated nginx directive {name}"
            assert tokens[pos] != "}", f"Directive {name} is missing a semicolon or block"
            if tokens[pos] == ";":
                pos += 1
                nodes.append((name, args, None))
            else:
                pos += 1
                nodes.append((name, args, sequence(True)))
        assert not expect_close, "Unclosed block in nginx.conf"
        return nodes

    result = sequence()
    assert pos == len(tokens)
    return result


def direct(nodes, name):
    return [node for node in nodes if node[0] == name]


def walk(nodes):
    for node in nodes:
        yield node
        if node[2] is not None:
            yield from walk(node[2])


def test_nginx_config():
    config_path = "/home/user/nginx.conf"
    assert os.path.isfile(config_path), f"{config_path} does not exist."

    with open(config_path, "r") as f:
        content = f.read()

    content_normalized = re.sub(r'\s+', ' ', content)

    assert "pid /home/user/nginx.pid;" in content_normalized, "Missing or incorrect pid directive."
    assert re.search(r"limit_req_zone\s+\$binary_remote_addr\s+zone=mylimit:10m\s+rate=2r/s\s*;", content_normalized), \
        "Missing or incorrect limit_req_zone directive."
    assert re.search(r"limit_req\s+zone=mylimit\s*;", content_normalized), \
        "Missing or incorrect limit_req directive."
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:9000\s*;", content_normalized), \
        "Missing or incorrect proxy_pass directive."
    assert re.search(r"listen\s+8080\s*;", content_normalized), \
        "Missing or incorrect listen directive."

    prefix = tempfile.mkdtemp(prefix="nginx-verify-")
    os.chmod(prefix, 0o777)
    checked = subprocess.run(
        ["runuser", "-u", "user", "--", "nginx", "-T", "-c", config_path, "-p", prefix + "/"],
        capture_output=True, text=True, timeout=15
    )
    assert checked.returncode == 0, f"nginx rejected the configuration as user:\n{checked.stderr}"
    expanded = checked.stdout
    assert not re.search(r"(?m)^\s*user\s+[^;]+;", expanded), "A user directive is not permitted."

    nodes = parse_nginx(content)
    assert not direct(nodes, "user"), "A user directive is not permitted."
    assert any(n[1] == ["/home/user/nginx.pid"] for n in direct(nodes, "pid")), (
        "pid must be set in the main context to /home/user/nginx.pid."
    )

    http_blocks = direct(nodes, "http")
    assert http_blocks, "nginx.conf must contain an http block."
    valid_zone = False
    valid_location = False
    for http in http_blocks:
        children = http[2]
        for zone in direct(children, "limit_req_zone"):
            if set(zone[1]) == {"$binary_remote_addr", "zone=mylimit:10m", "rate=2r/s"}:
                valid_zone = True
        for server in direct(children, "server"):
            if not any(n[1] == ["8080"] for n in direct(server[2], "listen")):
                continue
            for location in direct(server[2], "location"):
                if location[1] != ["/"]:
                    continue
                proxies = direct(location[2], "proxy_pass")
                limits = direct(location[2], "limit_req")
                if (any(n[1] == ["http://127.0.0.1:9000"] for n in proxies)
                        and any(n[1] == ["zone=mylimit"] for n in limits)):
                    valid_location = True

    assert valid_zone, "limit_req_zone must be in the http context with the exact requested key, zone, size, and rate."
    assert valid_location, "A server listening on 8080 must proxy location / and apply mylimit there without burst."

    access_logs = [n for n in walk(nodes) if n[0] == "access_log"]
    error_logs = [n for n in walk(nodes) if n[0] == "error_log"]
    assert access_logs, "An access_log directive is required."
    assert error_logs, "An error_log directive is required."
    assert all(n[1] and n[1][0].startswith("/home/user/") for n in access_logs), (
        "Every configured access log must be stored under /home/user/."
    )
    assert all(n[1] and n[1][0].startswith("/home/user/") for n in error_logs), (
        "Every configured error log must be stored under /home/user/."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
