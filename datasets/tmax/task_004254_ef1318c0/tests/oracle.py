import sys
import csv
import json
import re
import cv2
import math

def run():
    video_path = sys.argv[1]
    users_csv = sys.argv[2]
    events_csv = sys.argv[3]
    output_path = sys.argv[4]

    users = {}
    with open(users_csv, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            users[row['event_id']] = row['username']

    events = {}
    with open(events_csv, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            events[row['event_id']] = row['timestamp_sec']

    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)

    results = []
    for event_id in set(users.keys()).intersection(events.keys()):
        username = users[event_id]
        ts_str = events[event_id]

        if not re.match(r'^[A-Z]{3,4}$', username):
            continue

        try:
            ts = float(ts_str)
        except ValueError:
            continue

        if ts < 0.0 or ts > 10.0:
            continue

        frame_idx = int(ts * fps)
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
        ret, frame = cap.read()
        if not ret:
            continue

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        brightness = math.floor(gray.mean())

        results.append({
            "event_id": event_id,
            "username": username,
            "brightness": brightness
        })

    cap.release()

    results.sort(key=lambda x: x['event_id'])

    with open(output_path, 'w') as f:
        for res in results:
            f.write(json.dumps(res) + "\n")

if __name__ == '__main__':
    run()
