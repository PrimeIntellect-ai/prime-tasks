#!/bin/bash
set -u
mkdir -p /logs/verifier

# Replace the passive aggregator with a recording server on the same undocumented port.
pids="$(lsof -t -iTCP:8192 -sTCP:LISTEN 2>/dev/null || true)"
if [ -n "$pids" ]; then
    kill $pids 2>/dev/null || true
    sleep 0.5
fi

cat > /tmp/capture_server.py <<'PY'
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

OUT = '/tmp/received_posts.jsonl'

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            length = int(self.headers.get('Content-Length', '0'))
            body = self.rfile.read(length)
            payload = json.loads(body.decode('utf-8'))
            record = {'path': self.path, 'payload': payload}
            with open(OUT, 'a', encoding='utf-8') as f:
                f.write(json.dumps(record) + '\n')
            self.send_response(200)
            self.end_headers()
        except Exception:
            self.send_response(400)
            self.end_headers()

    def do_GET(self):
        self.send_response(200)
        self.end_headers()

    def log_message(self, *args):
        pass

HTTPServer(('127.0.0.1', 8192), Handler).serve_forever()
PY

: > /tmp/received_posts.jsonl
python3 /tmp/capture_server.py >/dev/null 2>&1 &
server_pid=$!
cleanup() {
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 30); do
    if ss -ltn | grep -q ':8192 '; then break; fi
    sleep 0.1
done

cat > /tmp/test_final_state.py <<'PY'
import collections
import json
import os
import re
import shutil
import stat
import subprocess

import cv2
import numpy as np

MONITOR = '/home/user/monitor.py'
WATCHDOG = '/home/user/watchdog.sh'
LOG = '/home/user/alerts.log'
VIDEO = '/app/rack_monitor.mp4'
POSTS = '/tmp/received_posts.jsonl'


def expected_frames(video_path):
    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f'Could not open {video_path}'
    result = []
    index = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        blue, green, red = frame.mean(axis=(0, 1))
        if red > 150 and green < 50 and blue < 50:
            result.append(index)
        index += 1
    cap.release()
    assert index > 0, 'Video contained no readable frames'
    return result


def read_log():
    assert os.path.isfile(LOG), f'Log file {LOG} does not exist.'
    perms = stat.S_IMODE(os.stat(LOG).st_mode)
    assert perms == 0o600, f'Permissions of {LOG} are {oct(perms)}, expected 0o600.'
    with open(LOG, encoding='utf-8') as f:
        lines = [line.rstrip('\n') for line in f]
    frames = []
    for line in lines:
        match = re.fullmatch(r'ALERT: Frame (\d+)', line)
        assert match, f'Invalid alerts.log line: {line!r}'
        frames.append(int(match.group(1)))
    return frames


def assert_f1(expected, predicted):
    truth_frames = set(expected)
    pred_frames = set(predicted)
    tp = len(truth_frames & pred_frames)
    fp = len(pred_frames - truth_frames)
    fn = len(truth_frames - pred_frames)
    if tp == 0:
        score = 0.0
    else:
        precision = tp / (tp + fp)
        recall = tp / (tp + fn)
        score = 2 * precision * recall / (precision + recall)
    assert score >= 0.95, (
        f'F1 Score is {score:.4f}, expected >= 0.95. '
        f'Truth frames: {truth_frames}, Predicted frames: {pred_frames}'
    )


def clear_outputs():
    try:
        os.unlink(LOG)
    except FileNotFoundError:
        pass
    with open(POSTS, 'w', encoding='utf-8'):
        pass


def read_posts():
    records = []
    with open(POSTS, encoding='utf-8') as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))
    for record in records:
        assert record['path'] == '/alert', f'POST used wrong path: {record}'
        assert set(record['payload']) == {'frame'}, f'Wrong JSON payload: {record}'
        assert isinstance(record['payload']['frame'], int), f'Frame must be an integer: {record}'
    return [record['payload']['frame'] for record in records]


def make_challenge_video(path):
    rng = np.random.default_rng()
    selected = sorted(rng.choice(np.arange(8, 129), size=11, replace=False).tolist())
    writer = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*'mp4v'), 30, (64, 64))
    assert writer.isOpened(), 'Could not create challenge video'
    for i in range(137):
        frame = np.zeros((64, 64, 3), dtype=np.uint8)
        if i in selected:
            frame[:, :] = (3, 4, 250)
        elif i % 9 == 0:
            frame[:, :] = (20, 100, 20)
        else:
            frame[:, :] = (10, 10, 10)
        writer.write(frame)
    writer.release()


def run(command, timeout):
    completed = subprocess.run(
        command, cwd='/home/user', stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=timeout
    )
    assert completed.returncode == 0, (
        f'{command} exited {completed.returncode}.\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )


def test_complete_monitoring_system():
    assert os.path.isfile(MONITOR), f'{MONITOR} is missing'
    assert os.path.isfile(WATCHDOG), f'{WATCHDOG} is missing'

    video_backup = '/tmp/rack_monitor.original.mp4'
    monitor_backup = '/tmp/monitor.original.py'
    shutil.copy2(VIDEO, video_backup)
    shutil.copy2(MONITOR, monitor_backup)

    try:
        # Exercise monitor.py against an unseen video so a prewritten log cannot pass.
        make_challenge_video(VIDEO)
        challenge_expected = expected_frames(VIDEO)
        clear_outputs()
        run(['python3', MONITOR], 60)
        challenge_logged = read_log()
        assert challenge_logged == challenge_expected, (
            f'Challenge log frames differ: expected {challenge_expected}, got {challenge_logged}'
        )
        assert_f1(challenge_expected, challenge_logged)
        challenge_posts = read_posts()
        assert collections.Counter(challenge_posts) == collections.Counter(challenge_expected), (
            f'Challenge POST frames differ: expected {challenge_expected}, got {challenge_posts}'
        )

        # Restore the required video and run the submitted watchdog to create final output.
        shutil.copy2(video_backup, VIDEO)
        original_expected = expected_frames(VIDEO)
        clear_outputs()
        run(['bash', WATCHDOG], 90)
        original_logged = read_log()
        assert_f1(original_expected, original_logged)
        assert set(original_logged) == set(original_expected), (
            f'Final log frames differ: expected {original_expected}, got {original_logged}'
        )
        original_posts = read_posts()
        assert set(original_posts) == set(original_expected), (
            f'Final POST frames differ: expected {original_expected}, got {original_posts}'
        )
        counts = collections.Counter(original_posts)
        assert all(counts[frame] >= 1 for frame in original_expected)

        # Independently verify that watchdog retries nonzero exits and stops on success.
        stub = '''import os, sys\np = "/tmp/watchdog_attempts"\ntry:\n    n = int(open(p).read())\nexcept Exception:\n    n = 0\nn += 1\nopen(p, "w").write(str(n))\nsys.exit(0 if n >= 3 else 7)\n'''
        with open(MONITOR, 'w', encoding='utf-8') as f:
            f.write(stub)
        os.chmod(MONITOR, 0o755)
        try:
            os.unlink('/tmp/watchdog_attempts')
        except FileNotFoundError:
            pass
        run(['bash', WATCHDOG], 20)
        with open('/tmp/watchdog_attempts', encoding='utf-8') as f:
            attempts = int(f.read())
        assert attempts == 3, f'Watchdog should retry twice then stop; observed {attempts} runs'
    finally:
        shutil.copy2(video_backup, VIDEO)
        shutil.copy2(monitor_backup, MONITOR)
PY

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
