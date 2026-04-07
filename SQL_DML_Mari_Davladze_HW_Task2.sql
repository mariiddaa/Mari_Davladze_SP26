
---task 2

-- =============================================================================
-- STEP 1: Create table with 10 million rows
-- =============================================================================

CREATE TABLE public.table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1, (10^7)::int) x;

-- generate_series() produces numbers 1 to 10,000,000
-- || concatenates each number with the string prefix
-- Result: 10,000,000 rows | Execution time: 44s


-- =============================================================================
-- STEP 2: Check space BEFORE any operation
-- =============================================================================

SELECT *, pg_size_pretty(total_bytes) AS total,
pg_size_pretty(index_bytes) AS INDEX,
pg_size_pretty(toast_bytes) AS toast,
pg_size_pretty(table_bytes) AS TABLE
FROM ( SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
FROM (SELECT c.oid,nspname AS table_schema,
relname AS TABLE_NAME,
c.reltuples AS row_estimate,
pg_total_relation_size(c.oid) AS total_bytes,
pg_indexes_size(c.oid) AS index_bytes,
pg_total_relation_size(reltoastrelid) AS toast_bytes
FROM pg_class c
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE relkind = 'r') a) a
WHERE table_name LIKE '%table_to_delete%';

-- Result: 575 MB


-- =============================================================================
-- STEP 3a: DELETE 1/3 of all rows
-- =============================================================================

DELETE FROM public.table_to_delete
WHERE REPLACE(col, 'veeeeeeery_long_string', '')::int % 3 = 0;

-- REPLACE strips the text part leaving just the number (e.g. '3' from 'veeeeeeery_long_string3')
-- ::int converts it to integer
-- % 3 = 0 targets every row whose number is divisible by 3
-- Result: 3,333,333 rows deleted | Execution time: 29s


-- =============================================================================
-- STEP 3b: Check space AFTER DELETE
-- =============================================================================

SELECT *, pg_size_pretty(total_bytes) AS total,
pg_size_pretty(index_bytes) AS INDEX,
pg_size_pretty(toast_bytes) AS toast,
pg_size_pretty(table_bytes) AS TABLE
FROM ( SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
FROM (SELECT c.oid,nspname AS table_schema,
relname AS TABLE_NAME,
c.reltuples AS row_estimate,
pg_total_relation_size(c.oid) AS total_bytes,
pg_indexes_size(c.oid) AS index_bytes,
pg_total_relation_size(reltoastrelid) AS toast_bytes
FROM pg_class c
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE relkind = 'r') a) a
WHERE table_name LIKE '%table_to_delete%';

-- Result: still 575 MB — nothing changed
-- Even though 3.3 million rows were deleted, the table occupies the same space.
-- PostgreSQL marks those rows as "dead" but does not remove them from disk yet.


-- =============================================================================
-- STEP 3c: VACUUM FULL to physically reclaim space

VACUUM FULL VERBOSE public.table_to_delete;

-- Output: found 967,613 removable dead tuples, 6,666,667 nonremovable row versions
-- Execution time: 18s


-- =============================================================================
-- STEP 3d: Check space AFTER VACUUM FULL
-- =============================================================================

SELECT *, pg_size_pretty(total_bytes) AS total,
pg_size_pretty(index_bytes) AS INDEX,
pg_size_pretty(toast_bytes) AS toast,
pg_size_pretty(table_bytes) AS TABLE
FROM ( SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
FROM (SELECT c.oid,nspname AS table_schema,
relname AS TABLE_NAME,
c.reltuples AS row_estimate,
pg_total_relation_size(c.oid) AS total_bytes,
pg_indexes_size(c.oid) AS index_bytes,
pg_total_relation_size(reltoastrelid) AS toast_bytes
FROM pg_class c
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE relkind = 'r') a) a
WHERE table_name LIKE '%table_to_delete%';

-- Result: 383 MB
-- VACUUM FULL rewrote the table from scratch keeping only live rows.
-- This brought the size down from 575 MB to 383 MB (roughly 2/3 of original).


-- =============================================================================
-- STEP 3e: Recreate table for TRUNCATE comparison
-- =============================================================================

DROP TABLE public.table_to_delete;

CREATE TABLE public.table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1, (10^7)::int) x;

-- Result: 10,000,000 rows recreated | Execution time: 42s
-- Size back to 575 MB


-- =============================================================================
-- STEP 4: TRUNCATE
-- =============================================================================

TRUNCATE public.table_to_delete;

-- Result: 0 rows | Execution time: 1.271s
-- Compare: DELETE took 29s to remove 3.3M rows, TRUNCATE took 1.271s for all 10M


-- =============================================================================
-- STEP 4c: Check space AFTER TRUNCATE
-- =============================================================================

SELECT *, pg_size_pretty(total_bytes) AS total,
pg_size_pretty(index_bytes) AS INDEX,
pg_size_pretty(toast_bytes) AS toast,
pg_size_pretty(table_bytes) AS TABLE
FROM ( SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
FROM (SELECT c.oid,nspname AS table_schema,
relname AS TABLE_NAME,
c.reltuples AS row_estimate,
pg_total_relation_size(c.oid) AS total_bytes,
pg_indexes_size(c.oid) AS index_bytes,
pg_total_relation_size(reltoastrelid) AS toast_bytes
FROM pg_class c
LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE relkind = 'r') a) a
WHERE table_name LIKE '%table_to_delete%';

-- Result: 8 KB (essentially nothing)
-- Unlike DELETE, TRUNCATE freed all disk space immediately with no need for VACUUM.


-- =============================================================================
-- STEP 5: INVESTIGATION RESULTS
-- =============================================================================

/*
A) SPACE CONSUMPTION AT EACH STAGE
───────────────────────────────────────────────────────────────
Stage Size
─────────────────────────────────────── ────────
After CREATE (10M rows) 575 MB
After DELETE (3.3M rows removed) 575 MB ← no change
After VACUUM FULL 383 MB ← space reclaimed
After DROP + CREATE (10M rows again) 575 MB
After TRUNCATE (all 10M rows removed) 8 KB ← instant


B) DELETE vs TRUNCATE COMPARISON
───────────────────────────────────────────────────────────────

EXECUTION TIME:
DELETE took 29 seconds to remove 3,333,333 rows.
TRUNCATE took 1.271 seconds to remove all 10,000,000 rows.
That is roughly 23x faster despite removing 3x more rows.
DELETE scans and logs every single row individually.
TRUNCATE just drops the data pages all at once — it does not
care how many rows are in the table.

DISK SPACE USAGE:
After DELETE the table was still 575 MB — same as before.
After VACUUM FULL it dropped to 383 MB.
After TRUNCATE it dropped to 8 KB immediately, no VACUUM needed.
DELETE leaves dead rows sitting on disk. TRUNCATE removes everything.

TRANSACTION BEHAVIOR:
DELETE is fully transactional — every deleted row gets its own
WAL (Write-Ahead Log) entry, which is why it is slow but safe.
TRUNCATE is also transactional in PostgreSQL but works at the
page level rather than row level, so it writes much less to WAL.
TRUNCATE also locks the entire table while running, blocking
other queries from reading or writing during that time.

ROLLBACK POSSIBILITY:
DELETE can be rolled back at any point before COMMIT —
all deleted rows come back as if nothing happened.
TRUNCATE can also technically be rolled back in PostgreSQL
since it is transactional, but in this task autocommit was ON,
so once TRUNCATE finished there was no way to undo it.


C) EXPLANATIONS
───────────────────────────────────────────────────────────────

WHY DELETE DOES NOT FREE SPACE IMMEDIATELY:
PostgreSQL uses MVCC (Multi-Version Concurrency Control).
When delete a row, PostgreSQL does not physically remove it —
it just marks it as invisible to new transactions. This is done
because another transaction that started before DELETE might
still need to read that row. So the row stays on disk until
PostgreSQL is sure nobody needs it anymore. That cleanup happens
during VACUUM, not during the DELETE itself.

WHY VACUUM FULL CHANGES TABLE SIZE:
Regular VACUUM marks dead rows as reusable space but does not
shrink the actual file on disk. VACUUM FULL is different — it
writes a completely new copy of the table with only the live rows,
then deletes the old file. That is why size dropped from 575 MB
to 383 MB. The downside is it locks the table completely while
doing this and needs extra disk space temporarily for the rewrite.

WHY TRUNCATE BEHAVES DIFFERENTLY:
TRUNCATE does not touch individual rows at all. It just tells
the OS to deallocate all the data pages belonging to the table.
This is why it finishes in 1.271 seconds regardless of how many
rows the table has, and why the size drops to almost zero instantly.
The tradeoff is you cannot use a WHERE clause — it is all or nothing.

HOW THESE OPERATIONS AFFECT PERFORMANCE AND STORAGE:
If DELETE runs frequently without regular VACUUM, dead rows pile up
and the table grows larger over time even if you are removing data.
Queries get slower because PostgreSQL has to skip over all those
dead rows to find the live ones. This is called table bloat.
TRUNCATE avoids this completely — no bloat, no cleanup needed.
For production systems, regular VACUUM (not FULL) runs automatically
in the background. VACUUM FULL is a last resort for badly bloated
tables since it locks the table and takes significant time and disk.
*/

