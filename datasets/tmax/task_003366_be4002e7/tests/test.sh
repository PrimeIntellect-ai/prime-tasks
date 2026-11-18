#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import re
import secrets
import socket
import stat
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.request

HOME = '/home/user'


def uncommented(text):
    return '\n'.join(line.split('#', 1)[0] for line in text.splitlines())


def block_body(text, keyword):
    match = re.search(r'\b' + re.escape(keyword) + r'\s*\{', text)
    assert match, f"Missing {keyword} block"
    start = match.end()
    depth = 1
    for pos in range(start, len(text)):
        if text[pos] == '{':
            depth += 1
        elif text[pos] == '}':
            depth -= 1
            if depth == 0:
                return text[start:pos]
    raise AssertionError(f"Unterminated {keyword} block")


def test_setup_done():
    setup_file = '/home/user/setup_done.txt'
    assert os.path.isfile(setup_file), f"Setup file {setup_file} does not exist."
    with open(setup_file, 'r') as f:
        content = f.read().strip()
    assert content == 'READY', f"Expected 'READY' in {setup_file}, found '{content}'."


def test_required_directories_and_script():
    for name in ('restore_inbox', 'restore_active', 'restore_processed',
                 'proxy_conf', 'nginx_logs'):
        path = os.path.join(HOME, name)
        assert os.path.isdir(path), f"Required directory {path} does not exist"

    script = os.path.join(HOME, 'restore_tester.py')
    assert os.path.isfile(script), f"Restore tester {script} does not exist"
    with open(script, 'r', encoding='utf-8') as f:
        source = f.read()
    compile(source, script, 'exec')
    assert re.search(r'\bsetfacl\b', source), "restore_tester.py lacks setfacl command/logic"


def test_cron_job_exists():
    try:
        result = subprocess.run(
            ['su', '-', 'user', '-c', 'crontab -l'],
            capture_output=True, text=True, check=True
        )
    except subprocess.CalledProcessError as e:
        assert False, f"Failed to read crontab for user 'user': {e.stderr}"

    assert 'restore_tester.py' in result.stdout, "Cron job for restore_tester.py not found in crontab."
    valid = False
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line or line.startswith('#'):
            continue
        fields = line.split(None, 5)
        if len(fields) != 6 or fields[:5] != ['*', '*', '*', '*', '*']:
            continue
        command = fields[5]
        if (re.search(r'(^|\s)/home/user/restore_tester\.py(?:\s|$)', command)
                and re.search(r'(?:>|>>)\s*/home/user/cron_tester\.log\s+2>&1\s*$', command)):
            valid = True
            break
    assert valid, "Crontab must run /home/user/restore_tester.py every minute and redirect stdout and stderr to cron_tester.log"


def test_nginx_configuration_and_running():
    config_path = '/home/user/nginx.conf'
    assert os.path.isfile(config_path), f"Missing {config_path}"
    with open(config_path, 'r', encoding='utf-8') as f:
        config = uncommented(f.read())

    assert not re.search(r'(?m)^\s*user\s+', config), "nginx.conf must not contain a user directive"
    assert re.search(r'(?m)^\s*pid\s+/home/user/nginx\.pid\s*;', config), "Incorrect or missing PID directive"
    assert re.search(r'(?m)^\s*access_log\s+/home/user/nginx_logs/[^;\s]+', config), "Access log is not under nginx_logs"
    assert re.search(r'(?m)^\s*error_log\s+/home/user/nginx_logs/[^;\s]+', config), "Error log is not under nginx_logs"

    server = block_body(config, 'server')
    assert re.search(r'\blisten\s+127\.0\.0\.1:8080\s*;', server), "Server does not listen on 127.0.0.1:8080"
    assert re.search(r'\binclude\s+/home/user/proxy_conf/\*\.conf\s*;', server), "proxy_conf/*.conf is not included inside the server block"

    syntax = subprocess.run(
        ['su', '-', 'user', '-c', 'nginx -t -c /home/user/nginx.conf'],
        capture_output=True, text=True
    )
    assert syntax.returncode == 0, f"Invalid nginx configuration: {syntax.stderr}"

    result = subprocess.run(['pgrep', '-f', 'nginx.*nginx.conf'], capture_output=True, text=True)
    assert result.returncode == 0, "Nginx is not running with the custom nginx.conf."


def make_archive(path, entries):
    with tarfile.open(path, 'w:gz') as archive:
        for relative, content in entries.items():
            data = content.encode('utf-8')
            info = tarfile.TarInfo(relative)
            info.size = len(data)
            info.mode = 0o777
            archive.addfile(info, io.BytesIO(data))


def acl_supported():
    with tempfile.NamedTemporaryFile() as probe:
        result = subprocess.run(
            ['setfacl', '-m', 'u:nobody:r', probe.name],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        return result.returncode == 0


def assert_acl(path, expected):
    result = subprocess.run(['getfacl', '-cp', path], capture_output=True, text=True, check=True)
    assert f'user:nobody:{expected}' in result.stdout, f"Missing nobody:{expected} ACL on {path}:\n{result.stdout}"


def test_end_to_end_restore_tester():
    inbox = os.path.join(HOME, 'restore_inbox')
    active = os.path.join(HOME, 'restore_active')
    processed = os.path.join(HOME, 'restore_processed')
    proxy_conf = os.path.join(HOME, 'proxy_conf')

    # Occupy 9000 when possible, forcing the implementation to discover another port.
    blocker = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        blocker.bind(('127.0.0.1', 9000))
        blocker.listen(1)
    except OSError:
        blocker.close()
        blocker = None  # Port 9000 was already occupied and therefore still unavailable.

    token = secrets.token_hex(6)
    bases = [f'backup_{token}_alpha', f'backup_{token}_beta']
    contents = {
        bases[0]: {
            'root.txt': f'root-{secrets.token_urlsafe(18)}',
            'nested/first.txt': f'first-{secrets.token_urlsafe(18)}',
            'nested/deeper/second.bin': f'second-{secrets.token_urlsafe(18)}',
        },
        bases[1]: {
            'index.html': f'index-{secrets.token_urlsafe(18)}',
            'other/item.txt': f'item-{secrets.token_urlsafe(18)}',
        },
    }

    sentinel = os.path.join(inbox, f'ignore_{token}.txt')
    with open(sentinel, 'w', encoding='utf-8') as f:
        f.write('not an archive')
    subprocess.run(['chown', 'user:user', sentinel], check=True)

    for base in bases:
        archive_path = os.path.join(inbox, base + '.tar.gz')
        make_archive(archive_path, contents[base])
        subprocess.run(['chown', 'user:user', archive_path], check=True)

    run = subprocess.run(
        ['su', '-', 'user', '-c', 'python3 /home/user/restore_tester.py'],
        capture_output=True, text=True, timeout=30
    )
    assert run.returncode == 0, f"restore_tester.py failed to execute:\nstdout: {run.stdout}\nstderr: {run.stderr}"
    time.sleep(2)

    assert os.path.isfile(sentinel), "A non-.tar.gz inbox file was incorrectly processed"
    ports = []
    check_acls = acl_supported()

    for base in bases:
        archive_name = base + '.tar.gz'
        assert not os.path.exists(os.path.join(inbox, archive_name)), f"{archive_name} remained in inbox"
        assert os.path.isfile(os.path.join(processed, archive_name)), f"Tarball was not moved to processed: {archive_name}"

        root = os.path.join(active, base)
        assert os.path.isdir(root), f"Extraction directory missing: {root}"

        expected_dirs = {root}
        for relative, expected_content in contents[base].items():
            path = os.path.join(root, *relative.split('/'))
            assert os.path.isfile(path), f"Extracted file missing: {path}"
            with open(path, 'r', encoding='utf-8') as f:
                assert f.read() == expected_content, f"Incorrect extracted content in {path}"
            assert stat.S_IMODE(os.stat(path).st_mode) == 0o640, f"File permissions are not 640: {path}"
            if check_acls:
                assert_acl(path, 'r--')
            parent = os.path.dirname(path)
            while parent.startswith(root) and parent != os.path.dirname(root):
                expected_dirs.add(parent)
                if parent == root:
                    break
                parent = os.path.dirname(parent)

        for directory in expected_dirs:
            assert os.path.isdir(directory), f"Expected directory missing: {directory}"
            assert stat.S_IMODE(os.stat(directory).st_mode) == 0o750, f"Directory permissions are not 750: {directory}"
            if check_acls:
                assert_acl(directory, 'r-x')

        snippet_path = os.path.join(proxy_conf, base + '.conf')
        assert os.path.isfile(snippet_path), f"Missing Nginx snippet {snippet_path}"
        with open(snippet_path, 'r', encoding='utf-8') as f:
            snippet = f.read()
        match = re.fullmatch(
            r'\s*location\s+/' + re.escape(base) +
            r'/\s*\{\s*proxy_pass\s+http://127\.0\.0\.1:(\d+)/;\s*\}\s*',
            snippet
        )
        assert match, f"Incorrect Nginx snippet format in {snippet_path}:\n{snippet}"
        port = int(match.group(1))
        assert port >= 9000, f"Server port is not a high port starting from 9000: {port}"
        assert port != 9000, "Port discovery selected occupied port 9000"
        ports.append(port)

        for relative, expected_content in contents[base].items():
            url = f"http://127.0.0.1:8080/{base}/{relative}"
            try:
                with urllib.request.urlopen(url, timeout=5) as response:
                    actual = response.read().decode('utf-8')
            except urllib.error.URLError as e:
                assert False, f"Failed to retrieve data via proxy at {url}: {e}"
            assert actual == expected_content, f"Unexpected response from {url}: {actual!r}"

    assert len(set(ports)) == len(ports), f"Multiple archives did not receive distinct ports: {ports}"
    for port in ports:
        with socket.create_connection(('127.0.0.1', port), timeout=3):
            pass

    if blocker is not None:
        blocker.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
