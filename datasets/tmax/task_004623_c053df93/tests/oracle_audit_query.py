import sys
import sqlite3

def main():
    badge_id = int(sys.argv[1])
    start_time = int(sys.argv[2])
    end_time = int(sys.argv[3])

    conn = sqlite3.connect('/app/access_logs.db')
    c = conn.cursor()

    gt_events = [45, 120, 310, 850, 1105, 1920, 2400, 3115, 3500]

    c.execute('SELECT scan_time FROM badge_scans WHERE badge_id = ? AND door_id = 1 AND scan_time >= ? AND scan_time <= ?', (badge_id, start_time, end_time))
    scans = c.fetchall()

    count = 0
    for (scan_time,) in scans:
        for ev in gt_events:
            if abs(scan_time - ev) <= 5:
                count += 1
                break

    print(count)

if __name__ == '__main__':
    main()
