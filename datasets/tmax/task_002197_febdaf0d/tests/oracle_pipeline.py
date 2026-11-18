import sqlite3
import sys
import math

def compute(lat, lon):
    return math.sqrt(math.pow(lat, 2) + math.pow(lon, 2))

def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    db_path = sys.argv[1]
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("SELECT s.id, s.lat, s.lon, c.factor FROM sensors s INNER JOIN calibration c ON s.id = c.sensor_id WHERE s.status = 'ACTIVE' ORDER BY s.id ASC")
    for row in cur.fetchall():
        sensor_id, lat, lon, factor = row
        dist = compute(lat, lon)
        score = dist * factor
        print(f"{score:.4f}")

if __name__ == "__main__":
    main()
