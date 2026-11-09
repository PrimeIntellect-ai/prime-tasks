#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import string
import subprocess
import tempfile
from pathlib import Path

import pytest

CLEAN_CORPUS_DIR = "/app/corpora/clean"
EVIL_CORPUS_DIR = "/app/corpora/evil"
PROVISIONER_DIR = Path("/home/user/provisioner")
PROVISIONER_BIN = PROVISIONER_DIR / "target/release/provisioner"
ACL_DIR = Path("/app/acl-manager-rs")
ACL_LIB = ACL_DIR / "src/lib.rs"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=120, **kwargs)


def invoke(path):
    return subprocess.run([str(PROVISIONER_BIN), str(path)], capture_output=True, timeout=10).returncode


def test_provisioner_binary_exists():
    """Ensure the provisioner binary has been compiled in release mode."""
    assert PROVISIONER_BIN.is_file(), f"Provisioner binary not found at {PROVISIONER_BIN}. Did you build in release mode?"
    assert os.access(PROVISIONER_BIN, os.X_OK), f"Provisioner binary at {PROVISIONER_BIN} is not executable."


def test_clean_corpus():
    """Ensure the provisioner accepts all valid profiles in the clean corpus."""
    assert PROVISIONER_BIN.is_file(), f"Missing binary {PROVISIONER_BIN}"
    failed_clean = []
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if f.endswith('.json')]
    for f in clean_files:
        if invoke(Path(CLEAN_CORPUS_DIR) / f) != 0:
            failed_clean.append(f)
    assert not failed_clean, f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected. Offending files: {', '.join(failed_clean)}"


def test_evil_corpus():
    """Ensure the provisioner firmly rejects all malformed profiles in the evil corpus."""
    assert PROVISIONER_BIN.is_file(), f"Missing binary {PROVISIONER_BIN}"
    bypassed_evil = []
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if f.endswith('.json')]
    for f in evil_files:
        if invoke(Path(EVIL_CORPUS_DIR) / f) == 0:
            bypassed_evil.append(f)
    assert not bypassed_evil, f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed. Offending files: {', '.join(bypassed_evil)}"


def test_acl_package_is_fixed_and_is_local_dependency():
    assert (ACL_DIR / "Cargo.toml").is_file()
    assert (ACL_DIR / "build.rs").is_file()
    assert (PROVISIONER_DIR / "Cargo.toml").is_file()

    env = os.environ.copy()
    env.pop("ACL_BUILD_MODE", None)
    with tempfile.TemporaryDirectory(prefix="acl-check-") as td:
        compiled_build_rs = Path(td) / "build-script"
        result = run(["rustc", str(ACL_DIR / "build.rs"), "-o", str(compiled_build_rs)], env=env)
        assert result.returncode == 0, result.stderr
        result = run([str(compiled_build_rs)], cwd=str(ACL_DIR), env=env)
        assert result.returncode == 0, "acl-manager-rs build.rs still fails when ACL_BUILD_MODE is absent"

    result = run(["cargo", "clean"], cwd=str(ACL_DIR), env=env)
    assert result.returncode == 0, result.stderr
    result = run(["cargo", "build"], cwd=str(ACL_DIR), env=env)
    assert result.returncode == 0, f"acl-manager-rs does not build independently:\n{result.stderr}"

    result = run(["cargo", "metadata", "--format-version", "1"], cwd=str(PROVISIONER_DIR), env=env)
    assert result.returncode == 0, result.stderr
    metadata = json.loads(result.stdout)
    acl_packages = [p for p in metadata["packages"] if p["name"] == "acl-manager-rs"]
    assert acl_packages, "provisioner does not depend on acl-manager-rs"
    expected_manifest = str((ACL_DIR / "Cargo.toml").resolve())
    assert any(str(Path(p["manifest_path"]).resolve()) == expected_manifest for p in acl_packages), \
        "acl-manager-rs dependency is not the required local /app/acl-manager-rs package"

    root = metadata.get("resolve", {}).get("root")
    root_node = next((n for n in metadata.get("resolve", {}).get("nodes", []) if n["id"] == root), None)
    acl_ids = {p["id"] for p in acl_packages}
    assert root_node and any(d["pkg"] in acl_ids for d in root_node.get("deps", [])), \
        "acl-manager-rs is not a direct provisioner dependency"


def test_randomized_validation_outside_corpora():
    rng = random.SystemRandom()
    letters = string.ascii_lowercase + string.digits + "_"

    def username(n):
        return ''.join(rng.choice(letters) for _ in range(n))

    def profile(**changes):
        value = {
            "username": username(rng.randint(3, 20)),
            "quota_mb": rng.randint(1, 10240),
            "ssh_key": rng.choice(["ssh-rsa ", "ssh-ed25519 "]) + secrets.token_urlsafe(24) + " user@host",
            "sync_ip": ".".join(str(rng.randint(0, 255)) for _ in range(4)),
        }
        value.update(changes)
        return value

    valid = [
        profile(username=username(1), quota_mb=1, sync_ip="0.0.0.0"),
        profile(username=username(32), quota_mb=10240, sync_ip="255.255.255.255"),
    ] + [profile() for _ in range(10)]

    invalid = [
        profile(username=""), profile(username=username(33)), profile(username="UpperCase"),
        profile(username="bad-name"), profile(username="../root"), profile(username="name/name"),
        profile(username="na.me"), profile(username="josé"), profile(quota_mb=0),
        profile(quota_mb=-1), profile(quota_mb=10241), profile(quota_mb=1.5),
        profile(quota_mb="500"), profile(quota_mb=True), profile(ssh_key="rsa AAAA"),
        profile(ssh_key="ssh-dss AAAA"), profile(ssh_key="ssh-rsa;AAAA"),
        profile(ssh_key="ssh-rsa AAA;whoami"), profile(ssh_key="ssh-ed25519 AAA|cat"),
        profile(ssh_key="ssh-rsa AAA&echo"), profile(ssh_key="ssh-rsa AAA$HOME"),
        profile(ssh_key="ssh-rsa AAA>file"), profile(ssh_key="ssh-rsa AAA<input"),
        profile(sync_ip="256.1.2.3"), profile(sync_ip="1.2.3"),
        profile(sync_ip="1.2.3.4.5"), profile(sync_ip="01.2.3.4"),
        profile(sync_ip="1.2.3.-1"), profile(sync_ip="localhost"),
    ]
    for field in ("username", "quota_mb", "ssh_key", "sync_ip"):
        p = profile()
        del p[field]
        invalid.append(p)

    with tempfile.TemporaryDirectory(prefix="profiles-" + secrets.token_hex(6) + "-") as td:
        root = Path(td)
        for expected, cases in ((0, valid), (1, invalid)):
            for data in cases:
                path = root / (secrets.token_hex(12) + ".dat")
                path.write_text(json.dumps(data), encoding="utf-8")
                rc = invoke(path)
                if expected == 0:
                    assert rc == 0, f"rejected generated valid profile: {data}"
                else:
                    assert rc != 0, f"accepted generated invalid profile: {data}"

        malformed = ["", "not json", "{", "[]", "null", '{"username":"a"']
        for text in malformed:
            path = root / (secrets.token_hex(12) + ".json")
            path.write_text(text, encoding="utf-8")
            assert invoke(path) != 0, f"accepted malformed JSON: {text!r}"

        missing = root / (secrets.token_hex(12) + ".json")
        assert invoke(missing) != 0, "accepted a nonexistent input file"

    no_arg = subprocess.run([str(PROVISIONER_BIN)], capture_output=True, timeout=10)
    assert no_arg.returncode != 0, "accepted invocation without a JSON path"


def test_dry_run_acl_result_is_actually_enforced():
    original = ACL_LIB.read_text(encoding="utf-8")
    pattern = re.compile(r"pub\s+fn\s+dry_run_acl\s*\(\s*\)\s*->\s*bool\s*\{[^{}]*\}", re.S)
    assert pattern.search(original), "acl-manager-rs no longer exposes the required dry_run_acl function"
    injected = pattern.sub("pub fn dry_run_acl() -> bool { false }", original, count=1)

    with tempfile.TemporaryDirectory(prefix="acl-runtime-") as td:
        sample = Path(td) / (secrets.token_hex(10) + ".json")
        sample.write_text(json.dumps({
            "username": "acl_" + secrets.token_hex(4),
            "quota_mb": random.SystemRandom().randint(1, 10240),
            "ssh_key": "ssh-ed25519 " + secrets.token_urlsafe(24),
            "sync_ip": "10.23.45.67",
        }), encoding="utf-8")
        try:
            ACL_LIB.write_text(injected, encoding="utf-8")
            result = run(["cargo", "clean"], cwd=str(PROVISIONER_DIR))
            assert result.returncode == 0, result.stderr
            result = run(["cargo", "build", "--release"], cwd=str(PROVISIONER_DIR))
            assert result.returncode == 0, f"provisioner failed to rebuild with its dependency:\n{result.stderr}"
            assert invoke(sample) != 0, "provisioner does not enforce acl-manager-rs dry_run_acl() failure"
        finally:
            ACL_LIB.write_text(original, encoding="utf-8")
            subprocess.run(["cargo", "clean"], cwd=str(PROVISIONER_DIR), capture_output=True)
            restored = run(["cargo", "build", "--release"], cwd=str(PROVISIONER_DIR))
            assert restored.returncode == 0, f"failed to restore final release build:\n{restored.stderr}"

    assert invoke(sample) == 0, "restored ACL implementation should permit the valid profile"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
