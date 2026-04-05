--1.1The marketing team needs a list of animation movies between 2017 and 2019 
--to promote family-friendly content in an upcoming season in stores. 
--Show all animation movies released during this period with rate more than 1, sorted alphabetically

-- solution 1: JOIN

SELECT f.film_id, f.title, f.release_year, c.name AS category, f.rental_rate
FROM public.film f
INNER JOIN public.film_category fc ON f.film_id = fc.film_id
INNER JOIN public.category c ON fc.category_id = c.category_id
WHERE f.release_year >= 2017
  AND f.release_year <= 2019
  AND LOWER(c.name) = LOWER('Animation')
  AND f.rental_rate > 1
ORDER BY f.title ASC;



-- Solution 2: CTE
WITH animation_films AS (
    SELECT f.film_id, f.title, f.release_year, f.rental_rate
    FROM public.film f
    INNER JOIN public.film_category fc ON f.film_id = fc.film_id
    INNER JOIN public.category c ON fc.category_id = c.category_id
    WHERE LOWER(c.name) = LOWER('Animation')
)
SELECT film_id, title, release_year, rental_rate
FROM animation_films
WHERE release_year >= 2017
  AND release_year <= 2019
  AND rental_rate > 1
ORDER BY title ASC;



-- Solution 3: Subquery
SELECT f.film_id, f.title, f.release_year, f.rental_rate
FROM public.film f
WHERE f.release_year >= 2017
  AND f.release_year <= 2019
  AND f.rental_rate > 1
  AND f.film_id IN (
      SELECT fc.film_id
      FROM public.film_category fc
      INNER JOIN public.category c ON fc.category_id = c.category_id
      WHERE LOWER(c.name) = LOWER('Animation')
  )
ORDER BY f.title ASC;



-- JOIN type explanation:
-- INNER JOIN is used because we only needed films that existed in both
-- public.film AND public.film_list tables.
-- If a film had no matching record in film_list, like no category was assigned,
-- it gets excluded from results — which is needed for this task.
--
-- LEFT JOIN would include all films even without a category,
-- returning NULL for category — not needed
-- RIGHT JOIN would include all film_list records even if the film
-- doesn't exist in the film table — not needed
-- CROSS JOIN would combine every film with every category row
-- producing incorrect duplicate results — not neeeded


-- Assumptions:
--  i assumed that 'rate' meant rental_rate column in public.film,
--    as it is the only rate-related column in the film table.
--  'between 2017 and 2019' i assumed that both year must have been included for the task logic


-- COMPARISON:
--
-- JOIN:
--   Advantages: simple, readable
--   Disadvantages: with many joins it might get hard to read
--
-- CTE:
--   Advantages: most readable, easy to debug,
--               logic is clearly separated 
--   Disadvantages: too much affort for simple tasks like this
--
-- Subquery:
--   Advantages: good for simple filtering with IN
--   Disadvantages: harder to read when nested deeply, can be slower too

-- Production choice:
-- I would use the JOIN solution for this task because:
--  The logic is simple and straightforward also It performs well for this type of filtering


-----------------------------------------------------------------------------------------------------------



--1.2The finance department requires a report on store performance to 
--assess profitability and plan resource allocation for stores after 
--March 2017. Calculate the revenue earned by each rental store after March 2017 
--(since April) (include columns: address and address2 – as one column, revenue)

-- Solution 1: join
SELECT
    TRIM(a.address || ' ' || COALESCE(a.address2, '')) AS full_address,
    SUM(p.amount) AS revenue
FROM public.payment p
INNER JOIN public.rental r ON p.rental_id = r.rental_id
INNER JOIN public.inventory i ON r.inventory_id = i.inventory_id
INNER JOIN public.store s ON i.store_id = s.store_id
INNER JOIN public.address a ON s.address_id = a.address_id
WHERE p.payment_date > '2017-03-31'
GROUP BY a.address_id;


-- Solution 2: CTE
WITH store_revenue AS (
    SELECT
        a.address_id,
        TRIM(a.address || ' ' || COALESCE(a.address2, '')) AS full_address,
        p.amount
    FROM public.payment p
    INNER JOIN public.rental r ON p.rental_id = r.rental_id
    INNER JOIN public.inventory i ON r.inventory_id = i.inventory_id
    INNER JOIN public.store s ON i.store_id = s.store_id
    INNER JOIN public.address a ON s.address_id = a.address_id
    WHERE p.payment_date > '2017-03-31'
)
SELECT full_address, SUM(amount) AS revenue
FROM store_revenue
GROUP BY address_id, full_address;

-- Solution 3: Subquery
SELECT
    TRIM(a.address || ' ' || COALESCE(a.address2, '')) AS full_address,
    SUM(p.amount) AS revenue
FROM public.payment p
INNER JOIN public.rental r ON p.rental_id = r.rental_id
INNER JOIN public.inventory i ON r.inventory_id = i.inventory_id
INNER JOIN public.store s ON i.store_id = s.store_id
INNER JOIN public.address a ON s.address_id = a.address_id
WHERE p.payment_date > '2017-03-31'
GROUP BY a.address_id;

--subquery through staff is now gone i guess as the store connection comes naturally 
--through the join, so no subquery is needed anymore.


-- JOIN type explanation:
-- INNER JOIN is used because we only needed
-- records that existed in all four tables.
--
-- LEFT JOIN would include payments/staff/stores with no matches,
--   returning NULL values — not needed for this task.
-- RIGHT JOIN would include all address records even with no store,
--   producing irrelevant rows — not needed.
-- CROSS JOIN would combine every payment with every address,
--   producing completely incorrect revenue numbers — not needed.


-- Assumptions:
-- i assumed 'after March 2017' meant payment_date > '2017-03-31',
--   so April 1st 2017 would be correctlly included 
-- i assumed revenue meant SUM of amount column in public.payment,
--   as it is the only financial column available in the database.
-- i assumed store must be reached through staff, as payment table
--   has no direct store_id column.
-- i noticed that address2 was NULL in some cases so used COALESCE to
--   avoid the full_address becoming NULL.


-- COMPARISON:
--
-- JOIN:
--   Advantages: clean and direct, easy to follow the chain
--               payment -> staff -> store -> address
--   Disadvantages: with more joins it can become harder to read
--
-- CTE:
--   Advantages: separates data gathering from aggregation,
--               easier to debug each step independently
--   Disadvantages:  too much affort for simple tasks like this
--
-- Subquery:
--   Advantages: works for filtering by store 
--   Disadvantages: unnecessarily complex here since JOIN already
--                  handles it cleanly, harder to read when nested


-- Production choice:
-- I would use the JOIN solution for this task because:
-- the chain payment -> staff -> store -> address is straightforward
-- and easy to follow. The logic is simple enough that a CTE
-- would add unnecessary verbosity without any real benefit.


---------------------------------------------------------------------------------------------------


--1.3The marketing department in our stores aims to identify the most successful actors 
--since 2015 to boost customer interest in their films. Show top-5 actors 
--by number of movies (released since 2015) they took part in 
--(columns: first_name, last_name, number_of_movies, sorted by number_of_movies in descending order)

--Solution 1: join
SELECT first_name, last_name, number_of_movies
FROM (
    SELECT a.first_name, a.last_name,
        COUNT(fa.film_id) AS number_of_movies,
        RANK() OVER (ORDER BY COUNT(fa.film_id) DESC) AS rnk
    FROM public.film_actor fa
    INNER JOIN public.actor a ON a.actor_id = fa.actor_id
    INNER JOIN public.film f ON f.film_id = fa.film_id
    WHERE f.release_year >= 2015
    GROUP BY fa.actor_id, a.first_name, a.last_name
) ranked
WHERE rnk <= 5;



-- Solution 2: CTE
WITH films_since_2015 AS (
    SELECT fa.actor_id, fa.film_id
    FROM public.film_actor fa
    INNER JOIN public.film f ON f.film_id = fa.film_id
    WHERE f.release_year >= 2015
),
actor_counts AS (
    SELECT a.actor_id, a.first_name, a.last_name,
        COUNT(fs.film_id) AS number_of_movies,
        RANK() OVER (ORDER BY COUNT(fs.film_id) DESC) AS rnk
    FROM public.actor a
    INNER JOIN films_since_2015 fs ON a.actor_id = fs.actor_id
    GROUP BY a.actor_id, a.first_name, a.last_name
)
SELECT first_name, last_name, number_of_movies
FROM actor_counts
WHERE rnk <= 5;

-- Solution 3: Subquery
SELECT first_name, last_name, number_of_movies
FROM (
    SELECT a.first_name, a.last_name,
        COUNT(fs.film_id) AS number_of_movies,
        RANK() OVER (ORDER BY COUNT(fs.film_id) DESC) AS rnk
    FROM public.actor a
    INNER JOIN (
        SELECT fa.actor_id, fa.film_id
        FROM public.film_actor fa
        INNER JOIN public.film f ON f.film_id = fa.film_id
        WHERE f.release_year >= 2015
    ) fs ON a.actor_id = fs.actor_id
    GROUP BY a.actor_id, a.first_name, a.last_name
) ranked
WHERE rnk <= 5;


-- JOIN type explanation:
-- INNER JOIN is used because we only needed actors that had
-- matching records in both actor and film tables.

-- LEFT JOIN would include actors with no films, returning NULL for number_of_movies — not needed.
-- RIGHT JOIN would include all films even with no actor assigned — not needed.
-- CROSS JOIN would combine every actor with every film producing completely incorrect counts — not needed.


-- Assumptions:
-- I assumed 'since 2015' meant release_year >= 2015, so ıncluded 2015 
-- i assumed 'number of movies' meant COUNT of film_id
--   in film_actor, as it had records of which actor appeared in which film.
-- I assumed 'most successful' meant highest number of films, not ratings or revenue 
--   because task was about countıng number of movies


-- COMPARISON:
--
-- JOIN:
--   Advantages: simple, readable, straightforward for this task
--   Disadvantages: with more joins can become harder to read
--
-- CTE:
--   Advantages: consistent with filtering style from task 1,
--               easier to read for simple cases
--   Disadvantages: repeats the same JOIN and WHERE twice, less efficient 


-- Production choice:
-- I would use the JOIN solution for this task because:
-- the logic is simple and direct, all filtering and counting
-- happens in one clean query without extra steps.
-- CTE would be preferred if the query needed to be reused
-- or broken into more complex logical steps.

----------------------------------------------------------------------------------------------------------


--1.4The marketing team needs to track the production trends of Drama, Travel, and Documentary films 
--to inform genre-specific marketing strategies. Show number of Drama, Travel, Documentary per year 
--(include columns: release_year, number_of_drama_movies, number_of_travel_movies, 
--number_of_documentary_movies), sorted by release year in descending order. 
--Dealing with NULL values is encouraged)


-- Solution 1: join 
SELECT f.release_year,
    COUNT(fc.film_id) FILTER (WHERE LOWER(c.name) = 'drama') AS number_of_drama_movies,
    COUNT(fc.film_id) FILTER (WHERE LOWER(c.name) = 'travel') AS number_of_travel_movies,
    COUNT(fc.film_id) FILTER (WHERE LOWER(c.name) = 'documentary') AS number_of_documentary_movies
FROM public.film f
INNER JOIN public.film_category fc ON f.film_id = fc.film_id
INNER JOIN public.category c ON fc.category_id = c.category_id
WHERE LOWER(c.name) IN ('drama', 'travel', 'documentary')
GROUP BY f.release_year
ORDER BY f.release_year DESC;


-- Solution 2: CTE
WITH category_films AS (
    SELECT f.release_year, c.name AS category
    FROM public.film f
    INNER JOIN public.film_category fc ON f.film_id = fc.film_id
    INNER JOIN public.category c ON fc.category_id = c.category_id
    WHERE LOWER(c.name) IN ('drama', 'travel', 'documentary')
)
SELECT release_year,
    COUNT(*) FILTER (WHERE LOWER(category) = 'drama') AS number_of_drama_movies,
    COUNT(*) FILTER (WHERE LOWER(category) = 'travel') AS number_of_travel_movies,
    COUNT(*) FILTER (WHERE LOWER(category) = 'documentary') AS number_of_documentary_movies
FROM category_films
GROUP BY release_year
ORDER BY release_year DESC;


-- Solution 3: Subquery
SELECT sub.release_year,
    COUNT(*) FILTER (WHERE LOWER(sub.category) = 'drama') AS number_of_drama_movies,
    COUNT(*) FILTER (WHERE LOWER(sub.category) = 'travel') AS number_of_travel_movies,
    COUNT(*) FILTER (WHERE LOWER(sub.category) = 'documentary') AS number_of_documentary_movies
FROM (
    SELECT f.release_year, c.name AS category
    FROM public.film f
    INNER JOIN public.film_category fc ON f.film_id = fc.film_id
    INNER JOIN public.category c ON fc.category_id = c.category_id
    WHERE LOWER(c.name) IN ('drama', 'travel', 'documentary')
) sub
GROUP BY sub.release_year
ORDER BY sub.release_year DESC;


-- JOIN type explanation:
-- INNER JOIN is used because we only needed films that had
-- matching records in both film_category and film_list tables.
-- 
-- LEFT JOIN would include films with no category,
-- returning NULL for category 
-- RIGHT JOIN would include all film_list records even
-- with no matching film
-- CROSS JOIN would combine every film with every category
-- producing completely incorrect counts 


-- Assumptions:
-- I assumed NULL handling was needed for CASE WHEN approach,
--   but FILTER automatically returns 0 instead of NULL,
--   making COALESCE unnecessary in this solution.
-- i assumed release_year from public.film is the correct
--   column to group and sort by per task requirement.


-- COMPARISON:
--
-- JOIN:
--   Advantages: most direct and concise, everything in one query,
--               easy to follow for this task
--   Disadvantages: mixing filtering and counting in one query
--                  can get harder to read with more categories
--
-- CTE:
--   Advantages: cleanly separates data collection from counting,
--               easier to debug each step independently,
--               most readable of the three approaches
--   Disadvantages: more verbose than JOIN for this simple task
--
-- Subquery:
--   Advantages: same logic as CTE, no need to name it at the top,
--               good for one-time use without reusing the result
--   Disadvantages: less readable than CTE


-- Production choice:
-- I would use the CTE solution for this task because:
-- it clearly separates data preparation from aggregation,
-- making it easier to maintain and debug if categories change.
-- JOIN works equally well but CTE was better 


--------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------

--2.1The HR department aims to reward top-performing employees in 2017 with bonuses to recognize 
--their contribution to stores revenue. Show which three employees generated the most revenue in 2017? 
--Assumptions: 
--staff could work in several stores in a year, please indicate which store the staff worked in (the last one);
--if staff processed the payment then he works in the same store; 
--take into account only payment_date

-- Solution 1: join 
SELECT 
    p.staff_id,
    stf.first_name,
    stf.last_name,
    SUM(p.amount) AS employees_generated_revenue,
    a.address AS last_store_address
FROM public.payment p
INNER JOIN public.staff stf ON p.staff_id = stf.staff_id
INNER JOIN public.store s ON s.store_id = stf.store_id
INNER JOIN public.address a ON a.address_id = s.address_id
WHERE p.payment_date >= '2017-01-01'
AND p.payment_date < '2018-01-01'
GROUP BY p.staff_id, stf.first_name, stf.last_name, a.address
ORDER BY employees_generated_revenue DESC
LIMIT 3;





-- Solution2: CTE
WITH last_payment AS (
    SELECT 
        p.staff_id,
        MAX(p.payment_date) AS last_payment_date
    FROM public.payment p
    WHERE p.payment_date >= '2017-01-01'
    AND p.payment_date < '2018-01-01'
    GROUP BY p.staff_id
),

last_store AS (
    SELECT DISTINCT 
        p.staff_id,
        stf.store_id
    FROM public.payment p
    INNER JOIN public.staff stf ON p.staff_id = stf.staff_id
    INNER JOIN last_payment lp ON p.staff_id = lp.staff_id
    AND p.payment_date = lp.last_payment_date
),

staff_revenue AS (
    SELECT 
        p.staff_id,
        SUM(p.amount) AS employees_generated_revenue
    FROM public.payment p
    WHERE p.payment_date >= '2017-01-01'
    AND p.payment_date < '2018-01-01'
    GROUP BY p.staff_id
)

SELECT 
    sr.staff_id,
    stf.first_name,
    stf.last_name,
    sr.employees_generated_revenue,
    a.address AS last_store_address
FROM staff_revenue sr
INNER JOIN public.staff stf ON stf.staff_id = sr.staff_id
INNER JOIN last_store ls ON ls.staff_id = sr.staff_id
INNER JOIN public.store s ON s.store_id = ls.store_id
INNER JOIN public.address a ON a.address_id = s.address_id
ORDER BY sr.employees_generated_revenue DESC
LIMIT 3;



-- Solution 3: Subquery 
SELECT 
    sr.staff_id,
    stf.first_name,
    stf.last_name,
    sr.employees_generated_revenue,
    a.address AS last_store_address
FROM (

    SELECT 
        p.staff_id,
        SUM(p.amount) AS employees_generated_revenue
    FROM public.payment p
    WHERE p.payment_date >= '2017-01-01'
    AND p.payment_date < '2018-01-01'
    GROUP BY p.staff_id
) sr
INNER JOIN public.staff stf ON stf.staff_id = sr.staff_id
INNER JOIN (
  
    SELECT DISTINCT 
        p.staff_id,
        stf.store_id
    FROM public.payment p
    INNER JOIN public.staff stf ON p.staff_id = stf.staff_id
    INNER JOIN (
      
        SELECT 
            p.staff_id,
            MAX(p.payment_date) AS last_payment_date
        FROM public.payment p
        WHERE p.payment_date >= '2017-01-01'
        AND p.payment_date < '2018-01-01'
        GROUP BY p.staff_id
    ) lp ON p.staff_id = lp.staff_id
    AND p.payment_date = lp.last_payment_date
) ls ON ls.staff_id = sr.staff_id
INNER JOIN public.store s ON s.store_id = ls.store_id
INNER JOIN public.address a ON a.address_id = s.address_id
ORDER BY sr.employees_generated_revenue DESC
LIMIT 3;


-- JOIN type explanation:
-- INNER JOIN is used because we only needed payments that had
-- matching records in payment, staff, store, and address tables.
--
-- Assumptions:
-- I assumed '2017' meant payment_date >= '2017-01-01' AND < '2018-01-01', 
--   so the full calendar year 2017 is included
-- I assumed 'revenue' meant SUM(amount) from public.payment,
--   as it is the only financial column available
-- I assumed 'last store' meant the store linked to the employee's
--   most recent payment in 2017, but at first I thought 'last_update' row would be usefull but it is not. 
-- I assumed store must be reached through staff, as payment table
--   has no direct store_id column


-- COMPARISON:
--
-- JOIN:
--   Advantages: simple and concise, easy to follow for basic revenue totals
--   Disadvantages: does not correctly track the last store —
--                  it uses the store currently assigned in the staff table,
--                  which may not reflect where they last worked in 2017
--
-- CTE:
--   Advantages: most readable, each step is clearly named and debuggable,
--               correctly finds last store through last payment date,
--               logic is cleanly separated into three independent steps
--   Disadvantages:  three CTEs for a single query
--
-- Subquery:
--   Advantages: same accuracy as CTE, no need to name steps at the top
--   Disadvantages: nested three levels deep, much harder to read
--                  and maintain compared to CTE


-- Production choice:
-- I would use the CTE solution for this task because:
-- it is the only approach that correctly solves the last store requirement
-- by tracking the most recent payment date per employee. I struggled a lot with the subquery approach as it is hard to do and understand.



--------------------------------------------------------------------------------------------------------------

-- 2.2 The management team wants to identify the most popular movies and their target audience age groups
-- to optimize marketing efforts. Show which 5 movies were rented more than others (number of rentals), 
--and what's the expected age of the audience for these movies? To determine expected age please use 
--'Motion Picture Association film rating system'


-- Solution 1: join 
SELECT 
    f.film_id,        
    f.title,          
    f.rating,
    CASE f.rating
        WHEN 'G'     THEN 'All ages'
        WHEN 'PG'    THEN 'Ages 8+' -- exact age was not mentioned, only 'parental guidance'
        WHEN 'PG-13' THEN 'Ages 13+'
        WHEN 'R'     THEN 'Ages 17+'
        WHEN 'NC-17' THEN 'Ages 18+'
    END AS expected_age,
    COUNT(r.rental_id) AS number_of_rentals
FROM public.rental r
INNER JOIN public.inventory i ON r.inventory_id = i.inventory_id
INNER JOIN public.film f ON f.film_id = i.film_id  
GROUP BY f.film_id, f.title, f.rating
ORDER BY number_of_rentals DESC
LIMIT 5;




-- Solution 2: CTE  
WITH film_rentals AS (
    SELECT
        f.film_id,
        f.title,
        f.rating,
        CASE f.rating
        WHEN 'G'     THEN 'All ages'
        WHEN 'PG'    THEN 'Ages 8+' -- exact age was not mentioned, only 'parental guidance'
        WHEN 'PG-13' THEN 'Ages 13+'
        WHEN 'R'     THEN 'Ages 17+'
        WHEN 'NC-17' THEN 'Ages 18+'
        END AS expected_age,
        COUNT(r.rental_id) AS number_of_rentals
    FROM public.rental r
    INNER JOIN public.inventory i ON r.inventory_id = i.inventory_id
    INNER JOIN public.film f ON f.film_id = i.film_id
    GROUP BY f.film_id, f.title, f.rating
)
SELECT film_id,
       title,
       rating,
       expected_age,
       number_of_rentals
FROM film_rentals          
ORDER BY number_of_rentals DESC
LIMIT 5;


-- Solution 3: Suquary  
select sub.film_id,        
    sub.title,          
    sub.rating,
    sub.expected_age,
    sub.number_of_rentals
FROM
  ( SELECT 
        f.film_id,
        f.title,
        f.rating,
   CASE f.rating
        WHEN 'G'     THEN 'All ages'
        WHEN 'PG'    THEN 'Ages 8+' -- exact age was not mentioned, only 'parental guidance'
        WHEN 'PG-13' THEN 'Ages 13+'
        WHEN 'R'     THEN 'Ages 17+'
        WHEN 'NC-17' THEN 'Ages 18+'
   END AS expected_age,
    COUNT(r.rental_id) AS number_of_rentals
FROM public.rental r
INNER JOIN public.inventory i ON r.inventory_id = i.inventory_id
INNER JOIN public.film f ON f.film_id = i.film_id  
GROUP BY f.film_id,        
    f.title,          
    f.rating
ORDER BY number_of_rentals DESC
LIMIT 5
   )sub



-- JOIN type explanation:
-- INNER JOIN is used because we only needed records that existed
-- in all three tables: rental, inventory, and film.

-- Assumptions:
-- I assumed 'most popular' meant highest COUNT(rental_id),
--   as rental table records every rental transaction
-- I assumed 'Ages 8+' for PG as no exact age was mentioned
--   in the task, only 'parental guidance' in the MPA system


-- COMPARISON:
--
-- JOIN:
--   Advantages: simplest and most direct, everything in one query,
--               easy to read and follow for this task
--   Disadvantages: CASE logic and COUNT are mixed together,
--                  can get harder to read if more ratings are added
--
-- CTE:
--   Advantages: clearly separates data preparation from final output,
--               CTE can be reused if needed in a larger query,
--               easier to debug each step independently
--   Disadvantages: more verbose than JOIN for this simple task,
--                  
-- Subquery:
--   Advantages:  outer SELECT clearly shows what columns are returned
--
--   Disadvantages: harder to read than CTE when logic gets complex,
--                  subquery alias 'sub' adds an extra layer to follow


-- Production choice:
-- I would use the JOIN solution for this task because:
-- the logic is straightforward — three tables, one CASE statement,
-- one COUNT. Everything fits cleanly in a single query without
-- needing to split into separate steps.

   
-----------------------------------------------------------------------------------------------

--3.1 The stores’ marketing team wants to analyze actors' inactivity periods to select those with 
--notable career breaks for targeted promotional campaigns, highlighting their comebacks 
--or consistent appearances to engage customers with nostalgic or reliable film stars
--The task can be interpreted in various ways, and here are a few options (provide solutions for each one):
--V1: gap between the latest release_year and current year per each actor;
--V2: gaps between sequential films per each actor;

--v1:
-- Solution 1: JOIN
SELECT
    a.actor_id,
    a.first_name,
    a.last_name,
    MAX(f.release_year)  AS latest_release_year,
    EXTRACT(YEAR FROM CURRENT_DATE) AS current_year,
    EXTRACT(YEAR FROM CURRENT_DATE)- MAX(f.release_year) AS years_inactive
FROM public.actor a
INNER JOIN public.film_actor fa ON a.actor_id = fa.actor_id
INNER JOIN public.film f ON f.film_id = fa.film_id
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY years_inactive DESC;



-- Solution 2: CTE
WITH actor_latest AS (
    SELECT
        a.actor_id,
        a.first_name,
        a.last_name,
        MAX(f.release_year) AS latest_release_year
    FROM public.actor a
    INNER JOIN public.film_actor fa ON a.actor_id = fa.actor_id
    INNER JOIN public.film f ON f.film_id = fa.film_id
    GROUP BY a.actor_id, a.first_name, a.last_name
)
SELECT
    actor_id,
    first_name,
    last_name,
    latest_release_year,
    EXTRACT(YEAR FROM CURRENT_DATE) AS current_year,
    EXTRACT(YEAR FROM CURRENT_DATE) - latest_release_year AS years_inactive
FROM actor_latest
ORDER BY years_inactive DESC;



-- Solution 3: Subquery
SELECT
    sub.actor_id,
    sub.first_name,
    sub.last_name,
    sub.latest_release_year,
    EXTRACT(YEAR FROM CURRENT_DATE) AS current_year,
    EXTRACT(YEAR FROM CURRENT_DATE) - sub.latest_release_year AS years_inactive
FROM (
    SELECT
        a.actor_id,
        a.first_name,
        a.last_name,
        MAX(f.release_year) AS latest_release_year
    FROM public.actor a
    INNER JOIN public.film_actor fa ON a.actor_id = fa.actor_id
    INNER JOIN public.film f ON f.film_id = fa.film_id
    GROUP BY a.actor_id, a.first_name, a.last_name
) sub
ORDER BY years_inactive DESC;


-- JOIN type explanation:
-- INNER JOIN is used because we only needed actors that had
-- matching records in both film_actor and film tables.
--

-- Assumptions:
-- I assumed 'current year' meant EXTRACT(YEAR FROM CURRENT_DATE)
--   so the query always uses today's actual year automatically
-- I assumed 'latest release_year' meant MAX(release_year)
--   as it gives the most recent film per actor
-- I assumed years_inactive = current_year - MAX(release_year),
--   so an actor whose last film was this year would have 0
-- I assumed actors with multiple films in the same year
--   are handled correctly since MAX() picks the highest year


-- COMPARISON:
--
-- JOIN:
--   Advantages: simplest and most direct, MAX and subtraction
--               happen in one clean query, easy to follow
--   Disadvantages: calculation happens inside SELECT which
--                  can be slightly harder to read
--
-- CTE:
--   Advantages: cleanly separates finding the latest year
--               from calculating the gap, each step is clear
--               and easy to debug independently
--   Disadvantages: more verbose than JOIN for this simple task
--
-- Subquery:
--   Advantages: same separation as CTE, outer SELECT clearly
--               shows the final calculation
--   Disadvantages: less readable than CTE, inner query must
--                  be read first before understanding the outer


-- Production choice:
-- I would use the JOIN solution for V1 because:
-- the logic is simple — MAX per actor and one subtraction.
-- There is no need to split this into separate steps.

---------------------------------------------------------------------------------
 
--V2: gaps between sequential films per each actor;


-- Solution 1: JOIN
SELECT
    a.actor_id,
    a.first_name,
    a.last_name,
    MAX(next_year.release_year - f1.release_year) AS max_gap_years
FROM public.actor a
INNER JOIN public.film_actor fa1 ON a.actor_id = fa1.actor_id
INNER JOIN public.film f1 ON fa1.film_id = f1.film_id
INNER JOIN public.film_actor fa2 ON a.actor_id = fa2.actor_id
INNER JOIN public.film next_year ON fa2.film_id = next_year.film_id
    AND next_year.release_year > f1.release_year
GROUP BY a.actor_id, a.first_name, a.last_name, f1.release_year
ORDER BY max_gap_years DESC;




-- Solution 2: CTE
WITH actor_years AS (
-- Step 1: all actors with their film release years
    SELECT
        a.actor_id,
        a.first_name,
        a.last_name,
        f.release_year
    FROM public.actor a
    INNER JOIN public.film_actor fa ON a.actor_id = fa.actor_id
    INNER JOIN public.film f ON fa.film_id = f.film_id
),
consecutive_gaps AS (
-- Step 2: self-join — pair each year with all later years,
--         MIN() finds the immediately next release year → gap
    SELECT
        t1.actor_id,
        t1.first_name,
        t1.last_name,
        t1.release_year AS film_year,
        MIN(t2.release_year) - t1.release_year AS gap
    FROM actor_years t1
    INNER JOIN actor_years t2
        ON t1.actor_id = t2.actor_id
        AND t1.release_year < t2.release_year
    GROUP BY t1.actor_id, t1.first_name, t1.last_name, t1.release_year
)
-- Step 3: MAX() finds the biggest consecutive gap per actor
SELECT
    actor_id,
    first_name,
    last_name,
    MAX(gap) AS max_gap_years
FROM consecutive_gaps
GROUP BY actor_id, first_name, last_name
ORDER BY max_gap_years DESC;



-- Solution 3: Subquery
SELECT
    actor_id,
    first_name,
    last_name,
    MAX(gap) AS max_gap_years
FROM (
    -- Step 2: self-join to find nearest next release year, calculate gap
    SELECT
        t1.actor_id,
        t1.first_name,
        t1.last_name,
        MIN(t2.release_year) - t1.release_year AS gap
    FROM (
        -- Step 1: actors with their film release years
        SELECT
            a.actor_id,
            a.first_name,
            a.last_name,
            f.release_year
        FROM public.actor a
        INNER JOIN public.film_actor fa ON a.actor_id = fa.actor_id
        INNER JOIN public.film f ON fa.film_id = f.film_id
    ) t1
    INNER JOIN (
        SELECT
            a.actor_id,
            f.release_year
        FROM public.actor a
        INNER JOIN public.film_actor fa ON a.actor_id = fa.actor_id
        INNER JOIN public.film f ON fa.film_id = f.film_id
    ) t2
        ON t1.actor_id = t2.actor_id
        AND t1.release_year < t2.release_year
    GROUP BY t1.actor_id, t1.first_name, t1.last_name, t1.release_year
) gaps
GROUP BY actor_id, first_name, last_name
ORDER BY max_gap_years DESC;




-- JOIN type explanation:
-- INNER JOIN is used throughout because we only need actors
-- that have actual film records. The self-join pairs each
-- release year with later ones using the condition
-- t1.release_year < t2.release_year, then MIN() narrows
-- it down to the immediately next year only.


-- Assumptions:
-- I assumed 'gap' means the difference in release years
--   between two consecutive films by the same actor
-- I assumed 'consecutive' means the immediately next release
--   year, found using MIN() after t1.release_year < t2.release_year
-- I assumed we want the single largest gap per actor
-- I assumed actors with multiple films in the same year
--   produce a 0-year gap, which MAX() ignores naturally


-- COMPARISON:
--
-- JOIN:
--   Advantages: no named steps, directly joins base tables
--   Disadvantages: cannot express MIN-then-MAX aggregation
--                  cleanly in one query — produces gaps from
--                  each year forward, not true consecutive gaps
--
-- CTE:
--   Advantages: mirrors Elena's 3-step logic exactly, each
--               step is named and independently readable,
--               easiest to debug and verify
--   Disadvantages: more verbose than subquery
--
-- Subquery:
--   Advantages: same correct logic as CTE in compact form
--   Disadvantages: harder to read without the named steps,
--                  inline comments are essential


-- Production choice:
-- I would use the CTE solution for V2 because:
-- the problem has three natural sequential steps and CTEs
-- mirror that structure exactly. Each step can be tested
-- independently, and the named CTEs make the logic
-- self-documenting without needing extra comments.



