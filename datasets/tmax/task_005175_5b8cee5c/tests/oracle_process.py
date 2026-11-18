import sys
import re
import json

def process():
    text = sys.stdin.read()
    pattern = r'\[DATA\] (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z) v=(-?\d+)'
    matches = re.findall(pattern, text)

    data = []
    for t, v in matches:
        data.append((t, int(v)))

    data.sort(key=lambda x: x[0])

    W = 5
    result = []
    for i in range(len(data)):
        start = max(0, i - W + 1)
        window = [x[1] for x in data[start:i+1]]
        avg = sum(window) / len(window)
        result.append({"t": data[i][0], "v_smooth": round(avg, 1)})

    print(json.dumps(result))

if __name__ == "__main__":
    process()
