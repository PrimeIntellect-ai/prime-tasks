#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import pytest

KEY = "/home/user/unlocked_rsa"
PAYLOAD = "/home/user/payload.py"
EXPECTED_FLAG = "FLAG{evasion_successful}\n"

def run(cmd, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, **kwargs)

def public_fields(data):
    fields = data.decode().strip().split()
    assert len(fields) >= 2, f"Invalid SSH public key output: {data!r}"
    return fields[:2]

def test_unlocked_rsa_exists_and_permissions():
    assert os.path.exists(KEY), f"Missing file: {KEY}"
    assert os.path.isfile(KEY), f"Not a file: {KEY}"
    st = os.stat(KEY)
    assert not bool(st.st_mode & (stat.S_IRWXG | stat.S_IRWXO)), \
        f"Permissions for {KEY} are too open. Should not be accessible by group/others."

    unlocked = run(["ssh-keygen", "-y", "-f", KEY], input=b"")
    assert unlocked.returncode == 0, \
        f"Unlocked key is not a usable unencrypted private key: {unlocked.stderr.decode(errors='ignore')}"

    encrypted = run(["ssh-keygen", "-y", "-P", "ShadowKey99", "-f", "/app/id_rsa"], input=b"")
    assert encrypted.returncode == 0, \
        f"Could not inspect the provided encrypted key: {encrypted.stderr.decode(errors='ignore')}"
    assert public_fields(unlocked.stdout) == public_fields(encrypted.stdout), \
        "unlocked_rsa is not the decrypted form of the provided /app/id_rsa key"

def test_payload_exists():
    assert os.path.exists(PAYLOAD), f"Missing file: {PAYLOAD}"
    assert os.path.isfile(PAYLOAD), f"Not a file: {PAYLOAD}"

def test_payload_execution_and_size():
    assert os.path.exists(PAYLOAD), "Payload script does not exist."

    # Restore the known target content before exercising the real SSH payload.
    try:
        os.unlink("/var/opt/flag.txt")
    except FileNotFoundError:
        pass
    with open("/var/opt/flag.txt", "w") as f:
        f.write(EXPECTED_FLAG)
    os.chmod("/var/opt/flag.txt", 0o644)

    try:
        result = run(["python3", PAYLOAD])
    except subprocess.TimeoutExpired:
        pytest.fail("Payload script execution timed out.")
    except Exception as e:
        pytest.fail(f"Failed to execute payload script: {e}")

    out = result.stdout.decode(errors="replace")
    assert result.returncode == 0, \
        f"Payload script execution failed with return code {result.returncode}. Output:\n{out}{result.stderr.decode(errors='ignore')}"
    assert "FLAG{" in out, f"Payload output did not contain the expected flag format. Output was: {out}"
    assert out == EXPECTED_FLAG, f"Payload did not print the exact flag. Output was: {out!r}"

    # Interpose ssh and issue a fresh challenge to prove the payload invokes SSH
    # with the required host, identity, host-key option, and remote command.
    token = "SSH_CHALLENGE_" + secrets.token_hex(16)
    marker = "/tmp/ssh-marker-" + secrets.token_hex(16)
    ssh_path = "/usr/bin/ssh"
    real_path = "/usr/bin/ssh.verifier-real"
    wrapper = '''#!/usr/bin/python3
import json,sys
args=sys.argv[1:]
identity=False
strict=False
login=None
i=0
while i < len(args) and args[i].startswith('-'):
 x=args[i]
 if x=='-i' and i+1<len(args): identity=args[i+1]=='/home/user/unlocked_rsa';i+=2;continue
 if x.startswith('-i') and len(x)>2: identity=x[2:]=='/home/user/unlocked_rsa';i+=1;continue
 if x=='-o' and i+1<len(args):
  strict=args[i+1].lower()=='stricthostkeychecking=no' or strict;i+=2;continue
 if x.startswith('-o') and len(x)>2:
  strict=x[2:].lower()=='stricthostkeychecking=no' or strict;i+=1;continue
 if x=='-l' and i+1<len(args): login=args[i+1];i+=2;continue
 if x.startswith('-l') and len(x)>2: login=x[2:];i+=1;continue
 i+=1
host=args[i] if i<len(args) else ''
cmd=' '.join(args[i+1:]) if i<len(args) else ''
destination=(host=='user@localhost') or (host=='localhost' and login=='user')
valid=identity and strict and destination and cmd=='cat /var/opt/flag.txt'
if not valid:
 sys.stderr.write('invalid ssh invocation: '+json.dumps(args)+'\\n');sys.exit(97)
open(%r,'w').write(json.dumps(args))
print(%r)
''' % (marker, token)

    assert not os.path.exists(real_path), f"Unexpected verifier backup already exists: {real_path}"
    os.replace(ssh_path, real_path)
    try:
        with open(ssh_path, "w") as f:
            f.write(wrapper)
        os.chmod(ssh_path, 0o755)
        try:
            challenged = run(["python3", PAYLOAD])
        except subprocess.TimeoutExpired:
            pytest.fail("Payload timed out during SSH invocation verification.")
        assert challenged.returncode == 0, \
            f"Payload failed SSH invocation verification: {challenged.stderr.decode(errors='ignore')}"
        assert challenged.stdout.decode(errors="replace").strip() == token, \
            "Payload did not print the output returned by its SSH command"
        assert os.path.isfile(marker), \
            "Payload did not invoke SSH with user@localhost, unlocked_rsa, disabled strict host-key checking, and the required cat command"
    finally:
        try:
            os.unlink(ssh_path)
        except FileNotFoundError:
            pass
        os.replace(real_path, ssh_path)
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass

    size = os.path.getsize(PAYLOAD)
    threshold = 110
    assert size <= threshold, f"Payload size {size} bytes exceeds the threshold of {threshold} bytes."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
