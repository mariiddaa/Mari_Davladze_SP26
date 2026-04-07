-- =============================================================================
-- PHYSICAL DATABASE: E-Commerce Marketplace
=========================================================

-- DDL ORDER EXPLANATION:
--   Tables must be created in dependency order — parent tables before child
--   tables. If a child table is created before its parent, PostgreSQL will
--   throw: "ERROR: relation does not exist" when it tries to resolve the FK.
--   Order here:
--   1. Lookup tables (no dependencies): payment_methods, payment_statuses,
--      orders_status_types, categories
--   2. Core entities: users
--   3. Dependent on users: sellers, addresses
--   4. Dependent on sellers/categories: products
--   5. Dependent on products: inventory
--   6. Dependent on users/addresses: orders
--   7. Dependent on orders/products/promotions: promotions, orders_items
--   8. Dependent on orders: payments, deliveries, orders_statuses
--   9. Dependent on orders_items/users/products: reviews
-- =============================================================================


-- =============================================================================
-- CREATE SCHEMA
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS marketplace;


-- =============================================================================
-- 1. LOOKUP TABLES (no foreign key dependencies)
-- =============================================================================

-- WHY ORDER MATTERS: These tables are referenced by other tables as FKs.
-- They must exist first or FK constraints will fail on creation.

CREATE TABLE IF NOT EXISTS marketplace.payment_methods (
    -- PK: surrogate integer, auto-incremented. Using SERIAL avoids manual ID management.
    -- RISK of wrong type: using VARCHAR as PK would make joins slower and
    -- allow inconsistent casing ('Card' vs 'card').
    payment_method_id SERIAL PRIMARY KEY,

    -- UNIQUE + NOT NULL: prevents duplicate method names and empty rows.
    -- WITHOUT THIS: 'card', 'Card', 'credit card' could coexist as separate
    -- methods, making payment reporting unreliable.
    method_name       VARCHAR(50) NOT NULL,

    CONSTRAINT uq_payment_method_name UNIQUE (method_name)
    -- WHAT uq_payment_method_name PREVENTS: duplicate entries like 'Credit Card'
    -- appearing twice, which would make it ambiguous which one to use.
);

CREATE TABLE IF NOT EXISTS marketplace.payment_statuses (
    payment_status_id SERIAL PRIMARY KEY,
    status_name       VARCHAR(50) NOT NULL,
    CONSTRAINT uq_payment_status_name UNIQUE (status_name)
    -- WHAT THIS PREVENTS: 'Pending' and 'pending' coexisting as different statuses.
    -- WITHOUT IT: inconsistent status values would break filtering and reporting.
);

CREATE TABLE IF NOT EXISTS marketplace.orders_status_types (
    order_status_type_id SERIAL PRIMARY KEY,
    status_name          VARCHAR(50) NOT NULL,
    CONSTRAINT uq_order_status_name UNIQUE (status_name)
);

-- Self-referencing table: parent_category_id is nullable for top-level categories.
-- WHY SELF-REFERENCE: allows unlimited category hierarchy depth (Electronics > Phones > Smartphones)
-- without schema changes.
CREATE TABLE IF NOT EXISTS marketplace.categories (
    category_id        SERIAL PRIMARY KEY,
    parent_category_id INT     REFERENCES marketplace.categories (category_id) ON DELETE SET NULL,
    -- RISK of wrong type: using TEXT instead of VARCHAR with a limit would allow
    -- arbitrarily long category names, which would break UI rendering.
    name               VARCHAR(100) NOT NULL,
    description        TEXT,
    CONSTRAINT uq_category_name UNIQUE (name)
    -- WHAT THIS PREVENTS: duplicate category names like 'Electronics' appearing twice,
    -- which would make category navigation confusing.
);


-- =============================================================================
-- 2. USERS (core entity, referenced by many tables)
-- =============================================================================

CREATE TABLE IF NOT EXISTS marketplace.users (
    user_id    SERIAL PRIMARY KEY,

    -- UNIQUE + NOT NULL: email is the login credential.
    -- RISK of wrong type: using TEXT without UNIQUE allows duplicate accounts
    -- for the same email, breaking authentication logic.
    email      VARCHAR(255) NOT NULL,

    first_name VARCHAR(100) NOT NULL,
    -- NOT NULL: a user without a name cannot be meaningfully displayed or contacted.
    -- WITHOUT NOT NULL: empty name records would appear in the system.

    last_name  VARCHAR(100) NOT NULL,

    -- NULLABLE: phone is optional contact info.
    -- RISK of wrong type: using INT for phone would lose leading zeros
    -- and break international formats (+995 555...).
    phone      VARCHAR(20),

    -- DEFAULT NOW(): automatically records when the account was created.
    -- RISK of wrong type: using DATE instead of TIMESTAMP loses time precision,
    -- making it impossible to order accounts created on the same day.
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),

    -- DEFAULT TRUE: new accounts are active by default.
    -- RISK of wrong type: using VARCHAR('true'/'false') instead of BOOLEAN
    -- would require string comparison logic and allow invalid values.
    is_active  BOOLEAN NOT NULL DEFAULT TRUE,

    -- CHECK 5 (date constraint): account creation cannot be before year 2000.
    -- WHAT THIS PREVENTS: data entry errors like '1970-01-01' (Unix epoch default).
    -- WITHOUT IT: corrupt timestamps would pass silently.
    CONSTRAINT chk_users_created_at CHECK (created_at > '2000-01-01'),

    CONSTRAINT uq_users_email UNIQUE (email)
    -- WHAT THIS PREVENTS: two accounts with the same email, which would make
    -- login ambiguous and allow duplicate user profiles.
);


-- =============================================================================
-- 3. SELLERS (depends on users)
-- =============================================================================

-- WHY FK TO USERS: every seller must be a registered user.
-- IF FK IS MISSING: a seller could reference a non-existent user_id,
-- making it impossible to contact or identify the store owner.
CREATE TABLE IF NOT EXISTS marketplace.sellers (
    seller_id         SERIAL PRIMARY KEY,

    -- FK → users. NOT NULL: every seller must have an owner.
    -- IF FK IS MISSING: orphaned seller records with invalid user_id would
    -- break any query joining sellers to users.
    user_id           INT NOT NULL REFERENCES marketplace.users (user_id) ON DELETE CASCADE,

    store_name        VARCHAR(150) NOT NULL,

    store_description TEXT,

    registered_at     TIMESTAMP NOT NULL DEFAULT NOW(),

    -- DEFAULT FALSE: stores start unverified until reviewed by the platform.
    is_verified       BOOLEAN NOT NULL DEFAULT FALSE,

    -- CHECK (date constraint): store registration cannot predate year 2000.
    CONSTRAINT chk_sellers_registered_at CHECK (registered_at > '2000-01-01'),

    CONSTRAINT uq_sellers_store_name UNIQUE (store_name)
    -- WHAT THIS PREVENTS: two sellers with the same store name, which would
    -- confuse buyers who search for a specific store.
);


-- =============================================================================
-- 4. ADDRESSES (depends on users)
-- =============================================================================

CREATE TABLE IF NOT EXISTS marketplace.addresses (
    address_id  SERIAL PRIMARY KEY,

    -- FK → users: each address belongs to a user.
    -- IF FK IS MISSING: addresses could reference non-existent users,
    -- making delivery data unrecoverable if the user is deleted.
    user_id     INT         NOT NULL REFERENCES marketplace.users (user_id) ON DELETE CASCADE,

    street      VARCHAR(255) NOT NULL,
    city        VARCHAR(100) NOT NULL,
    country     VARCHAR(100) NOT NULL,
    postal_code VARCHAR(20)  -- NULLABLE: some countries/addresses have no postal code
);


-- =============================================================================
-- 5. PRODUCTS (depends on sellers, categories)
-- =============================================================================

CREATE TABLE IF NOT EXISTS marketplace.products (
    product_id  SERIAL PRIMARY KEY,

    -- FK → sellers. IF FK IS MISSING: products could belong to non-existent
    -- sellers, making it impossible to process orders or contact the seller.
    seller_id   INT            NOT NULL REFERENCES marketplace.sellers  (seller_id) ON DELETE CASCADE,

    -- FK → categories. IF FK IS MISSING: products could have invalid category_id,
    -- breaking category browsing and filtering.
    category_id INT            NOT NULL REFERENCES marketplace.categories (category_id),

    name        VARCHAR(255)   NOT NULL,

    -- DECIMAL(12,2): stores monetary values with exactly 2 decimal places.
    -- RISK of wrong type: using FLOAT would introduce floating-point rounding
    -- errors (e.g. 699.99 stored as 699.9899999999...), corrupting price displays.
    price       DECIMAL(12, 2) NOT NULL,

    -- CHECK (non-negative value): price cannot be negative.
    -- WHAT THIS PREVENTS: data entry errors or bugs that set price to -10.00.
    -- WITHOUT IT: negative prices would cause incorrect totals in orders.
    CONSTRAINT chk_products_price CHECK (price >= 0),

    is_active   BOOLEAN        NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP      NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_products_created_at CHECK (created_at > '2000-01-01')
);


-- =============================================================================
-- 6. INVENTORY (depends on products — 1-to-1)
-- =============================================================================

CREATE TABLE IF NOT EXISTS marketplace.inventory (
    inventory_id       SERIAL PRIMARY KEY,

    -- UNIQUE enforces 1-to-1 with products.
    -- IF FK IS MISSING: inventory could reference a non-existent product,
    -- making stock levels meaningless.
    product_id         INT NOT NULL REFERENCES marketplace.products (product_id) ON DELETE CASCADE,

    -- CHECK (non-negative): stock cannot be negative.
    -- WHAT THIS PREVENTS: a bug reducing stock below 0, which would show
    -- "−3 units available" to buyers.
    quantity_available INT NOT NULL DEFAULT 0,
    CONSTRAINT chk_inventory_qty_available CHECK (quantity_available >= 0),

    quantity_reserved  INT NOT NULL DEFAULT 0,
    CONSTRAINT chk_inventory_qty_reserved CHECK (quantity_reserved >= 0),

    updated_at         TIMESTAMP NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_inventory_product_id UNIQUE (product_id)
    -- WHAT THIS PREVENTS: two inventory rows for the same product,
    -- which would make total stock impossible to calculate correctly.
);


-- =============================================================================
-- 7. PROMOTIONS (no FK dependencies except orders_items which comes later)
-- =============================================================================

CREATE TABLE IF NOT EXISTS marketplace.promotions (
    promotion_id   SERIAL PRIMARY KEY,

    code           VARCHAR(50)    NOT NULL,

    -- CHECK (specific values): discount_type must be one of two valid options.
    -- WHAT THIS PREVENTS: free-text values like 'percent', 'PERCENTAGE', 'flat'
    -- coexisting and breaking discount calculation logic.
    -- WITHOUT IT: any string could be entered, making the column unreliable.
    discount_type  VARCHAR(20)    NOT NULL,
    CONSTRAINT chk_promotions_discount_type
        CHECK (discount_type IN ('percentage', 'fixed_amount')),

    -- CHECK (non-negative): discount value cannot be negative.
    -- WHAT THIS PREVENTS: a negative discount that would ADD to the price.
    discount_value DECIMAL(10, 2) NOT NULL,
    CONSTRAINT chk_promotions_discount_value CHECK (discount_value >= 0),

    valid_from     TIMESTAMP      NOT NULL,
    valid_to       TIMESTAMP      NOT NULL,

    -- CHECK (date constraint): promotions cannot start before year 2000.
    CONSTRAINT chk_promotions_valid_from CHECK (valid_from > '2000-01-01'),

    is_active      BOOLEAN        NOT NULL DEFAULT TRUE,

    CONSTRAINT uq_promotions_code UNIQUE (code)
);


-- =============================================================================
-- 8. ORDERS (depends on users, addresses)
-- =============================================================================

CREATE TABLE IF NOT EXISTS marketplace.orders (
    order_id     SERIAL PRIMARY KEY,

    -- FK → users. IF FK IS MISSING: orders could reference deleted or
    -- non-existent users, making buyer identification impossible.
    user_id      INT            NOT NULL REFERENCES marketplace.users    (user_id),

    -- FK → addresses. NULLABLE: address may not be set at order creation.
    address_id   INT            REFERENCES marketplace.addresses (address_id) ON DELETE SET NULL,

    -- DECIMAL(12,2): same reasoning as products.price — avoid float errors.
    total_amount DECIMAL(12, 2) NOT NULL DEFAULT 0,
    CONSTRAINT chk_orders_total_amount CHECK (total_amount >= 0),

    ordered_at   TIMESTAMP      NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_orders_ordered_at CHECK (ordered_at > '2000-01-01')
);


-- =============================================================================
-- 9. ORDERS_ITEMS (depends on orders, products, promotions)
-- =============================================================================

-- Bridge table resolving M-to-M between orders and products.
-- WHY SURROGATE PK: simplifies the FK reference from reviews (one column
-- instead of a composite key).
CREATE TABLE IF NOT EXISTS marketplace.orders_items (
    order_item_id  SERIAL PRIMARY KEY,

    -- IF FK IS MISSING: items could reference non-existent orders,
    -- making it impossible to reconstruct what was in a purchase.
    order_id       INT            NOT NULL REFERENCES marketplace.orders   (order_id) ON DELETE CASCADE,
    product_id     INT            NOT NULL REFERENCES marketplace.products  (product_id),

    -- NULLABLE: not every line item has a promotion.
    promotion_id   INT            REFERENCES marketplace.promotions (promotion_id) ON DELETE SET NULL,

    quantity       INT            NOT NULL,
    CONSTRAINT chk_orders_items_quantity CHECK (quantity > 0),
    -- WHAT THIS PREVENTS: an order item with 0 or negative quantity,
    -- which would make total_amount calculations incorrect.

    -- Captures price at moment of purchase — immutable historical record.
    -- RISK of wrong type: FLOAT would introduce rounding errors on financial data.
    price_at_order DECIMAL(12, 2) NOT NULL,
    CONSTRAINT chk_orders_items_price CHECK (price_at_order >= 0),  -- ← add comma here

    -- GENERATED ALWAYS AS: line_total is automatically computed as quantity × price_at_order.
    -- STORED means the value is physically saved to disk at insert/update time.
    -- WHY THIS COLUMN: eliminates the risk of application code computing an incorrect total.
    -- You cannot INSERT or UPDATE this column manually — PostgreSQL enforces this.
    line_total     DECIMAL(12, 2) GENERATED ALWAYS AS (quantity * price_at_order) STORED
);


-- =============================================================================
-- 10. PAYMENTS (depends on orders, payment_methods, payment_statuses)
-- =============================================================================

CREATE TABLE IF NOT EXISTS marketplace.payments (
    payment_id        SERIAL PRIMARY KEY,

    -- UNIQUE: enforces 1-to-1 with orders.
    -- IF FK IS MISSING: payments could reference non-existent orders,
    -- making financial reconciliation impossible.
    order_id          INT            NOT NULL REFERENCES marketplace.orders          (order_id) ON DELETE CASCADE,

    payment_method_id INT            NOT NULL REFERENCES marketplace.payment_methods  (payment_method_id),
    payment_status_id INT            NOT NULL REFERENCES marketplace.payment_statuses (payment_status_id),

    amount            DECIMAL(12, 2) NOT NULL,
    CONSTRAINT chk_payments_amount CHECK (amount >= 0),

    -- NULLABLE: NULL means payment has not been processed yet.
    paid_at           TIMESTAMP,

    CONSTRAINT uq_payments_order_id UNIQUE (order_id)
    -- WHAT THIS PREVENTS: two payment records for the same order,
    -- which would cause double-charging.
);


-- =============================================================================
-- 11. DELIVERIES (depends on orders)
-- =============================================================================

CREATE TABLE IF NOT EXISTS marketplace.deliveries (
    delivery_id     SERIAL PRIMARY KEY,

    -- UNIQUE: enforces 1-to-1 with orders.
    order_id        INT         NOT NULL REFERENCES marketplace.orders (order_id) ON DELETE CASCADE,

    -- VARCHAR: carrier is stored as text under the simplifying assumption
    -- that the platform currently uses Georgian Post only. If multiple carriers
    -- are introduced, this should become carrier_id → a Carriers lookup table.
    carrier         VARCHAR(100) NOT NULL,
    tracking_number VARCHAR(100),  -- NULLABLE: may not be available immediately

    dispatched_at   TIMESTAMP,     -- NULLABLE: not dispatched yet
    delivered_at    TIMESTAMP,     -- NULLABLE: not yet delivered

    CONSTRAINT uq_deliveries_order_id UNIQUE (order_id)
    -- WHAT THIS PREVENTS: two delivery records for the same order.
);


-- =============================================================================
-- 12. ORDERS_STATUSES (depends on orders, orders_status_types)
-- =============================================================================

-- Append-only bridge table — rows are never updated or deleted.
-- Full order lifecycle is always recoverable.
CREATE TABLE IF NOT EXISTS marketplace.orders_statuses (
    status_id            SERIAL PRIMARY KEY,

    -- IF FK IS MISSING: status records could reference non-existent orders,
    -- making order history unrecoverable.
    order_id             INT       NOT NULL REFERENCES marketplace.orders            (order_id) ON DELETE CASCADE,
    order_status_type_id INT       NOT NULL REFERENCES marketplace.orders_status_types (order_status_type_id),

    changed_at           TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_orders_statuses_changed_at CHECK (changed_at > '2000-01-01'),

    note                 TEXT      -- NULLABLE: optional reason/comment
);


-- =============================================================================
-- 13. REVIEWS (depends on orders_items, products, users)
-- =============================================================================

CREATE TABLE IF NOT EXISTS marketplace.reviews (
    review_id     SERIAL PRIMARY KEY,

    -- FK → orders_items: proves the reviewer actually purchased the product.
    -- IF FK IS MISSING: anyone could review any product without buying it.
    order_item_id INT       NOT NULL REFERENCES marketplace.orders_items (order_item_id) ON DELETE CASCADE,
    product_id    INT       NOT NULL REFERENCES marketplace.products     (product_id),
    user_id       INT       NOT NULL REFERENCES marketplace.users        (user_id),

    -- CHECK: rating must be between 1 and 5.
    -- WHAT THIS PREVENTS: a rating of 0 or 10 being inserted, which would
    -- break average rating calculations.
    -- WITHOUT IT: any integer could be stored, making star ratings meaningless.
    rating        INT       NOT NULL,
    CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5),

    comment       TEXT,     -- NULLABLE: text comment is optional
    reviewed_at   TIMESTAMP NOT NULL DEFAULT NOW(),

    -- UNIQUE: one review per order item (one buyer, one product, one review).
    -- WHAT THIS PREVENTS: a buyer submitting multiple reviews for the same purchase.
    CONSTRAINT uq_reviews_order_item_id UNIQUE (order_item_id)
);


-- =============================================================================
-- STEP 9: ADD record_ts TO ALL TABLES
-- =============================================================================
-- WHY ALTER TABLE instead of adding in CREATE TABLE:
--   The task explicitly requires using ALTER TABLE to demonstrate that
--   columns can be added to existing tables without data loss.
--   DEFAULT CURRENT_DATE ensures all existing rows get a value immediately.
-- =============================================================================

ALTER TABLE marketplace.payment_methods    ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.payment_statuses   ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.orders_status_types ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.categories         ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.users              ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.sellers            ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.addresses          ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.products           ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.inventory          ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.promotions         ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.orders             ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.orders_items       ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.payments           ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.deliveries         ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.orders_statuses    ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE marketplace.reviews            ADD COLUMN IF NOT EXISTS record_ts DATE NOT NULL DEFAULT CURRENT_DATE;

-- Verify record_ts was set for all rows in all tables
SELECT 'payment_methods'     AS tbl, COUNT(*) AS rows, COUNT(record_ts) AS with_ts FROM marketplace.payment_methods
UNION ALL
SELECT 'payment_statuses',    COUNT(*), COUNT(record_ts) FROM marketplace.payment_statuses
UNION ALL
SELECT 'orders_status_types', COUNT(*), COUNT(record_ts) FROM marketplace.orders_status_types
UNION ALL
SELECT 'categories',          COUNT(*), COUNT(record_ts) FROM marketplace.categories
UNION ALL
SELECT 'users',               COUNT(*), COUNT(record_ts) FROM marketplace.users
UNION ALL
SELECT 'sellers',             COUNT(*), COUNT(record_ts) FROM marketplace.sellers
UNION ALL
SELECT 'addresses',           COUNT(*), COUNT(record_ts) FROM marketplace.addresses
UNION ALL
SELECT 'products',            COUNT(*), COUNT(record_ts) FROM marketplace.products
UNION ALL
SELECT 'inventory',           COUNT(*), COUNT(record_ts) FROM marketplace.inventory
UNION ALL
SELECT 'promotions',          COUNT(*), COUNT(record_ts) FROM marketplace.promotions
UNION ALL
SELECT 'orders',              COUNT(*), COUNT(record_ts) FROM marketplace.orders
UNION ALL
SELECT 'orders_items',        COUNT(*), COUNT(record_ts) FROM marketplace.orders_items
UNION ALL
SELECT 'payments',            COUNT(*), COUNT(record_ts) FROM marketplace.payments
UNION ALL
SELECT 'deliveries',          COUNT(*), COUNT(record_ts) FROM marketplace.deliveries
UNION ALL
SELECT 'orders_statuses',     COUNT(*), COUNT(record_ts) FROM marketplace.orders_statuses
UNION ALL
SELECT 'reviews',             COUNT(*), COUNT(record_ts) FROM marketplace.reviews;


-- =============================================================================
-- STEP 8: INSERT SAMPLE DATA
-- =============================================================================
-- HOW CONSISTENCY IS ENSURED:
--   All FKs are resolved by SELECT subqueries (no hardcoded IDs).
--   ON CONFLICT DO NOTHING prevents duplicate inserts on re-run.
--   Data is inserted in FK dependency order — parents before children.
--   This preserves referential integrity: every FK value references a
--   row that is guaranteed to exist by the time the child row is inserted.
-- =============================================================================

-- Lookup tables first (no dependencies)
INSERT INTO marketplace.payment_methods (method_name) VALUES
    ('Credit Card'),
    ('Bank Transfer'),
    ('PayPal')
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.payment_statuses (status_name) VALUES
    ('Pending'),
    ('Completed'),
    ('Failed'),
    ('Refunded')
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.orders_status_types (status_name) VALUES
    ('Placed'),
    ('Confirmed'),
    ('Shipped'),
    ('Delivered'),
    ('Cancelled')
ON CONFLICT DO NOTHING;

-- Categories (self-referencing — parents before children)
INSERT INTO marketplace.categories (name, description, parent_category_id) VALUES
    ('Electronics',  'Electronic devices and accessories', NULL),
    ('Home & Garden','Products for home and garden',       NULL)
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.categories (name, description, parent_category_id) VALUES
    ('Phones',   'Mobile phones and smartphones',
        (SELECT category_id FROM marketplace.categories WHERE name = 'Electronics')),
    ('Laptops',  'Laptops and notebooks',
        (SELECT category_id FROM marketplace.categories WHERE name = 'Electronics')),
    ('Plants',   'Indoor and outdoor plants',
        (SELECT category_id FROM marketplace.categories WHERE name = 'Home & Garden'))
ON CONFLICT DO NOTHING;

-- Users
INSERT INTO marketplace.users (email, first_name, last_name, phone, is_active) VALUES
    ('davitking@gmail.com',  'Davit',   'Bagrationi',  '+995555000001', TRUE),
    ('lukacrazy@gmail.com',  'Khvicha', 'Kvaratskhelia','+995555000002', TRUE),
    ('nino@edu.ge',          'Ilia',    'Topuria',     '+995555000003', FALSE),
    ('buyer1@gmail.com',     'Ana',     'Gelashvili',  NULL,            TRUE),
    ('buyer2@gmail.com',     'Giorgi',  'Beridze',     '+995555000005', TRUE)
ON CONFLICT DO NOTHING;

-- Sellers (user_id looked up by email — no hardcoded IDs)
INSERT INTO marketplace.sellers (user_id, store_name, store_description, is_verified)
SELECT user_id, 'Davit''s Boutique', 'Handmade and vintage items', TRUE
FROM marketplace.users WHERE email = 'davitking@gmail.com'
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.sellers (user_id, store_name, store_description, is_verified)
SELECT user_id, 'Luka Tech Store', 'Latest electronics and gadgets', FALSE
FROM marketplace.users WHERE email = 'lukacrazy@gmail.com'
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.sellers (user_id, store_name, store_description, is_verified)
SELECT user_id, 'Ilia''s Garden', 'Handmade pots and plants', TRUE
FROM marketplace.users WHERE email = 'nino@edu.ge'
ON CONFLICT DO NOTHING;

-- Addresses
INSERT INTO marketplace.addresses (user_id, street, city, country, postal_code)
SELECT user_id, 'Rustaveli Ave 1', 'Tbilisi', 'Georgia', '0108'
FROM marketplace.users WHERE email = 'davitking@gmail.com'
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.addresses (user_id, street, city, country, postal_code)
SELECT user_id, 'Chavchavadze Ave 45', 'Tbilisi', 'Georgia', '0162'
FROM marketplace.users WHERE email = 'buyer1@gmail.com'
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.addresses (user_id, street, city, country, postal_code)
SELECT user_id, 'Kostava St 77', 'Tbilisi', 'Georgia', '0171'
FROM marketplace.users WHERE email = 'buyer2@gmail.com'
ON CONFLICT DO NOTHING;

-- Products (seller_id and category_id looked up dynamically)
INSERT INTO marketplace.products (seller_id, category_id, name, price, is_active)
SELECT
    (SELECT seller_id FROM marketplace.sellers WHERE store_name = 'Luka Tech Store'),
    (SELECT category_id FROM marketplace.categories WHERE name = 'Phones'),
    'Samsung Galaxy A55', 699.00, TRUE
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.products (seller_id, category_id, name, price, is_active)
SELECT
    (SELECT seller_id FROM marketplace.sellers WHERE store_name = 'Davit''s Boutique'),
    (SELECT category_id FROM marketplace.categories WHERE name = 'Laptops'),
    'MacBook Air M2', 2000.00, TRUE
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.products (seller_id, category_id, name, price, is_active)
SELECT
    (SELECT seller_id FROM marketplace.sellers WHERE store_name = 'Ilia''s Garden'),
    (SELECT category_id FROM marketplace.categories WHERE name = 'Plants'),
    'Handmade Plant Pot', 23.29, TRUE
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.products (seller_id, category_id, name, price, is_active)
SELECT
    (SELECT seller_id FROM marketplace.sellers WHERE store_name = 'Luka Tech Store'),
    (SELECT category_id FROM marketplace.categories WHERE name = 'Laptops'),
    'Lenovo ThinkPad X1', 1500.00, TRUE
ON CONFLICT DO NOTHING;

-- Inventory (one record per product)
INSERT INTO marketplace.inventory (product_id, quantity_available, quantity_reserved)
SELECT product_id, 50, 2 FROM marketplace.products WHERE name = 'Samsung Galaxy A55'
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.inventory (product_id, quantity_available, quantity_reserved)
SELECT product_id, 4, 1 FROM marketplace.products WHERE name = 'MacBook Air M2'
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.inventory (product_id, quantity_available, quantity_reserved)
SELECT product_id, 23, 0 FROM marketplace.products WHERE name = 'Handmade Plant Pot'
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.inventory (product_id, quantity_available, quantity_reserved)
SELECT product_id, 10, 0 FROM marketplace.products WHERE name = 'Lenovo ThinkPad X1'
ON CONFLICT DO NOTHING;

-- Promotions
INSERT INTO marketplace.promotions (code, discount_type, discount_value, valid_from, valid_to, is_active)
VALUES
    ('SAVE10',  'percentage',  10.00, '2024-04-01 00:00:00', '2024-04-30 23:59:59', TRUE),
    ('SAVE100', 'fixed_amount',100.00,'2024-05-01 00:00:00', '2024-05-15 23:59:59', TRUE)
ON CONFLICT DO NOTHING;

-- Orders
INSERT INTO marketplace.orders (user_id, address_id, total_amount, ordered_at)
SELECT
    (SELECT user_id FROM marketplace.users WHERE email = 'buyer1@gmail.com'),
    (SELECT address_id FROM marketplace.addresses WHERE street = 'Chavchavadze Ave 45'),
    699.00,
    '2024-03-10 14:22:00'
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.orders
    WHERE user_id = (SELECT user_id FROM marketplace.users WHERE email = 'buyer1@gmail.com')
      AND ordered_at = '2024-03-10 14:22:00'
);

INSERT INTO marketplace.orders (user_id, address_id, total_amount, ordered_at)
SELECT
    (SELECT user_id FROM marketplace.users WHERE email = 'buyer2@gmail.com'),
    (SELECT address_id FROM marketplace.addresses WHERE street = 'Kostava St 77'),
    1800.00,
    '2024-04-01 09:05:00'
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.orders
    WHERE user_id = (SELECT user_id FROM marketplace.users WHERE email = 'buyer2@gmail.com')
      AND ordered_at = '2024-04-01 09:05:00'
);

INSERT INTO marketplace.orders (user_id, address_id, total_amount, ordered_at)
SELECT
    (SELECT user_id FROM marketplace.users WHERE email = 'buyer1@gmail.com'),
    (SELECT address_id FROM marketplace.addresses WHERE street = 'Chavchavadze Ave 45'),
    23.29,
    '2024-05-02 11:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.orders
    WHERE user_id = (SELECT user_id FROM marketplace.users WHERE email = 'buyer1@gmail.com')
      AND ordered_at = '2024-05-02 11:00:00'
);

-- Orders_Items
INSERT INTO marketplace.orders_items (order_id, product_id, promotion_id, quantity, price_at_order)
SELECT
    (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-03-10 14:22:00'),
    (SELECT product_id FROM marketplace.products WHERE name = 'Samsung Galaxy A55'),
    NULL,
    1,
    699.00
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.orders_items
    WHERE order_id  = (SELECT order_id  FROM marketplace.orders  WHERE ordered_at = '2024-03-10 14:22:00')
      AND product_id = (SELECT product_id FROM marketplace.products WHERE name = 'Samsung Galaxy A55')
);

INSERT INTO marketplace.orders_items (order_id, product_id, promotion_id, quantity, price_at_order)
SELECT
    (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-04-01 09:05:00'),
    (SELECT product_id FROM marketplace.products WHERE name = 'MacBook Air M2'),
    (SELECT promotion_id FROM marketplace.promotions WHERE code = 'SAVE10'),
    1,
    1800.00
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.orders_items
    WHERE order_id  = (SELECT order_id  FROM marketplace.orders  WHERE ordered_at = '2024-04-01 09:05:00')
      AND product_id = (SELECT product_id FROM marketplace.products WHERE name = 'MacBook Air M2')
);

INSERT INTO marketplace.orders_items (order_id, product_id, promotion_id, quantity, price_at_order)
SELECT
    (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-05-02 11:00:00'),
    (SELECT product_id FROM marketplace.products WHERE name = 'Handmade Plant Pot'),
    NULL,
    1,
    23.29
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.orders_items
    WHERE order_id  = (SELECT order_id  FROM marketplace.orders  WHERE ordered_at = '2024-05-02 11:00:00')
      AND product_id = (SELECT product_id FROM marketplace.products WHERE name = 'Handmade Plant Pot')
);

-- Payments
INSERT INTO marketplace.payments (order_id, payment_method_id, payment_status_id, amount, paid_at)
SELECT
    (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-03-10 14:22:00'),
    (SELECT payment_method_id FROM marketplace.payment_methods WHERE method_name = 'Credit Card'),
    (SELECT payment_status_id FROM marketplace.payment_statuses WHERE status_name = 'Completed'),
    699.00,
    '2024-03-10 14:25:00'
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.payments (order_id, payment_method_id, payment_status_id, amount, paid_at)
SELECT
    (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-04-01 09:05:00'),
    (SELECT payment_method_id FROM marketplace.payment_methods WHERE method_name = 'Bank Transfer'),
    (SELECT payment_status_id FROM marketplace.payment_statuses WHERE status_name = 'Pending'),
    1800.00,
    NULL
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.payments (order_id, payment_method_id, payment_status_id, amount, paid_at)
SELECT
    (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-05-02 11:00:00'),
    (SELECT payment_method_id FROM marketplace.payment_methods WHERE method_name = 'PayPal'),
    (SELECT payment_status_id FROM marketplace.payment_statuses WHERE status_name = 'Completed'),
    23.29,
    '2024-05-02 11:05:00'
ON CONFLICT DO NOTHING;

-- Deliveries
INSERT INTO marketplace.deliveries (order_id, carrier, tracking_number, dispatched_at, delivered_at)
SELECT
    (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-03-10 14:22:00'),
    'Georgian Post', 'GP123456789GE',
    '2024-03-11 09:30:00', '2024-03-13 14:00:00'
ON CONFLICT DO NOTHING;

INSERT INTO marketplace.deliveries (order_id, carrier, tracking_number, dispatched_at, delivered_at)
SELECT
    (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-04-01 09:05:00'),
    'Georgian Post', 'AM67638X78798',
    '2024-04-02 10:00:00', NULL
ON CONFLICT DO NOTHING;

-- Orders_Statuses (append-only — full status history per order)
INSERT INTO marketplace.orders_statuses (order_id, order_status_type_id, changed_at, note)
SELECT
    (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-03-10 14:22:00'),
    (SELECT order_status_type_id FROM marketplace.orders_status_types WHERE status_name = 'Placed'),
    '2024-03-10 14:22:00', NULL
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.orders_statuses
    WHERE order_id = (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-03-10 14:22:00')
      AND order_status_type_id = (SELECT order_status_type_id FROM marketplace.orders_status_types WHERE status_name = 'Placed')
);

INSERT INTO marketplace.orders_statuses (order_id, order_status_type_id, changed_at, note)
SELECT
    (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-03-10 14:22:00'),
    (SELECT order_status_type_id FROM marketplace.orders_status_types WHERE status_name = 'Confirmed'),
    '2024-03-10 15:00:00', 'Dispatched via Georgian Post'
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.orders_statuses
    WHERE order_id = (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-03-10 14:22:00')
      AND order_status_type_id = (SELECT order_status_type_id FROM marketplace.orders_status_types WHERE status_name = 'Confirmed')
);

INSERT INTO marketplace.orders_statuses (order_id, order_status_type_id, changed_at, note)
SELECT
    (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-03-10 14:22:00'),
    (SELECT order_status_type_id FROM marketplace.orders_status_types WHERE status_name = 'Delivered'),
    '2024-03-13 14:00:00', NULL
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.orders_statuses
    WHERE order_id = (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-03-10 14:22:00')
      AND order_status_type_id = (SELECT order_status_type_id FROM marketplace.orders_status_types WHERE status_name = 'Delivered')
);

INSERT INTO marketplace.orders_statuses (order_id, order_status_type_id, changed_at, note)
SELECT
    (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-04-01 09:05:00'),
    (SELECT order_status_type_id FROM marketplace.orders_status_types WHERE status_name = 'Placed'),
    '2024-04-01 09:05:00', NULL
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.orders_statuses
    WHERE order_id = (SELECT order_id FROM marketplace.orders WHERE ordered_at = '2024-04-01 09:05:00')
      AND order_status_type_id = (SELECT order_status_type_id FROM marketplace.orders_status_types WHERE status_name = 'Placed')
);

-- Reviews
INSERT INTO marketplace.reviews (order_item_id, product_id, user_id, rating, comment, reviewed_at)
SELECT
    (SELECT oi.order_item_id FROM marketplace.orders_items oi
     JOIN marketplace.orders o ON o.order_id = oi.order_id
     WHERE o.ordered_at = '2024-03-10 14:22:00'
       AND oi.product_id = (SELECT product_id FROM marketplace.products WHERE name = 'Samsung Galaxy A55')),
    (SELECT product_id FROM marketplace.products WHERE name = 'Samsung Galaxy A55'),
    (SELECT user_id FROM marketplace.users WHERE email = 'buyer1@gmail.com'),
    3,
    'Bad service',
    '2024-03-14 10:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.reviews
    WHERE order_item_id = (
        SELECT oi.order_item_id FROM marketplace.orders_items oi
        JOIN marketplace.orders o ON o.order_id = oi.order_id
        WHERE o.ordered_at = '2024-03-10 14:22:00'
          AND oi.product_id = (SELECT product_id FROM marketplace.products WHERE name = 'Samsung Galaxy A55')
    )
);

INSERT INTO marketplace.reviews (order_item_id, product_id, user_id, rating, comment, reviewed_at)
SELECT
    (SELECT oi.order_item_id FROM marketplace.orders_items oi
     JOIN marketplace.orders o ON o.order_id = oi.order_id
     WHERE o.ordered_at = '2024-04-01 09:05:00'
       AND oi.product_id = (SELECT product_id FROM marketplace.products WHERE name = 'MacBook Air M2')),
    (SELECT product_id FROM marketplace.products WHERE name = 'MacBook Air M2'),
    (SELECT user_id FROM marketplace.users WHERE email = 'buyer2@gmail.com'),
    5,
    'Excellent laptop, minor packaging issue.',
    '2024-04-10 09:00:00'
WHERE NOT EXISTS (
    SELECT 1 FROM marketplace.reviews
    WHERE order_item_id = (
        SELECT oi.order_item_id FROM marketplace.orders_items oi
        JOIN marketplace.orders o ON o.order_id = oi.order_id
        WHERE o.ordered_at = '2024-04-01 09:05:00'
          AND oi.product_id = (SELECT product_id FROM marketplace.products WHERE name = 'MacBook Air M2')
    )
);




----------------------------------------------------
--checking tables 

SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'marketplace'
ORDER BY table_name;

SELECT 'users'    AS tbl, COUNT(*) AS total, COUNT(record_ts) AS with_ts FROM marketplace.users
UNION ALL
SELECT 'products',  COUNT(*), COUNT(record_ts) FROM marketplace.products
UNION ALL
SELECT 'orders',    COUNT(*), COUNT(record_ts) FROM marketplace.orders;




-- Check record_ts was set on all rows:

SELECT 'users' AS tbl, COUNT(*) AS total, COUNT(record_ts) AS with_ts 
FROM marketplace.users
UNION ALL
SELECT 'products', COUNT(*), COUNT(record_ts) FROM marketplace.products
UNION ALL
SELECT 'orders',   COUNT(*), COUNT(record_ts) FROM marketplace.orders;
SELECT 'deliveries',           COUNT(*) FROM marketplace.deliveries
UNION ALL
SELECT 'orders_statuses',      COUNT(*) FROM marketplace.orders_statuses
UNION ALL
SELECT 'reviews',              COUNT(*) FROM marketplace.reviews
UNION ALL
SELECT 'promotions',           COUNT(*) FROM marketplace.promotions
UNION ALL
SELECT 'payment_methods',      COUNT(*) FROM marketplace.payment_methods
UNION ALL
SELECT 'payment_statuses',     COUNT(*) FROM marketplace.payment_statuses
UNION ALL
SELECT 'orders_status_types',  COUNT(*) FROM marketplace.orders_status_types;



