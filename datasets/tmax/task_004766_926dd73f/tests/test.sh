#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gc
import importlib.util
import json
import os
import random
import signal
import string
import subprocess
import sys
import time
import tracemalloc
import urllib.error
import urllib.request


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def test_nginx_configuration():
    nginx_conf_path = "/home/user/pipeline/nginx/nginx.conf"
    assert os.path.exists(nginx_conf_path), f"Nginx config not found at {nginx_conf_path}"
    with open(nginx_conf_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "proxy_pass" in content, "proxy_pass directive not found in nginx.conf"
    assert "5000/ingest" in content, "proxy_pass does not seem to route to the correct Flask endpoint (port 5000, path /ingest)"

    result = subprocess.run(
        ["nginx", "-t", "-c", nginx_conf_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Nginx configuration is invalid:\n{result.stdout}"


def test_flask_configuration():
    flask_app_path = "/home/user/pipeline/flask/app.py"
    assert os.path.exists(flask_app_path), f"Flask app not found at {flask_app_path}"
    with open(flask_app_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "127.0.0.1" in content or "localhost" in content, "Redis host not set to 127.0.0.1 or localhost"
    assert "6379" in content, "Redis port not set to 6379"


def generate_fuzz_inputs(n):
    random.seed(42)
    inputs = [
        "2023-10-12T15:30:00Z",
        "2023-10-12T15:30:00+00:00",
        "2023-10-12T15:30:00-05:00",
        "2023-10-12T15:30:00+0530",
        "invalid_date_string",
        "2023-13-12T15:30:00Z",
        "",
    ]
    chars = string.ascii_letters + string.digits + "-:+TZ "
    for _ in range(n - len(inputs)):
        length = random.randint(5, 30)
        inputs.append("".join(random.choices(chars, k=length)))
    return inputs


def test_time_parser_does_not_retain_unbounded_inputs():
    agent_path = "/home/user/pipeline/flask/time_parser.py"
    assert os.path.exists(agent_path), f"Agent time_parser.py not found at {agent_path}"
    agent_mod = load_module("agent_time_parser_memory", agent_path)
    assert hasattr(agent_mod, "parse_and_normalize"), "Agent module missing parse_and_normalize function"

    mutable_types = (dict, list, set)
    before_sizes = {
        name: len(value)
        for name, value in vars(agent_mod).items()
        if isinstance(value, mutable_types)
    }

    # Warm parser/dateutil internals before measuring retained allocations.
    for i in range(100):
        agent_mod.parse_and_normalize(f"2024-01-01T00:{i % 60:02d}:00+00:00")
    gc.collect()
    tracemalloc.start()
    baseline = tracemalloc.take_snapshot()

    for i in range(6000):
        day = (i % 28) + 1
        hour = (i // 28) % 24
        minute = (i // (28 * 24)) % 60
        value = f"2024-02-{day:02d}T{hour:02d}:{minute:02d}:{i % 60:02d}+00:00 tag{i}"
        # The trailing token makes each accepted/rejected input unique. Errors are
        # allowed here; neither successful nor failed inputs may be retained forever.
        try:
            agent_mod.parse_and_normalize(value)
        except ValueError:
            pass

    gc.collect()
    final = tracemalloc.take_snapshot()
    retained = sum(stat.size_diff for stat in final.compare_to(baseline, "filename") if stat.size_diff > 0)
    tracemalloc.stop()

    for name, old_size in before_sizes.items():
        value = vars(agent_mod).get(name)
        if isinstance(value, mutable_types):
            assert len(value) - old_size <= 256, (
                f"Module-level container {name!r} retained {len(value) - old_size} inputs; "
                "parse_and_normalize must not use an unbounded cache"
            )
    assert retained < 500000, f"Parser retained approximately {retained} bytes after unique inputs; possible unbounded cache"


def test_time_parser_fuzz_equivalence():
    agent_path = "/home/user/pipeline/flask/time_parser.py"
    oracle_path = "/app/oracle_time_parser.pyc"

    assert os.path.exists(agent_path), f"Agent time_parser.py not found at {agent_path}"
    assert os.path.exists(oracle_path), f"Oracle oracle_time_parser.pyc not found at {oracle_path}"

    agent_mod = load_module("agent_time_parser", agent_path)
    oracle_mod = load_module("oracle_time_parser", oracle_path)
    assert hasattr(agent_mod, "parse_and_normalize"), "Agent module missing parse_and_normalize function"

    for val in generate_fuzz_inputs(10000):
        oracle_err = None
        oracle_res = None
        try:
            oracle_res = oracle_mod.parse_and_normalize(val)
        except Exception as exc:
            oracle_err = exc

        agent_err = None
        agent_res = None
        try:
            agent_res = agent_mod.parse_and_normalize(val)
        except Exception as exc:
            agent_err = exc

        # Preserve the original behavioral assertions and additionally verify exact
        # exception type and message.
        if oracle_err is not None:
            assert agent_err is not None, f"Oracle raised {type(oracle_err).__name__} for input {val!r}, but agent returned {agent_res!r}"
            assert type(agent_err) is type(oracle_err), f"Wrong exception type for {val!r}"
            assert str(agent_err) == str(oracle_err), f"Wrong exception message for {val!r}"
        else:
            assert agent_err is None, f"Oracle returned {oracle_res!r} for input {val!r}, but agent raised {type(agent_err).__name__}"
            assert agent_res == oracle_res, f"Mismatch for input {val!r}: Oracle returned {oracle_res!r}, Agent returned {agent_res!r}"


def request_json(url, payload):
    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=2) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8")
        try:
            body = json.loads(body)
        except Exception:
            pass
        return exc.code, body


def test_end_to_end_services_via_start_script():
    start_path = "/home/user/pipeline/start.sh"
    assert os.path.isfile(start_path), f"Start script not found at {start_path}"
    assert os.access(start_path, os.X_OK), "start.sh is not executable"

    # Ensure the test exercises the submitted files rather than services the agent
    # may have left running with older configuration.
    subprocess.run(["redis-cli", "shutdown", "nosave"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/home/user/pipeline/flask/app.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.5)

    log = open("/tmp/pipeline-start.log", "w+")
    proc = subprocess.Popen(
        [start_path],
        cwd="/home/user/pipeline",
        stdout=log,
        stderr=subprocess.STDOUT,
        preexec_fn=os.setsid,
    )

    try:
        deadline = time.time() + 20
        last_result = None
        while time.time() < deadline:
            if proc.poll() is not None:
                break
            try:
                last_result = request_json(
                    "http://127.0.0.1:8080/api/ingest",
                    {"time": "2023-10-12T15:30:00+0530"},
                )
                if last_result[0] == 200:
                    break
            except Exception as exc:
                last_result = repr(exc)
            time.sleep(0.25)

        if not (isinstance(last_result, tuple) and last_result[0] == 200):
            log.flush()
            log.seek(0)
            raise AssertionError(f"End-to-end ingest never succeeded; last result={last_result!r}\nService log:\n{log.read()}")

        status, body = last_result
        assert status == 200
        assert body == {"status": "success", "time": "2023-10-12T10:00:00Z"}

        import redis
        client = redis.Redis(host="127.0.0.1", port=6379, db=0, decode_responses=True)
        assert client.ping(), "Redis is not reachable on localhost:6379"
        assert client.get("2023-10-12T10:00:00Z") == "ingested", "Flask did not write the normalized timestamp to Redis"

        bad_status, bad_body = request_json("http://127.0.0.1:8080/api/ingest", {"time": "not-a-time"})
        assert bad_status == 400
        assert bad_body == {"error": "Invalid time format"}
    finally:
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
        subprocess.run(["redis-cli", "shutdown", "nosave"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["pkill", "nginx"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
