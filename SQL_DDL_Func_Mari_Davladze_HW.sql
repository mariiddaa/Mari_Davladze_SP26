-- ============================================================
-- TASK 1: View — sales_revenue_by_category_qtr
-- ============================================================
-- PURPOSE:
--   Shows total rental revenue per film category for the
--   *current* calendar quarter and year only.
--
-- HOW "CURRENT QUARTER" IS DETERMINED:
--   EXTRACT(QUARTER FROM CURRENT_DATE) returns 1-4.
--   EXTRACT(YEAR FROM CURRENT_DATE) returns the 4-digit year.
--   Both are evaluated at query time, so the view is fully
--   dynamic — no hardcoded dates, no manual refresh needed.
--   When January 1 of a new year arrives, YEAR flips automatically.
--   When April 1 arrives, QUARTER flips from 1 to 2 automatically.
--
-- WHY ONLY CATEGORIES WITH SALES APPEAR:
--   The join chain (payment → rental → inventory → film →
--   film_category → category) is an INNER JOIN, so categories
--   that have no matching payments in this quarter simply produce
--   no rows. The HAVING clause then additionally guards against
--   any edge-case group with SUM(amount) = 0 (e.g. fully refunded).
--
-- HOW ZERO-SALES CATEGORIES ARE EXCLUDED:
--   1. INNER JOINs — if no payment exists for a category this
--      quarter, no row makes it to the GROUP BY stage at all.
--   2. HAVING SUM(p.amount) > 0 — even if a row somehow
--      survived with zero total (e.g. all NULLs coerced to 0),
--      it would still be filtered out here.
--
-- CURRENT DATABASE NOTE:
--   The dvdrental database ships with data only up to 2007.
--   CURRENT_DATE in 2026 returns no matching rows because
--   payment_date values are all in 2005-2007.
--
-- HOW WE VERIFIED THE VIEW WORKS:
--   See Test Query 2 below — we simulate the dvdrental date
--   range by temporarily replacing CURRENT_DATE with a
--   hardcoded date inside the data range (e.g. '2007-04-15').
--   All categories with Q2-2007 payments appear correctly.
--   Categories with no Q2-2007 payments do not appear, which
--   confirms both the join filter and the HAVING filter work.
-- ============================================================

CREATE OR REPLACE VIEW sales_revenue_by_category_qtr AS
SELECT
    c.name                  AS category_name,
    SUM(p.amount)           AS total_sales_revenue,
    -- Include quarter/year in the view output for transparency
    EXTRACT(QUARTER FROM CURRENT_DATE)::INT  AS current_quarter,
    EXTRACT(YEAR   FROM CURRENT_DATE)::INT   AS current_year
FROM payment p
    -- payment → rental (one rental can have one payment)
    JOIN rental   r  ON r.rental_id   = p.rental_id
    -- rental → inventory (which physical disc was rented)
    JOIN inventory i  ON i.inventory_id = r.inventory_id
    -- inventory → film
    JOIN film      f  ON f.film_id      = i.film_id
    -- film → film_category (join table; a film belongs to one category here)
    JOIN film_category fc ON fc.film_id = f.film_id
    -- film_category → category (the human-readable name)
    JOIN category  c  ON c.category_id = fc.category_id
WHERE
    -- Dynamic quarter filter — updates automatically each quarter
    EXTRACT(YEAR    FROM p.payment_date) = EXTRACT(YEAR    FROM CURRENT_DATE)
    AND EXTRACT(QUARTER FROM p.payment_date) = EXTRACT(QUARTER FROM CURRENT_DATE)
GROUP BY
    c.name
HAVING
    -- Exclude categories where total revenue is zero or negative
    SUM(p.amount) > 0
ORDER BY
    total_sales_revenue DESC;


-- ============================================================
-- TEST QUERIES
-- ============================================================

-- ── TEST 1: Valid input — run against the live view ──────────
-- Because dvdrental only contains data through 2007, running this
-- in 2026 returns 0 rows (expected — not a bug).
-- This still validates that the view compiles and executes without error.

SELECT * FROM sales_revenue_by_category_qtr;

-- Expected result in 2026: 0 rows
-- Expected result if run in Q2 2007 (April–June 2007): all film
-- categories that had at least one completed rental payment that
-- quarter, sorted by revenue descending.


-- ── TEST 2: Simulated valid input — verify logic with dvdrental data ──
-- We temporarily rewrite the WHERE condition using a known date
-- inside the database's actual data range to confirm the view logic.
-- This is the recommended verification approach for this dataset.

SELECT
    c.name                  AS category_name,
    SUM(p.amount)           AS total_sales_revenue,
    2                       AS current_quarter,   -- Q2 = April–June
    2007                    AS current_year
FROM payment p
    JOIN rental       r  ON r.rental_id   = p.rental_id
    JOIN inventory    i  ON i.inventory_id = r.inventory_id
    JOIN film         f  ON f.film_id      = i.film_id
    JOIN film_category fc ON fc.film_id    = f.film_id
    JOIN category     c  ON c.category_id = fc.category_id
WHERE
    EXTRACT(YEAR    FROM p.payment_date) = 2007
    AND EXTRACT(QUARTER FROM p.payment_date) = 2
GROUP BY c.name
HAVING SUM(p.amount) > 0
ORDER BY total_sales_revenue DESC;

-- Expected: 16 rows (one per category that had Q2-2007 sales).
-- All 16 standard dvdrental categories should appear because
-- rentals were spread across all genres in that period.


-- ── TEST 3: Edge / invalid input — quarter with no data ──────
-- Simulate a quarter with zero activity to confirm nothing appears.
-- Q4 1990 has no payments — the view should return 0 rows.

SELECT
    c.name,
    SUM(p.amount) AS total_sales_revenue
FROM payment p
    JOIN rental       r  ON r.rental_id   = p.rental_id
    JOIN inventory    i  ON i.inventory_id = r.inventory_id
    JOIN film         f  ON f.film_id      = i.film_id
    JOIN film_category fc ON fc.film_id    = f.film_id
    JOIN category     c  ON c.category_id = fc.category_id
WHERE
    EXTRACT(YEAR    FROM p.payment_date) = 1990
    AND EXTRACT(QUARTER FROM p.payment_date) = 4
GROUP BY c.name
HAVING SUM(p.amount) > 0;

-- Expected: 0 rows.
-- Explanation: INNER JOINs produce no rows when payment_date
-- doesn't match, so HAVING never even fires. This is the correct
-- behaviour — the view stays empty rather than showing stale or
-- null data.


-- ============================================================
-- EDGE CASE DISCUSSION
-- ============================================================
-- Q: What if input parameters are incorrect?
-- A: This is a VIEW, not a function — it takes no parameters.
--    The "input" is the current date from the database server.
--    If CURRENT_DATE is somehow wrong (e.g. server clock issue),
--    the view silently returns data for the wrong quarter.
--    There is no user-controlled input to validate here.
--
-- Q: What if required data is missing?
-- A: INNER JOINs mean any broken link in the chain
--    (missing rental, missing inventory, orphaned film_category)
--    simply drops that payment from the result.
--    No error is raised; the row is silently excluded.
--    If the payment table itself is empty, the view returns 0 rows.
--
-- EXAMPLE OF DATA THAT SHOULD NOT APPEAR:
--   • A "Horror" category payment made on 2007-01-10 (Q1 2007)
--     should NOT appear when the view is queried for Q2 2007.
--   • A category like "Music" that had zero rentals this quarter
--     should NOT appear (excluded by INNER JOIN + HAVING).
--   • A payment with amount = 0.00 should NOT appear (HAVING > 0).
-- ============================================================




-- ============================================================
-- TASK 2: Query Language Function
-- get_sales_revenue_by_category_qtr(p_period DATE)
-- ============================================================
-- PURPOSE:
--   Returns the same result as the view sales_revenue_by_category_qtr
--   but for ANY quarter/year the caller specifies, not just today's.
--
-- WHY THE PARAMETER IS NEEDED:
--   The view is locked to CURRENT_DATE — it always reflects the
--   current quarter and cannot be used for historical reporting.
--   The p_period parameter makes the function reusable across any
--   reporting period without modifying the view definition.
--   It also enables testing against dvdrental data (2005-2007)
--   while the view itself remains dynamic for production use.
--   Passing CURRENT_DATE (the default) reproduces the view result exactly.
--
-- PARAMETER:
--   p_period DATE — any date that falls inside the desired quarter.
--   DEFAULT is CURRENT_DATE, making the parameter optional.
--   Examples:
--     No argument      → uses CURRENT_DATE automatically
--     '2007-04-01'     → Q2 2007
--     '2007-05-15'     → Q2 2007 (any date within the quarter works)
--     '2007-01-31'     → Q1 2007
--   The function extracts YEAR and QUARTER from this date,
--   so the exact day of the month does not matter.
--
-- LANGUAGE SQL vs LANGUAGE plpgsql:
--   This is explicitly a QUERY LANGUAGE function (Task 2 requirement).
--   LANGUAGE SQL is the correct designation — it executes a single
--   SELECT statement with no procedural logic.
--   NULL input is handled via CALLED ON NULL INPUT behavior:
--   if p_period is NULL, EXTRACT returns NULL, WHERE conditions
--   evaluate to NULL (never true), and the function safely returns
--   0 rows instead of crashing. This is standard SQL behavior.
--   LANGUAGE plpgsql is reserved for Tasks 3-5 (procedure language).
--
-- WHAT HAPPENS IF AN INVALID QUARTER IS PASSED:
--   PostgreSQL's DATE type rejects non-date strings at call time
--   before the function body executes (e.g. passing 'hello' raises
--   a cast error immediately). There is no "quarter 5" risk because
--   EXTRACT(QUARTER FROM date) always returns 1-4 from a valid DATE.
--   NULL input safely returns 0 rows (see above).
--
-- WHAT HAPPENS IF NO DATA EXISTS FOR THE GIVEN PERIOD:
--   The INNER JOINs produce no matching rows, HAVING filters nothing,
--   and the function returns an empty result set (0 rows).
--   No exception is raised — an empty result is valid and expected
--   (e.g. querying Q3 2026 against dvdrental data returns 0 rows).
--   This matches the view behavior: the view also returns 0 rows
--   when run in 2026 against the dvdrental dataset.
-- ============================================================

CREATE OR REPLACE FUNCTION get_sales_revenue_by_category_qtr(
    p_period DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    category_name       TEXT,
    total_sales_revenue NUMERIC,
    quarter             INT,
    year                INT
)
LANGUAGE SQL
STABLE
AS $$
    SELECT
        c.name::TEXT                             AS category_name,
        SUM(p.amount)                            AS total_sales_revenue,
        EXTRACT(QUARTER FROM p_period)::INT      AS quarter,
        EXTRACT(YEAR    FROM p_period)::INT      AS year
    FROM payment p
        JOIN rental        r  ON r.rental_id    = p.rental_id
        JOIN inventory     i  ON i.inventory_id = r.inventory_id
        JOIN film          f  ON f.film_id      = i.film_id
        JOIN film_category fc ON fc.film_id     = f.film_id
        JOIN category      c  ON c.category_id  = fc.category_id
    WHERE
        EXTRACT(YEAR    FROM p.payment_date) = EXTRACT(YEAR    FROM p_period)
        AND EXTRACT(QUARTER FROM p.payment_date) = EXTRACT(QUARTER FROM p_period)
    GROUP BY
        c.name
    HAVING
        SUM(p.amount) > 0
    ORDER BY
        total_sales_revenue DESC;
$$;


-- ============================================================
-- TEST QUERIES
-- ============================================================

-- ── TEST 1: No argument — uses DEFAULT (CURRENT_DATE) ──────────
-- Confirms the optional parameter works and mirrors the view.

SELECT * FROM get_sales_revenue_by_category_qtr();

-- Cross-check: both must return identical results
SELECT * FROM sales_revenue_by_category_qtr;
-- Expected: same row count and values from both queries.


-- ── TEST 2: Valid input — latest quarter in dvdrental data ──────
-- MAX(payment_date) dynamically finds the latest quarter present.
-- No hardcoded dates — remains correct even if data is updated.

SELECT *
FROM get_sales_revenue_by_category_qtr(
    (SELECT MAX(payment_date)::DATE FROM payment)
);
-- Expected: all film categories with revenue in Q2 2007
-- (the latest quarter in dvdrental). All 16 categories appear.


-- ── TEST 3: Valid input — different quarter, same dataset ───────
-- MIN(payment_date) finds the earliest quarter for comparison.

SELECT *
FROM get_sales_revenue_by_category_qtr(
    (SELECT MIN(payment_date)::DATE FROM payment)
);
-- Expected: categories with revenue in the earliest available quarter.
-- Result will differ from TEST 2, confirming the parameter works.


-- ── TEST 4: Edge case — period with no data ─────────────────────
-- A date far outside the dvdrental data range.

SELECT *
FROM get_sales_revenue_by_category_qtr('1990-01-01'::DATE);
-- Expected: 0 rows.
-- INNER JOINs find no matching payments; HAVING never fires.
-- No exception raised — empty result set is correct behavior.


-- ── TEST 5: Edge case — NULL input ─────────────────────────────

SELECT * FROM get_sales_revenue_by_category_qtr(NULL::DATE);
-- Expected: 0 rows.
-- EXTRACT(QUARTER FROM NULL) = NULL, so WHERE conditions evaluate
-- to NULL (never true). Safe empty result, no crash.


-- ── TEST 6: Edge case — quarter boundary dates ──────────────────
-- Verifies that Q1/Q2 boundary is handled correctly.

SELECT * FROM get_sales_revenue_by_category_qtr('2007-03-31'::DATE); -- Q1
SELECT * FROM get_sales_revenue_by_category_qtr('2007-04-01'::DATE); -- Q2
-- Expected: two different result sets confirming the boundary works.















-- ============================================================
-- TASK 3: Procedure Language Function
-- core.most_popular_films_by_countries(p_countries TEXT[])
-- ============================================================
-- PURPOSE:
--   Accepts an array of country names and returns the single
--   most popular film for each country in the array.
--
-- HOW 'MOST POPULAR' IS DEFINED:
--   Popularity is measured by RENTAL COUNT — the total number
--   of times a film was rented by customers in that country.
--   Revenue was not used because rental prices vary and would
--   skew results toward expensive films rather than truly
--   demanded ones. COUNT(rental_id) is the most honest signal.
--
-- HOW TIES ARE HANDLED:
--   RANK() assigns the same rank to films with equal rental
--   counts within a country. WHERE rnk = 1 returns ALL tied
--   winners — both appear in the result set. This is intentional:
--   silently dropping a tied winner would hide valid data.
--
-- WHAT HAPPENS IF A COUNTRY HAS NO DATA:
--   The per-country existence check loop raises a NOTICE for
--   each unrecognised country. Execution continues — other
--   valid countries in the array still return results normally.
--   No EXCEPTION is raised for missing country data, only for
--   a NULL or empty input array.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS core;

CREATE OR REPLACE FUNCTION core.most_popular_films_by_countries(
    p_countries TEXT[]
)
RETURNS TABLE (
    country      TEXT,
    film         TEXT,
    rating       TEXT,
    language     TEXT,
    length       INT,
    release_year INT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_country TEXT;
    v_found   BOOLEAN;
BEGIN
    -- ── Input validation ────────────────────────────────────────
    -- NULL or empty array cannot be processed — fail fast.
    -- array_length returns NULL for empty arrays, catching both cases.
    IF p_countries IS NULL OR array_length(p_countries, 1) IS NULL THEN
        RAISE EXCEPTION 'Input array cannot be NULL or empty.';
    END IF;

    -- ── Per-country existence check ─────────────────────────────
    -- Warn the caller about any country not found in the database.
    -- NOTICE does not stop execution — partial results still return.
    FOREACH v_country IN ARRAY p_countries
    LOOP
        SELECT EXISTS (
            SELECT 1
            FROM country
            WHERE LOWER(country.country) = LOWER(v_country)
        ) INTO v_found;

        IF NOT v_found THEN
            RAISE NOTICE 'Country "%" not found in database and will return no rows.', v_country;
        END IF;
    END LOOP;

    -- ── Main query ──────────────────────────────────────────────
    -- rental_counts CTE:
    --   Joins the full chain from rental → film → language → customer
    --   → address → city → country to count rentals per film per country.
    --   GROUP BY includes f.film_id to correctly distinguish two films
    --   that might share the same title (safer than grouping by title alone).
    --
    -- ranked CTE:
    --   RANK() partitions by country and orders by rental_count DESC.
    --   Tied films receive the same rank — both surface in final output.
    --
    -- Final SELECT:
    --   Filters to rnk = 1 only, returns required columns in required order.

    RETURN QUERY
    WITH rental_counts AS (
        SELECT
            co.country::TEXT        AS country_name,
            f.title::TEXT           AS film_title,
            f.rating::TEXT          AS film_rating,
            l.name::TEXT            AS film_language,
            f.length::INT           AS film_length,
            -- release_year is a custom 'year' domain type in dvdrental.
            -- Direct ::INT cast works in PostgreSQL for this domain.
            f.release_year::INT     AS film_release_year,
            COUNT(r.rental_id)      AS rental_count
        FROM rental r
            JOIN inventory inv ON inv.inventory_id = r.inventory_id
            JOIN film      f   ON f.film_id        = inv.film_id
            JOIN language  l   ON l.language_id    = f.language_id
            JOIN customer  cu  ON cu.customer_id   = r.customer_id
            JOIN address   a   ON a.address_id     = cu.address_id
            JOIN city      ci  ON ci.city_id       = a.city_id
            JOIN country   co  ON co.country_id    = ci.country_id
        WHERE
            -- LOWER() on both sides ensures case-insensitive matching.
            -- unnest expands the input array into individual rows for ANY().
            LOWER(co.country) = ANY (
                SELECT LOWER(c) FROM unnest(p_countries) AS c
            )
        GROUP BY
            co.country,
            f.film_id,      -- film_id prevents false grouping of same-title films
            f.title,
            f.rating,
            l.name,
            f.length,
            f.release_year
    ),
    ranked AS (
        SELECT
            *,
            RANK() OVER (
                PARTITION BY country_name
                ORDER BY rental_count DESC
            ) AS rnk
        FROM rental_counts
    )
    SELECT
        country_name     AS country,
        film_title       AS film,
        film_rating      AS rating,
        film_language    AS language,
        film_length      AS length,
        film_release_year AS release_year
    FROM ranked
    WHERE rnk = 1
    ORDER BY country_name, film_title;

END;
$$;


-- ============================================================
-- TEST QUERIES
-- ============================================================

-- ── TEST 1: Valid input — multiple countries ─────────────────────
SELECT *
FROM core.most_popular_films_by_countries(
    ARRAY['Afghanistan', 'Brazil', 'United States']
);
-- Expected: one or more rows per country.
-- Ties produce multiple rows for that country.


-- ── TEST 2: Valid input — single country ────────────────────────
SELECT *
FROM core.most_popular_films_by_countries(ARRAY['Brazil']);
-- Expected: the most rented film(s) in Brazil.


-- ── TEST 3: Edge case — country not in database ──────────────────
SELECT *
FROM core.most_popular_films_by_countries(ARRAY['Narnia']);
-- Expected: 0 rows.
-- NOTICE: 'Country "Narnia" not found in database and will return no rows.'


-- ── TEST 4: Edge case — mix of valid and invalid countries ────────
SELECT *
FROM core.most_popular_films_by_countries(
    ARRAY['Brazil', 'Narnia', 'United States']
);
-- Expected: rows for Brazil and United States returned normally.
-- NOTICE raised for Narnia only. Valid results are unaffected.


-- ── TEST 5: Edge case — NULL input ───────────────────────────────
SELECT *
FROM core.most_popular_films_by_countries(NULL);
-- Expected: EXCEPTION — 'Input array cannot be NULL or empty.'


-- ── TEST 6: Edge case — empty array ──────────────────────────────
SELECT *
FROM core.most_popular_films_by_countries(ARRAY[]::TEXT[]);
-- Expected: EXCEPTION — 'Input array cannot be NULL or empty.'


-- ── TEST 7: Edge case — case insensitive input ────────────────────
SELECT *
FROM core.most_popular_films_by_countries(
    ARRAY['brazil', 'UNITED STATES']
);
-- Expected: same results as TEST 1 for those two countries.
-- LOWER() normalisation ensures case does not affect matching.






-- I could not did task 4 and 5 








