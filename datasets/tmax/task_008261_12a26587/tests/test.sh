#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import subprocess
import tempfile
import secrets
import string


def test_policy_decrypted():
    path = "/home/user/policy.txt"
    assert os.path.isfile(path), f"Missing decrypted policy file at {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "POLICY_STRICT_ENFORCEMENT_992", f"Incorrect decrypted policy content: {content}"


def test_report_json():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"Missing report.json at {report_path}"

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, "report.json is not valid JSON"

    assert "cwe_id" in report, "Missing 'cwe_id' in report.json"
    assert report["cwe_id"] == "CWE-601", f"Incorrect CWE ID: {report['cwe_id']}"

    assert "decrypted_policy" in report, "Missing 'decrypted_policy' in report.json"
    assert report["decrypted_policy"] == "POLICY_STRICT_ENFORCEMENT_992", "Incorrect decrypted_policy in report.json"

    binary_path = "/home/user/auth_server/target/debug/auth_server"
    assert os.path.isfile(binary_path), f"Missing compiled binary at {binary_path}"

    with open(binary_path, "rb") as f:
        binary_hash = hashlib.sha256(f.read()).hexdigest()

    assert "fixed_binary_sha256" in report, "Missing 'fixed_binary_sha256' in report.json"
    assert report["fixed_binary_sha256"] == binary_hash, "Incorrect fixed_binary_sha256 in report.json"


def test_rust_logic_fixed():
    main_rs_path = "/home/user/auth_server/src/main.rs"
    assert os.path.isfile(main_rs_path), f"Missing main.rs at {main_rs_path}"

    with open(main_rs_path, "r") as f:
        original_code = f.read()

    # Preserve the original fixed checks and add unpredictable cases so the
    # implementation must enforce the redirect rule rather than special-case
    # a known list of inputs.
    cases = {
        "/profile",
        "//evil.com",
        "http://evil.com",
        "evil.com",
        "",
        "/",
        "///triple",
        "/safe/nested/path",
        "ftp://example.test",
        "\\\\example.test\\share",
    }
    alphabet = string.ascii_letters + string.digits + "-._~/?#:@!$&'()*+,;=%"
    non_slash_start = string.ascii_letters + string.digits + "-._~:?#@\\\\ "

    for _ in range(150):
        length = secrets.randbelow(80)
        suffix = "".join(secrets.choice(alphabet) for _ in range(length))
        cases.add("/" + suffix)

        length = secrets.randbelow(80)
        suffix = "".join(secrets.choice(alphabet) for _ in range(length))
        cases.add("//" + suffix)

        length = secrets.randbelow(79)
        invalid = secrets.choice(non_slash_start) + "".join(
            secrets.choice(alphabet) for _ in range(length)
        )
        cases.add(invalid)

    generated_assertions = []
    for value in cases:
        expected = value if value.startswith("/") and not value.startswith("//") else "/dashboard"
        generated_assertions.append(
            f"assert_eq!(get_redirect_url({json.dumps(value)}), {json.dumps(expected)});"
        )

    module_name = "verifier_tests_" + secrets.token_hex(8)
    test_code = original_code + f"""

#[cfg(test)]
mod {module_name} {{
    use super::*;

    #[test]
    fn test_redirect_logic() {{
        assert_eq!(get_redirect_url("/profile"), "/profile");
        assert_eq!(get_redirect_url("//evil.com"), "/dashboard");
        assert_eq!(get_redirect_url("http://evil.com"), "/dashboard");
        assert_eq!(get_redirect_url("evil.com"), "/dashboard");
        {''.join(generated_assertions)}
    }}
}}
"""

    with tempfile.NamedTemporaryFile(mode="w", suffix=".rs", delete=False) as tmp:
        tmp.write(test_code)
        tmp_path = tmp.name

    try:
        compile_proc = subprocess.run(
            ["rustc", "--test", tmp_path, "-o", tmp_path + "_test"],
            capture_output=True,
            text=True,
        )
        assert compile_proc.returncode == 0, f"Failed to compile test code:\n{compile_proc.stderr}"

        test_proc = subprocess.run(
            [tmp_path + "_test"], capture_output=True, text=True
        )
        assert test_proc.returncode == 0, (
            f"Vulnerability fix logic failed tests:\n{test_proc.stdout}\n{test_proc.stderr}"
        )
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
        if os.path.exists(tmp_path + "_test"):
            os.remove(tmp_path + "_test")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
