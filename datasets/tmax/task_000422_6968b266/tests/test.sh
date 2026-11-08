#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tempfile
import urllib.request


def test_environment_variables():
    profile_path = "/home/user/.bash_profile"
    assert os.path.isfile(profile_path), f"{profile_path} does not exist."
    with open(profile_path, "r") as f:
        content = f.read()
    assert "BACKEND1_PORT=9001" in content or "BACKEND1_PORT=\"9001\"" in content or "BACKEND1_PORT='9001'" in content, "BACKEND1_PORT=9001 not found in .bash_profile"
    assert "BACKEND2_PORT=9002" in content or "BACKEND2_PORT=\"9002\"" in content or "BACKEND2_PORT='9002'" in content, "BACKEND2_PORT=9002 not found in .bash_profile"

    # Verify that sourcing the profile actually exports the requested values to
    # child processes rather than merely containing matching text.
    command = (
        "source /home/user/.bash_profile >/dev/null 2>&1; "
        "python3 -c 'import os; print(os.environ.get(\"BACKEND1_PORT\", \"\") + \"|\" + os.environ.get(\"BACKEND2_PORT\", \"\"))'"
    )
    env = os.environ.copy()
    env.update({"HOME": "/home/user", "USER": "user", "LOGNAME": "user"})
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "bash", "--noprofile", "--norc", "-c", command],
        capture_output=True,
        text=True,
        timeout=10,
        env=env,
    )
    assert result.returncode == 0, f"Could not source user profile: {result.stderr}"
    assert result.stdout.strip() == "9001|9002", f"Profile did not export the required ports: {result.stdout!r}"


def fetch(url):
    req = urllib.request.Request(url, headers={"Connection": "close"})
    with urllib.request.urlopen(req, timeout=2) as response:
        return response.read().decode("utf-8").strip()


def test_proxy_and_load_balancing():
    proxy_source = "/home/user/proxy.go"
    proxy_bin = "/home/user/proxy"
    assert os.path.isfile(proxy_source), f"Proxy source {proxy_source} not found."
    assert os.path.isfile(proxy_bin), f"Proxy binary {proxy_bin} not found."
    assert os.access(proxy_bin, os.X_OK), f"Proxy binary {proxy_bin} is not executable."

    with tempfile.TemporaryDirectory() as build_dir:
        built_proxy = os.path.join(build_dir, "proxy")
        build = subprocess.run(
            ["go", "build", "-o", built_proxy, proxy_source],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"proxy.go does not compile: {build.stderr}"

    # The shipped backend directories are intentionally otherwise identical.
    # Add unpredictable, temporary marker files so a real proxy can be tested
    # without requiring the agent to alter backend content.
    token = secrets.token_hex(16)
    marker_name = f".verifier_backend_{token}.txt"
    marker1 = f"backend1-{secrets.token_hex(16)}"
    marker2 = f"backend2-{secrets.token_hex(16)}"
    path1 = os.path.join("/app/backend1", marker_name)
    path2 = os.path.join("/app/backend2", marker_name)
    with open(path1, "w") as f:
        f.write(marker1)
    with open(path2, "w") as f:
        f.write(marker2)

    try:
        assert fetch(f"http://127.0.0.1:9001/{marker_name}") == marker1, "Backend 1 is not reachable on port 9001"
        assert fetch(f"http://127.0.0.1:9002/{marker_name}") == marker2, "Backend 2 is not reachable on port 9002"

        responses = []
        proxy_url = f"http://127.0.0.1:8080/{marker_name}"
        for _ in range(10):
            try:
                responses.append(fetch(proxy_url))
            except Exception as e:
                assert False, f"Request to proxy failed: {e}"

        counts = {}
        for response in responses:
            counts[response] = counts.get(response, 0) + 1

        assert set(counts) == {marker1, marker2}, f"Expected responses from exactly the two backends, got: {counts}"
        for key, value in counts.items():
            assert value == 5, f"Expected 5 requests per backend, got {value} for backend response {key}"
        assert all(responses[i] != responses[i + 1] for i in range(9)), f"Responses were not round-robin: {responses}"
    finally:
        for path in (path1, path2):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def run_filter(binary, path):
    return subprocess.run([binary, path], capture_output=True, timeout=5).returncode


def test_adversarial_filter():
    filter_source = "/home/user/filter.go"
    filter_bin = "/home/user/filter"
    assert os.path.isfile(filter_source), f"Filter source {filter_source} not found."
    assert os.path.isfile(filter_bin), f"Filter binary {filter_bin} not found."
    assert os.access(filter_bin, os.X_OK), f"Filter binary {filter_bin} is not executable."

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    for clean_file in clean_files:
        if run_filter(filter_bin, clean_file) != 0:
            clean_failed.append(os.path.basename(clean_file))

    evil_failed = []
    for evil_file in evil_files:
        if run_filter(filter_bin, evil_file) != 1:
            evil_failed.append(os.path.basename(evil_file))

    assert len(clean_failed) == 0, f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {clean_failed}"
    assert len(evil_failed) == 0, f"{len(evil_failed)} of {len(evil_files)} evil bypassed (accepted): {evil_failed}"

    with tempfile.TemporaryDirectory() as temp_dir:
        rebuilt_filter = os.path.join(temp_dir, "filter")
        build = subprocess.run(
            ["go", "build", "-o", rebuilt_filter, filter_source],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"filter.go does not compile: {build.stderr}"

        cases = {}
        cases["random_clean.json"] = (json.dumps({"nonce": secrets.token_hex(64), "items": [1, True, None]}).encode(), 0)
        cases["exact_limit.json"] = (b'{"x":"' + b'A' * (10240 - len(b'{"x":""}')) + b'"}', 0)
        cases["over_limit.json"] = (b'{"x":"' + b'B' * (10241 - len(b'{"x":""}')) + b'"}', 1)
        cases["forward_traversal.json"] = (json.dumps({"nonce": secrets.token_hex(8), "path": "../private"}).encode(), 1)
        cases["backward_traversal.json"] = (json.dumps({"nonce": secrets.token_hex(8), "path": r"..\windows\system32"}).encode(), 1)
        cases["malformed.json"] = (b'{"nonce":' + secrets.token_hex(12).encode(), 1)

        paths = {}
        for name, (payload, expected) in cases.items():
            path = os.path.join(temp_dir, name)
            with open(path, "wb") as f:
                f.write(payload)
            paths[name] = (path, expected)

        for binary in (filter_bin, rebuilt_filter):
            for name, (path, expected) in paths.items():
                actual = run_filter(binary, path)
                assert actual == expected, f"{binary} returned {actual} for dynamic case {name}; expected {expected}"

            no_args = subprocess.run([binary], capture_output=True, timeout=5)
            assert no_args.returncode != 0, f"{binary} accepted an invocation with no file argument"
            two_args = subprocess.run(
                [binary, paths["random_clean.json"][0], paths["exact_limit.json"][0]],
                capture_output=True,
                timeout=5,
            )
            assert two_args.returncode != 0, f"{binary} accepted an invocation with more than one argument"


def test_storage_monitoring():
    monitor_script = "/home/user/monitor.sh"
    assert os.path.isfile(monitor_script), f"Monitor script {monitor_script} not found."
    assert os.access(monitor_script, os.X_OK), f"Monitor script {monitor_script} is not executable."

    logs_dir = "/home/user/logs"
    os.makedirs(logs_dir, exist_ok=True)

    for entry in os.listdir(logs_dir):
        path = os.path.join(logs_dir, entry)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.remove(path)

    res = subprocess.run([monitor_script], capture_output=True, text=True)
    assert res.stdout.strip() == "OK", f"Expected 'OK' when size is small, got '{res.stdout.strip()}'"

    big_file = os.path.join(logs_dir, "big_file.log")
    with open(big_file, "wb") as f:
        f.write(b"0" * 60000)

    try:
        res = subprocess.run([monitor_script], capture_output=True, text=True)
        assert res.stdout.strip() == "WARNING: QUOTA EXCEEDED", f"Expected 'WARNING: QUOTA EXCEEDED', got '{res.stdout.strip()}'"
    finally:
        os.remove(big_file)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
