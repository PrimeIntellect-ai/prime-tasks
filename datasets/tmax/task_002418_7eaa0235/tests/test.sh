#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import stat
import subprocess
import time
import pytest

PIPELINE = "/home/user/run_pipeline.sh"
EVENT_LOG = "/tmp/pipeline-events.jsonl"
TRACE = ""
EVENTS = []


def _make_wrapper(name, target):
    path = os.path.join("/tmp/verify-bin", name)
    with open(path, "w") as f:
        f.write("#!/usr/bin/python3\n")
        f.write("import json, os, sys\n")
        f.write(f"p={target!r}\n")
        f.write(f"with open({EVENT_LOG!r}, 'a') as out:\n")
        f.write("    out.write(json.dumps({'cmd': os.path.basename(sys.argv[0]), 'args': sys.argv[1:], 'cwd': os.getcwd()}) + '\\n')\n")
        f.write("os.execv(p, [p] + sys.argv[1:])\n")
    os.chmod(path, 0o755)


def _load_events():
    if not os.path.exists(EVENT_LOG):
        return []
    result = []
    with open(EVENT_LOG) as f:
        for line in f:
            line = line.strip()
            if line:
                result.append(json.loads(line))
    return result


def _has_trace(pattern):
    return re.search(pattern, TRACE, re.MULTILINE) is not None


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline():
    global TRACE, EVENTS
    assert os.path.isfile(PIPELINE), f"Pipeline script {PIPELINE} does not exist."
    assert os.stat(PIPELINE).st_mode & stat.S_IXUSR, f"Pipeline script {PIPELINE} is not executable."

    os.makedirs("/tmp/verify-bin", exist_ok=True)
    open(EVENT_LOG, "w").close()
    _make_wrapper("docker", "/usr/bin/docker")
    _make_wrapper("curl", "/usr/bin/curl")
    _make_wrapper("python3", "/usr/bin/python3")
    _make_wrapper("python", "/usr/bin/python3")

    subprocess.run(["pkill", "-f", "http.server.*8080"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["docker", "rmi", "-f", "obs-dash:latest"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    for path in ("/home/user/dashboard.html", "/home/user/deploy_status.txt"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["PATH"] = "/tmp/verify-bin:" + env.get("PATH", "")
    started = time.time()
    try:
        result = subprocess.run(
            ["bash", "-x", PIPELINE], env=env, cwd="/home/user",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"run_pipeline.sh did not finish within 120 seconds: {exc}")
    TRACE = result.stderr
    EVENTS = _load_events()
    assert result.returncode == 0, (
        f"run_pipeline.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    for path in ("/home/user/dashboard.html", "/home/user/deploy_status.txt"):
        assert os.path.exists(path), f"Pipeline did not create {path}"
        assert os.path.getmtime(path) >= started - 1, f"{path} was not freshly produced by the pipeline"


def test_pipeline_script_exists_and_executable():
    path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(path), f"Pipeline script {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Pipeline script {path} is not executable."


def test_dockerfile_exists():
    path = "/app/obs-dash-gen/Dockerfile"
    assert os.path.isfile(path), f"Dockerfile {path} does not exist."
    text = open(path).read()
    assert re.search(r"^\s*FROM\s+python(?::|@|\s)", text, re.I | re.M), "Dockerfile must use a standard Python base image."
    assert re.search(r"^\s*COPY\s+", text, re.I | re.M), "Dockerfile must copy the package into the image."
    assert re.search(r"^\s*ENTRYPOINT\s+", text, re.I | re.M), "Dockerfile must define an entrypoint."


def test_pipeline_executed_required_commands():
    docker_events = [e for e in EVENTS if e["cmd"] == "docker"]
    build_events = [e for e in docker_events if "build" in e["args"]]
    build_ok = False
    for event in build_events:
        args = event["args"]
        tagged = ("-t" in args and args.index("-t") + 1 < len(args) and args[args.index("-t") + 1] == "obs-dash:latest")
        tagged = tagged or any(a == "--tag=obs-dash:latest" for a in args)
        if tagged:
            context = args[-1]
            context = os.path.realpath(os.path.join(event["cwd"], context)) if not os.path.isabs(context) else os.path.realpath(context)
            if context == "/app/obs-dash-gen":
                build_ok = True
    build_ok = build_ok or _has_trace(r"docker\s+build[^\n]*(?:-t\s+obs-dash:latest|--tag(?:=|\s+)obs-dash:latest)")
    assert build_ok, "Pipeline did not build obs-dash:latest from /app/obs-dash-gen."

    run_ok = False
    for event in docker_events:
        args = event["args"]
        joined = " ".join(args)
        if "run" in args and "obs-dash:latest" in args and "/system.log" in args:
            if "/home/user/system.log:/system.log" in joined:
                run_ok = True
    run_ok = run_ok or _has_trace(r"docker\s+run[^\n]*/home/user/system\.log:/system\.log[^\n]*obs-dash:latest[^\n]*/system\.log")
    assert run_ok, "Pipeline did not run the image with system.log mounted at /system.log."

    server_ok = any(
        e["cmd"] in ("python", "python3") and e["args"][:2] == ["-m", "http.server"] and "8080" in e["args"]
        for e in EVENTS
    ) or _has_trace(r"python3?\s+-m\s+http\.server[^\n]*8080")
    assert server_ok, "Pipeline did not start Python http.server on port 8080."

    curl_ok = any(
        e["cmd"] == "curl" and "http://localhost:8080/dashboard.html" in e["args"]
        for e in EVENTS
    ) or _has_trace(r"curl[^\n]*http://localhost:8080/dashboard\.html")
    assert curl_ok, "Pipeline did not curl http://localhost:8080/dashboard.html."


def _expected_output(lines):
    pattern = re.compile(r"^(.*)-(.*)-(.*)-(\d+)-(.*)$")
    parsed = []
    for line in lines:
        match = pattern.match(line.strip())
        if match:
            parsed.append(match.groups())
    out = ["<html><body><h1>Dashboard</h1><ul>"]
    out.extend(f"<li>{item}</li>" for item in parsed[:100])
    out.append("</ul></body></html>")
    return "\n".join(out) + "\n"


def test_dashboard_generated():
    path = "/home/user/dashboard.html"
    assert os.path.isfile(path), f"Dashboard file {path} was not generated."
    assert os.path.getsize(path) > 0, f"Dashboard file {path} is empty."
    with open(path, 'r') as f:
        content = f.read()
    assert "html" in content.lower(), f"Dashboard file {path} does not appear to contain HTML."

    first_relevant = []
    pattern = re.compile(r"^(.*)-(.*)-(.*)-(\d+)-(.*)$")
    with open("/home/user/system.log") as f:
        for line in f:
            first_relevant.append(line)
            if sum(pattern.match(x.strip()) is not None for x in first_relevant) >= 100:
                break
    assert content == _expected_output(first_relevant), "dashboard.html does not contain the correctly parsed first 100 log records."


def test_deploy_status():
    path = "/home/user/deploy_status.txt"
    assert os.path.isfile(path), f"Deploy status file {path} does not exist."
    with open(path, 'r') as f:
        content = f.read().strip()
    assert "200" in content, f"Deploy status file {path} does not contain '200'. Content: {content}"
    assert re.search(r"(?:^|\s)200\s*$", content), f"Deploy status does not end with an actual HTTP 200 status code: {content!r}"


def test_docker_image_exists():
    result = subprocess.run(
        ["docker", "images", "-q", "obs-dash:latest"],
        capture_output=True, text=True
    )
    assert result.stdout.strip(), "Docker image 'obs-dash:latest' was not built."

    inspected = subprocess.run(
        ["docker", "image", "inspect", "obs-dash:latest", "--format", "{{json .Config}}"],
        capture_output=True, text=True, check=True
    )
    config = json.loads(inspected.stdout)
    command = (config.get("Entrypoint") or []) + (config.get("Cmd") or [])
    command_text = " ".join(command)
    assert "main.py" in command_text, f"Image entrypoint does not run main.py: {command}"
    assert re.search(r"python", command_text, re.I), f"Image entrypoint does not invoke Python: {command}"


def test_parser_correctness_on_derived_cases(tmp_path):
    lines = [
        "A-B-C-1-D\n",
        "prefix-with-dashes-x-y-42-tail-more\n",
        "--x-000-z\n",
        "INFO-app-module-123-message\n",
        "malformed-line\n",
        "a-a-a-notanumber-tail\n",
        "one-two-three-987654-final\n",
    ]
    source = tmp_path / "cases.log"
    source.write_text("".join(lines))
    result = subprocess.run(
        ["docker", "run", "--rm", "-v", f"{source}:/cases.log:ro", "obs-dash:latest", "/cases.log"],
        capture_output=True, text=True
    )
    assert result.returncode == 0, f"Container failed on correctness cases: {result.stderr}"
    assert result.stdout == _expected_output(lines), "Parser output is incorrect on independently derived valid and malformed cases."


def test_parser_performance():
    # Metric test: measure wall-clock time of running the parser
    # The truth specifies: docker run --rm -v /home/user/system.log:/system.log obs-dash:latest /system.log
    # But since the entrypoint is main.py, we can just run the container and pass the file.
    log_file = "/home/user/system.log"
    assert os.path.isfile(log_file), f"Log file {log_file} does not exist."

    start_time = time.time()
    result = subprocess.run(
        [
            "docker", "run", "--rm",
            "-v", f"{log_file}:/system.log:ro",
            "obs-dash:latest", "/system.log"
        ],
        capture_output=True, text=True
    )
    end_time = time.time()

    assert result.returncode == 0, f"Docker container execution failed with error: {result.stderr}"

    execution_time = end_time - start_time
    threshold = 2.0
    assert execution_time <= threshold, (
        f"Execution time {execution_time:.2f}s exceeded the threshold of {threshold}s. "
        "The parser regex optimization is likely insufficient or incorrect."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
