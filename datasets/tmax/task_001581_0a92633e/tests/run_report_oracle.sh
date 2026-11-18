#!/bin/bash
USER_ID=$1
sqlite3 /home/user/ecommerce.db <<DBEOF
.mode csv
SELECT p.category, printf('%.2f', SUM(p.price * oi.quantity)) as total_spend
FROM users u
JOIN orders o ON u.id = o.user_id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id
WHERE u.id = ${USER_ID}
GROUP BY p.category
ORDER BY SUM(p.price * oi.quantity) DESC, p.category ASC;
DBEOF
