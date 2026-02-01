-- Connect to default DB or create it (usually 'postgres' user default DB is 'postgres')
-- This script runs automatically by the postgres docker image

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price NUMERIC(10, 2) NOT NULL
);

CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(id),
    product_id INT REFERENCES products(id),
    qty INT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Seed Data
INSERT INTO users (id, name, email) VALUES 
(1, 'Alice Corp', 'alice@example.com'),
(2, 'Bob Ltd', 'bob@example.com'),
(3, 'Charlie Inc', 'charlie@example.com')
ON CONFLICT (id) DO NOTHING;
-- Reset sequence to avoid Id collisions
SELECT setval('users_id_seq', (SELECT MAX(id) FROM users));


INSERT INTO products (id, name, price) VALUES 
(1, 'Widget A', 10.50),
(2, 'Widget B', 25.00),
(3, 'Super Gadget', 99.99)
ON CONFLICT (id) DO NOTHING;
SELECT setval('products_id_seq', (SELECT MAX(id) FROM products));

