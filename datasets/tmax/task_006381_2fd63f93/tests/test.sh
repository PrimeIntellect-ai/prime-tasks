#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import subprocess


def strip_hash_comments(text):
    output = []
    for line in text.splitlines():
        result = []
        quote = None
        escaped = False
        for char in line:
            if escaped:
                result.append(char)
                escaped = False
                continue
            if char == "\\" and quote:
                result.append(char)
                escaped = True
                continue
            if char in ("'", '"'):
                if quote == char:
                    quote = None
                elif quote is None:
                    quote = char
                result.append(char)
                continue
            if char == "#" and quote is None:
                break
            result.append(char)
        output.append("".join(result))
    return "\n".join(output)


def parse_nginx(text):
    active = strip_hash_comments(text)
    raw_tokens = re.findall(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{};]|[^\s{};]+', active)
    tokens = []
    for token in raw_tokens:
        if len(token) >= 2 and token[0] == token[-1] and token[0] in ("'", '"'):
            tokens.append(token[1:-1])
        else:
            tokens.append(token)

    def parse_sequence(index, nested=False):
        nodes = []
        while index < len(tokens):
            if tokens[index] == "}":
                assert nested, "Unexpected closing brace in Nginx configuration."
                return nodes, index + 1

            words = []
            while index < len(tokens) and tokens[index] not in ("{", "}", ";"):
                words.append(tokens[index])
                index += 1
            assert words, "Malformed Nginx statement."
            assert index < len(tokens), "Unterminated Nginx statement."

            terminator = tokens[index]
            if terminator == ";":
                nodes.append(("directive", words, []))
                index += 1
            elif terminator == "{":
                children, index = parse_sequence(index + 1, True)
                nodes.append(("block", words, children))
            else:
                raise AssertionError("Nginx statement is missing a semicolon or opening brace.")

        assert not nested, "Unclosed block in Nginx configuration."
        return nodes, index

    nodes, final_index = parse_sequence(0)
    assert final_index == len(tokens), "Could not parse the complete Nginx configuration."
    return nodes


def test_nginx_config():
    conf_path = "/home/user/nginx/nginx.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} is missing."
    with open(conf_path, "r") as f:
        content = f.read()

    expected_directive = "proxy_pass http://unix:/home/user/app/run/gunicorn.sock;"
    assert expected_directive in content, "Nginx proxy_pass directive not updated to the correct socket path."

    nodes = parse_nginx(content)
    found = []

    def walk(items, contexts):
        for kind, words, children in items:
            if kind == "block":
                walk(children, contexts + [words])
            elif words and words[0] == "proxy_pass":
                in_http = any(ctx == ["http"] for ctx in contexts)
                in_server = any(ctx and ctx[0] == "server" for ctx in contexts)
                in_root_location = any(ctx[:2] == ["location", "/"] for ctx in contexts)
                if in_http and in_server and in_root_location:
                    found.append(words)

    walk(nodes, [])
    assert found == [["proxy_pass", "http://unix:/home/user/app/run/gunicorn.sock"]], \
        "The active root-location proxy_pass must point only to the correct Gunicorn socket."


def parse_logrotate(text):
    lines = []
    for raw_line in strip_hash_comments(text).splitlines():
        line = raw_line.strip()
        if line:
            lines.append(line)

    blocks = []
    current_header = None
    current_entries = []
    known_directives = {
        "daily", "weekly", "monthly", "yearly", "hourly", "size", "minsize", "maxsize",
        "rotate", "compress", "nocompress", "delaycompress", "missingok", "nomissingok",
        "notifempty", "ifempty", "create", "nocreate", "copy", "nocopy", "copytruncate",
        "nocopytruncate", "dateext", "nodateext", "dateformat", "dateyesterday", "datehourago",
        "olddir", "noolddir", "mail", "nomail", "mailfirst", "maillast", "sharedscripts",
        "nosharedscripts", "prerotate", "postrotate", "firstaction", "lastaction", "endscript",
        "su", "extension", "addextension", "start", "shred", "noshred", "shredcycles",
        "maxage", "tabooext", "include", "renamecopy", "norenamecopy"
    }

    for line in lines:
        assert ";" not in line, "Logrotate directives must not use shell-style semicolons."
        if current_header is None:
            assert line.endswith("{"), "Expected a log path followed by an opening brace."
            header_text = line[:-1].strip()
            assert header_text, "Logrotate block has no log path."
            current_header = shlex.split(header_text, comments=False, posix=True)
            assert current_header, "Logrotate block has no log path."
            current_entries = []
        else:
            if line == "}":
                blocks.append((current_header, current_entries))
                current_header = None
                current_entries = []
                continue
            assert "{" not in line and "}" not in line, "Malformed or nested logrotate block."
            entry = shlex.split(line, comments=False, posix=True)
            assert entry, "Empty logrotate directive."
            assert entry[0] in known_directives, f"Unknown logrotate directive: {entry[0]}"
            current_entries.append(entry)

    assert current_header is None, "Unclosed logrotate block."
    assert blocks, "Logrotate configuration contains no blocks."
    return blocks


def test_logrotate_config():
    conf_path = "/home/user/metrics_logrotate.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} is missing."
    with open(conf_path, "r") as f:
        content = f.read()

    assert "/home/user/nginx/logs/access.log" in content, "Logrotate config does not target the correct log file."
    assert "daily" in content, "Logrotate config missing 'daily' directive."
    assert re.search(r"rotate\s+7", content), "Logrotate config missing 'rotate 7' directive."
    assert "compress" in content, "Logrotate config missing 'compress' directive."

    blocks = parse_logrotate(content)
    matching = [entries for paths, entries in blocks if "/home/user/nginx/logs/access.log" in paths]
    assert len(matching) == 1, "The access log must be targeted by exactly one active logrotate block."
    entries = matching[0]
    assert entries.count(["daily"]) == 1, "The access-log block must contain one active daily directive."
    assert entries.count(["rotate", "7"]) == 1, "The access-log block must contain one active 'rotate 7' directive."
    assert entries.count(["compress"]) == 1, "The access-log block must contain one active compress directive."


def test_fstab_entry():
    fstab_path = "/home/user/capacity_fstab"
    assert os.path.isfile(fstab_path), f"File {fstab_path} is missing."
    with open(fstab_path, "r") as f:
        content = f.read().strip()

    lines = [line for line in content.splitlines() if line.strip() and not line.strip().startswith("#")]
    assert len(lines) == 1, "fstab file should contain exactly one uncommented line."

    parts = lines[0].split()
    assert len(parts) == 6, "fstab entry does not have exactly 6 fields."
    assert parts[0] == "/dev/nvme1n1", "fstab entry device is incorrect."
    assert parts[1] == "/home/user/capacity_metrics", "fstab entry mount point is incorrect."
    assert parts[2] == "xfs", "fstab entry filesystem type is incorrect."
    assert parts[3] == "defaults", "fstab entry options are incorrect."
    assert parts[4] == "0", "fstab entry dump value is incorrect."
    assert parts[5] == "2", "fstab entry pass value is incorrect."


def test_firewall_rule():
    script_path = "/home/user/firewall_rule.sh"
    assert os.path.isfile(script_path), f"File {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert "iptables" in content, "iptables command not found."
    assert "-A INPUT" in content, "Missing append to INPUT chain."
    assert "-j DROP" in content, "Missing DROP target."
    assert "8080" in content, "Missing port 8080."
    assert "192.168.1.100" in content, "Missing source IP 192.168.1.100."
    assert "-p tcp" in content, "Missing TCP protocol specification."

    valid_patterns = [
        r"iptables\s+-A\s+INPUT\s+-s\s+192\.168\.1\.100\s+-p\s+tcp\s+--dport\s+8080\s+-j\s+DROP",
        r"iptables\s+-A\s+INPUT\s+-p\s+tcp\s+-s\s+192\.168\.1\.100\s+--dport\s+8080\s+-j\s+DROP",
        r"iptables\s+-A\s+INPUT\s+-p\s+tcp\s+--dport\s+8080\s+-s\s+192\.168\.1\.100\s+-j\s+DROP"
    ]
    match = any(re.search(pattern, content) for pattern in valid_patterns)
    assert match, "The iptables command does not match the required arguments and structure."

    syntax = subprocess.run(["bash", "-n", script_path], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Firewall script has invalid Bash syntax: {syntax.stderr}"

    raw_lines = content.splitlines()
    assert raw_lines and re.match(r"^#!\s*/(?:usr/bin/env\s+)?bash(?:\s|$)", raw_lines[0]), \
        "Firewall rule must be a Bash script with a Bash shebang."
    command_lines = [line.strip() for line in raw_lines[1:] if line.strip() and not line.lstrip().startswith("#")]
    assert len(command_lines) == 1, "Firewall script must contain exactly one executable command."

    lexer = shlex.shlex(command_lines[0], posix=True, punctuation_chars=";&|<>()")
    lexer.whitespace_split = True
    lexer.commenters = "#"
    argv = list(lexer)
    assert not any(token in {";", "&", "&&", "|", "||", "<", ">", "(", ")"} for token in argv), \
        "Firewall script must not contain additional shell commands or control operators."
    assert argv and argv[0] == "iptables", "The executable command must be iptables."
    assert len(argv) == 11, "The iptables command must contain exactly the requested rule arguments."

    pairs = argv[1:]
    parsed = {}
    for index in range(0, len(pairs), 2):
        option, value = pairs[index:index + 2]
        assert option not in parsed, f"Duplicate iptables option: {option}"
        parsed[option] = value
    assert parsed == {
        "-A": "INPUT",
        "-p": "tcp",
        "-s": "192.168.1.100",
        "--dport": "8080",
        "-j": "DROP",
    }, "The active iptables command does not exactly implement the requested rule."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
