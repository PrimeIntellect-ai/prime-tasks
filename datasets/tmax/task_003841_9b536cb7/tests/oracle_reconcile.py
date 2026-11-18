import sys
import sqlite3
import csv

def main():
    db_path = sys.argv[1]
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    query = """
    WITH ValidJobs AS (
        SELECT bj.job_id, bj.node_id, bj.completed_at
        FROM backup_jobs bj
        JOIN storage_nodes sn ON bj.node_id = sn.node_id
        WHERE bj.status = 'COMPLETED' 
          AND bj.integrity_hash IS NOT NULL
          AND sn.region != 'us-east-legacy'
    ),
    LatestJobs AS (
        SELECT job_id, node_id
        FROM (
            SELECT job_id, node_id, 
                   ROW_NUMBER() OVER(PARTITION BY node_id ORDER BY completed_at DESC) as rn
            FROM ValidJobs
        ) WHERE rn = 1
    ),
    JobSizes AS (
        SELECT job_id, SUM(bytes_size) as total_backup_bytes
        FROM job_chunks
        GROUP BY job_id
    )
    SELECT sn.node_id, sn.node_name, lj.job_id, COALESCE(js.total_backup_bytes, 0)
    FROM storage_nodes sn
    JOIN LatestJobs lj ON sn.node_id = lj.node_id
    LEFT JOIN JobSizes js ON lj.job_id = js.job_id
    ORDER BY sn.node_id ASC;
    """
    cur.execute(query)
    writer = csv.writer(sys.stdout)
    for row in cur.fetchall():
        writer.writerow(row)

if __name__ == "__main__":
    main()
