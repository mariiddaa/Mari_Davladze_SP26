
-- =============================================================================
-- SUBTASK 1: INSERT 3 FILMS INTO public.film
-- =============================================================================
-- WHY A SEPARATE TRANSACTION:
--   Films must exist before actors, inventory, and rentals can reference them.
--   Isolating this block means if it fails, nothing else is affected.
--
-- WHAT HAPPENS IF TRANSACTION FAILS:
--   No films are inserted. All subsequent subtasks would also fail since
--   they depend on these film_ids. Safe to re-run after fixing the error.
--
-- ROLLBACK: Possible — until COMMIT is reached, all inserts can be rolled back.
--
-- HOW DUPLICATES ARE AVOIDED:
--   WHERE NOT EXISTS checks if a film with the same title already exists.
--   If it does, the INSERT is skipped entirely. Script is safe to re-run.
--
-- WHY INSERT INTO ... SELECT INSTEAD OF INSERT INTO ... VALUES:
--   SELECT allows us to dynamically look up language_id by name ('English')
--   instead of hardcoding the number 1. This makes the script portable —
--   it works correctly even if language_id differs in another environment.
--
-- RELATIONSHIPS ESTABLISHED:
--   film.language_id → public.language (looked up dynamically by name)
-- =============================================================================

-- PRE-CHECK: Verify language table and confirm films don't exist yet
SELECT language_id, name FROM public.language;

SELECT film_id, title, release_year, rental_duration, rental_rate
FROM public.film
WHERE title IN ('Past Lives', 'Little Miss Sunshine', 'Gone Girl');

BEGIN;

INSERT INTO public.film (
    title, description, release_year, language_id,
    rental_duration, rental_rate, replacement_cost, rating, last_update
)
SELECT
    'Past Lives',
    'Two childhood sweethearts in South Korea are separated and reunite years later in New York City.',
    2023,
    (SELECT language_id FROM public.language WHERE name = 'English'), -- dynamic lookup, no hardcoded ID
    3,       -- rental_duration: 3 weeks 
    19.99,   -- rental_rate
    24.99,   -- replacement_cost
    'PG-13', -- rating
    CURRENT_DATE -- last_update set to current date
WHERE NOT EXISTS (
    -- UNIQUENESS: skip insert if film with this title already exists
    SELECT 1 FROM public.film WHERE title = 'Past Lives'
)
RETURNING film_id, title, rental_duration, rental_rate; -- confirm what was inserted

INSERT INTO public.film (
    title, description, release_year, language_id,
    rental_duration, rental_rate, replacement_cost, rating, last_update
)
SELECT
    'Little Miss Sunshine',
    'A dysfunctional family road trip to help their daughter compete in a beauty pageant.',
    2006,
    (SELECT language_id FROM public.language WHERE name = 'English'),
    1,       -- rental_duration: 1 week 
    4.99,
    19.99,
    'R',
    CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM public.film WHERE title = 'Little Miss Sunshine'
)
RETURNING film_id, title, rental_duration, rental_rate;

INSERT INTO public.film (
    title, description, release_year, language_id,
    rental_duration, rental_rate, replacement_cost, rating, last_update
)
SELECT
    'Gone Girl',
    'A man becomes the prime suspect in the mysterious disappearance of his wife.',
    2014,
    (SELECT language_id FROM public.language WHERE name = 'English'),
    2,       -- rental_duration: 2 weeks 
    9.99,
    24.99,
    'R',
    CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM public.film WHERE title = 'Gone Girl'
)
RETURNING film_id, title, rental_duration, rental_rate;

COMMIT;

-- POST-CHECK: Verify all 3 films were inserted correctly
SELECT film_id, title, release_year, rental_duration, rental_rate, rating, last_update
FROM public.film
WHERE title IN ('Past Lives', 'Little Miss Sunshine', 'Gone Girl');


-- =============================================================================
-- SUBTASK 2: INSERT ACTORS INTO public.actor AND LINK TO FILMS IN public.film_actor
-- =============================================================================
-- WHY A SEPARATE TRANSACTION:
--   Actors and their film links are logically one unit. If actor inserts
--   succeed but film_actor links fail, we'd have orphaned actors. Keeping
--   them in one transaction ensures both succeed or both roll back together.
--
-- WHAT HAPPENS IF TRANSACTION FAILS:
--   No actors are inserted and no film_actor links are created.
--   Previously committed films are unaffected. Safe to re-run.
--
-- ROLLBACK: Possible — until COMMIT, all actor and film_actor inserts roll back.
--
-- HOW DUPLICATES ARE AVOIDED:
--   Actors: ON CONFLICT DO NOTHING skips insert if actor already exists.
--   film_actor: WHERE NOT EXISTS checks if the (actor_id, film_id) pair
--   already exists before inserting. Prevents duplicate links.
--
-- RELATIONSHIPS ESTABLISHED:
--   film_actor.actor_id → public.actor (looked up by first_name + last_name)
--   film_actor.film_id  → public.film  (looked up by title)
--   Both foreign keys are resolved dynamically — no hardcoded IDs.
--
-- HOW REFERENTIAL INTEGRITY IS PRESERVED:
--   film_actor rows reference valid actor_id and film_id values that were
--   just inserted above in this same transaction. If either lookup returns
--   NULL (film or actor not found), the insert is skipped safely.
-- =============================================================================

-- PRE-CHECK: Confirm none of our actors already exist in the database
SELECT actor_id, first_name, last_name
FROM public.actor
WHERE (first_name = 'Greta'    AND last_name = 'Lee')
   OR (first_name = 'Teo'      AND last_name = 'Yoo')
   OR (first_name = 'Steve'    AND last_name = 'Carell')
   OR (first_name = 'Alan'     AND last_name = 'Arkin')
   OR (first_name = 'Rosamund' AND last_name = 'Pike')
   OR (first_name = 'Ben'      AND last_name = 'Affleck');

BEGIN;

-- Insert 6 actors — ON CONFLICT DO NOTHING prevents duplicates on re-run
INSERT INTO public.actor (first_name, last_name, last_update)
VALUES
    ('Greta',     'Lee',     CURRENT_DATE),
    ('Teo',       'Yoo',     CURRENT_DATE),
    ('Steve',     'Carell',  CURRENT_DATE),
    ('Alan',      'Arkin',   CURRENT_DATE),
    ('Rosamund',  'Pike',    CURRENT_DATE),
    ('Ben',       'Affleck', CURRENT_DATE)
ON CONFLICT DO NOTHING
RETURNING actor_id, first_name, last_name;

-- Link actors to films using dynamic lookups (no hardcoded IDs)
-- Past Lives → Greta Lee
INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT
    (SELECT actor_id FROM public.actor WHERE first_name = 'Greta' AND last_name = 'Lee'),
    (SELECT film_id  FROM public.film  WHERE title = 'Past Lives'),
    CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM public.film_actor
    WHERE actor_id = (SELECT actor_id FROM public.actor WHERE first_name = 'Greta' AND last_name = 'Lee')
      AND film_id  = (SELECT film_id  FROM public.film  WHERE title = 'Past Lives')
)
RETURNING actor_id, film_id;

-- Past Lives → Teo Yoo
INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT
    (SELECT actor_id FROM public.actor WHERE first_name = 'Teo' AND last_name = 'Yoo'),
    (SELECT film_id  FROM public.film  WHERE title = 'Past Lives'),
    CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM public.film_actor
    WHERE actor_id = (SELECT actor_id FROM public.actor WHERE first_name = 'Teo' AND last_name = 'Yoo')
      AND film_id  = (SELECT film_id  FROM public.film  WHERE title = 'Past Lives')
)
RETURNING actor_id, film_id;

-- Little Miss Sunshine → Steve Carell
INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT
    (SELECT actor_id FROM public.actor WHERE first_name = 'Steve' AND last_name = 'Carell'),
    (SELECT film_id  FROM public.film  WHERE title = 'Little Miss Sunshine'),
    CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM public.film_actor
    WHERE actor_id = (SELECT actor_id FROM public.actor WHERE first_name = 'Steve' AND last_name = 'Carell')
      AND film_id  = (SELECT film_id  FROM public.film  WHERE title = 'Little Miss Sunshine')
)
RETURNING actor_id, film_id;

-- Little Miss Sunshine → Alan Arkin
INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT
    (SELECT actor_id FROM public.actor WHERE first_name = 'Alan' AND last_name = 'Arkin'),
    (SELECT film_id  FROM public.film  WHERE title = 'Little Miss Sunshine'),
    CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM public.film_actor
    WHERE actor_id = (SELECT actor_id FROM public.actor WHERE first_name = 'Alan' AND last_name = 'Arkin')
      AND film_id  = (SELECT film_id  FROM public.film  WHERE title = 'Little Miss Sunshine')
)
RETURNING actor_id, film_id;

-- Gone Girl → Rosamund Pike
INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT
    (SELECT actor_id FROM public.actor WHERE first_name = 'Rosamund' AND last_name = 'Pike'),
    (SELECT film_id  FROM public.film  WHERE title = 'Gone Girl'),
    CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM public.film_actor
    WHERE actor_id = (SELECT actor_id FROM public.actor WHERE first_name = 'Rosamund' AND last_name = 'Pike')
      AND film_id  = (SELECT film_id  FROM public.film  WHERE title = 'Gone Girl')
)
RETURNING actor_id, film_id;

-- Gone Girl → Ben Affleck
INSERT INTO public.film_actor (actor_id, film_id, last_update)
SELECT
    (SELECT actor_id FROM public.actor WHERE first_name = 'Ben' AND last_name = 'Affleck'),
    (SELECT film_id  FROM public.film  WHERE title = 'Gone Girl'),
    CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM public.film_actor
    WHERE actor_id = (SELECT actor_id FROM public.actor WHERE first_name = 'Ben' AND last_name = 'Affleck')
      AND film_id  = (SELECT film_id  FROM public.film  WHERE title = 'Gone Girl')
)
RETURNING actor_id, film_id;

COMMIT;

-- POST-CHECK: Verify all actor-film links were created correctly
SELECT a.actor_id, a.first_name, a.last_name, f.title
FROM public.film_actor fa
JOIN public.actor a ON a.actor_id = fa.actor_id
JOIN public.film  f ON f.film_id  = fa.film_id
WHERE f.title IN ('Past Lives', 'Little Miss Sunshine', 'Gone Girl')
ORDER BY f.title;


-- =============================================================================
-- SUBTASK 3: ADD FILMS TO STORE INVENTORY (public.inventory)
-- =============================================================================
-- WHY A SEPARATE TRANSACTION:
--   Inventory must be committed before rentals can reference inventory_id.
--   Isolating this block ensures inventory exists before Subtask 6 runs.
--
-- WHAT HAPPENS IF TRANSACTION FAILS:
--   No inventory rows are created. Rentals in Subtask 6 would fail.
--   Films and actors already committed are unaffected. Safe to re-run.
--
-- ROLLBACK: Possible — until COMMIT, all inventory inserts roll back.
--
-- HOW DUPLICATES ARE AVOIDED:
--   WHERE NOT EXISTS checks if copies of the film already exist in store 1.
--   If they do, the entire insert for that film is skipped.
--
-- RELATIONSHIPS ESTABLISHED:
--   inventory.film_id  → public.film  (looked up dynamically by title)
--   inventory.store_id → public.store (store_id = 1, verified to exist)
-- =============================================================================

-- PRE-CHECK: Confirm stores exist and films are not yet in inventory
SELECT store_id FROM public.store;

SELECT i.inventory_id, f.title, i.store_id
FROM public.inventory i
JOIN public.film f ON f.film_id = i.film_id
WHERE f.title IN ('Past Lives', 'Little Miss Sunshine', 'Gone Girl');

BEGIN;

-- CROSS JOIN generate_series(1,2) creates 2 copies of each film
-- film_id is looked up dynamically by title — no hardcoded IDs
INSERT INTO public.inventory (film_id, store_id, last_update)
SELECT f.film_id, 1, CURRENT_DATE
FROM public.film f
CROSS JOIN generate_series(1, 2) -- 2 copies per film
WHERE f.title IN ('Past Lives', 'Little Miss Sunshine', 'Gone Girl')
  AND NOT EXISTS (
      -- UNIQUENESS: skip if this film already has inventory in store 1
      SELECT 1 FROM public.inventory i
      WHERE i.film_id = f.film_id AND i.store_id = 1
  )
RETURNING inventory_id, film_id, store_id;

COMMIT;

-- POST-CHECK: Verify 6 inventory rows exist (2 per film)
SELECT i.inventory_id, f.title, i.store_id
FROM public.inventory i
JOIN public.film f ON f.film_id = i.film_id
WHERE f.title IN ('Past Lives', 'Little Miss Sunshine', 'Gone Girl')
ORDER BY f.title;


-- =============================================================================
-- SUBTASK 4: UPDATE EXISTING CUSTOMER TO MARI DAVLADZE
-- =============================================================================
-- WHY A SEPARATE TRANSACTION:
--   Customer update is independent of film/actor inserts. If this fails,
--   we still have valid films and inventory. Easier to retry in isolation.
--
-- WHAT HAPPENS IF TRANSACTION FAILS:
--   Customer record stays as Eleanor Hunt. No data is lost or corrupted.
--   Safe to re-run after identifying the issue.
--
-- ROLLBACK: Possible — UPDATE is rolled back if transaction fails before COMMIT.
--
-- HOW REFERENTIAL INTEGRITY IS PRESERVED:
--   We do NOT change customer_id — only personal details (name, email, address).
--   All 92 existing rental and payment records still reference customer_id = 148
--   and remain valid. address_id = 1 references an existing row in public.address.
--
-- NOTE: We deliberately do NOT update the address table as instructed —
--   we only reassign which existing address this customer points to.
-- =============================================================================

-- PRE-CHECK: Find customer with at least 43 rentals AND 43 payments
SELECT
    c.customer_id, c.first_name, c.last_name, c.email,
    COUNT(DISTINCT r.rental_id)  AS rental_count,
    COUNT(DISTINCT p.payment_id) AS payment_count
FROM public.customer c
JOIN public.rental  r ON r.customer_id = c.customer_id
JOIN public.payment p ON p.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.email
HAVING COUNT(DISTINCT r.rental_id)  >= 43
   AND COUNT(DISTINCT p.payment_id) >= 43
ORDER BY rental_count DESC
LIMIT 5;

-- PRE-CHECK: See Eleanor's current details before updating
SELECT customer_id, first_name, last_name, email, address_id, active
FROM public.customer
WHERE customer_id = 148;

BEGIN;

-- UPDATE personal data only — customer_id stays the same to preserve FK links
UPDATE public.customer
SET
    first_name  = 'Mari',
    last_name   = 'Davladze',
    email       = 'maridavladze20@gmail.com',
    address_id  = 1,          -- existing address, no changes to address table
    active      = 1,
    last_update = CURRENT_DATE
WHERE customer_id = 148
RETURNING customer_id, first_name, last_name, email, address_id, last_update;

COMMIT;

-- POST-CHECK: Confirm update was applied correctly
SELECT customer_id, first_name, last_name, email, address_id, active, last_update
FROM public.customer
WHERE customer_id = 148;


-- =============================================================================
-- SUBTASK 5: DELETE ELEANOR'S RENTAL AND PAYMENT RECORDS
-- =============================================================================
-- WHY A SEPARATE TRANSACTION:
--   Deletes are high-risk operations. Isolating them lets us verify with
--   SELECT before committing, and roll back if anything looks wrong.
--
-- WHAT HAPPENS IF TRANSACTION FAILS:
--   No records are deleted. Data remains intact. Safe to re-run.
--
-- ROLLBACK: Possible — until COMMIT, all deletes can be rolled back.
--
-- WHY DELETING IS SAFE:
--   We delete ONLY records belonging to customer_id = 148.
--   We do NOT touch: customer, inventory, film, actor, or film_actor tables.
--   The customer record itself is preserved as instructed.
--
-- HOW REFERENTIAL INTEGRITY IS PRESERVED:
--   payment.rental_id references rental.rental_id (FK dependency).
--   We MUST delete payments first, then rentals.
--   If we deleted rentals first, the DB would reject it due to FK violation.
--
-- HOW NO UNINTENDED DATA LOSS OCCURS:
--   WHERE customer_id = 148 ensures we only touch Mari's records.
--   Pre-check SELECT confirms exact count before deletion.
--   No other customers are affected.
-- =============================================================================

-- PRE-CHECK: Count records before deleting — must match expectations
SELECT 'payment' AS table_name, COUNT(*) AS record_count
FROM public.payment
WHERE customer_id = 148
UNION ALL
SELECT 'rental', COUNT(*)
FROM public.rental
WHERE customer_id = 148;

BEGIN;

-- Step 1: Delete payments FIRST (FK: payment.rental_id → rental.rental_id)
-- Payments must go before rentals to avoid FK constraint violation
DELETE FROM public.payment
WHERE customer_id = 148
RETURNING payment_id;

-- Step 2: Delete rentals AFTER payments are gone
DELETE FROM public.rental
WHERE customer_id = 148
RETURNING rental_id;

COMMIT;

-- POST-CHECK: Confirm both tables now show 0 records for customer 148
SELECT 'payment' AS table_name, COUNT(*) AS record_count
FROM public.payment
WHERE customer_id = 148
UNION ALL
SELECT 'rental', COUNT(*)
FROM public.rental
WHERE customer_id = 148;


-- =============================================================================
-- SUBTASK 6: RENT FAVORITE FILMS AND ADD PAYMENT RECORDS
-- =============================================================================
-- WHY A SEPARATE TRANSACTION:
--   Rentals and payments are tightly coupled — each payment must reference
--   a valid rental_id. Keeping them in one transaction ensures if any
--   payment insert fails, the corresponding rental is also rolled back,
--   preventing orphaned rental records with no payment.
--
-- WHAT HAPPENS IF TRANSACTION FAILS:
--   No rentals or payments are inserted. Inventory and customer records
--   are unaffected. Safe to re-run.
--
-- ROLLBACK: Possible — until COMMIT, all rentals and payments roll back together.
--
-- HOW DUPLICATES ARE AVOIDED:
--   Rental: WHERE NOT EXISTS checks if Mari already has a rental for that
--   specific inventory_id. Prevents renting the same copy twice.
--   Payment: WHERE NOT EXISTS checks if a payment already exists for that
--   rental_id. Prevents double-charging.
--
-- RELATIONSHIPS ESTABLISHED:
--   rental.inventory_id → public.inventory (specific copy of the film)
--   rental.customer_id  → public.customer  (Mari, customer_id = 148)
--   rental.staff_id     → public.staff     (staff_id = 1)
--   payment.rental_id   → public.rental    (the rental just created above)
--   payment.customer_id → public.customer  (Mari, customer_id = 148)
--
-- WHY PAYMENT DATE IS 2017-01-15:
--   The payment table is partitioned by date. Existing partitions only
--   cover 2017. Using today's date (2026) would cause a partition error.
--
-- RETURN DATE CALCULATION:
--   rental_duration is stored in weeks in our film table.
--   return_date = rental_date + rental_duration * 7 days
-- =============================================================================

-- PRE-CHECK: Confirm inventory items are available for our films in store 1
SELECT i.inventory_id, f.title, f.rental_rate, f.rental_duration
FROM public.inventory i
JOIN public.film f ON f.film_id = i.film_id
WHERE f.title IN ('Past Lives', 'Little Miss Sunshine', 'Gone Girl')
  AND i.store_id = 1
ORDER BY f.title;

BEGIN;

-- RENT: Past Lives (inventory_id 4589)
INSERT INTO public.rental (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)
SELECT
    '2017-01-15 10:00:00',
    4589,
    148,
    -- return_date = rental_date + rental_duration weeks (dynamic lookup by title)
    '2017-01-15'::date + (SELECT rental_duration FROM public.film WHERE title = 'Past Lives') * INTERVAL '7 days',
    1,
    CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM public.rental WHERE inventory_id = 4589 AND customer_id = 148
)
RETURNING rental_id, inventory_id, customer_id, rental_date, return_date;

-- PAYMENT: Past Lives — amount looked up dynamically from film table
INSERT INTO public.payment (customer_id, staff_id, rental_id, amount, payment_date)
SELECT
    148,
    1,
    (SELECT rental_id FROM public.rental WHERE inventory_id = 4589 AND customer_id = 148),
    (SELECT rental_rate FROM public.film WHERE title = 'Past Lives'),
    '2017-01-15 10:05:00'
WHERE NOT EXISTS (
    SELECT 1 FROM public.payment
    WHERE rental_id = (SELECT rental_id FROM public.rental WHERE inventory_id = 4589 AND customer_id = 148)
)
RETURNING payment_id, rental_id, amount, payment_date;

-- RENT: Little Miss Sunshine (inventory_id 4587)
INSERT INTO public.rental (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)
SELECT
    '2017-01-15 10:10:00',
    4587,
    148,
    '2017-01-15'::date + (SELECT rental_duration FROM public.film WHERE title = 'Little Miss Sunshine') * INTERVAL '7 days',
    1,
    CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM public.rental WHERE inventory_id = 4587 AND customer_id = 148
)
RETURNING rental_id, inventory_id, customer_id, rental_date, return_date;

-- PAYMENT: Little Miss Sunshine
INSERT INTO public.payment (customer_id, staff_id, rental_id, amount, payment_date)
SELECT
    148,
    1,
    (SELECT rental_id FROM public.rental WHERE inventory_id = 4587 AND customer_id = 148),
    (SELECT rental_rate FROM public.film WHERE title = 'Little Miss Sunshine'),
    '2017-01-15 10:15:00'
WHERE NOT EXISTS (
    SELECT 1 FROM public.payment
    WHERE rental_id = (SELECT rental_id FROM public.rental WHERE inventory_id = 4587 AND customer_id = 148)
)
RETURNING payment_id, rental_id, amount, payment_date;

-- RENT: Gone Girl (inventory_id 4585)
INSERT INTO public.rental (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)
SELECT
    '2017-01-15 10:20:00',
    4585,
    148,
    '2017-01-15'::date + (SELECT rental_duration FROM public.film WHERE title = 'Gone Girl') * INTERVAL '7 days',
    1,
    CURRENT_DATE
WHERE NOT EXISTS (
    SELECT 1 FROM public.rental WHERE inventory_id = 4585 AND customer_id = 148
)
RETURNING rental_id, inventory_id, customer_id, rental_date, return_date;

-- PAYMENT: Gone Girl
INSERT INTO public.payment (customer_id, staff_id, rental_id, amount, payment_date)
SELECT
    148,
    1,
    (SELECT rental_id FROM public.rental WHERE inventory_id = 4585 AND customer_id = 148),
    (SELECT rental_rate FROM public.film WHERE title = 'Gone Girl'),
    '2017-01-15 10:25:00'
WHERE NOT EXISTS (
    SELECT 1 FROM public.payment
    WHERE rental_id = (SELECT rental_id FROM public.rental WHERE inventory_id = 4585 AND customer_id = 148)
)
RETURNING payment_id, rental_id, amount, payment_date;

COMMIT;

-- POST-CHECK: Verify all rentals and payments for Mari are correct
SELECT r.rental_id, f.title, r.rental_date, r.return_date
FROM public.rental r
JOIN public.inventory i ON i.inventory_id = r.inventory_id
JOIN public.film     f ON f.film_id       = i.film_id
WHERE r.customer_id = 148
ORDER BY r.rental_date;

SELECT p.payment_id, f.title, p.amount, p.payment_date
FROM public.payment  p
JOIN public.rental   r ON r.rental_id   = p.rental_id
JOIN public.inventory i ON i.inventory_id = r.inventory_id
JOIN public.film     f ON f.film_id       = i.film_id
WHERE p.customer_id = 148
ORDER BY p.payment_date;



