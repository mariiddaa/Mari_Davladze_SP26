-- ============================================================
-- TASK 2 – Role-Based Authentication Model
-- ============================================================
 
-- ----------------------------------------------------------
-- Step 1. Create user "rentaluser" with connect privilege only
-- ----------------------------------------------------------
CREATE USER rentaluser WITH PASSWORD 'rentalpassword';
 
-- Grant CONNECT to the database (run as superuser connected to dvdrental)
GRANT CONNECT ON DATABASE dvdrental TO rentaluser;
 
-- Verify: rentaluser has no table-level rights yet
-- (run as rentaluser -> should return permission denied)
-- SELECT * FROM customer;   -- Expected: ERROR: permission denied for table customer
 
 
-- ----------------------------------------------------------
-- Step 2. Grant SELECT on "customer" to rentaluser
-- ----------------------------------------------------------
GRANT SELECT ON TABLE customer TO rentaluser;
 
-- Verify (run as rentaluser):
SET ROLE rentaluser;
SELECT * FROM customer;          -- Expected: all rows visible
RESET ROLE;
 
 
-- ----------------------------------------------------------
-- Step 3. Create group role "rental" and add rentaluser
-- ----------------------------------------------------------
CREATE ROLE rental;
GRANT rental TO rentaluser;
 
 
-- ----------------------------------------------------------
-- Step 4. Grant INSERT and UPDATE on "rental" to group "rental"
--         Then insert a new row and update an existing one
-- ----------------------------------------------------------
GRANT INSERT, UPDATE ON TABLE rental TO rental;
 
-- Also grant USAGE on the sequence so INSERT can generate rental_id
GRANT USAGE, SELECT ON SEQUENCE rental_rental_id_seq TO rental;
 
-- Switch to rentaluser (who inherits the rental group permissions)
SET ROLE rentaluser;
 
-- INSERT a new rental row
INSERT INTO rental (rental_date, inventory_id, customer_id, staff_id, return_date)
VALUES (NOW(), 1, 1, 1, NOW() + INTERVAL '7 days');
 
-- UPDATE an existing rental row
UPDATE rental
SET return_date = NOW() + INTERVAL '14 days'
WHERE rental_id = (SELECT MIN(rental_id) FROM rental);
 
RESET ROLE;
 
 
-- ----------------------------------------------------------
-- Step 5. Revoke INSERT from "rental" group; verify denial
-- ----------------------------------------------------------
REVOKE INSERT ON TABLE rental FROM rental;
 
-- Attempt INSERT as rentaluser -> must fail
SET ROLE rentaluser;
 
-- Expected: ERROR: permission denied for table rental
INSERT INTO rental (rental_date, inventory_id, customer_id, staff_id, return_date)
VALUES (NOW(), 2, 2, 1, NOW() + INTERVAL '3 days');
 
RESET ROLE;
 
 
-- ----------------------------------------------------------
-- Step 6. Create a personalised role for an existing customer
--         who has both rental AND payment history.
--
--         Chosen customer: Mary Smith  (customer_id = 1)
--         Role name      : client_Mary_Smith
-- ----------------------------------------------------------
 
-- Confirm the customer has rental and payment history
SELECT c.customer_id, c.first_name, c.last_name,
       COUNT(DISTINCT r.rental_id)  AS rental_count,
       COUNT(DISTINCT p.payment_id) AS payment_count
FROM   customer  c
JOIN   rental    r ON r.customer_id  = c.customer_id
JOIN   payment   p ON p.customer_id  = c.customer_id
WHERE  c.customer_id = 1
GROUP  BY c.customer_id, c.first_name, c.last_name;
 
-- Create the personalised role (with login so we can SET ROLE to it easily)
CREATE ROLE client_Mary_Smith;
 
-- Grant CONNECT so the role can reach the DB if needed
GRANT CONNECT ON DATABASE dvdrental TO client_Mary_Smith;
 
-- RLS-restricted SELECT on rental and payment ( Task 3 below)
GRANT SELECT ON TABLE rental  TO client_Mary_Smith;
GRANT SELECT ON TABLE payment TO client_Mary_Smith;
 
 
-- ============================================================
-- TASK 3 – Row-Level Security
-- ============================================================
 
-- ----------------------------------------------------------
-- 3a. Enable RLS on rental and payment tables
-- ----------------------------------------------------------
ALTER TABLE rental  ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment ENABLE ROW LEVEL SECURITY;
 
-- IMPORTANT: by default, the table owner bypasses RLS.
-- Force RLS even for the owner (optional but shows correctness):
ALTER TABLE rental  FORCE ROW LEVEL SECURITY;
ALTER TABLE payment FORCE ROW LEVEL SECURITY;
 
 
-- ----------------------------------------------------------
-- 3b. Create policies
--
--     Strategy: store customer_id as a custom GUC variable
--     (app.current_customer_id) set at login / session start.
--     The policy compares the row's customer_id to this value.
-- ----------------------------------------------------------
 
-- Policy on rental
CREATE POLICY rental_own_rows ON rental
    FOR SELECT
    TO client_Mary_Smith
    USING (customer_id = current_setting('app.current_customer_id')::INTEGER);
 
-- Policy on payment
CREATE POLICY payment_own_rows ON payment
    FOR SELECT
    TO client_Mary_Smith
    USING (customer_id = current_setting('app.current_customer_id')::INTEGER);
 
 
-- ----------------------------------------------------------
-- 3c. Test: set the session variable to Mary Smith's id (1)
--     and switch role
-- ----------------------------------------------------------
SET ROLE client_Mary_Smith;
 
-- Set the customer context for this session
SET app.current_customer_id = '1';
 
--  Should return ONLY rows where customer_id = 1
SELECT rental_id, customer_id, rental_date, return_date
FROM   rental
LIMIT  10;
 
SELECT payment_id, customer_id, amount, payment_date
FROM   payment
LIMIT  10;
 
RESET ROLE;
 
 
-- ----------------------------------------------------------
-- 3d. Attempt to read another customer's rows (customer_id = 2)
--     while session is set to customer_id = 1
-- ----------------------------------------------------------
SET ROLE client_Mary_Smith;
SET app.current_customer_id = '1';
 
--  Should return 0 rows – RLS filters out customer 2
SELECT rental_id, customer_id
FROM   rental
WHERE  customer_id = 2;
 
-- Same for payment
SELECT payment_id, customer_id
FROM   payment
WHERE  customer_id = 2;
 
RESET ROLE;
-- Expected result: 0 rows returned (no error, just empty result set –
-- this is correct RLS behaviour; PostgreSQL silently hides filtered rows).