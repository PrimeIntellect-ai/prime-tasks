#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl gnupg
    pip3 install pytest

    # Install MongoDB 6.0 and Node.js
    curl -fsSL https://pgp.mongodb.com/server-6.0.asc | gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/6.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-6.0.list
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get update
    apt-get install -y mongodb-org nodejs

    # Setup /app and install dependencies
    mkdir -p /app
    cd /app
    npm init -y
    npm install express mongodb

    # Create buggy server.js
    cat << 'EOF' > /app/server.js
const express = require('express');
const { MongoClient } = require('mongodb');

const app = express();
const port = 8000;
const mongoUrl = 'mongodb://127.0.0.1:27017';
const dbName = 'corp';

app.get('/api/subordinates', async (req, res) => {
    const managerId = parseInt(req.query.manager_id);
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;

    const client = new MongoClient(mongoUrl);
    try {
        await client.connect();
        const db = client.db(dbName);
        const collection = db.collection('employees');

        // Buggy aggregation pipeline
        const result = await collection.aggregate([
            { $match: { managerId: managerId } },
            { $lookup: { from: 'employees', localField: 'managerId', foreignField: 'managerId', as: 'subs' } }
        ]).toArray();

        res.json(result);
    } catch (err) {
        res.status(500).send(err.toString());
    } finally {
        await client.close();
    }
});

app.listen(port, '127.0.0.1', () => {
    console.log(`Server running at http://127.0.0.1:${port}/`);
});
EOF

    # Populate MongoDB data
    mkdir -p /data/db
    mongod --fork --logpath /var/log/mongodb.log --dbpath /data/db --port 27018

    # Wait for MongoDB to start
    sleep 3

    mongosh --port 27018 corp --eval 'db.employees.insertMany([{_id:1, name:"Alice"}, {_id:2, name:"Bob", managerId:1}, {_id:3, name:"Charlie", managerId:1}, {_id:4, name:"David", managerId:2}, {_id:5, name:"Eve", managerId:2}, {_id:6, name:"Frank", managerId:3}, {_id:7, name:"Grace", managerId:3}])'

    mongod --dbpath /data/db --shutdown

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app /data/db /var/log/mongodb.log
