#!/bin/bash
set -e

# Run docker compose
echo "Starting local development stack..."
docker compose up --build -d

echo "Waiting for services to be ready..."
sleep 5

echo "Setup complete. Services running."
echo "User Service: http://localhost:3000"
echo "Product Service: http://localhost:3001"
echo "Order Service: http://localhost:3002"
