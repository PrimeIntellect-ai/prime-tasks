#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import os
import secrets
import stat
import subprocess
import tempfile
import time
import urllib.parse


def test_ssh_deploy_key():
    key_path = "/home/user/.ssh/deploy_key"
    pub_path = key_path + ".pub"
    assert os.path.isfile(key_path), f"SSH key {key_path} was not created."
    assert os.path.isfile(pub_path), f"SSH public key {pub_path} was not created."

    with open(key_path, "r") as f:
        content = f.read()
    assert "OPENSSH PRIVATE KEY" in content, "deploy_key does not appear to be a valid OpenSSH private key."

    result = subprocess.run(
        ["ssh-keygen", "-y", "-f", key_path],
        input="",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, "deploy_key is not a valid unencrypted private key."
    derived_fields = result.stdout.strip().split()
    assert len(derived_fields) >= 2 and derived_fields[0] == "ssh-ed25519", "deploy_key is not an Ed25519 key."
    derived_public = " ".join(derived_fields[:2])

    with open(pub_path, "r") as f:
        public_fields = f.read().strip().split()
    assert len(public_fields) >= 2, "deploy_key.pub is not a valid public key."
    assert " ".join(public_fields[:2]) == derived_public, "deploy_key.pub does not match deploy_key."


def test_authorized_keys():
    auth_keys_path = "/home/user/.ssh/authorized_keys"
    assert os.path.isfile(auth_keys_path), f"{auth_keys_path} does not exist."

    with open(auth_keys_path, "r") as f:
        content = f.read()

    expected_prefix = 'no-pty,no-port-forwarding,no-X11-forwarding,command="/home/user/run_sandboxed.sh" ssh-ed25519'
    assert expected_prefix in content, "authorized_keys does not contain the correct restrictions and key type."

    result = subprocess.run(
        ["ssh-keygen", "-y", "-f", "/home/user/.ssh/deploy_key"],
        input="",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0
    key_fields = result.stdout.strip().split()
    expected_entry = (
        'no-pty,no-port-forwarding,no-X11-forwarding,command="/home/user/run_sandboxed.sh" '
        + " ".join(key_fields[:2])
    )
    lines = [line.strip() for line in content.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    assert any(line == expected_entry or line.startswith(expected_entry + " ") for line in lines), \
        "authorized_keys restrictions are not attached to the public key generated from deploy_key."


def test_run_sandboxed_script():
    script_path = "/home/user/run_sandboxed.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert content.startswith("#!/bin/bash"), "Script must start with #!/bin/bash shebang."
    expected_bwrap = "bwrap --ro-bind / / --dev /dev --unshare-all --share-net --bind /home/user/app /home/user/app /home/user/app/target/release/web_app"
    assert expected_bwrap in content, "Script does not contain the exact bwrap command required."
    subprocess.run(["bash", "-n", script_path], check=True, timeout=5)

    expected_args = [
        "--ro-bind", "/", "/", "--dev", "/dev", "--unshare-all", "--share-net",
        "--bind", "/home/user/app", "/home/user/app",
        "/home/user/app/target/release/web_app",
    ]
    with tempfile.TemporaryDirectory(prefix="verify-bwrap-") as fake_dir:
        fake_bwrap = os.path.join(fake_dir, "bwrap")
        log_path = os.path.join(fake_dir, "arguments")
        with open(fake_bwrap, "w") as f:
            f.write('#!/bin/sh\nprintf "%s\\n" "$@" > "$BWRAP_VERIFY_LOG"\n')
        os.chmod(fake_bwrap, 0o755)
        env = os.environ.copy()
        env["PATH"] = fake_dir + os.pathsep + env.get("PATH", "")
        env["BWRAP_VERIFY_LOG"] = log_path
        result = subprocess.run(
            [script_path], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=10,
        )
        assert result.returncode == 0, f"Sandbox script failed when executed: {result.stderr}"
        assert os.path.isfile(log_path), "Executing the script did not invoke bwrap."
        with open(log_path, "r") as f:
            actual_args = f.read().splitlines()
        assert actual_args == expected_args, f"bwrap was invoked with incorrect arguments: {actual_args}"


def test_rust_app_redirect():
    bin_path = "/home/user/app/target/release/web_app"
    assert os.path.isfile(bin_path), f"Compiled application not found at {bin_path}."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled application is not an ELF executable."
    assert os.access(bin_path, os.X_OK), "Compiled application is not executable."

    process = subprocess.Popen([bin_path], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        deadline = time.time() + 8
        while time.time() < deadline:
            if process.poll() is not None:
                stderr = process.stderr.read().decode(errors="replace")
                raise AssertionError(f"Application exited before serving requests: {stderr}")
            try:
                conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=0.5)
                conn.request("GET", "/login")
                response = conn.getresponse()
                response.read()
                conn.close()
                break
            except OSError:
                time.sleep(0.1)
        else:
            raise AssertionError("Application did not start listening on 127.0.0.1:8080.")

        def fetch_location(target):
            conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=2)
            conn.request("GET", target)
            response = conn.getresponse()
            location = response.getheader("Location")
            status = response.status
            response.read()
            conn.close()
            assert status in (301, 302, 303, 307, 308), f"Expected redirect for {target}, got HTTP {status}"
            return location

        # Preserve the original fixed assertions.
        assert fetch_location("/login?next=/profile") == "/profile"
        assert fetch_location("/login?next=http://evil.com") == "/dashboard"
        assert fetch_location("/login?next=//evil.com") == "/dashboard"
        assert fetch_location("/login") == "/dashboard"

        # Exercise fresh, unpredictable valid and invalid values so fixed-response servers fail.
        valid_values = ["/"]
        invalid_values = ["", "relative", "https://example.invalid", "///triple"]
        for _ in range(24):
            a = secrets.token_hex(8)
            b = secrets.token_hex(6)
            valid_values.extend([f"/{a}", f"/{a}/{b}"])
            invalid_values.extend([
                a,
                f"http://{a}.invalid/{b}",
                f"//{a}.invalid/{b}",
                f"///{a}/{b}",
            ])

        for value in valid_values:
            query = urllib.parse.quote(value, safe="")
            location = fetch_location("/login?next=" + query)
            assert location == value, f"Expected redirect to {value!r}, got {location!r}"

        for value in invalid_values:
            query = urllib.parse.quote(value, safe="")
            location = fetch_location("/login?next=" + query)
            assert location == "/dashboard", f"Expected fallback for {value!r}, got {location!r}"
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
