#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import importlib.util
import json
import os
import shutil
import stat
import subprocess
import tempfile
import uuid

from cryptography.fernet import Fernet

APP_DIR = "/home/user/app"
UPLOADS_DIR = os.path.join(APP_DIR, "uploads")


def test_ssh_key_rotation():
    ssh_dir = "/home/user/.ssh"
    id_rsa = os.path.join(ssh_dir, "id_rsa")
    id_rsa_pub = os.path.join(ssh_dir, "id_rsa.pub")
    id_ed25519 = os.path.join(ssh_dir, "id_ed25519")
    id_ed25519_pub = os.path.join(ssh_dir, "id_ed25519.pub")
    auth_keys = os.path.join(ssh_dir, "authorized_keys")

    assert not os.path.exists(id_rsa), "Old id_rsa key was not deleted."
    assert not os.path.exists(id_rsa_pub), "Old id_rsa.pub key was not deleted."
    assert os.path.isfile(id_ed25519), "New id_ed25519 key was not generated."
    assert os.path.isfile(id_ed25519_pub), "New id_ed25519.pub key was not generated."

    with open(id_ed25519_pub, "r") as f:
        pub_key_content = f.read().strip()
    assert os.path.isfile(auth_keys), "authorized_keys file is missing."
    with open(auth_keys, "r") as f:
        auth_keys_content = f.read().strip()
    assert auth_keys_content == pub_key_content, "authorized_keys does not exactly match the new id_ed25519 public key."

    pub_fields = pub_key_content.split()
    assert len(pub_fields) >= 2 and pub_fields[0] == "ssh-ed25519", "Public key is not an Ed25519 key."
    derived = subprocess.run(
        ["ssh-keygen", "-y", "-f", id_ed25519], capture_output=True, text=True
    )
    assert derived.returncode == 0, f"id_ed25519 is not a valid private SSH key: {derived.stderr}"
    derived_fields = derived.stdout.strip().split()
    assert len(derived_fields) >= 2 and derived_fields[0] == "ssh-ed25519", "Private key is not Ed25519."
    assert derived_fields[:2] == pub_fields[:2], "Ed25519 public and private keys do not form a keypair."

    assert stat.S_IMODE(os.stat(ssh_dir).st_mode) == 0o700, ".ssh directory permissions are not 700."
    assert stat.S_IMODE(os.stat(auth_keys).st_mode) == 0o600, "authorized_keys permissions are not 600."


def canonical_crypto_state():
    expected_plaintexts = {
        "doc1.txt": b"Confidential HR document 1.",
        "doc2.txt": b"Financial report 2023.",
        "doc3.txt": b"Server passwords and secrets.",
    }
    stored_plaintexts = dict(expected_plaintexts)
    stored_plaintexts["doc3.txt"] = b"MALICIOUS PAYLOAD"
    expected_hashes = {
        name: hashlib.sha256(data).hexdigest()
        for name, data in expected_plaintexts.items()
    }
    tampered = sorted(
        name for name, data in stored_plaintexts.items()
        if hashlib.sha256(data).hexdigest() != expected_hashes[name]
    )
    return expected_hashes, tampered


def test_tampered_log():
    log_path = os.path.join(APP_DIR, "tampered.log")
    assert os.path.exists(log_path), "tampered.log was not created."
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    _, expected_tampered = canonical_crypto_state()
    assert len(lines) == 1, f"tampered.log should contain exactly one entry, found {len(lines)}."
    assert lines[0] == "doc3.txt", f"tampered.log should contain 'doc3.txt', found '{lines[0]}'."
    assert sorted(lines) == expected_tampered, "tampered.log does not match the independently derived tampered-file set."


def test_encryption_and_integrity():
    new_key_path = os.path.join(APP_DIR, "new_key.key")
    old_key_path = os.path.join(APP_DIR, "old_key.key")
    hashes_path = os.path.join(APP_DIR, "file_hashes.json")

    assert os.path.exists(new_key_path), "new_key.key was not created."
    assert os.path.exists(os.path.join(UPLOADS_DIR, "doc1.txt")), "doc1.txt is missing from uploads."
    assert os.path.exists(os.path.join(UPLOADS_DIR, "doc2.txt")), "doc2.txt is missing from uploads."
    assert not os.path.exists(os.path.join(UPLOADS_DIR, "doc3.txt")), "doc3.txt should have been deleted."

    with open(hashes_path, "r") as f:
        original_hashes = json.load(f)
    expected_hashes, _ = canonical_crypto_state()
    assert original_hashes == expected_hashes, "file_hashes.json was modified or does not contain the original hashes."

    with open(new_key_path, "rb") as f:
        new_key = f.read()
    fernet = Fernet(new_key)
    if os.path.exists(old_key_path):
        with open(old_key_path, "rb") as f:
            assert new_key != f.read(), "new_key.key is not a rotated key."

    decrypted = []
    for name in ("doc1.txt", "doc2.txt"):
        with open(os.path.join(UPLOADS_DIR, name), "rb") as f:
            decrypted.append(fernet.decrypt(f.read()))

    doc1_hash = hashlib.sha256(decrypted[0]).hexdigest()
    doc2_hash = hashlib.sha256(decrypted[1]).hexdigest()
    assert doc1_hash == original_hashes.get("doc1.txt"), "doc1.txt content hash does not match original."
    assert doc2_hash == original_hashes.get("doc2.txt"), "doc2.txt content hash does not match original."
    assert doc1_hash == expected_hashes["doc1.txt"], "doc1.txt does not match the independently known original."
    assert doc2_hash == expected_hashes["doc2.txt"], "doc2.txt does not match the independently known original."


def test_rotation_script_on_fresh_independent_inputs():
    script_path = os.path.join(APP_DIR, "rotate_encryption.py")
    assert os.path.isfile(script_path), "rotate_encryption.py was not created."

    managed = ["uploads", "old_key.key", "new_key.key", "file_hashes.json", "tampered.log"]
    backup = tempfile.mkdtemp(prefix="rotation-state-")
    present = set()
    try:
        for name in managed:
            src = os.path.join(APP_DIR, name)
            if os.path.lexists(src):
                present.add(name)
                dst = os.path.join(backup, name)
                if os.path.isdir(src) and not os.path.islink(src):
                    shutil.copytree(src, dst)
                else:
                    shutil.copy2(src, dst, follow_symlinks=False)

        for name in managed:
            path = os.path.join(APP_DIR, name)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            elif os.path.lexists(path):
                os.unlink(path)
        os.mkdir(UPLOADS_DIR)

        token = uuid.uuid4().hex
        valid = {
            f"valid-{token}-a.bin": os.urandom(41),
            f"valid-{token}-b.bin": os.urandom(137),
            f"valid-{token}-c.bin": b"independent verifier payload " + os.urandom(23),
        }
        tampered_name = f"tampered-{token}.bin"
        originals = dict(valid)
        originals[tampered_name] = os.urandom(89)
        hashes = {name: hashlib.sha256(data).hexdigest() for name, data in originals.items()}

        old_key = Fernet.generate_key()
        old_fernet = Fernet(old_key)
        with open(os.path.join(APP_DIR, "old_key.key"), "wb") as f:
            f.write(old_key)
        with open(os.path.join(APP_DIR, "file_hashes.json"), "w") as f:
            json.dump(hashes, f)
        for name, data in valid.items():
            with open(os.path.join(UPLOADS_DIR, name), "wb") as f:
                f.write(old_fernet.encrypt(data))
        with open(os.path.join(UPLOADS_DIR, tampered_name), "wb") as f:
            f.write(old_fernet.encrypt(os.urandom(73)))

        result = subprocess.run(
            ["python3", script_path], cwd=APP_DIR, capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, f"rotate_encryption.py failed on fresh inputs: {result.stderr}"

        with open(os.path.join(APP_DIR, "file_hashes.json"), "r") as f:
            assert json.load(f) == hashes, "rotate_encryption.py altered the original hash records."
        with open(os.path.join(APP_DIR, "new_key.key"), "rb") as f:
            generated_key = f.read()
        assert generated_key != old_key, "rotate_encryption.py did not generate a new key."
        rotated = Fernet(generated_key)

        assert set(os.listdir(UPLOADS_DIR)) == set(valid), "Script did not retain exactly the valid files."
        for name, expected in valid.items():
            with open(os.path.join(UPLOADS_DIR, name), "rb") as f:
                assert rotated.decrypt(f.read()) == expected, f"{name} was not correctly re-encrypted."
        with open(os.path.join(APP_DIR, "tampered.log"), "r") as f:
            logged = [line.strip() for line in f if line.strip()]
        assert logged == [tampered_name], "Script did not dynamically identify the tampered file."
    finally:
        for name in managed:
            path = os.path.join(APP_DIR, name)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            elif os.path.lexists(path):
                os.unlink(path)
        for name in present:
            src = os.path.join(backup, name)
            dst = os.path.join(APP_DIR, name)
            if os.path.isdir(src) and not os.path.islink(src):
                shutil.copytree(src, dst)
            else:
                shutil.copy2(src, dst, follow_symlinks=False)
        shutil.rmtree(backup, ignore_errors=True)


def test_app_firewall_policy():
    app_path = os.path.join(APP_DIR, "app.py")
    assert os.path.exists(app_path), "app.py is missing."
    with open(app_path, "r") as f:
        content = f.read()

    assert "before_request" in content, "before_request hook is missing in app.py."
    assert "request.remote_addr" in content, "request.remote_addr is not checked in app.py."
    assert "127.0.0.1" in content, "127.0.0.1 is not present in the firewall logic."
    assert "abort(403)" in content or "abort(403" in content.replace(" ", ""), "abort(403) is missing in app.py."

    module_name = "submitted_app_" + uuid.uuid4().hex
    spec = importlib.util.spec_from_file_location(module_name, app_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "app"), "app.py does not define a Flask app named app."
    module.app.config.update(TESTING=True)
    client = module.app.test_client()

    local = client.post("/upload", environ_base={"REMOTE_ADDR": "127.0.0.1"})
    assert local.status_code != 403, "The firewall incorrectly blocks 127.0.0.1."
    remote = client.post("/upload", environ_base={"REMOTE_ADDR": "203.0.113.77"})
    assert remote.status_code == 403, "The firewall does not block a non-local requester with HTTP 403."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
