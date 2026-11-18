import sqlite3
import argparse

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db-path', required=True)
    parser.add_argument('--researcher-id', type=int, required=True)
    args = parser.parse_args()

    conn = sqlite3.connect(args.db_path)
    cur = conn.cursor()

    query = """
        SELECT COUNT(DISTINCT w2.researcher_id)
        FROM wrote w1
        JOIN documents d ON w1.document_id = d.id
        JOIN wrote w2 ON d.id = w2.document_id
        WHERE w1.researcher_id = ? 
          AND w2.researcher_id != ?
          AND d.year > 2015
    """
    cur.execute(query, (args.researcher_id, args.researcher_id))
    result = cur.fetchone()[0]
    print(result)

if __name__ == '__main__':
    main()
