import sqlite3
import argparse
import json

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--researcher', type=str, required=True)
    parser.add_argument('--min-val', type=float, required=True)
    args = parser.parse_args()

    conn = sqlite3.connect('/home/user/research_data.db')
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    query = """
        SELECT e.name as experiment_name, m.date as measurement_date, m.value as value
        FROM researchers r
        JOIN experiments e ON r.id = e.researcher_id
        JOIN measurements m ON e.id = m.exp_id
        WHERE r.name = ? 
          AND e.status != 'REJECTED'
          AND m.value >= ?
        ORDER BY m.date ASC, e.name ASC
    """

    cursor.execute(query, (args.researcher, args.min_val))
    rows = cursor.fetchall()

    result = []
    for row in rows:
        result.append({
            "experiment_name": row["experiment_name"],
            "measurement_date": row["measurement_date"],
            "value": row["value"]
        })

    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
