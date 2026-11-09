#!/bin/bash
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import collections
import hashlib
import math
import os
import re
import secrets
import shutil
import signal
import socket
import subprocess
import time

HOST, PORT = "127.0.0.1", 9090
TRAIN = "/home/user/train.sh"
SERVE = "/home/user/serve.sh"
MODEL = "/home/user/model.txt"
DATASET = "/home/user/dataset/logs.txt"
ORACLE = "/app/log_oracle"


def send_request(host, port, message):
    try:
        with socket.create_connection((host, port), timeout=5) as s:
            s.sendall(message.encode("utf-8"))
            return s.recv(1024).decode("utf-8")
    except Exception as e:
        return str(e)


def test_files_exist():
    assert os.path.exists(TRAIN), "/home/user/train.sh does not exist"
    assert os.path.exists(SERVE), "/home/user/serve.sh does not exist"
    assert os.path.exists(MODEL), "/home/user/model.txt does not exist"


def test_auth_failure():
    message = "AUTH:wrong|LOG:login failed admin\n"
    response = send_request(HOST, PORT, message)
    assert response == "ERROR: UNAUTHORIZED\n", f"Expected 'ERROR: UNAUTHORIZED\\n', got {response!r}"


def test_inference_benign_calculation():
    message = "AUTH:sysresearch_2024|LOG:session opened user\n"
    response = send_request(HOST, PORT, message)
    expected = "RESULT:0.1937\n"
    assert response == expected, f"Expected {expected!r}, got {response!r}"


def assert_bash_artifact(path):
    assert os.path.isfile(path), f"{path} is not a regular file"
    assert os.path.getsize(path) > 0, f"{path} is empty"
    checked = subprocess.run(["/bin/bash", "-n", path], capture_output=True, text=True)
    assert checked.returncode == 0, f"{path} is not valid Bash: {checked.stderr}"
    text = open(path, "r", encoding="utf-8", errors="replace").read()
    code = "\n".join(line.split("#", 1)[0] for line in text.splitlines())
    forbidden = re.compile(r"(^|[\s;/|&])(?:/usr/bin/|/usr/local/bin/)?(?:python(?:[0-9.]*)?|perl|ruby|node)(?=\s|$)", re.I)
    assert not forbidden.search(code), f"{path} invokes a forbidden scripting language"


def listening_inodes():
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        try:
                            port = int(fields[1].rsplit(":", 1)[1], 16)
                        except ValueError:
                            continue
                        if port == PORT:
                            result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def stop_existing_service():
    me = os.getpid()
    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            cmd = open(f"/proc/{entry}/cmdline", "rb").read().replace(b"\0", b" ")
            if SERVE.encode() in cmd:
                victims.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass

    inodes = listening_inodes()
    if inodes:
        for entry in os.listdir("/proc"):
            if not entry.isdigit() or int(entry) == me:
                continue
            fd_dir = f"/proc/{entry}/fd"
            try:
                for fd in os.listdir(fd_dir):
                    try:
                        target = os.readlink(os.path.join(fd_dir, fd))
                    except OSError:
                        continue
                    if target.startswith("socket:[") and target[8:-1] in inodes:
                        victims.add(int(entry))
                        break
            except (FileNotFoundError, PermissionError, ProcessLookupError):
                pass

    for sig in (signal.SIGTERM, signal.SIGKILL):
        for pid in list(victims):
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.3)


def wait_for_service(proc, timeout=10):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            with socket.create_connection((HOST, PORT), timeout=0.3):
                return
        except OSError as e:
            last_error = e
            if proc.poll() not in (None, 0):
                break
            time.sleep(0.1)
    raise AssertionError(f"serve.sh did not start a TCP listener on {HOST}:{PORT}: {last_error}")


def oracle_label(binary, line):
    result = subprocess.run([binary, line], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, f"oracle failed for {line!r}"
    label = result.stdout.strip()
    assert label in ("MALICIOUS", "BENIGN"), f"bad oracle label {label!r}"
    return label


def expected_probability(lines, query, oracle_binary):
    docs = {"MALICIOUS": 0, "BENIGN": 0}
    counts = {"MALICIOUS": collections.Counter(), "BENIGN": collections.Counter()}
    totals = {"MALICIOUS": 0, "BENIGN": 0}
    vocab = set()

    for line in lines:
        label = oracle_label(oracle_binary, line)
        words = line.split()
        docs[label] += 1
        counts[label].update(words)
        totals[label] += len(words)
        vocab.update(words)

    total_docs = sum(docs.values())
    assert docs["MALICIOUS"] and docs["BENIGN"]
    scores = {}
    for label in ("MALICIOUS", "BENIGN"):
        score = math.log(docs[label] / total_docs)
        denominator = totals[label] + len(vocab)
        for word in query.split():
            score += math.log((counts[label][word] + 1) / denominator)
        scores[label] = score

    peak = max(scores.values())
    malicious = math.exp(scores["MALICIOUS"] - peak)
    benign = math.exp(scores["BENIGN"] - peak)
    return malicious / (malicious + benign)


def dynamic_training_and_inference_test():
    assert_bash_artifact(TRAIN)
    assert_bash_artifact(SERVE)
    assert os.path.isfile(MODEL), f"{MODEL} is not a regular file"

    suffix = secrets.token_hex(8)
    words = {name: name + suffix for name in (
        "ma", "mb", "mc", "md", "me", "mf", "mg", "mh", "mi", "mj", "mk", "ml",
        "ba", "bb", "bc", "bd", "be", "bf", "bg", "bh", "common"
    )}
    lines = [
        f"failed {words['ma']} {words['mb']}",
        f"invalid {words['mc']} {words['common']} {words['md']}",
        f"error {words['me']} {words['mf']} {words['mg']} {words['common']}",
        f"failed {words['mh']} {words['mi']} {words['mj']} {words['mk']} {words['ml']}",
        f"login {words['ba']} {words['common']}",
        f"session {words['bb']} {words['bc']} {words['bd']}",
        f"success {words['be']} {words['bf']} {words['common']} {words['bg']} {words['bh']}",
    ]
    queries = [
        f"{words['common']} {words['ba']} {words['ma']}",
        f"{words['mc']} {words['md']} {words['bf']}",
        f"{words['mh']} {words['mi']} login {words['common']}",
        f"{words['be']} {words['bg']} {words['bh']}",
        f"failed {words['bb']} {words['mf']} {words['common']}",
    ]

    with open(DATASET, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    backup = f"/tmp/log_oracle.{secrets.token_hex(8)}"
    call_log = f"/tmp/oracle_calls.{secrets.token_hex(8)}"
    os.replace(ORACLE, backup)
    wrapper = f'''#!/bin/bash
printf '%s\\n' "$1" >> {call_log!r}
exec {backup!r} "$@"
'''
    with open(ORACLE, "w", encoding="utf-8") as f:
        f.write(wrapper)
    os.chmod(ORACLE, 0o755)

    before_hash = hashlib.sha256(open(MODEL, "rb").read()).digest()
    try:
        trained = subprocess.run(["/bin/bash", TRAIN], cwd="/home/user", capture_output=True, text=True, timeout=30)
        assert trained.returncode == 0, f"train.sh failed:\nstdout={trained.stdout}\nstderr={trained.stderr}"
    finally:
        try:
            os.unlink(ORACLE)
        except FileNotFoundError:
            pass
        os.replace(backup, ORACLE)

    assert os.path.isfile(MODEL), "train.sh did not create a regular model.txt"
    assert os.path.getsize(MODEL) > 0, "train.sh created an empty model.txt"
    after_hash = hashlib.sha256(open(MODEL, "rb").read()).digest()
    assert after_hash != before_hash, "train.sh did not update the model for the changed dataset"

    try:
        calls = open(call_log, "r", encoding="utf-8").read().splitlines()
    except FileNotFoundError:
        calls = []
    finally:
        try:
            os.unlink(call_log)
        except FileNotFoundError:
            pass
    call_counts = collections.Counter(calls)
    for line in lines:
        assert call_counts[line] >= 1, f"train.sh did not label dataset line with /app/log_oracle: {line!r}"

    stop_existing_service()
    log = open("/tmp/serve-verifier.log", "wb")
    proc = subprocess.Popen(["/bin/bash", SERVE], cwd="/home/user", stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        wait_for_service(proc)

        bad_token = "wrong" + secrets.token_hex(6)
        response = send_request(HOST, PORT, f"AUTH:{bad_token}|LOG:{queries[0]}\n")
        assert response == "ERROR: UNAUTHORIZED\n", f"random unauthorized request returned {response!r}"

        for query in queries:
            probability = expected_probability(lines, query, ORACLE)
            expected = f"RESULT:{probability:.4f}\n"
            response = send_request(HOST, PORT, f"AUTH:sysresearch_2024|LOG:{query}\n")
            assert response == expected, f"For dynamic query {query!r}, expected {expected!r}, got {response!r}"
    finally:
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        log.close()
        stop_existing_service()


def main():
    # Preserve the original fixed assertions against the initially running service.
    test_files_exist()
    test_auth_failure()
    test_inference_benign_calculation()
    # Then execute training on a runtime-generated corpus and exercise fresh inference.
    dynamic_training_and_inference_test()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
