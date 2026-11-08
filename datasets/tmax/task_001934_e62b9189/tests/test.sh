#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import re
import signal
import subprocess
import time
import unicodedata
from pathlib import Path

import requests
from PIL import Image, ImageDraw, ImageFont

BASE_URL = "http://127.0.0.1:8000/api/v1/record"
AUTH_HEADER = {"Authorization": "Bearer ds_secret_2024"}
EXPECTED_KEYS = {"id", "tokens", "imputed_a", "scaled_b"}


def request_record(record_id, headers=AUTH_HEADER, timeout=5):
    try:
        return requests.get(f"{BASE_URL}/{record_id}", headers=headers, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        raise AssertionError(f"Failed to connect to API or request timed out: {exc}")


def check_record(record_id, expected_tokens, expected_a, expected_b):
    response = request_record(record_id)
    assert response.status_code == 200, (
        f"Expected status code 200 for record {record_id}, got "
        f"{response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        raise AssertionError(
            f"Response for record {record_id} is not valid JSON: {response.text}"
        )

    assert set(data) == EXPECTED_KEYS, f"Unexpected response fields for {record_id}: {data}"
    assert data["id"] == record_id, f"Expected id {record_id}, got {data['id']}"
    assert data["tokens"] == expected_tokens, (
        f"Expected tokens {expected_tokens}, got {data['tokens']}"
    )
    assert isinstance(data["imputed_a"], (int, float)) and not isinstance(data["imputed_a"], bool)
    assert isinstance(data["scaled_b"], (int, float)) and not isinstance(data["scaled_b"], bool)
    assert math.isclose(data["imputed_a"], expected_a, rel_tol=1e-5, abs_tol=1e-5), (
        f"Expected imputed_a {expected_a}, got {data['imputed_a']}"
    )
    assert math.isclose(data["scaled_b"], expected_b, rel_tol=1e-5, abs_tol=1e-5), (
        f"Expected scaled_b {expected_b}, got {data['scaled_b']}"
    )


def listening_pid(port=8000):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local_port = int(fields[1].rsplit(":", 1)[1], 16)
            state = fields[3]
            if local_port == port and state == "0A":
                inodes.add(fields[9])

    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(proc.name)
        except OSError:
            continue
    raise AssertionError("Could not identify the process listening on port 8000")


def process_details(pid):
    raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    argv = [part.decode(errors="surrogateescape") for part in raw.split(b"\0") if part]
    assert argv, "The API listener has an empty command line"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = {}
    for item in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            env[key.decode(errors="ignore")] = value.decode(errors="surrogateescape")
    env.pop("WERKZEUG_RUN_MAIN", None)
    env.pop("WERKZEUG_SERVER_FD", None)
    return argv, cwd, env


def implementation_text(argv, cwd):
    chunks = [" ".join(argv)]
    candidates = []
    for arg in argv:
        if arg.endswith(".py"):
            path = Path(arg)
            candidates.append(path if path.is_absolute() else Path(cwd) / path)
    for root in (Path("/app"), Path("/home/user")):
        if root.exists():
            candidates.extend(root.rglob("*.py"))

    seen = set()
    for path in candidates:
        try:
            resolved = path.resolve()
            if resolved in seen or not resolved.is_file() or resolved.stat().st_size > 1_000_000:
                continue
            seen.add(resolved)
            chunks.append(resolved.read_text(errors="ignore"))
        except OSError:
            pass
    return "\n".join(chunks)


def stop_process(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 5
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def wait_for_server(timeout=15):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(f"{BASE_URL}/0", headers=AUTH_HEADER, timeout=1)
            if response.status_code in (200, 404):
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.25)
    raise AssertionError(f"Restarted API did not become ready: {last_error}")


def normalize_tokens(text):
    normalized = unicodedata.normalize("NFKC", text)
    cleaned = "".join(ch for ch in normalized if ch.isalnum() or ch.isspace())
    return cleaned.lower().split()


def expected_interpolation(rows):
    ordered = sorted(rows, key=lambda row: row["id"])
    values = [row["value_a"] for row in ordered]
    for index, value in enumerate(values):
        if value is not None:
            continue
        left = index - 1
        while left >= 0 and values[left] is None:
            left -= 1
        right = index + 1
        while right < len(values) and values[right] is None:
            right += 1
        assert left >= 0 and right < len(values), "Test data must have interpolation anchors"
        values[index] = values[left] + (values[right] - values[left]) * (index - left) / (right - left)
    return {row["id"]: values[index] for index, row in enumerate(ordered)}


def write_dynamic_inputs(rows, multiplier):
    with open("/app/dirty_corpus.csv", "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["id", "text_entry", "value_a", "value_b"])
        writer.writeheader()
        for row in rows:
            writer.writerow({
                "id": row["id"],
                "text_entry": row["text_entry"],
                "value_a": "" if row["value_a"] is None else row["value_a"],
                "value_b": row["value_b"],
            })

    image = Image.new("RGB", (900, 240), "white")
    draw = ImageDraw.Draw(image)
    font_path = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
    font = ImageFont.truetype(font_path, 58)
    draw.text((30, 75), f"GLOBAL MULTIPLIER: {multiplier:.2f}", fill="black", font=font)
    image.save("/app/reference_key.png")


def main():
    # Preserve the original behavioral assertions and add the previously omitted row.
    check_record(1, ["café", "ñandú", "hola"], 10.0, 6.28)
    check_record(2, ["the", "quick", "brown", "fox"], 20.0, 15.7)
    check_record(3, ["こんにちは世界", "123"], 30.0, 31.4)
    check_record(4, ["ænima", "songtest"], 40.0, 4.71)
    check_record(5, ["русский", "текст"], 50.0, 0.0)

    response = request_record(99)
    assert response.status_code == 404, f"Expected 404 for missing record 99, got {response.status_code}"
    response = request_record(1, {"Authorization": "Bearer wrong_token"})
    assert response.status_code == 401, f"Expected 401 for wrong token, got {response.status_code}"
    response = request_record(1, None)
    assert response.status_code == 401, f"Expected 401 for missing auth, got {response.status_code}"

    pid = listening_pid()
    argv, cwd, env = process_details(pid)
    source = implementation_text(argv, cwd).lower()
    assert "tesseract" in source, "Implementation does not invoke tesseract OCR"
    assert ("multiprocessing" in source or "concurrent.futures" in source), (
        "Implementation does not use multiprocessing or concurrent.futures"
    )
    assert re.search(r"processpoolexecutor|threadpoolexecutor|\.pool\s*\(|\bpool\s*\(", source), (
        "Implementation does not construct a parallel pool/executor"
    )

    nonce = random.SystemRandom().randrange(10000, 90000)
    multiplier = random.SystemRandom().choice([2.75, 4.25, 6.50, 7.25, 8.50])
    rows = [
        {"id": nonce + 47, "text_entry": "Ｆｕｌｌ－Ｗｉｄｔｈ Café!!! ９９", "value_a": 34.0, "value_b": 2.0},
        {"id": nonce + 3, "text_entry": "Русский текст... 😊", "value_a": 10.0, "value_b": -1.5},
        {"id": nonce + 101, "text_entry": "こんにちは 世界—test", "value_a": None, "value_b": 4.0},
        {"id": nonce + 29, "text_entry": "  𝕿𝖍𝖊\tquick_fox ", "value_a": None, "value_b": 0.25},
        {"id": nonce + 211, "text_entry": "mañana + Ελληνικά 42", "value_a": 90.0, "value_b": 0.0},
    ]
    expected_a = expected_interpolation(rows)
    write_dynamic_inputs(rows, multiplier)

    stop_process(pid)
    subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_server()

    for row in rows:
        check_record(
            row["id"],
            normalize_tokens(row["text_entry"]),
            expected_a[row["id"]],
            row["value_b"] * multiplier,
        )

    # Old IDs must disappear, proving the restarted artifact loaded the varied CSV.
    response = request_record(1)
    assert response.status_code == 404, f"Expected old record 1 to disappear, got {response.status_code}"
    response = request_record(nonce + 9999)
    assert response.status_code == 404, f"Expected randomized missing ID to return 404, got {response.status_code}"
    response = request_record(rows[0]["id"], {"Authorization": "Bearer wrong_token"})
    assert response.status_code == 401, f"Expected 401 for wrong token, got {response.status_code}"
    response = request_record(rows[0]["id"], None)
    assert response.status_code == 401, f"Expected 401 for missing auth, got {response.status_code}"


if __name__ == "__main__":
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
