#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas numpy scikit-learn scipy

    useradd -m -s /bin/bash user || true

    python3 -c "
import os
import sqlite3
import pandas as pd
import numpy as np

os.makedirs('/home/user/data', exist_ok=True)
np.random.seed(42)

# 1. Create customers.csv
n_customers = 500
customer_ids = np.arange(1, n_customers + 1)
ages = np.random.randint(15, 105, size=n_customers).astype(object) # Some invalid
regions = np.random.choice(['North', 'South', 'East', 'West', 'Unknown', 'N/A'], size=n_customers, p=[0.25, 0.25, 0.2, 0.2, 0.05, 0.05])

# Inject schema violations
ages[10] = 'twenty'
ages[45] = 17 # Invalid age
ages[90] = 101 # Invalid age
customer_ids[100] = -5 # Invalid ID

customers = pd.DataFrame({'CustomerID': customer_ids, 'Age': ages, 'Region': regions})
customers.to_csv('/home/user/data/customers.csv', index=False)

# 2. Create transactions.csv
n_transactions = 2000
tx_ids = np.arange(1, n_transactions + 1)
tx_cust_ids = np.random.choice(customer_ids, size=n_transactions)
amounts = np.random.uniform(-10, 100, size=n_transactions) # Some invalid negative

transactions = pd.DataFrame({'TransactionID': tx_ids, 'CustomerID': tx_cust_ids, 'Amount': amounts})
transactions.to_csv('/home/user/data/transactions.csv', index=False)

# 3. Create support.db
conn = sqlite3.connect('/home/user/data/support.db')
cursor = conn.cursor()
cursor.execute('CREATE TABLE tickets (CustomerID INTEGER, TicketCount INTEGER)')

# Only about 60% of customers have tickets
n_tickets = 300
ticket_cust_ids = np.random.choice(customer_ids, size=n_tickets, replace=False)
ticket_counts = np.random.randint(-1, 5, size=n_tickets) # -1 is invalid

ticket_data = list(zip(ticket_cust_ids.tolist(), ticket_counts.tolist()))
cursor.executemany('INSERT INTO tickets VALUES (?, ?)', ticket_data)
conn.commit()
conn.close()
"

    chmod -R 777 /home/user
