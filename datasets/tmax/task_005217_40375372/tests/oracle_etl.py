import sys
import json

def main():
    state = {}
    for line in sys.stdin:
        if not line.strip():
            continue
        data = json.loads(line)
        sensor = data["sensor"]
        temp = data["temp"]
        ts = data["ts"]
        status = data["status"]

        if temp is None:
            temp = state.get(sensor, 0.0)
        else:
            state[sensor] = temp

        print(f"Data point[{sensor}]={temp:.1f}_{ts} {status}")

if __name__ == "__main__":
    main()
