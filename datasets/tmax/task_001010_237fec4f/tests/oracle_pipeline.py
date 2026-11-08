#!/usr/bin/env python3
import sys, csv, json, math, subprocess
from collections import defaultdict

def extract_video():
    cmd = ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "packet=pts_time,size,flags", "-of", "csv=p=0", "/app/reference_feed.mp4"]
    out = subprocess.check_output(cmd, text=True).strip().split('\n')
    keyframes = []
    for line in out:
        parts = line.split(',')
        if len(parts) >= 3 and 'K' in parts[2]:
            keyframes.append({"pts": float(parts[0]), "size": int(parts[1])})
    return keyframes

def main():
    if len(sys.argv) < 2: sys.exit(1)

    keyframes = extract_video()

    data = defaultdict(dict)
    sensors = set()
    min_t, max_t = float('inf'), float('-inf')
    with open(sys.argv[1], 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            t = float(row['timestamp'])
            val = float(row['value'])
            sid = row['sensor_id']
            data[t][sid] = val
            sensors.add(sid)
            if t < min_t: min_t = t
            if t > max_t: max_t = t

    if min_t == float('inf'):
        sys.exit(0)

    start_grid = math.floor(min_t)
    end_grid = math.ceil(max_t)

    # create grid
    grid_times = []
    curr = start_grid
    while curr <= end_grid:
        grid_times.append(curr)
        curr += 0.5

    sorted_input_times = sorted(data.keys())

    # ffill and calculate dist
    resampled = {}
    last_vals = {s: 0.0 for s in sensors}

    for gt in grid_times:
        # find the latest timestamp <= gt
        latest_t = None
        for it in sorted_input_times:
            if it <= gt:
                latest_t = it
            else:
                break

        row_vals = []
        if latest_t is not None:
            # apply ffill for missing sensors from all past data
            current_state = {s: 0.0 for s in sensors}
            for it in sorted_input_times:
                if it > gt: break
                for s, v in data[it].items():
                    current_state[s] = v
            row_vals = list(current_state.values())
        else:
            row_vals = [0.0] * len(sensors)

        dist = math.sqrt(sum(v*v for v in row_vals))
        resampled[gt] = dist

    out = []
    for kf in keyframes:
        pts = kf['pts']
        sz = kf['size']
        # round to nearest 0.5
        rounded = round(pts * 2.0) / 2.0

        if rounded in resampled:
            dist = resampled[rounded]
        else:
            dist = -1.0

        sim = abs(dist - sz) / sz
        out.append({
            "pts": pts,
            "rounded_pts": rounded,
            "similarity": round(sim, 4)
        })

    print(json.dumps(out))

if __name__ == "__main__":
    main()
