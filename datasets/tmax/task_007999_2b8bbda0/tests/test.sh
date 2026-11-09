#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import subprocess
import time
import urllib.parse
import urllib.request


def test_server_fixed_exists():
    fixed_script = "/home/user/app/server_fixed.py"
    assert os.path.isfile(fixed_script), f"Fixed server script {fixed_script} does not exist."


def test_server_fixed_uses_parameterized_queries():
    fixed_script = "/home/user/app/server_fixed.py"
    assert os.path.isfile(fixed_script), f"Fixed server script {fixed_script} does not exist."

    with open(fixed_script, "r") as f:
        source = f.read()

    tree = ast.parse(source)

    execute_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Attribute) and node.func.attr == "execute":
                execute_calls.append(node)

    assert len(execute_calls) > 0, "No cursor.execute calls found in the fixed script."

    safe_query_found = False
    for call in execute_calls:
        if not call.args:
            continue
        first_arg = call.args[0]

        is_select = False
        if isinstance(first_arg, ast.Constant) and isinstance(first_arg.value, str):
            if "SELECT" in first_arg.value.upper() and "FROM USERS" in first_arg.value.upper():
                is_select = True

        if is_select:
            assert len(call.args) > 1, "The SELECT query in cursor.execute does not use parameterized arguments."
            safe_query_found = True

    if not safe_query_found:
        for call in execute_calls:
            if not call.args:
                continue
            first_arg = call.args[0]
            if isinstance(first_arg, ast.JoinedStr):
                for value in first_arg.values:
                    if isinstance(value, ast.Constant) and isinstance(value.value, str):
                        if "SELECT" in value.value.upper():
                            assert False, "Found an f-string used for a SELECT query in cursor.execute. Use parameterized queries."
            elif isinstance(first_arg, ast.BinOp):
                assert False, "Found string concatenation/formatting used in cursor.execute. Use parameterized queries."

    # Also recognize a parameterized SELECT stored in a variable before execute().
    assigned_strings = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assigned_strings[target.id] = node.value.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            if isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
                assigned_strings[node.target.id] = node.value.value

    if not safe_query_found:
        for call in execute_calls:
            if not call.args or not isinstance(call.args[0], ast.Name):
                continue
            query_text = assigned_strings.get(call.args[0].id, "")
            if "SELECT" in query_text.upper() and "FROM USERS" in query_text.upper():
                assert len(call.args) > 1, "The SELECT query in cursor.execute does not use parameterized arguments."
                safe_query_found = True

    assert safe_query_found, "Could not find a parameterized SELECT query against the users table."


def test_policy_json_exists_and_correct():
    policy_file = "/home/user/policy.json"
    assert os.path.isfile(policy_file), f"Policy file {policy_file} does not exist."

    with open(policy_file, "r") as f:
        try:
            policy_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Policy file {policy_file} is not valid JSON."

    assert "blocked_entities" in policy_data, "Policy JSON is missing the 'blocked_entities' key."

    blocked = policy_data["blocked_entities"]
    assert isinstance(blocked, list), "'blocked_entities' must be a list."

    expected_blocked = [
        {
            "ip": "192.168.1.105",
            "client_id": "malicious_client_99"
        }
    ]

    assert len(blocked) == len(expected_blocked), f"Expected {len(expected_blocked)} blocked entities, found {len(blocked)}."

    blocked_sorted = sorted(blocked, key=lambda x: x.get("ip", ""))
    expected_sorted = sorted(expected_blocked, key=lambda x: x["ip"])

    assert blocked_sorted == expected_sorted, f"Blocked entities do not match expected output. Got {blocked_sorted}, expected {expected_sorted}."


def test_server_fixed_preserves_legitimate_behavior_and_blocks_injection():
    fixed_script = "/home/user/app/server_fixed.py"
    proc = subprocess.Popen(
        ["python3", fixed_script],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        base = "http://localhost:8080/api/users?" 
        for _ in range(40):
            if proc.poll() is not None:
                stderr = proc.stderr.read()
                assert False, f"server_fixed.py exited before serving requests: {stderr}"
            try:
                with urllib.request.urlopen(base + urllib.parse.urlencode({"username": "alice"}), timeout=0.25) as response:
                    legitimate = response.read().decode()
                    legitimate_status = response.status
                break
            except Exception:
                time.sleep(0.1)
        else:
            assert False, "server_fixed.py did not start listening on localhost:8080."

        assert legitimate_status == 200
        assert legitimate == "[(2, 'alice', 'user')]", "Legitimate lookup behavior was changed."

        payload = "admin' OR 1=1 -- "
        with urllib.request.urlopen(base + urllib.parse.urlencode({"username": payload}), timeout=2) as response:
            injected = response.read().decode()
            injected_status = response.status
        assert injected_status == 200
        assert injected == "[]", "The SQL injection payload still changed the query result."
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def test_generate_policy_executes_and_derives_policy_from_logs():
    import datetime
    import jwt
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    script = "/home/user/generate_policy.py"
    log_path = "/home/user/logs/access.log"
    public_path = "/home/user/keys/public.pem"
    policy_path = "/home/user/policy.json"
    assert os.path.isfile(script), f"Policy generator {script} does not exist."

    def snapshot(path):
        if not os.path.exists(path):
            return None
        with open(path, "rb") as f:
            return f.read()

    old_log = snapshot(log_path)
    old_public = snapshot(public_path)
    old_policy = snapshot(policy_path)

    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    public_pem = private_key.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    wrong_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    now = datetime.datetime.now(datetime.timezone.utc)

    client_a = "dynamic_" + secrets.token_hex(8)
    client_b = "dynamic_" + secrets.token_hex(8)
    valid_a = jwt.encode({"client_id": client_a, "exp": now + datetime.timedelta(hours=1)}, private_key, algorithm="RS256")
    valid_b = jwt.encode({"client_id": client_b, "exp": now + datetime.timedelta(hours=1)}, private_key, algorithm="RS256")
    expired = jwt.encode({"client_id": "expired_" + secrets.token_hex(4), "exp": now - datetime.timedelta(hours=1)}, private_key, algorithm="RS256")
    bad_signature = jwt.encode({"client_id": "forged_" + secrets.token_hex(4), "exp": now + datetime.timedelta(hours=1)}, wrong_key, algorithm="RS256")
    normal = jwt.encode({"client_id": "normal_" + secrets.token_hex(4), "exp": now + datetime.timedelta(hours=1)}, private_key, algorithm="RS256")
    failed = jwt.encode({"client_id": "failed_" + secrets.token_hex(4), "exp": now + datetime.timedelta(hours=1)}, private_key, algorithm="RS256")

    ip_a = f"198.51.100.{secrets.randbelow(80) + 10}"
    ip_b = f"10.23.45.{secrets.randbelow(80) + 10}"

    def line(ip, request, status, token):
        return f'{ip} - - [12/Sep/2026:12:00:00 +0000] "GET {request} HTTP/1.1" {status} 42 "Authorization: Bearer {token}"'

    lines = [
        line(ip_a, "/api/users?username=admin' OR 1=1 --", 200, valid_a),
        line(ip_b, "/api/users?username=admin' UNION SELECT * FROM users --", 200, valid_b),
        line("203.0.113.20", "/api/users?username=admin' OR 1=1 --", 200, expired),
        line("203.0.113.21", "/api/users?username=admin' UNION SELECT * FROM users --", 200, bad_signature),
        line("203.0.113.22", "/api/users?username=alice", 200, normal),
        line("203.0.113.23", "/api/users?username=admin' OR 1=1 --", 500, failed),
    ]

    try:
        with open(public_path, "wb") as f:
            f.write(public_pem)
        with open(log_path, "w") as f:
            f.write("\n".join(lines) + "\n")
        if os.path.exists(policy_path):
            os.remove(policy_path)

        result = subprocess.run(
            ["python3", script],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"generate_policy.py failed: {result.stderr}"
        assert os.path.isfile(policy_path), "generate_policy.py did not create /home/user/policy.json."

        with open(policy_path) as f:
            generated = json.load(f)

        expected_entities = sorted(
            [
                {"ip": ip_a, "client_id": client_a},
                {"ip": ip_b, "client_id": client_b},
            ],
            key=lambda item: item["ip"],
        )
        assert set(generated.keys()) == {"blocked_entities"}, "Policy JSON does not have the exact required top-level structure."
        assert generated["blocked_entities"] == expected_entities, (
            f"Generated policy was not derived correctly from the supplied logs and JWTs. "
            f"Got {generated['blocked_entities']}, expected {expected_entities}."
        )
    finally:
        for path, content in ((log_path, old_log), (public_path, old_public), (policy_path, old_policy)):
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
