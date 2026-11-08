import sys
import sqlite3

def solve(account_id):
    conn = sqlite3.connect('/app/ledger.db')
    cursor = conn.cursor()
    cursor.execute("DROP INDEX IF EXISTS idx_corrupted_src")

    # Depth 1 and 2 outbound sum
    query = """
    WITH RECURSIVE
      depth1 AS (
        SELECT dst, amount FROM transfers WHERE src = ?
      ),
      depth2 AS (
        SELECT t.amount FROM depth1 d JOIN transfers t ON d.dst = t.src
      )
    SELECT COALESCE((SELECT SUM(amount) FROM depth1), 0) + 
           COALESCE((SELECT SUM(amount) FROM depth2), 0)
    """
    cursor.execute(query, (account_id,))
    result = cursor.fetchone()[0]
    print(result)

if __name__ == "__main__":
    solve(int(sys.argv[1]))
