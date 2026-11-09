#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import datetime
import hashlib
import json
import os
import subprocess
import tempfile

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

SCRIPT = "/home/user/jwt_filter.py"
VIDEO = "/app/dashboard_recording.mp4"
SECRET = "Sup3rS3cr3tHmacK3y2023!"
CSP = "default-src 'self'"


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def make_cert(common_name):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=10))
            .sign(key, hashes.SHA256()))
    der = cert.public_bytes(serialization.Encoding.DER)
    x5c = base64.b64encode(der).decode()
    fp = hashlib.sha256(der).hexdigest().upper()
    return key, cert, x5c, fp


def video_fingerprint():
    with tempfile.TemporaryDirectory() as td:
        pattern = os.path.join(td, "frame_%03d.png")
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", VIDEO,
                        "-vf", "select=between(n\\,145\\,160)", "-vsync", "0", pattern],
                       check=True, timeout=30)
        for name in os.listdir(td):
            proc = subprocess.run(["tesseract", os.path.join(td, name), "stdout"],
                                  text=True, capture_output=True, timeout=15)
            for line in proc.stdout.splitlines():
                if "TRUSTED_FINGERPRINT" in line:
                    value = line.split("TRUSTED_FINGERPRINT", 1)[1].lstrip(" :")
                    normalized = "".join(c for c in value if c in "0123456789abcdefABCDEF").upper()
                    if len(normalized) == 64:
                        return normalized
    raise AssertionError("Could not independently extract trusted fingerprint from video")


def run_token(token, basename):
    # Every invocation uses a fresh, neutrally named directory and file so behavior
    # cannot be keyed to the public corpus labels or stable paths.
    with tempfile.TemporaryDirectory(prefix="jwtcase_") as td:
        path = os.path.join(td, basename)
        with open(path, "w") as f:
            f.write(token)
        return subprocess.run(["python3", SCRIPT, path], capture_output=True, timeout=10).returncode


def assert_case(token, clean, name):
    rc = run_token(token, name)
    assert (rc == 0) == clean, f"case {name}: expected {'clean' if clean else 'evil'}, exit={rc}"


def test_jwt_filter_exists_and_dynamic_behavior():
    assert os.path.isfile(SCRIPT), f"Expected script at {SCRIPT} is missing."
    assert os.path.isfile(VIDEO), f"Expected video at {VIDEO} is missing."

    # Recover the setup-generated trusted certificate from the valid public RS256
    # token, but derive its expected fingerprint independently from the video.
    public_rs = open("/app/verifier/corpus/clean/clean2.txt").read().strip()
    trusted_x5c = jwt.get_unverified_header(public_rs)["x5c"][0]
    trusted_der = base64.b64decode(trusted_x5c)
    trusted_cert = x509.load_der_x509_certificate(trusted_der)
    assert hashlib.sha256(trusted_der).hexdigest().upper() == video_fingerprint()

    # Fresh tokens and randomized paths defeat fixed corpus/path lookup. These
    # cover all specified decisions plus malformed input and header edge cases.
    nonce = b64url(os.urandom(9))
    good_user = {"role": "user", "csp": CSP, "nonce": nonce}
    assert_case(jwt.encode(good_user, SECRET, algorithm="HS256"), True, "a.dat")
    assert_case(jwt.encode({"role": "auditor", "csp": CSP, "nonce": nonce}, SECRET, algorithm="HS256"), True, "b.bin")
    assert_case(jwt.encode({"role": "admin", "csp": CSP, "nonce": nonce}, SECRET, algorithm="HS256"), False, "c.input")
    assert_case(jwt.encode({"role": "user", "nonce": nonce}, SECRET, algorithm="HS256"), False, "d.dat")
    assert_case(jwt.encode({"role": "user", "csp": "default-src *", "nonce": nonce}, SECRET, algorithm="HS256"), False, "e.bin")
    assert_case(jwt.encode(good_user, SECRET + "wrong", algorithm="HS256"), False, "f.input")
    assert_case(jwt.encode(good_user, "", algorithm="none"), False, "g.dat")

    # Reuse the genuinely valid setup token under an unrelated path, while also
    # generating a fresh untrusted certificate/key and corresponding signatures.
    assert_case(public_rs, True, "h.bin")
    bad_key, bad_cert, bad_x5c, _ = make_cert("dynamic-untrusted-" + nonce)
    bad_admin = jwt.encode({"role": "admin", "csp": CSP, "nonce": nonce}, bad_key,
                           algorithm="RS256", headers={"x5c": [bad_x5c]})
    assert_case(bad_admin, False, "i.input")
    bad_user = jwt.encode(good_user, bad_key, algorithm="RS256", headers={"x5c": [bad_x5c]})
    assert_case(bad_user, False, "j.dat")

    # Trusted certificate in x5c but signature made by another key.
    wrong_sig = jwt.encode(good_user, bad_key, algorithm="RS256", headers={"x5c": [trusted_x5c]})
    assert_case(wrong_sig, False, "k.bin")
    # RS256 without required x5c, malformed x5c cardinality, unsupported alg,
    # malformed compact JWT, and unreadable/nonexistent input.
    no_x5c = jwt.encode(good_user, bad_key, algorithm="RS256")
    assert_case(no_x5c, False, "l.input")
    two_x5c = jwt.encode(good_user, bad_key, algorithm="RS256", headers={"x5c": [bad_x5c, bad_x5c]})
    assert_case(two_x5c, False, "m.dat")
    header = b64url(json.dumps({"alg": "HS384", "typ": "JWT"}).encode())
    payload = b64url(json.dumps(good_user).encode())
    assert_case(header + "." + payload + "." + b64url(os.urandom(32)), False, "n.bin")
    assert_case("not.a.jwt", False, "o.input")

    missing = os.path.join(tempfile.gettempdir(), "jwt_missing_" + nonce)
    rc = subprocess.run(["python3", SCRIPT, missing], capture_output=True, timeout=10).returncode
    assert rc == 1, f"missing input must exit 1, got {rc}"


if __name__ == "__main__":
    test_jwt_filter_exists_and_dynamic_behavior()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
