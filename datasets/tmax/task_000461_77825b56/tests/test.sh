#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import itertools
import os
import random
import shutil
import socket
import stat
import subprocess
import tempfile
import time

HOST = "127.0.0.1"
PORT = 8888
SCRIPT = "/home/user/recommend.sh"
CSV = "/home/user/items.csv"
SCORE = "/app/score_calc"


def connect_with_retries(attempts=10):
    last = None
    for _ in range(attempts):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(2.0)
        try:
            s.connect((HOST, PORT))
            return s
        except (ConnectionRefusedError, socket.timeout, OSError) as exc:
            last = exc
            s.close()
            time.sleep(0.5)
    raise AssertionError(f"Could not connect to service at {HOST}:{PORT}: {last}")


def read_line(s):
    data = bytearray()
    while b"\n" not in data:
        chunk = s.recv(1024)
        if not chunk:
            break
        data.extend(chunk)
    return bytes(data).split(b"\n", 1)[0].decode("utf-8").strip()


def request_once(item_id):
    s = connect_with_retries()
    try:
        s.sendall((str(item_id) + "\n").encode())
        return read_line(s)
    finally:
        s.close()


def check_original_service():
    # Preserve the original exact assertion for item 101.
    response = request_once(101)
    assert response == "102,104,103", f"Expected '102,104,103', got {response!r}"

    # Preserve the original multiple-sequential-request assertion, preferring
    # one connection but allowing a reconnect as the original verifier did.
    s = connect_with_retries()
    try:
        s.sendall(b"101\n")
        first = read_line(s)
        assert first == "102,104,103", f"First repeated request got {first!r}"
        try:
            s.sendall(b"101\n")
            second = read_line(s)
        except (BrokenPipeError, ConnectionResetError, socket.timeout, OSError):
            second = ""
    finally:
        s.close()
    if not second:
        second = request_once(101)
    assert second == "102,104,103", f"Second repeated request got {second!r}"


def stop_services():
    subprocess.run(["pkill", "-f", "/home/user/recommend.sh"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-x", "nc"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["pkill", "-x", "socat"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.4)


def score(binary, left, right):
    out = subprocess.check_output([binary, left, right], text=True, timeout=3).strip()
    return float(out)


def main():
    assert os.path.isfile(SCRIPT), f"Missing required script: {SCRIPT}"
    assert os.path.getsize(SCRIPT) > 0, f"Required script is empty: {SCRIPT}"
    with open(SCRIPT, "rb") as f:
        assert b"\x00" not in f.read(), "recommend.sh is not a text shell script"
    subprocess.run(["bash", "-n", SCRIPT], check=True, timeout=5)
    assert os.path.isfile(SCORE) and os.access(SCORE, os.X_OK), "Missing executable /app/score_calc"

    check_original_service()

    csv_backup = tempfile.mktemp(prefix="items-backup-", dir="/tmp")
    score_real = tempfile.mktemp(prefix="score-calc-real-", dir="/tmp")
    call_log = tempfile.mktemp(prefix="score-calls-", dir="/tmp")
    shutil.copy2(CSV, csv_backup)
    shutil.copy2(SCORE, score_real)
    launched = None

    try:
        stop_services()

        rng = random.SystemRandom()
        ids = rng.sample(range(1000, 9000), 7)
        vectors = []
        seen = set()
        while len(vectors) < len(ids):
            values = tuple(round(rng.uniform(-8.0, 12.0), 3) for _ in range(3))
            if values not in seen:
                seen.add(values)
                vectors.append(values)

        vector_strings = [",".join(f"{x:.3f}" for x in vec) for vec in vectors]
        with open(CSV, "w", encoding="utf-8") as f:
            for item_id, vec in zip(ids, vector_strings):
                f.write(f"{item_id},{vec}\n")

        expected = {}
        for i, item_id in enumerate(ids):
            candidates = []
            for j, other_id in enumerate(ids):
                if i == j:
                    continue
                candidates.append((score(score_real, vector_strings[i], vector_strings[j]), other_id))
            candidates.sort(key=lambda pair: pair[0], reverse=True)
            expected[item_id] = ",".join(str(pair[1]) for pair in candidates[:3])

        wrapper = (
            "#!/bin/bash\n"
            + "printf '%s\\t%s\\n' \"$1\" \"$2\" >> " + repr(call_log) + "\n"
            + "exec " + repr(score_real) + " \"$@\"\n"
        )
        with open(SCORE, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(SCORE, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                        stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

        launched = subprocess.Popen(["bash", SCRIPT], stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL, start_new_session=True)

        for item_id in ids:
            actual = request_once(item_id)
            assert actual == expected[item_id], (
                f"For randomized item {item_id}, expected {expected[item_id]!r}, got {actual!r}"
            )

        # Confirm the relaunched artifact remains available for sequential requests.
        repeated = request_once(ids[0])
        assert repeated == expected[ids[0]], "Service did not remain available for another request"

        assert os.path.exists(call_log), "recommend.sh did not invoke /app/score_calc"
        observed_pairs = set()
        with open(call_log, encoding="utf-8", errors="replace") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) != 2:
                    continue
                try:
                    left = tuple(float(x) for x in parts[0].split(","))
                    right = tuple(float(x) for x in parts[1].split(","))
                except ValueError:
                    continue
                observed_pairs.add(frozenset((left, right)))

        required_pairs = {
            frozenset((vectors[i], vectors[j]))
            for i, j in itertools.combinations(range(len(vectors)), 2)
        }
        missing = required_pairs - observed_pairs
        assert not missing, (
            "recommend.sh did not use /app/score_calc for every candidate pair; "
            f"missing {len(missing)} pair(s)"
        )
    finally:
        stop_services()
        if os.path.exists(csv_backup):
            shutil.copy2(csv_backup, CSV)
            os.unlink(csv_backup)
        if os.path.exists(score_real):
            shutil.copy2(score_real, SCORE)
            os.unlink(score_real)
        if os.path.exists(call_log):
            os.unlink(call_log)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
