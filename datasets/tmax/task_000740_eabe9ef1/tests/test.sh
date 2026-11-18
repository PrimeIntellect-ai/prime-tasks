#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import http.server
import json
import os
import re
import secrets
import subprocess
import tempfile
import threading
import time
import urllib.parse
import urllib.request


def run_pipeline(input_csv, output_csv):
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"Script not found at {script_path}. The data processing script must be created."

    result = subprocess.run(
        ["bash", script_path, input_csv, output_csv],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Script execution failed on {input_csv}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    assert os.path.isfile(output_csv), f"Script did not create the expected output file: {output_csv}"


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=5) as response:
        assert response.status == 200
        return json.loads(response.read().decode("utf-8"))


def test_00_services_and_configuration():
    with open("/app/api/.env", "r") as f:
        env_text = f.read()
    values = {}
    for line in env_text.splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip("'\"")
    assert values.get("REDIS_PORT") == "6379", "/app/api/.env must configure Redis port 6379"

    with open("/etc/nginx/conf.d/api.conf", "r") as f:
        nginx_text = f.read()
    assert re.search(r"\blisten\s+8080\s*;", nginx_text), "Nginx must listen on port 8080"
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:5000\s*;", nginx_text), "Nginx must proxy /score to the Flask API on port 5000"

    nginx_check = subprocess.run(["nginx", "-t"], capture_output=True, text=True)
    assert nginx_check.returncode == 0, f"Invalid Nginx configuration:\n{nginx_check.stdout}\n{nginx_check.stderr}"

    redis_ping = subprocess.run(["redis-cli", "-h", "127.0.0.1", "-p", "6379", "ping"], capture_output=True, text=True)
    assert redis_ping.returncode == 0 and redis_ping.stdout.strip() == "PONG", "Redis is not running on port 6379"

    direct_clean = fetch_json("http://127.0.0.1:5000/score?cluster=c_44&text=ordinary%20sample")
    direct_evil = fetch_json("http://127.0.0.1:5000/score?cluster=c_99&text=contains%20poison")
    assert direct_clean == {"status": "clean"}
    assert direct_evil == {"status": "evil"}

    proxied_clean = fetch_json("http://127.0.0.1:8080/score?cluster=c_44&text=ordinary%20sample")
    proxied_evil = fetch_json("http://127.0.0.1:8080/score?cluster=c_99&text=contains%20a%20leak")
    assert proxied_clean == {"status": "clean"}
    assert proxied_evil == {"status": "evil"}

    assert read_nonempty_lines("/app/data/embeddings.csv") == [
        "id,cluster_id",
        "101,c_44",
        "102,c_99",
        "103,c_10",
        "104,c_11",
    ]


def test_pipeline_evil_corpus():
    evil_dir = "/app/corpus/evil/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.csv')]
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []

    for f in evil_files:
        input_csv = os.path.join(evil_dir, f)
        with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
            output_csv = tmp.name

        try:
            run_pipeline(input_csv, output_csv)
            with open(output_csv, 'r') as out_f:
                lines = [line.strip() for line in out_f.readlines() if line.strip()]

            if lines != ["id,text_data"]:
                failed_files.append(f)
        finally:
            if os.path.exists(output_csv):
                os.remove(output_csv)

    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil bypassed (failed to drop all malicious rows): {', '.join(failed_files)}"


def test_pipeline_clean_corpus():
    clean_dir = "/app/corpus/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.csv')]
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []

    for f in clean_files:
        input_csv = os.path.join(clean_dir, f)
        with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
            output_csv = tmp.name

        try:
            run_pipeline(input_csv, output_csv)
            with open(input_csv, 'r') as in_f:
                expected_lines = [line.strip() for line in in_f.readlines() if line.strip()]
            with open(output_csv, 'r') as out_f:
                actual_lines = [line.strip() for line in out_f.readlines() if line.strip()]

            if actual_lines != expected_lines:
                failed_files.append(f)
        finally:
            if os.path.exists(output_csv):
                os.remove(output_csv)

    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified (failed to perfectly preserve clean data): {', '.join(failed_files)}"


def test_pipeline_dynamic_join_queries_and_url_encoding():
    token = secrets.token_urlsafe(12)
    rows = [
        ("101", f"safe & plus+hash# {token}"),
        ("102", f"prefix &x=1 # poison {token}"),
        ("103", f"LEAK {token} % + & ="),
        ("104", f"another safe value {token}"),
    ]
    clusters = {"101": "c_44", "102": "c_99", "103": "c_10", "104": "c_11"}
    expected_requests = collections.Counter((clusters[row_id], text) for row_id, text in rows)
    received = []
    received_lock = threading.Lock()

    class TrackingHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urllib.parse.urlsplit(self.path)
            if parsed.path != "/score":
                self.send_response(404)
                self.end_headers()
                return
            params = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
            cluster = params.get("cluster", [""])[0]
            text = params.get("text", [""])[0]
            with received_lock:
                received.append((cluster, text))
            status = "evil" if "leak" in text.lower() or "poison" in text.lower() else "clean"
            body = json.dumps({"status": status}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, fmt, *args):
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), TrackingHandler)
    tracker_port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    nginx_path = "/etc/nginx/conf.d/api.conf"
    with open(nginx_path, "r") as f:
        original_nginx = f.read()

    with tempfile.TemporaryDirectory(prefix="pipeline-verifier-") as workdir:
        input_csv = os.path.join(workdir, "random-input.csv")
        output_csv = os.path.join(workdir, "random-output.csv")
        with open(input_csv, "w") as f:
            f.write("id,text_data\n")
            for row_id, text in rows:
                f.write(f"{row_id},{text}\n")

        try:
            with open(nginx_path, "w") as f:
                f.write(f"""server {{
    listen 8080;
    location /score {{
        proxy_pass http://127.0.0.1:{tracker_port};
    }}
}}
""")
            reload_result = subprocess.run(["nginx", "-s", "reload"], capture_output=True, text=True)
            assert reload_result.returncode == 0, f"Could not reload Nginx for pipeline exercise: {reload_result.stderr}"
            time.sleep(0.5)

            run_pipeline(input_csv, output_csv)

            expected_output = [
                "id,text_data",
                f"101,{rows[0][1]}",
                f"104,{rows[3][1]}",
            ]
            assert read_nonempty_lines(output_csv) == expected_output, "Pipeline did not preserve exactly the dynamically scored clean rows"
            with received_lock:
                actual_requests = collections.Counter(received)
            assert actual_requests == expected_requests, (
                "Pipeline must query /score once for every joined row with the exact cluster and URL-decoded text; "
                f"expected {expected_requests}, received {actual_requests}"
            )
        finally:
            with open(nginx_path, "w") as f:
                f.write(original_nginx)
            subprocess.run(["nginx", "-s", "reload"], capture_output=True, text=True)
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
