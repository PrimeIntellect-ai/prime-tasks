#!/bin/bash
ID=$1
RES=$(sqlite3 /app/sales.db "SELECT c.name, COUNT(t.tx_id), IFNULL(SUM(t.amount), 0), IFNULL(AVG(t.amount), 0) FROM customers c LEFT JOIN transactions t ON c.id = t.customer_id AND t.amount >= 50 WHERE c.id = $ID GROUP BY c.id;")
if [ -z "$RES" ]; then
    exit 1
fi
NAME=$(echo "$RES" | cut -d'|' -f1)
COUNT=$(echo "$RES" | cut -d'|' -f2)
SUM=$(echo "$RES" | cut -d'|' -f3)
AVG=$(echo "$RES" | cut -d'|' -f4)

if [ "$COUNT" -eq 0 ]; then
    echo "Customer $NAME (ID: $ID): No valid transactions"
else
    printf "Customer %s (ID: %d): Total=%.2f, Avg=%.2f\n" "$NAME" "$ID" "$SUM" "$AVG"
fi
