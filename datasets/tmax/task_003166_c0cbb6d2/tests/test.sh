#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import stat
import subprocess
import tempfile


def test_block_sh_content_and_execution():
    script_path = "/home/user/block.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    # Preserve the original content assertions.
    assert "iptables" in content, "The block.sh script does not contain an 'iptables' command."
    assert "-A INPUT" in content or "--append INPUT" in content, "The iptables command must append to the INPUT chain."
    assert "-j DROP" in content or "--jump DROP" in content, "The iptables command must DROP the traffic."
    assert "203.0.113.88" in content, "The iptables command does not block the correct malicious IP (203.0.113.88)."
    assert "8080" in content, "The iptables command does not specify the correct port (8080)."
    assert "-p tcp" in content or "--protocol tcp" in content, "The iptables command does not specify the TCP protocol."

    syntax = subprocess.run(["bash", "-n", script_path], capture_output=True, text=True)
    assert syntax.returncode == 0, f"block.sh has invalid bash syntax:\n{syntax.stderr}"

    # Execute the script with a harmless mock iptables and inspect the actual rule.
    with tempfile.TemporaryDirectory() as mock_dir:
        log_path = os.path.join(mock_dir, "calls.jsonl")
        mock_path = os.path.join(mock_dir, "iptables")
        with open(mock_path, "w") as f:
            f.write("""#!/usr/bin/python3
import json, os, sys
with open(os.environ[\"IPTABLES_LOG\"], \"a\") as out:
    out.write(json.dumps(sys.argv[1:]) + \"\\n\")
""")
        os.chmod(mock_path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)

        env = os.environ.copy()
        env["PATH"] = mock_dir + os.pathsep + env.get("PATH", "")
        env["IPTABLES_LOG"] = log_path
        result = subprocess.run(
            ["bash", script_path],
            cwd="/home/user",
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"block.sh failed when executed with a mock iptables:\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(log_path), "block.sh did not execute an iptables command."
        with open(log_path) as f:
            calls = [json.loads(line) for line in f if line.strip()]

    assert len(calls) == 1, f"Expected exactly one iptables command, observed {len(calls)}."
    args = calls[0]
    seen = {}
    i = 0
    aliases = {
        "-A": "chain", "--append": "chain",
        "-p": "protocol", "--protocol": "protocol",
        "-s": "source", "--source": "source",
        "--dport": "port", "--destination-port": "port",
        "-j": "jump", "--jump": "jump",
    }
    while i < len(args):
        arg = args[i]
        if arg in ("-m", "--match"):
            assert i + 1 < len(args) and args[i + 1] == "tcp", "Only the optional TCP match module is allowed."
            i += 2
            continue
        assert arg in aliases, f"Unexpected argument in iptables rule: {arg!r}"
        assert i + 1 < len(args), f"Missing value after {arg!r}."
        key = aliases[arg]
        assert key not in seen, f"Duplicate iptables option for {key}."
        seen[key] = args[i + 1]
        i += 2

    assert seen == {
        "chain": "INPUT",
        "protocol": "tcp",
        "source": "203.0.113.88",
        "port": "8080",
        "jump": "DROP",
    }, f"The executed iptables rule was not the required rule: {args!r}"


def rust_string(value):
    # Generated values are ASCII, so JSON string syntax is valid Rust syntax.
    return json.dumps(value)


def test_rust_auth_implementation():
    auth_service_dir = "/home/user/auth_service"
    auth_path = os.path.join(auth_service_dir, "src", "auth.rs")
    assert os.path.isfile(auth_path), f"The required Rust source file {auth_path} does not exist."

    tests_dir = os.path.join(auth_service_dir, "tests")
    os.makedirs(tests_dir, exist_ok=True)
    target_name = "eval_" + secrets.token_hex(10)
    test_file_path = os.path.join(tests_dir, target_name + ".rs")

    valid_urls = [
        "https://trusted.corp/",
        "https://trusted.corp/" + secrets.token_hex(12),
        "https://trusted.corp/a/b?nonce=" + secrets.token_hex(10),
        "https://trusted.corp/../" + secrets.token_hex(8),
    ]
    invalid_urls = [
        "",
        "http://evil.com",
        "https://trusted.corp",
        "https://trusted.corp.evil/" + secrets.token_hex(8),
        "http://trusted.corp/" + secrets.token_hex(8),
        "HTTPS://trusted.corp/" + secrets.token_hex(8),
        " https://trusted.corp/" + secrets.token_hex(8),
        "https://" + secrets.token_hex(6) + ".example/",
    ]
    usernames = [
        "admin",
        "",
        "alice smith",
        "user/with:punctuation",
    ] + [secrets.token_hex(length) for length in (3, 7, 13, 21, 31)]

    lines = [
        "use auth_service::auth::{get_safe_redirect, generate_secure_token};",
        "",
        "#[test]",
        "fn original_fixed_cases() {",
        '    assert_eq!(get_safe_redirect("http://evil.com"), "https://trusted.corp/home", "Failed to fallback to safe URL for evil.com");',
        '    assert_eq!(get_safe_redirect("https://trusted.corp/app"), "https://trusted.corp/app", "Failed to keep trusted URL");',
        '    assert_eq!(generate_secure_token("admin"), "2c53b66df87016ea98e72efcc162b70b5550a25fc5f6fb87c672b144fb2b152d", "Token generation did not match the expected SHA-256 hash");',
        "}",
        "",
        "#[test]",
        "fn generated_redirect_cases() {",
    ]
    for url in valid_urls:
        literal = rust_string(url)
        lines.append(f"    assert_eq!(get_safe_redirect({literal}), {literal});")
    for url in invalid_urls:
        lines.append(
            f'    assert_eq!(get_safe_redirect({rust_string(url)}), "https://trusted.corp/home");'
        )
    lines.extend(["}", "", "#[test]", "fn generated_token_cases() {"])
    for username in usernames:
        expected = hashlib.sha256((username + "BIRD_IS_THE_WORD").encode()).hexdigest()
        lines.append(
            f"    assert_eq!(generate_secure_token({rust_string(username)}), {rust_string(expected)});"
        )
    lines.extend(["}", ""])

    with open(test_file_path, "x") as f:
        f.write("\n".join(lines))

    build = subprocess.run(
        ["cargo", "build"],
        cwd=auth_service_dir,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert build.returncode == 0, (
        f"Rust project did not compile with cargo build.\n{build.stdout}\n{build.stderr}"
    )

    result = subprocess.run(
        ["cargo", "test", "--test", target_name],
        cwd=auth_service_dir,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Rust implementation verification failed. "
        f"Cargo test output:\n{result.stdout}\n{result.stderr}"
    )
PY_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
