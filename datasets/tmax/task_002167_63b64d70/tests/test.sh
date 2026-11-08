#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_supervisor.py
import ast
import os
import secrets
import stat
import subprocess

SCRIPT = "/home/user/deploy_supervisor.py"
CONF = "/home/user/app.conf"
LOG = "/home/user/deploy.log"
COUNT = "/home/user/.deploy_count"
LEGACY = "/home/user/legacy_deploy.sh"
SECRET = "S3cr3tH4rd3n!"


def run_supervisor(env=None, timeout=30):
    result = subprocess.run(
        [SCRIPT],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    return result


def write_legacy(content):
    with open(LEGACY, "w") as f:
        f.write(content)
    os.chmod(LEGACY, 0o755)


def reset_files():
    with open(CONF, "w") as f:
        f.write("insecure_mode=true\nlog_level=debug\nverifier_sentinel=preserve-me\n")
    for path in (LOG, COUNT, "/tmp/verifier_attempts", "/tmp/verifier_passphrases", "/tmp/legacy_invoked"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def assert_uses_pexpect():
    with open(SCRIPT, "r") as f:
        tree = ast.parse(f.read(), filename=SCRIPT)

    pexpect_aliases = set()
    spawn_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pexpect":
                    pexpect_aliases.add(alias.asname or "pexpect")
        elif isinstance(node, ast.ImportFrom) and node.module == "pexpect":
            for alias in node.names:
                if alias.name == "spawn":
                    spawn_aliases.add(alias.asname or "spawn")

    assert pexpect_aliases or spawn_aliases, "deploy_supervisor.py must import pexpect"

    found_spawn = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        fn = node.func
        if isinstance(fn, ast.Attribute) and fn.attr == "spawn" and isinstance(fn.value, ast.Name):
            found_spawn |= fn.value.id in pexpect_aliases
        elif isinstance(fn, ast.Name):
            found_spawn |= fn.id in spawn_aliases
    assert found_spawn, "deploy_supervisor.py must call pexpect.spawn"


def test_deploy_supervisor_exists_and_executable():
    script_file = SCRIPT
    assert os.path.exists(script_file), f"File {script_file} does not exist."
    assert os.path.isfile(script_file), f"{script_file} is not a regular file."
    st = os.stat(script_file)
    assert bool(st.st_mode & stat.S_IXUSR), f"{script_file} is not executable."


def test_app_conf_updated():
    assert os.path.exists(CONF), f"File {CONF} does not exist."
    with open(CONF, "r") as f:
        content = f.read()
    assert "insecure_mode=false" in content, f"{CONF} does not contain 'insecure_mode=false'."
    assert "insecure_mode=true" not in content, f"{CONF} still contains 'insecure_mode=true'."


def test_deploy_log_content():
    assert os.path.exists(LOG), f"File {LOG} does not exist. The supervisor script may not have run successfully."
    with open(LOG, "r") as f:
        content = f.read()
    assert "Deployment Secure" in content, f"Expected 'Deployment Secure' in {LOG}, but got: {content}"


def test_deploy_count():
    assert os.path.exists(COUNT), f"File {COUNT} does not exist. The legacy script was likely not executed."
    with open(COUNT, "r") as f:
        content = f.read().strip()
    assert content.isdigit(), f"Expected a number in {COUNT}, got: {content}"
    count = int(content)
    assert count >= 3, f"Expected deploy count to be at least 3, got: {count}"


def test_supervisor_behavior():
    test_deploy_supervisor_exists_and_executable()
    assert_uses_pexpect()

    with open(LEGACY, "rb") as f:
        original_legacy = f.read()
    original_mode = stat.S_IMODE(os.stat(LEGACY).st_mode)

    try:
        # Force the standard-library free-space APIs to report zero bytes and
        # verify that processing stops before configuration or deployment.
        reset_files()
        patch_dir = "/tmp/lowspace_patch"
        os.makedirs(patch_dir, exist_ok=True)
        with open(os.path.join(patch_dir, "sitecustomize.py"), "w") as f:
            f.write('''import os\nimport shutil\n_real_statvfs = os.statvfs\ndef _statvfs(path):\n    if os.path.abspath(os.fspath(path)) == "/home/user/data":\n        return os.statvfs_result((4096, 4096, 100, 100, 0, 0, 0, 255, 255, 255))\n    return _real_statvfs(path)\nos.statvfs = _statvfs\nshutil.disk_usage = lambda path: shutil._ntuple_diskusage(409600, 409600, 0) if os.path.abspath(os.fspath(path)) == "/home/user/data" else shutil._disk_usage(path)\n''')
        write_legacy("#!/bin/bash\necho invoked > /tmp/legacy_invoked\nexit 0\n")
        env = os.environ.copy()
        env["PYTHONPATH"] = patch_dir + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
        run_supervisor(env=env)
        assert not os.path.exists("/tmp/legacy_invoked"), "legacy deployment ran despite insufficient storage"
        with open(CONF, "r") as f:
            low_conf = f.read()
        assert "insecure_mode=true" in low_conf, "configuration changed before the low-space early exit"
        assert os.path.exists(LOG), "low-space run did not create deploy.log"
        with open(LOG, "r") as f:
            assert "ERROR: Insufficient space" in f.read()

        # An always-failing interactive deployment must be attempted exactly
        # five times, with the required passphrase supplied on every attempt.
        reset_files()
        write_legacy('''#!/bin/bash
n=0
[ -f /tmp/verifier_attempts ] && n=$(cat /tmp/verifier_attempts)
n=$((n + 1))
echo "$n" > /tmp/verifier_attempts
IFS= read -r -p "Enter hardening passphrase: " PASS
printf '%s\\n' "$PASS" >> /tmp/verifier_passphrases
echo "controlled failure $n"
exit 9
''')
        run_supervisor()
        assert os.path.exists("/tmp/verifier_attempts"), "legacy deployment was not executed"
        with open("/tmp/verifier_attempts", "r") as f:
            assert f.read().strip() == "5", "supervisor must stop after exactly 5 failed attempts"
        with open("/tmp/verifier_passphrases", "r") as f:
            supplied = f.read().splitlines()
        assert supplied == [SECRET] * 5, "incorrect passphrase was supplied to the interactive process"
        assert os.path.exists(LOG), "max-retry run did not create deploy.log"
        with open(LOG, "r") as f:
            assert "ERROR: Max retries reached" in f.read()

        # Fail twice, then return a verifier-generated final output line. This
        # proves that retries execute the legacy script and its actual final
        # output is captured rather than a fixed artifact being fabricated.
        reset_files()
        token = secrets.token_hex(16)
        final_line = "Deployment Secure " + token
        write_legacy(f'''#!/bin/bash
n=0
[ -f "{COUNT}" ] && n=$(cat "{COUNT}")
n=$((n + 1))
echo "$n" > "{COUNT}"
IFS= read -r -p "Enter hardening passphrase: " PASS
printf '%s\\n' "$PASS" >> /tmp/verifier_passphrases
if [ "$PASS" != "{SECRET}" ]; then
    echo "Invalid passphrase"
    exit 2
fi
if [ "$n" -lt 3 ]; then
    echo "transient verifier failure $n"
    exit 17
fi
echo "intermediate output {token}"
echo "{final_line}"
exit 0
''')
        result = run_supervisor()
        assert result.returncode == 0, f"successful supervised deployment exited {result.returncode}: {result.stderr}"
        with open("/tmp/verifier_passphrases", "r") as f:
            assert f.read().splitlines() == [SECRET] * 3
        with open(LOG, "r") as f:
            log_lines = [line.rstrip("\r\n") for line in f if line.strip()]
        assert log_lines and log_lines[-1] == final_line, "deploy.log does not contain the actual final output line"
        with open(CONF, "r") as f:
            assert "verifier_sentinel=preserve-me" in f.read(), "configuration management discarded unrelated settings"

        # Preserve all assertions from the original verifier against the final
        # successful state.
        test_app_conf_updated()
        test_deploy_log_content()
        test_deploy_count()
    finally:
        with open(LEGACY, "wb") as f:
            f.write(original_legacy)
        os.chmod(LEGACY, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_supervisor.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
