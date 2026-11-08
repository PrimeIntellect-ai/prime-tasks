#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess


def test_launcher_sh_start_order():
    path = "/home/user/launcher.sh"
    assert os.path.exists(path), f"{path} does not exist"

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original static call-order assertions.
    lines = content.splitlines()
    proxy_idx = -1
    capacity_idx = -1

    for i, line in enumerate(lines):
        line = line.strip()
        if line.startswith("start_proxy") and "()" not in line:
            proxy_idx = i
        elif line.startswith("start_capacity_tool") and "()" not in line:
            capacity_idx = i

    assert proxy_idx != -1, "start_proxy call not found in launcher.sh"
    assert capacity_idx != -1, "start_capacity_tool call not found in launcher.sh"
    assert proxy_idx < capacity_idx, "start_proxy is not called before start_capacity_tool in launcher.sh"

    # Execute the launcher under shell tracing and verify the calls really occur in order.
    result = subprocess.run(
        ["timeout", "10s", "bash", "-x", path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"launcher.sh failed when executed: {result.stderr}"
    trace = result.stderr.splitlines()
    proxy_calls = [i for i, line in enumerate(trace) if re.fullmatch(r"\+ start_proxy", line.strip())]
    capacity_calls = [i for i, line in enumerate(trace) if re.fullmatch(r"\+ start_capacity_tool", line.strip())]
    assert proxy_calls, "launcher.sh did not execute start_proxy"
    assert capacity_calls, "launcher.sh did not execute start_capacity_tool"
    assert proxy_calls[0] < capacity_calls[0], "launcher.sh executed the capacity tool before the proxy"


def _parse_nginx(content):
    # Remove comments and parse enough of nginx's brace/directive grammar to
    # verify that directives occur in the required contexts.
    content = re.sub(r"#.*", "", content)
    tokens = re.findall(r"[^\s{};]+|[{};]", content)
    pos = 0

    def parse_block(expect_close=False):
        nonlocal pos
        items = []
        words = []
        while pos < len(tokens):
            token = tokens[pos]
            pos += 1
            if token == ";":
                assert words, "Empty directive in proxy.conf"
                items.append(("directive", tuple(words), []))
                words = []
            elif token == "{":
                assert words, "Block without a name in proxy.conf"
                children = parse_block(True)
                items.append(("block", tuple(words), children))
                words = []
            elif token == "}":
                assert expect_close, "Unexpected closing brace in proxy.conf"
                assert not words, "Unterminated directive before closing brace in proxy.conf"
                return items
            else:
                words.append(token)
        assert not expect_close, "Unclosed block in proxy.conf"
        assert not words, "Unterminated directive in proxy.conf"
        return items

    result = parse_block(False)
    assert pos == len(tokens)
    return result


def test_proxy_conf_content():
    path = "/home/user/proxy.conf"
    assert os.path.exists(path), f"{path} does not exist"

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original content assertions.
    cleaned_content = re.sub(r"\s+", " ", content)
    assert "daemon off;" in cleaned_content, "Missing 'daemon off;' in proxy.conf"
    assert "pid /home/user/nginx.pid;" in cleaned_content, "Missing 'pid /home/user/nginx.pid;' in proxy.conf"
    assert "error_log /home/user/error.log;" in cleaned_content, "Missing 'error_log /home/user/error.log;' in proxy.conf"
    assert re.search(r"listen\s+(?:\*:)?8080;", cleaned_content), "Missing 'listen 8080;' or 'listen *:8080;' in proxy.conf"
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:9090;", cleaned_content), "Missing 'proxy_pass http://127.0.0.1:9090;' in proxy.conf"

    tree = _parse_nginx(content)

    def directives(items):
        return [words for kind, words, _ in items if kind == "directive"]

    def blocks(items, name, args=()):
        return [children for kind, words, children in items
                if kind == "block" and words == (name,) + tuple(args)]

    top_directives = directives(tree)
    assert ("daemon", "off") in top_directives, "'daemon off;' must be in the top-level context"
    assert ("pid", "/home/user/nginx.pid") in top_directives, "pid directive must be top-level"
    assert any(d[:2] == ("error_log", "/home/user/error.log") for d in top_directives), \
        "error_log directive must be top-level"

    assert blocks(tree, "events"), "Missing top-level events {} block"
    http_blocks = blocks(tree, "http")
    assert http_blocks, "Missing top-level http {} block"
    server_blocks = [server for http in http_blocks for server in blocks(http, "server")]
    assert server_blocks, "Missing server {} block inside http {}"

    matching_servers = []
    for server in server_blocks:
        if any(d in (("listen", "8080"), ("listen", "*:8080")) for d in directives(server)):
            matching_servers.append(server)
    assert matching_servers, "listen 8080 must be inside a server block within http"

    locations = [loc for server in matching_servers for loc in blocks(server, "location", ("/",))]
    assert locations, "Missing location / block inside the port 8080 server"
    assert any(("proxy_pass", "http://127.0.0.1:9090") in directives(loc) for loc in locations), \
        "proxy_pass must be inside location /"


def test_generate_report_exp_exists_and_content_and_executes():
    path = "/home/user/generate_report.exp"
    assert os.path.exists(path), f"{path} does not exist"

    with open(path, "r") as f:
        content = f.read()

    # Preserve the original static assertions.
    assert "spawn" in content, "Expect script does not contain a 'spawn' command"
    assert "/home/user/capacity_cli" in content, "Expect script does not spawn '/home/user/capacity_cli'"

    # Replace the CLI temporarily with a fresh challenge implementation. It only
    # emits the unpredictable token after receiving all four mandated answers.
    cli = "/home/user/capacity_cli"
    with open(cli, "rb") as f:
        original_cli = f.read()
    original_mode = stat.S_IMODE(os.stat(cli).st_mode)
    token = "EXPECT_RUN_" + secrets.token_hex(16)
    challenge = f'''#!/bin/bash
read -r -p "Enter Target Timezone: " tz
read -r -p "Enter System Locale: " loc
read -r -p "Enter Planner Username: " usr
read -r -p "Enter Planner Group: " grp
if [ "$tz" != "America/New_York" ] || [ "$loc" != "en_US.UTF-8" ] || [ "$usr" != "sys_planner" ] || [ "$grp" != "capacity_admins" ]; then
    echo "Incorrect interactive response" >&2
    exit 23
fi
echo "=== CAPACITY PROJECTION ==="
echo "TZ: $tz"
echo "LOC: $loc"
echo "USER: $usr"
echo "GROUP: $grp"
echo "STATUS: SUCCESS"
echo "{token}"
'''

    report = "/home/user/capacity_report.txt"
    if os.path.exists(report):
        os.unlink(report)

    try:
        with open(cli, "w") as f:
            f.write(challenge)
        os.chmod(cli, 0o755)
        result = subprocess.run(
            ["timeout", "15s", "expect", path],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    finally:
        with open(cli, "wb") as f:
            f.write(original_cli)
        os.chmod(cli, original_mode)

    assert result.returncode == 0, \
        f"generate_report.exp failed or did not reach EOF (stdout={result.stdout!r}, stderr={result.stderr!r})"
    assert os.path.exists(report), "Executing generate_report.exp did not create capacity_report.txt"
    with open(report, "r") as f:
        generated = f.read()
    assert token in generated, "capacity_report.txt did not capture the fresh final output from capacity_cli"


def test_capacity_report_txt_content():
    path = "/home/user/capacity_report.txt"
    assert os.path.exists(path), f"{path} does not exist. The expect script might not have been executed or did not save the output."

    with open(path, "r") as f:
        content = f.read()

    # Preserve all original report assertions; this report was freshly generated above.
    assert "TZ: America/New_York" in content, "Missing or incorrect TZ output in capacity_report.txt"
    assert "LOC: en_US.UTF-8" in content, "Missing or incorrect LOC output in capacity_report.txt"
    assert "USER: sys_planner" in content, "Missing or incorrect USER output in capacity_report.txt"
    assert "GROUP: capacity_admins" in content, "Missing or incorrect GROUP output in capacity_report.txt"
    assert "STATUS: SUCCESS" in content, "Missing STATUS: SUCCESS in capacity_report.txt"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
