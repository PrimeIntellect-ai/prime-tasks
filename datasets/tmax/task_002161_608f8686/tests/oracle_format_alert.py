import sys, json, re

def main():
    raw = sys.stdin.read().strip()
    match = re.match(r'^\[(.*?)\]\s*(\{.*\})$', raw)
    if not match:
        print("INVALID LOG")
        return
    level, json_str = match.groups()
    try:
        data = json.loads(json_str)
        if not all(k in data for k in ("user", "action", "ip")):
            print("INVALID LOG")
            return
        print(f"ALERT LEVEL: {level}\nACTION: {data['action']}\nUSER: {data['user']}\nIP: {data['ip']}")
    except json.JSONDecodeError:
        print("INVALID LOG")

if __name__ == "__main__":
    main()
