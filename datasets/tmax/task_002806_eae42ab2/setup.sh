#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/transaction_processor.py
import threading
import time
import random

class Account:
    def __init__(self, account_id, balance):
        self.account_id = account_id
        self.balance = balance
        self.lock = threading.Lock()

def transfer(account_a, account_b, amount):
    # Simulate a deadlock-prone transfer
    with account_a.lock:
        time.sleep(0.005) # Force context switch
        with account_b.lock:
            if account_a.balance >= amount:
                account_a.balance -= amount
                account_b.balance += amount

def worker(accounts, iterations):
    for _ in range(iterations):
        a, b = random.sample(accounts, 2)
        transfer(a, b, 10)

def main():
    random.seed(42)
    accounts = [Account(i, 1000) for i in range(5)]
    threads = []
    for _ in range(10):
        t = threading.Thread(target=worker, args=(accounts, 50))
        threads.append(t)
        t.start()

    for t in threads:
        t.join()

    total_balance = sum(a.balance for a in accounts)
    with open('/home/user/success.log', 'w') as f:
        f.write(f"Total balance: {total_balance}")
    print("Done")

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
