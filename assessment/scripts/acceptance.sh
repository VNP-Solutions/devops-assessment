#!/bin/bash
set -e

BASE_URL=${BASE_URL:-"http://localhost"}

if [ -z "$BASE_URL" ] || [ "$BASE_URL" == "http://localhost" ]; then
    USER_URL="http://localhost:3000"
    PRODUCT_URL="http://localhost:3001"
    ORDER_URL="http://localhost:3002"
    echo "Running in LOCAL mode (direct ports)"
else
    USER_URL="$BASE_URL"
    PRODUCT_URL="$BASE_URL"
    ORDER_URL="$BASE_URL"
    echo "Running in INGRESS mode (base: $BASE_URL)"
fi

echo "--- Checking Health ---"
curl -s -f "$USER_URL/health" || (echo "User Service health check failed" && exit 1)
echo "User Service: OK"
curl -s -f "$PRODUCT_URL/health" || (echo "Product Service health check failed" && exit 1)
echo "Product Service: OK"
curl -s -f "$ORDER_URL/health" || (echo "Order Service health check failed" && exit 1)
echo "Order Service: OK"

echo "--- Checking Ready ---"
curl -s -f "$USER_URL/ready" > /dev/null
echo "User Service: READY"
curl -s -f "$PRODUCT_URL/ready" > /dev/null
echo "Product Service: READY"
curl -s -f "$ORDER_URL/ready" > /dev/null
echo "Order Service: READY"

echo "--- Checking Data ---"
# Check User
curl -s -f "$USER_URL/users/1" | grep "Alice" > /dev/null || (echo "User 1 check failed" && exit 1)
echo "User 1: OK"

# Check Product (Test Cache potentially?)
# First hit: initializes cache
curl -s -f "$PRODUCT_URL/products/1" | grep "Widget" > /dev/null || (echo "Product 1 check failed" && exit 1)
echo "Product 1: OK (Cache Miss/Hit)"

echo "--- Creating Order ---"
# Post to /orders
if [ "$ORDER_URL" == "$BASE_URL" ]; then
    ORDER_POST_URL="$ORDER_URL/orders"
else
    ORDER_POST_URL="$ORDER_URL/orders"
fi

RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d '{"userId": 1, "productId": 1, "qty": 2}' "$ORDER_POST_URL")

echo "Response: $RESPONSE"

if echo "$RESPONSE" | grep -q "orderId"; then
    echo "Order Created: OK"
else
    echo "Order Creation Failed!"
    exit 1
fi

echo "=== All Acceptance Tests Passed ==="
