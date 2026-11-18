#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    sqlite3 /home/user/data.db <<EOF
CREATE TABLE daily_prices (date TEXT, price REAL);
INSERT INTO daily_prices VALUES ('2023-01-01', 100.0);
INSERT INTO daily_prices VALUES ('2023-01-02', 105.0);
INSERT INTO daily_prices VALUES ('2023-01-03', 102.0);
INSERT INTO daily_prices VALUES ('2023-01-04', 108.0);
EOF

    cat << 'EOF' > /home/user/process_data.py
import sqlite3
import sys

def calculate_ema(prices, alpha=0.1):
    if not prices:
        return 0.0
    ema = prices[0]
    for price in prices[1:]:
        # BUG: incorrect formula
        ema = (price * (1 - alpha)) + (ema * alpha)
    return ema

def main():
    try:
        conn = sqlite3.connect('/home/user/data.db')
        cursor = conn.cursor()

        # BUG: Wrong order (DESC instead of ASC) and wrong table name (stock_prices instead of daily_prices)
        cursor.execute("SELECT price FROM stock_prices ORDER BY date DESC")
        rows = cursor.fetchall()

        if not rows:
            print("No data found")
            sys.exit(1)

        prices = [row[0] for row in rows]
        final_ema = calculate_ema(prices)

        print(f"{final_ema:.4f}")
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > /home/user/pipeline.sh
#!/bin/bash

# BUG: missing python execution command properly, trying to execute the file directly without executable permissions
process_data.py > /home/user/final_ema.txt
EOF

    chmod +x /home/user/pipeline.sh
    chmod -R 777 /home/user
