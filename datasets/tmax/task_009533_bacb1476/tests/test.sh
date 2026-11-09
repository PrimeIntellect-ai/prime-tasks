#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shlex
import stat
import subprocess
import tempfile


def parse_nginx(content):
    cleaned = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    tokens = re.findall(r"[{};]|[^\s{};]+", cleaned)

    def parse_items(index, nested=False):
        items = []
        words = []
        while index < len(tokens):
            token = tokens[index]
            if token == ";":
                if words:
                    items.append(("directive", words))
                    words = []
                index += 1
            elif token == "{":
                assert words, "nginx.conf contains a block without a header."
                children, index = parse_items(index + 1, True)
                items.append(("block", words, children))
                words = []
            elif token == "}":
                assert nested, "nginx.conf contains an unmatched closing brace."
                assert not words, "nginx.conf contains an unterminated directive."
                return items, index + 1
            else:
                words.append(token)
                index += 1
        assert not nested, "nginx.conf contains an unclosed block."
        assert not words, "nginx.conf contains an unterminated directive."
        return items, index

    parsed, _ = parse_items(0)
    return parsed


def child_blocks(items, name):
    return [item for item in items if item[0] == "block" and item[1] and item[1][0] == name]


def directives(items, name):
    return [item[1] for item in items if item[0] == "directive" and item[1] and item[1][0] == name]


def test_nginx_config_updated():
    nginx_conf_path = "/home/user/microservices-config/nginx.conf"
    assert os.path.isfile(nginx_conf_path), f"File {nginx_conf_path} does not exist."

    with open(nginx_conf_path, "r") as f:
        content = f.read()

    # Preserve the original checks for the new and old endpoints.
    assert "127.0.0.1:8081" in content, "nginx.conf does not route to 127.0.0.1:8081 for /auth."
    assert "127.0.0.1:8082" in content, "nginx.conf does not route to 127.0.0.1:8082 for /data."
    assert "127.0.0.1:9000" not in content, "nginx.conf still contains the old port 9000."
    assert "127.0.0.1:9001" not in content, "nginx.conf still contains the old port 9001."

    # Parse the configuration so ports in comments or unrelated blocks do not pass.
    root = parse_nginx(content)
    http_blocks = child_blocks(root, "http")
    assert http_blocks, "nginx.conf has no http block."

    valid_server = False
    for http_block in http_blocks:
        for server in child_blocks(http_block[2], "server"):
            listens = directives(server[2], "listen")
            has_listen_8080 = any(len(d) >= 2 and d[1] == "8080" for d in listens)
            if not has_listen_8080:
                continue

            locations = {
                block[1][1]: block[2]
                for block in child_blocks(server[2], "location")
                if len(block[1]) == 2
            }
            auth_passes = directives(locations.get("/auth", []), "proxy_pass")
            data_passes = directives(locations.get("/data", []), "proxy_pass")
            auth_ok = any(d == ["proxy_pass", "http://127.0.0.1:8081"] for d in auth_passes)
            data_ok = any(d == ["proxy_pass", "http://127.0.0.1:8082"] for d in data_passes)
            if auth_ok and data_ok:
                valid_server = True
                break

    assert valid_server, (
        "A server listening on 8080 must route /auth to 127.0.0.1:8081 "
        "and /data to 127.0.0.1:8082."
    )


def test_bashrc_env_vars():
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"File {bashrc_path} does not exist."

    with open(bashrc_path, "r") as f:
        content = f.read()

    # Preserve the original textual checks.
    auth_secret_match = re.search(r'AUTH_SECRET\s*=\s*["\']?supersecret["\']?', content)
    assert auth_secret_match is not None, "AUTH_SECRET is not correctly set to 'supersecret' in .bashrc."
    data_dir_match = re.search(r'DATA_DIR\s*=\s*["\']?/home/user/data["\']?', content)
    assert data_dir_match is not None, "DATA_DIR is not correctly set to '/home/user/data' in .bashrc."

    # Source .bashrc in a fresh interactive shell and inspect a child process's
    # environment. Shell-local assignments therefore cannot pass this check.
    fd, output_path = tempfile.mkstemp(prefix="bashrc-env-")
    os.close(fd)
    try:
        child_code = (
            "import json, os; "
            f"open({output_path!r}, 'w').write(json.dumps("
            "[os.environ.get('AUTH_SECRET'), os.environ.get('DATA_DIR')]))"
        )
        env = os.environ.copy()
        env.pop("AUTH_SECRET", None)
        env.pop("DATA_DIR", None)
        result = subprocess.run(
            ["/bin/bash", "--noprofile", "--rcfile", bashrc_path, "-ic", f"python3 -c {shlex.quote(child_code)}"],
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"A new shell could not load .bashrc: {result.stderr}"
        with open(output_path, "r") as f:
            values = json.load(f)
        assert values == ["supersecret", "/home/user/data"], (
            "AUTH_SECRET and DATA_DIR must be exported to child processes by .bashrc."
        )
    finally:
        if os.path.exists(output_path):
            os.unlink(output_path)


def test_git_pre_commit_hook():
    repo_path = "/home/user/microservices-config"
    hook_path = os.path.join(repo_path, ".git/hooks/pre-commit")
    validate_path = os.path.join(repo_path, "validate.sh")
    assert os.path.isfile(hook_path), f"Pre-commit hook file {hook_path} does not exist."

    st = os.stat(hook_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Pre-commit hook {hook_path} is not executable."

    with open(hook_path, "r") as f:
        content = f.read()
    assert "validate.sh" in content, "Pre-commit hook does not appear to call validate.sh."

    # Replace validate.sh briefly with a probe. The hook must really execute it
    # and must reject the commit when validation fails.
    assert os.path.isfile(validate_path), f"Validation script {validate_path} does not exist."
    with open(validate_path, "rb") as f:
        original_validate = f.read()
    original_mode = stat.S_IMODE(os.stat(validate_path).st_mode)
    fd, sentinel = tempfile.mkstemp(prefix="validate-invoked-")
    os.close(fd)
    os.unlink(sentinel)
    probe = f"#!/bin/bash\nprintf invoked > {shlex.quote(sentinel)}\nexit 37\n"
    try:
        with open(validate_path, "w") as f:
            f.write(probe)
        os.chmod(validate_path, 0o755)
        result = subprocess.run(
            [hook_path],
            cwd=repo_path,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert os.path.isfile(sentinel), "The pre-commit hook did not execute validate.sh."
        assert result.returncode != 0, "The pre-commit hook allowed a failing validation."
    finally:
        with open(validate_path, "wb") as f:
            f.write(original_validate)
        os.chmod(validate_path, original_mode)
        if os.path.exists(sentinel):
            os.unlink(sentinel)


def test_cron_schedule():
    cron_file_path = "/home/user/cron_schedule.txt"
    assert os.path.isfile(cron_file_path), f"File {cron_file_path} does not exist."

    with open(cron_file_path, "r") as f:
        content = f.read().strip()

    normalized_content = re.sub(r'\s+', ' ', content)
    expected_schedule = "0 2 * * * /home/user/backup.sh"
    assert normalized_content == expected_schedule, f"Cron schedule is incorrect. Expected '{expected_schedule}', got '{normalized_content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
