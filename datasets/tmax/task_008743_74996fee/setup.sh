#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nodejs npm procps
    pip3 install pytest

    mkdir -p /home/user/api_source
    cat << 'EOF' > /home/user/api_source/package.json
{
  "name": "vulnerable-api",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

    cat << 'EOF' > /home/user/api_source/server.js
const express = require('express');
const app = express();

const sensitiveData = {
  status: "success",
  data: [
    { id: 1, name: "Alice CEO", ssn: "123-45-6789", access: "full" },
    { id: 2, name: "Bob CTO", ssn: "987-65-4321", access: "full" },
    { id: 3, name: "Charlie CFO", ssn: "555-12-3456", access: "full" }
  ]
};

// Custom weak JWT middleware
function verifyToken(req, res, next) {
  const authHeader = req.headers['authorization'];
  if (!authHeader) return res.status(401).send('No token provided');

  const token = authHeader.split(' ')[1];
  if (!token) return res.status(401).send('Invalid token format');

  try {
    const parts = token.split('.');
    if (parts.length !== 3) throw new Error("Invalid JWT format");

    const header = JSON.parse(Buffer.from(parts[0], 'base64url').toString());
    const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString());

    // VULNERABILITY: Accepts 'none' algorithm
    if (header.alg && header.alg.toLowerCase() === 'none') {
      req.user = payload;
      return next();
    }

    // Standard fake validation for other algs (always fails in this mock for non-none)
    return res.status(403).send('Invalid signature');
  } catch (err) {
    return res.status(400).send('Malformed token');
  }
}

app.get('/api/admin/data', verifyToken, (req, res) => {
  if (req.user && req.user.role === 'admin') {
    res.json(sensitiveData);
  } else {
    res.status(403).json({ error: "Access denied. Admin role required." });
  }
});

app.listen(3000, '127.0.0.1', () => {
  console.log('Server running on port 3000');
});
EOF

    cd /home/user/api_source
    npm install

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
