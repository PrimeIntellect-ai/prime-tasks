import sys
import sqlite3

def run(dc, min_size):
    conn = sqlite3.connect('/home/user/backup_metrics.db')
    cursor = conn.cursor()

    query = """
    WITH 
    ValidServers AS (
        SELECT DISTINCT s.id, s.hostname 
        FROM servers s
        JOIN backups b ON s.id = b.server_id
        WHERE s.datacenter = ? AND b.size_bytes > ?
    ),
    LatestBackup AS (
        SELECT server_id, status 
        FROM (
            SELECT server_id, status, ROW_NUMBER() OVER(PARTITION BY server_id ORDER BY timestamp DESC) as rn
            FROM backups
        ) WHERE rn = 1
    ),
    TotalSize AS (
        SELECT server_id, SUM(size_bytes) as total_size
        FROM backups 
        WHERE status = 'SUCCESS'
        GROUP BY server_id
    ),
    RestoreStats AS (
        SELECT b.server_id, 
               COUNT(r.id) as total_restores,
               SUM(CASE WHEN r.is_successful = 1 THEN 1 ELSE 0 END) as successful_restores
        FROM backups b
        LEFT JOIN restores r ON b.id = r.backup_id
        GROUP BY b.server_id
    )
    SELECT vs.hostname, 
           lb.status, 
           COALESCE(ts.total_size, 0),
           rs.total_restores,
           rs.successful_restores
    FROM ValidServers vs
    LEFT JOIN LatestBackup lb ON vs.id = lb.server_id
    LEFT JOIN TotalSize ts ON vs.id = ts.server_id
    LEFT JOIN RestoreStats rs ON vs.id = rs.server_id
    ORDER BY vs.hostname ASC
    """

    cursor.execute(query, (dc, min_size))
    for row in cursor.fetchall():
        hostname = row[0]
        latest_status = row[1]
        total_size = row[2]
        total_restores = row[3]
        succ_restores = row[4]

        if total_restores is None or total_restores == 0:
            rate_str = "N/A"
        else:
            rate = (succ_restores / total_restores) * 100.0
            rate_str = f"{rate:.2f}"

        print(f"{hostname},{latest_status},{total_size},{rate_str}")

if __name__ == "__main__":
    run(sys.argv[1], int(sys.argv[2]))
