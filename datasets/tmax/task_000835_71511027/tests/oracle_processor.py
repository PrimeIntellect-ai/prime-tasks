import sys
import re
from datetime import datetime, timedelta

def main():
    line = sys.stdin.read().strip()
    pattern = r'^\[(?P<start>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\] TO \[(?P<end>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\] VALUE: (?P<val>-?\d+\.\d+) STATUS: (?P<status>[A-Z]+)$'

    match = re.match(pattern, line)
    if not match:
        print("INVALID_FORMAT")
        return

    start_str = match.group('start')
    end_str = match.group('end')
    val = match.group('val')
    status = match.group('status')

    try:
        start_dt = datetime.strptime(start_str, '%Y-%m-%dT%H:%M:%S')
        end_dt = datetime.strptime(end_str, '%Y-%m-%dT%H:%M:%S')
    except ValueError:
        print("INVALID_FORMAT")
        return

    if end_dt < start_dt:
        print("INVALID_FORMAT")
        return

    curr_dt = start_dt
    while curr_dt <= end_dt:
        print(f"{curr_dt.strftime('%Y-%m-%dT%H:%M:%S')}|{val}|{status}")
        curr_dt += timedelta(seconds=1)

if __name__ == "__main__":
    main()
