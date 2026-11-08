#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


def test_validator_source_exists():
    """Verify that the validator source code exists."""
    source_path = "/home/user/validator.cpp"
    assert os.path.isfile(source_path), f"Missing validator source file: {source_path}"


def test_validator_binary_exists():
    """Verify that the compiled validator binary exists and is executable."""
    binary_path = "/home/user/validator"
    assert os.path.isfile(binary_path), f"Missing compiled validator binary: {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Validator binary is not executable: {binary_path}"


def test_deploy_log_content():
    """Verify that the staged binary was approved."""
    log_path = "/home/user/deploy.log"
    assert os.path.isfile(log_path), f"Missing deploy.log file: {log_path}"

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "DEPLOY_APPROVED", f"Expected DEPLOY_APPROVED in deploy.log, but got: '{content}'"


def _run(cmd, cwd):
    subprocess.run(cmd, cwd=cwd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_validator_behavior():
    validator = Path("/home/user/validator")
    root_path = Path("/home/user/root_ca.pem")
    log_path = Path("/home/user/deploy.log")
    original_root = root_path.read_bytes()
    original_mode = root_path.stat().st_mode

    with tempfile.TemporaryDirectory(prefix="validator-tests-") as td:
        work = Path(td)
        try:
            # Generate a fresh trust hierarchy so expected certificate results are
            # independently derived by this test rather than taken from staged files.
            _run(["openssl", "genrsa", "-out", "test_root.key", "2048"], work)
            _run([
                "openssl", "req", "-x509", "-new", "-key", "test_root.key",
                "-sha256", "-days", "30", "-out", "test_root.pem",
                "-subj", "/CN=Verifier Test Root"
            ], work)

            (work / "leaf.ext").write_text(
                "basicConstraints=critical,CA:FALSE\n"
                "keyUsage=critical,digitalSignature,keyEncipherment\n"
            )
            (work / "intermediate.ext").write_text(
                "basicConstraints=critical,CA:TRUE,pathlen:0\n"
                "keyUsage=critical,keyCertSign,cRLSign\n"
                "subjectKeyIdentifier=hash\n"
                "authorityKeyIdentifier=keyid,issuer\n"
            )

            # A leaf signed directly by the trusted root.
            _run(["openssl", "genrsa", "-out", "direct.key", "2048"], work)
            _run([
                "openssl", "req", "-new", "-key", "direct.key", "-out", "direct.csr",
                "-subj", "/CN=Direct Test Leaf"
            ], work)
            _run([
                "openssl", "x509", "-req", "-in", "direct.csr",
                "-CA", "test_root.pem", "-CAkey", "test_root.key", "-CAcreateserial",
                "-out", "direct.pem", "-days", "20", "-sha256", "-extfile", "leaf.ext"
            ], work)

            # A leaf signed through an intermediate, supplied as a multi-cert chain.
            _run(["openssl", "genrsa", "-out", "intermediate.key", "2048"], work)
            _run([
                "openssl", "req", "-new", "-key", "intermediate.key",
                "-out", "intermediate.csr", "-subj", "/CN=Verifier Intermediate"
            ], work)
            _run([
                "openssl", "x509", "-req", "-in", "intermediate.csr",
                "-CA", "test_root.pem", "-CAkey", "test_root.key", "-CAcreateserial",
                "-out", "intermediate.pem", "-days", "20", "-sha256",
                "-extfile", "intermediate.ext"
            ], work)
            _run(["openssl", "genrsa", "-out", "chain_leaf.key", "2048"], work)
            _run([
                "openssl", "req", "-new", "-key", "chain_leaf.key",
                "-out", "chain_leaf.csr", "-subj", "/CN=Chained Test Leaf"
            ], work)
            _run([
                "openssl", "x509", "-req", "-in", "chain_leaf.csr",
                "-CA", "intermediate.pem", "-CAkey", "intermediate.key", "-CAcreateserial",
                "-out", "chain_leaf.pem", "-days", "10", "-sha256", "-extfile", "leaf.ext"
            ], work)
            (work / "multi_chain.pem").write_bytes(
                (work / "chain_leaf.pem").read_bytes() + (work / "intermediate.pem").read_bytes()
            )
            _run([
                "openssl", "verify", "-CAfile", "test_root.pem", "-untrusted",
                "intermediate.pem", "chain_leaf.pem"
            ], work)

            # A well-formed certificate that is not rooted in the trusted CA.
            _run(["openssl", "genrsa", "-out", "rogue.key", "2048"], work)
            _run([
                "openssl", "req", "-x509", "-new", "-key", "rogue.key",
                "-sha256", "-days", "20", "-out", "rogue.pem",
                "-subj", "/CN=Untrusted Certificate"
            ], work)

            (work / "base.c").write_text("int main(void) { return 0; }\n")
            _run(["gcc", "base.c", "-o", "base"], work)

            secure = b"default-src 'self'; script-src 'self' https://cdn.example; object-src 'none';"
            safe_other_directive = b"default-src 'unsafe-inline'; script-src 'self'; object-src 'none';"
            unsafe_inline = b"default-src 'self'; script-src 'self' 'unsafe-inline';"
            unsafe_eval = b"default-src 'self'; script-src 'unsafe-eval' https://cdn.example;"

            def make_elf(name, csp=None, cert=None):
                output = work / name
                shutil.copy2(work / "base", output)
                cmd = ["objcopy"]
                if csp is not None:
                    csp_file = work / (name + ".csp")
                    csp_file.write_bytes(csp)
                    cmd += ["--add-section", f".csp_policy={csp_file}",
                            "--set-section-flags", ".csp_policy=readonly"]
                if cert is not None:
                    cmd += ["--add-section", f".cert_chain={cert}",
                            "--set-section-flags", ".cert_chain=readonly"]
                cmd.append(str(output))
                _run(cmd, work)
                return output

            cases = [
                (make_elf("valid_direct", secure, work / "direct.pem"), "DEPLOY_APPROVED"),
                (make_elf("valid_multi", secure, work / "multi_chain.pem"), "DEPLOY_APPROVED"),
                (make_elf("safe_scope", safe_other_directive, work / "direct.pem"), "DEPLOY_APPROVED"),
                (make_elf("unsafe_inline", unsafe_inline, work / "direct.pem"), "DEPLOY_REJECTED"),
                (make_elf("unsafe_eval", unsafe_eval, work / "direct.pem"), "DEPLOY_REJECTED"),
                (make_elf("untrusted_chain", secure, work / "rogue.pem"), "DEPLOY_REJECTED"),
                (make_elf("missing_csp", None, work / "direct.pem"), "DEPLOY_REJECTED"),
                (make_elf("missing_cert", secure, None), "DEPLOY_REJECTED"),
            ]

            root_path.write_bytes((work / "test_root.pem").read_bytes())
            for artifact, expected in cases:
                if log_path.exists():
                    log_path.unlink()
                subprocess.run(
                    [str(validator), str(artifact)],
                    cwd=work,
                    timeout=15,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=False,
                )
                assert log_path.is_file(), f"Validator did not create deploy.log for {artifact.name}"
                actual = log_path.read_text()
                assert actual == expected, (
                    f"For {artifact.name}, expected exactly {expected!r}, got {actual!r}"
                )
        finally:
            root_path.write_bytes(original_root)
            os.chmod(root_path, original_mode)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
