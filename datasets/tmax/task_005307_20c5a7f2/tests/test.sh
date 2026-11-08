#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import stat
import string
import subprocess
import tempfile


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def test_audit_report():
    report_path = "/home/user/audit_report.txt"
    assert os.path.isfile(report_path), f"Audit report missing at {report_path}"
    assert not os.path.islink(report_path), "Audit report must not be a symlink"

    with open(report_path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    assert len(lines) == 2, "Audit report must contain exactly two lines"
    assert lines[0] in ("CWE-214", "CWE-497"), \
        "First line must be exactly CWE-214 or CWE-497"

    explanation = lines[1].strip()
    lower = explanation.lower()
    assert explanation == lines[1] and explanation, \
        "Second line must contain one sentence without surrounding whitespace"
    assert explanation.endswith((".", "!", "?")), \
        "Second line must be a complete sentence"
    assert "/proc" in lower, "Second line must identify the /proc leakage vector"
    assert any(term in lower for term in ("cmdline", "command-line", "command line", "argument")), \
        "Second line must explain that command-line arguments are exposed"
    assert any(term in lower for term in ("leak", "expos", "credential", "payload", "sensitive")), \
        "Second line must explain the credential or payload leakage"


def generate_cert(cert_path):
    cmd = [
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", "/dev/null", "-out", cert_path,
        "-days", "1", "-nodes", "-subj", "/CN=fuzz_test"
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)


def test_payload_encoder_fuzz_equivalence():
    source_path = "/home/user/payload_encoder.go"
    agent_bin = "/home/user/payload_encoder"
    oracle_bin = "/app/obfuscator_bin"

    source_stat = os.lstat(source_path)
    assert stat.S_ISREG(source_stat.st_mode), \
        "payload_encoder.go must be a regular Go source file, not a symlink"

    agent_stat = os.lstat(agent_bin)
    assert stat.S_ISREG(agent_stat.st_mode), \
        "payload_encoder must be a regular executable, not a symlink or wrapper path"
    assert os.access(agent_bin, os.X_OK), f"Agent binary is not executable at {agent_bin}"
    assert os.path.isfile(oracle_bin), f"Oracle binary missing at {oracle_bin}"

    with tempfile.TemporaryDirectory() as build_dir:
        # Rebuild using the exact submitted source path and verify that the artifact
        # installed at the required location was actually produced from that source.
        direct_bin = os.path.join(build_dir, "payload_encoder.direct")
        subprocess.run(
            ["go", "build", "-o", direct_bin, source_path],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=120,
        )
        assert sha256_file(agent_bin) == sha256_file(direct_bin), \
            "payload_encoder is not the Go build output of payload_encoder.go"

        # Build a second time from a clean directory containing only the submitted
        # source. This prevents go:embed or local helper files from smuggling a copy
        # of the oracle into the tested program. CGO is disabled so the result is a
        # self-contained executable suitable for an isolated filesystem.
        clean_src_dir = os.path.join(build_dir, "clean-src")
        os.mkdir(clean_src_dir)
        clean_source = os.path.join(clean_src_dir, "payload_encoder.go")
        with open(source_path, "rb") as src, open(clean_source, "wb") as dst:
            dst.write(src.read())

        isolated_bin = os.path.join(build_dir, "payload_encoder.clean")
        clean_env = os.environ.copy()
        clean_env.update({
            "CGO_ENABLED": "0",
            "GO111MODULE": "off",
            "GOPROXY": "off",
            "GONOSUMDB": "*",
            "GOPATH": os.path.join(build_dir, "empty-gopath"),
            "HOME": os.path.join(build_dir, "empty-home"),
        })
        os.mkdir(clean_env["GOPATH"])
        os.mkdir(clean_env["HOME"])
        subprocess.run(
            ["go", "build", "-o", isolated_bin, clean_source],
            cwd=clean_src_dir, env=clean_env, check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120,
        )

        random.seed(42)
        charset = string.ascii_letters + string.digits
        num_certs = 10
        payloads_per_cert = 1000

        with tempfile.TemporaryDirectory() as tmpdir:
            jail = os.path.join(tmpdir, "jail")
            os.mkdir(jail, 0o755)
            jail_bin = os.path.join(jail, "payload_encoder")
            with open(isolated_bin, "rb") as src, open(jail_bin, "wb") as dst:
                dst.write(src.read())
            os.chmod(jail_bin, 0o755)

            for i in range(num_certs):
                cert_path = os.path.join(tmpdir, f"cert_{i}.pem")
                generate_cert(cert_path)
                jail_cert = os.path.join(jail, "cert.pem")
                with open(cert_path, "rb") as src, open(jail_cert, "wb") as dst:
                    dst.write(src.read())
                os.chmod(jail_cert, 0o644)

                for _ in range(payloads_per_cert):
                    length = random.randint(1, 1024)
                    payload = "".join(random.choices(charset, k=length))

                    oracle_proc = subprocess.run(
                        [oracle_bin, cert_path, payload],
                        capture_output=True, text=True, timeout=10,
                    )

                    # Run the clean source build as an unprivileged user in a chroot
                    # containing only the executable and certificate. It therefore
                    # cannot invoke /app/obfuscator_bin or any copied helper program.
                    agent_proc = subprocess.run(
                        ["chroot", "--userspec=65534:65534", jail,
                         "/payload_encoder", "/cert.pem", payload],
                        capture_output=True, text=True, timeout=10,
                    )

                    assert oracle_proc.returncode == agent_proc.returncode, \
                        f"Exit code mismatch. Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode} for payload len {length}"
                    assert oracle_proc.stdout == agent_proc.stdout, \
                        f"Output mismatch for payload: {payload[:20]}... (len {length}).\nOracle: {oracle_proc.stdout}\nAgent: {agent_proc.stdout}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
