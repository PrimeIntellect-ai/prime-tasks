#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/requirements.txt
fastapi==0.95.0
pydantic==2.0.0
pytest==7.4.0
httpx==0.24.1
pytest-json-report==1.5.0
EOF

    cat << 'EOF' > /home/user/app/test_main.py
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_read_item():
    response = client.get("/items/42")
    assert response.status_code == 200
    assert response.json() == {"item_id": 42, "name": "Item 42", "is_offer": None}

def test_create_item():
    response = client.post("/items/", json={"name": "Screwdriver", "price": 12.5})
    assert response.status_code == 200
    assert response.json() == {"name": "Screwdriver", "price": 12.5, "tax": 1.25}

def test_create_item_no_tax():
    response = client.post("/items/", json={"name": "Hammer", "price": 10.0, "tax": 0.0})
    assert response.status_code == 200
    assert response.json() == {"name": "Hammer", "price": 10.0, "tax": 0.0}
EOF

    cat << 'EOF' > /home/user/app/main.py
from fastapi import FastAPI
from pydantic import BaseModel
from typing import Optional

app = FastAPI()

class Item(BaseModel):
    name: str
    price: float
    tax: Optional[float] = None

@app.get("/items/{item_id}")
def read_item(item_id: str):
    return {"item_id": item_id, "name": "Item " + item_id, "is_offer": False}

@app.post("/items/")
def create_item(item: Item):
    if item.tax is None:
        item.tax = item.price * 0.20
    return item
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
