#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import subprocess
import time
import uuid

import requests

BINARY = "/home/user/helper_tool/payload_eval"
PROJECT = "/home/user/helper_tool"
URL = "http://127.0.0.1:8080/submit"
STATE_DIR = "/tmp/api_state"


def extract_token():
    result = subprocess.run(
        [
            "ffprobe", "-v", "error", "-show_entries", "format_tags=title",
            "-of", "default=noprint_wrappers=1:nokey=1", "/app/system_auth.mp3"
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return result.stdout.strip()


TOKEN = extract_token()
HEADERS = {"Authorization": f"Bearer {TOKEN}"}


def clear_rate_state():
    os.makedirs(STATE_DIR, exist_ok=True)
    os.chmod(STATE_DIR, 0o777)
    for name in os.listdir(STATE_DIR):
        path = os.path.join(STATE_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def post(data, headers=None):
    return requests.post(URL, headers=headers, data=data, timeout=5)


def test_01_payload_eval_is_built_by_cmake_and_works():
    assert TOKEN == "QA-BASH-TOKEN-8832", "The title metadata does not contain the expected authentication token"

    build = subprocess.run(
        ["bash", "-lc", "cmake . && make clean && make"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert build.returncode == 0, f"The helper project does not build with cmake . && make:\n{build.stdout}"
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} does not exist. Did you fix CMakeLists.txt and build?"
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."

    dynamic = subprocess.run(
        ["readelf", "-d", BINARY], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True
    ).stdout
    assert "libm.so" in dynamic, "payload_eval is not dynamically linked to the math library (libm)"

    rng = random.SystemRandom()
    cases = []
    for _ in range(8):
        cases.append((str(rng.randint(0, 100)), False))
        cases.append((str(rng.randint(101, 100000)), True))
    rng.shuffle(cases)
    for payload, should_pass in cases:
        result = subprocess.run([BINARY], input=payload, text=True)
        if should_pass:
            assert result.returncode == 0, f"payload_eval rejected valid randomized payload {payload}"
        else:
            assert result.returncode != 0, f"payload_eval accepted invalid randomized payload {payload}"


def test_02_original_server_assertions():
    clear_rate_state()
    try:
        r1 = post("150")
    except requests.exceptions.RequestException as exc:
        raise AssertionError(f"Failed to connect to the server at {URL}. Is it running? Error: {exc}")
    assert r1.status_code == 401, f"Expected 401 Unauthorized for missing auth, got {r1.status_code}"

    r2 = post("50", HEADERS)
    assert r2.status_code == 400, f"Expected 400 Bad Request for invalid payload, got {r2.status_code}"

    for i in range(3):
        response = post("150", HEADERS)
        assert response.status_code == 200, f"Expected 200 OK on successful request {i + 1}, got {response.status_code}"

    response = post("150", HEADERS)
    assert response.status_code == 429, f"Expected 429 Too Many Requests on 4th rapid request, got {response.status_code}"


def test_03_randomized_authentication_validation_and_rate_window():
    clear_rate_state()
    rng = random.SystemRandom()

    trials = []
    for _ in range(3):
        trials.append((str(rng.randint(101, 100000)), None, 401))
        wrong = "Bearer WRONG-" + uuid.uuid4().hex
        trials.append((str(rng.randint(101, 100000)), {"Authorization": wrong}, 401))
        trials.append((str(rng.randint(0, 100)), HEADERS, 400))
    rng.shuffle(trials)

    for payload, headers, expected in trials:
        response = post(payload, headers)
        assert response.status_code == expected, (
            f"Randomized request with payload {payload!r} expected {expected}, got {response.status_code}"
        )

    valid_payloads = [str(rng.randint(101, 100000)) for _ in range(4)]
    for payload in valid_payloads[:3]:
        response = post(payload, HEADERS)
        assert response.status_code == 200, f"Expected a successful randomized payload, got {response.status_code}"

    response = post(valid_payloads[3], HEADERS)
    assert response.status_code == 429, f"Expected the fourth successful request in the window to be limited, got {response.status_code}"

    time.sleep(10.8)
    response = post(str(rng.randint(101, 100000)), HEADERS)
    assert response.status_code == 200, f"Rate limit did not expire after the 10-second window; got {response.status_code}"


def test_04_server_actually_executes_helper_with_request_body():
    clear_rate_state()
    backup = BINARY + ".verifier-backup"
    control = "/tmp/verifier_helper_exit"
    captured = "/tmp/verifier_helper_input"
    for path in (backup, control, captured):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    os.rename(BINARY, backup)
    try:
        with open(BINARY, "w") as handle:
            handle.write(
                "#!/bin/bash\n"
                "cat > /tmp/verifier_helper_input\n"
                "exit \"$(cat /tmp/verifier_helper_exit)\"\n"
            )
        os.chmod(BINARY, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

        first_body = "probe-" + uuid.uuid4().hex
        with open(control, "w") as handle:
            handle.write("7")
        os.chmod(control, 0o644)
        response = post(first_body, HEADERS)
        assert response.status_code == 400, f"Server ignored a non-zero helper exit status; got {response.status_code}"
        with open(captured, "rb") as handle:
            assert handle.read() == first_body.encode(), "Server did not pass the exact request body to payload_eval on stdin"

        second_body = "forced-valid-" + uuid.uuid4().hex
        with open(control, "w") as handle:
            handle.write("0")
        response = post(second_body, HEADERS)
        assert response.status_code == 200, f"Server ignored a zero helper exit status; got {response.status_code}"
        with open(captured, "rb") as handle:
            assert handle.read() == second_body.encode(), "Server did not pass the exact request body to payload_eval on stdin"
    finally:
        try:
            os.unlink(BINARY)
        except FileNotFoundError:
            pass
        os.rename(backup, BINARY)
        for path in (control, captured):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
