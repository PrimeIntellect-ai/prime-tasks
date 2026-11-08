#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import re
import secrets
import string
import subprocess
import tempfile
import time
import urllib.request
import urllib.error
import pytest

DETECTOR = "/home/user/detector.py"
APP_DIR = "/home/user/app"


def expected_leak(cmdline):
    for i, arg in enumerate(cmdline):
        if re.fullmatch(r"AKIA[A-Z0-9]{16}", arg):
            return True
        if arg.startswith("--password=") or arg.startswith("--secret="):
            return True
        if arg in ("-p", "-s") and i + 1 < len(cmdline):
            value = cmdline[i + 1]
            if value and not value.startswith("-"):
                return True
    return False


def run_detector(records):
    assert os.path.isfile(DETECTOR), f"Detector script not found at {DETECTOR}"
    with tempfile.TemporaryDirectory() as td:
        in_path = os.path.join(td, "input.jsonl")
        out_path = os.path.join(td, "output.jsonl")
        with open(in_path, "w") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")
        result = subprocess.run(
            ["python3", DETECTOR, in_path, out_path],
            check=False, capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(out_path), "Detector did not create the output JSONL file"
        parsed = []
        with open(out_path) as f:
            for line_no, line in enumerate(f, 1):
                assert line.strip(), f"Blank output line {line_no}"
                try:
                    obj = json.loads(line)
                except Exception as exc:
                    pytest.fail(f"Invalid output JSON on line {line_no}: {exc}")
                assert isinstance(obj, dict), f"Output line {line_no} is not an object"
                assert set(obj) == {"id", "leak"}, f"Output line {line_no} must contain exactly id and leak"
                assert isinstance(obj["leak"], bool), f"Output leak on line {line_no} is not boolean"
                parsed.append(obj)
        return parsed


def assert_detector_records(records):
    output = run_detector(records)
    assert len(output) == len(records), f"Expected {len(records)} output records, got {len(output)}"
    assert [x["id"] for x in output] == [x["id"] for x in records], "Output IDs/order do not match input"
    expected = [expected_leak(x["cmdline"]) for x in records]
    assert [x["leak"] for x in output] == expected, f"Incorrect classifications: {output}"


def test_detector_evil_corpus():
    records = []
    evil_dir = "/home/user/corpora/evil"
    for filename in sorted(os.listdir(evil_dir)):
        if filename.endswith(".jsonl"):
            with open(os.path.join(evil_dir, filename)) as f:
                records.extend(json.loads(line) for line in f if line.strip())
    assert records, "Evil corpus is empty"
    assert_detector_records(records)


def test_detector_clean_corpus():
    records = []
    clean_dir = "/home/user/corpora/clean"
    for filename in sorted(os.listdir(clean_dir)):
        if filename.endswith(".jsonl"):
            with open(os.path.join(clean_dir, filename)) as f:
                records.extend(json.loads(line) for line in f if line.strip())
    assert records, "Clean corpus is empty"
    assert_detector_records(records)


def test_detector_adversarial_cases():
    suffix = ''.join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(16))
    token = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(23))
    records = [
        {"id": "r0", "cmdline": ["tool", "AKIA" + suffix]},
        {"id": "r1", "cmdline": ["tool", "xAKIA" + suffix]},
        {"id": "r2", "cmdline": ["tool", "AKIA" + suffix + "X"]},
        {"id": "r3", "cmdline": ["tool", "--password=" + token]},
        {"id": "r4", "cmdline": ["tool", "--secret="]},
        {"id": "r5", "cmdline": ["tool", "--password-file=" + token]},
        {"id": "r6", "cmdline": ["tool", "-p", token]},
        {"id": "r7", "cmdline": ["tool", "-s", "-" + token]},
        {"id": "r8", "cmdline": ["tool", "-p", ""]},
        {"id": "r9", "cmdline": ["tool", token, "-s", token[::-1]]},
        {"id": "r10", "cmdline": ["tool", "-s"]},
        {"id": "r11", "cmdline": ["tool", "--SECRET=" + token]},
    ]
    assert_detector_records(records)


def test_api_code_patched():
    api_path = os.path.join(APP_DIR, "api.py")
    assert os.path.exists(api_path), "api.py not found"
    with open(api_path) as f:
        api_code = f.read()
    assert "0.0.0.0" not in api_code, "api.py still binds to 0.0.0.0"
    assert "127.0.0.1" in api_code, "api.py does not bind to 127.0.0.1"
    assert "env=" in api_code or "os.environ" in api_code, "api.py does not seem to pass environment variables to the worker"


def test_worker_code_patched():
    worker_path = os.path.join(APP_DIR, "worker.py")
    assert os.path.exists(worker_path), "worker.py not found"
    with open(worker_path) as f:
        worker_code = f.read()
    assert "os.environ" in worker_code or "environ.get" in worker_code, "worker.py does not read from environment variables"


def test_worker_reads_secret_token_not_arguments():
    secret = "dyn_" + secrets.token_hex(12)
    result = subprocess.run(
        ["python3", os.path.join(APP_DIR, "worker.py")], cwd=APP_DIR,
        env={**os.environ, "SECRET_TOKEN": secret}, capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == f"Processed_{secret[:4]}***"


def wait_for_url(url, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            urllib.request.urlopen(url, timeout=1)
        except urllib.error.HTTPError:
            return
        except Exception:
            time.sleep(0.2)
        else:
            return
    pytest.fail(f"Service did not become ready at {url}")


def test_end_to_end_flow_and_no_cmdline_secret():
    start_script = os.path.join(APP_DIR, "start.sh")
    assert os.path.exists(start_script), "start.sh not found"
    subprocess.run(["pkill", "-f", "nginx"], check=False)
    subprocess.run(["pkill", "-f", "/home/user/app/api.py"], check=False)
    time.sleep(1)
    subprocess.run(["bash", start_script], check=True, timeout=15)
    try:
        wait_for_url("http://127.0.0.1:8080/")
        for _ in range(2):
            secret = "z" + secrets.token_hex(15)
            req = urllib.request.Request(
                "http://127.0.0.1:8080/process",
                data=json.dumps({"secret": secret}).encode(),
                headers={"Content-Type": "application/json"}, method="POST"
            )
            try:
                with urllib.request.urlopen(req, timeout=10) as response:
                    assert response.status == 200
                    data = json.loads(response.read().decode())
            except urllib.error.URLError as exc:
                pytest.fail(f"Request failed: {exc}")
            assert data.get("worker_output") == f"Processed_{secret[:4]}***", data

        ss_out = subprocess.run(["ss", "-tln"], capture_output=True, text=True, check=True).stdout
        assert "0.0.0.0:5000" not in ss_out
        assert "*:5000" not in ss_out
        assert re.search(r"127\.0\.0\.1:5000\b", ss_out), f"Flask is not bound on loopback: {ss_out}"

        # Observe the API's actual worker invocation while keeping subprocess.run blocked.
        probe = "q" + secrets.token_hex(18)
        marker = os.path.join(APP_DIR, ".worker_probe")
        wrapper_dir = tempfile.mkdtemp()
        wrapper = os.path.join(wrapper_dir, "python3")
        real_python = subprocess.run(["which", "python3"], capture_output=True, text=True, check=True).stdout.strip()
        with open(wrapper, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("if [[ \"$*\" == *worker.py* ]]; then printf '%s\\0' \"$@\" > " + marker + ".args; printf '%s' \"${SECRET_TOKEN-}\" > " + marker + ".env; sleep 2; fi\n")
            f.write("exec " + real_python + " \"$@\"\n")
        os.chmod(wrapper, 0o755)
        subprocess.run(["pkill", "-f", "/home/user/app/api.py"], check=False)
        env = {**os.environ, "PATH": wrapper_dir + os.pathsep + os.environ.get("PATH", "")}
        api = subprocess.Popen([real_python, os.path.join(APP_DIR, "api.py")], cwd=APP_DIR, env=env,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            time.sleep(1)
            req = urllib.request.Request("http://127.0.0.1:8080/process",
                data=json.dumps({"secret": probe}).encode(), headers={"Content-Type": "application/json"}, method="POST")
            with urllib.request.urlopen(req, timeout=10) as response:
                assert response.status == 200
            with open(marker + ".args", "rb") as f:
                argv_blob = f.read()
            with open(marker + ".env") as f:
                env_secret = f.read()
            assert probe.encode() not in argv_blob, "Secret was passed in the worker command line"
            assert env_secret == probe, "SECRET_TOKEN was not passed to the worker environment"
        finally:
            api.terminate()
            try: api.wait(timeout=3)
            except subprocess.TimeoutExpired: api.kill()
            for suffix in (".args", ".env"):
                if os.path.exists(marker + suffix): os.remove(marker + suffix)
    finally:
        subprocess.run(["pkill", "-f", "nginx"], check=False)
        subprocess.run(["pkill", "-f", "/home/user/app/api.py"], check=False)


def test_nginx_configuration():
    conf = os.path.join(APP_DIR, "nginx.conf")
    assert os.path.isfile(conf), "nginx.conf not found"
    check = subprocess.run(["nginx", "-t", "-c", conf], capture_output=True, text=True)
    assert check.returncode == 0, check.stderr
    with open(conf) as f:
        text = f.read()
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:5000\s*;", text), "nginx does not proxy to 127.0.0.1:5000"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
