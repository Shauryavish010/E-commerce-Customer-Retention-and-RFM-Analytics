-- ================================================================
-- E-COMMERCE CUSTOMER RETENTION & RFM ANALYTICS  (refactored)
-- PostgreSQL
--
-- IDEA: write each repeated block ONCE as a VIEW, then every report
-- is a short SELECT on top of it.
--
--   v_customer_orders   one row per order, with the real customer id
--   v_customer_months   one row per customer per active month (+ cohort)
--   v_customer_rfm      one row per customer (delivered orders only)
--   v_rfm_scores        R, F, M scores
--   v_customer_segments final segment label
--
-- Run PART 1 first (creates views), then run any query in PART 2.
--
-- SCOPE AND DEFINITIONS (keep these identical in Power BI and the README)
--  1) Customer = customer_unique_id (customer_id is created per order).
--  2) Reports B, C, D, E use ALL order statuses (retention view of activity).
--     RFM, F, G, H, I, J use DELIVERED orders only. Do not compare their
--     customer counts directly (96,096 vs 93,358).
--  3) "Product sales" = SUM(order_items.price). It EXCLUDES freight_value
--     and is not the same as payments.payment_value (which includes freight).
--  4) Recency reference date = latest delivered purchase in the data.
--  5) Frequency score is rule-based (1 / 2 / 3+ orders). NTILE is not used
--     because 97% of customers have exactly 1 order (ties).
--  6) Segment labels are definitions, not findings. The findings are the
--     numbers in report G. Check them before drawing conclusions.
--  7) Cohorts under 100 customers are flagged as unreliable (tiny samples
--     give misleading retention percentages).
-- ================================================================


-- ================================================================
-- PART 1: VIEWS (run once)
-- ================================================================

-- 1) Orders joined to the REAL customer (customer_unique_id)
CREATE OR REPLACE VIEW ecommerce.v_customer_orders AS
SELECT
    c.customer_unique_id,
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp,
    DATE_TRUNC('month', o.order_purchase_timestamp) AS purchase_month
FROM ecommerce.orders o
JOIN ecommerce.customers c
    ON c.customer_id = o.customer_id
WHERE o.order_purchase_timestamp IS NOT NULL;


-- 2) One row per customer per active month, with cohort + month_number
--    (replaces customer_orders + customer_cohorts + cohort_activity CTEs)
CREATE OR REPLACE VIEW ecommerce.v_customer_months AS
WITH active_months AS (
    SELECT DISTINCT customer_unique_id, purchase_month
    FROM ecommerce.v_customer_orders
)
SELECT
    customer_unique_id,
    purchase_month,
    MIN(purchase_month) OVER (PARTITION BY customer_unique_id) AS cohort_month,
    (EXTRACT(YEAR  FROM purchase_month) * 12 + EXTRACT(MONTH FROM purchase_month))
  - (EXTRACT(YEAR  FROM MIN(purchase_month) OVER (PARTITION BY customer_unique_id)) * 12
   + EXTRACT(MONTH FROM MIN(purchase_month) OVER (PARTITION BY customer_unique_id)))
        AS month_number
FROM active_months;


-- 3) RFM base: one row per customer, DELIVERED orders only
--    Reference date is calculated from the data, not typed by hand.
CREATE OR REPLACE VIEW ecommerce.v_customer_rfm AS
WITH ref AS (
    SELECT MAX(order_purchase_timestamp)::DATE AS ref_date
    FROM ecommerce.orders
    WHERE order_status = 'delivered'
)
SELECT
    c.customer_unique_id,
    MAX(o.order_purchase_timestamp) AS latest_purchase_date,
    (SELECT ref_date FROM ref) - MAX(o.order_purchase_timestamp)::DATE AS recency_days,
    COUNT(DISTINCT o.order_id) AS frequency,
    ROUND(SUM(oi.price), 2) AS monetary  -- product sales, excludes freight
FROM ecommerce.customers c
JOIN ecommerce.orders o ON o.customer_id = c.customer_id
JOIN ecommerce.order_items oi ON oi.order_id   = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id;


-- 4) RFM scores
--    R and M: NTILE(5), 5 = best.  customer_unique_id breaks ties so the
--    result is the same every time you run it.
--    F: fixed rules, NOT NTILE (97% of customers have exactly 1 order, and
--    NTILE would split those identical customers across different scores).
CREATE OR REPLACE VIEW ecommerce.v_rfm_scores AS
SELECT
    customer_unique_id,
    latest_purchase_date,
    recency_days,
    frequency,
    monetary,
    NTILE(5) OVER (ORDER BY recency_days DESC, customer_unique_id) AS r_score,
    CASE
        WHEN frequency >= 3 THEN 3
        WHEN frequency  = 2 THEN 2
        ELSE 1
    END AS f_score,
    NTILE(5) OVER (ORDER BY monetary, customer_unique_id) AS m_score
FROM ecommerce.v_customer_rfm;


-- 5) Segments (CASE runs top to bottom, first match wins)
CREATE OR REPLACE VIEW ecommerce.v_customer_segments AS
SELECT
    *,
    CASE
        WHEN f_score >= 2 AND r_score >= 4 THEN 'Champions'
        WHEN f_score >= 2 AND r_score  = 3 THEN 'Loyal Customers'
        WHEN f_score >= 2 THEN 'At Risk Repeat Buyers'
        WHEN r_score >= 4 AND m_score >= 4 THEN 'New High-Value'
        WHEN r_score >= 4 THEN 'New / Recent'
        WHEN r_score <= 2 AND m_score <= 2 THEN 'Inactive Low-Value'
        ELSE 'One-Time Customers (Cooling)'
    END AS customer_segment
FROM ecommerce.v_rfm_scores;


-- ================================================================
-- PART 2: REPORTS (each one is now short)
-- ================================================================

-- A) Customer vs order records (why we use customer_unique_id)
SELECT
    COUNT(*) AS total_orders,
    COUNT(DISTINCT c.customer_id) AS customer_id_records,
    COUNT(DISTINCT c.customer_unique_id) AS real_customers
FROM ecommerce.orders o
JOIN ecommerce.customers c ON c.customer_id = o.customer_id;


-- B) Orders per customer: distribution + repeat rate (all statuses)
WITH customer_orders AS (
    SELECT customer_unique_id, COUNT(*) AS total_orders
    FROM ecommerce.v_customer_orders
    GROUP BY customer_unique_id
)
SELECT
    total_orders,
    COUNT(*) AS number_of_customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_customers
FROM customer_orders
GROUP BY total_orders
ORDER BY total_orders;


-- C) Monthly orders, active customers, new vs returning
SELECT
    purchase_month,
    COUNT(*) AS active_customers,
    COUNT(*) FILTER (WHERE month_number = 0) AS new_customers,
    COUNT(*) FILTER (WHERE month_number > 0) AS returning_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE month_number > 0) / COUNT(*), 2)
        AS returning_customer_rate
FROM ecommerce.v_customer_months
GROUP BY purchase_month
ORDER BY purchase_month;


-- D) Cohort retention (long format, good for Power BI)
WITH cohort_activity AS (
    SELECT cohort_month, month_number,
           COUNT(*) AS active_customers
    FROM ecommerce.v_customer_months
    GROUP BY cohort_month, month_number
)
SELECT
    ca.cohort_month,
    ca.month_number,
    ca.active_customers,
    cs.active_customers AS cohort_size,
    ROUND(100.0 * ca.active_customers / cs.active_customers, 2) AS retention_pct,
    (cs.active_customers >= 100) AS reliable_cohort
FROM cohort_activity ca
JOIN cohort_activity cs
    ON cs.cohort_month = ca.cohort_month
   AND cs.month_number = 0
ORDER BY ca.cohort_month, ca.month_number;


-- E) Cohort retention matrix (one row per cohort, month_0 ... month_6)
WITH cohort_activity AS (
    SELECT cohort_month, month_number, COUNT(*) AS active_customers
    FROM ecommerce.v_customer_months
    GROUP BY cohort_month, month_number
),
retention AS (
    SELECT
        ca.cohort_month,
        ca.month_number,
        100.0 * ca.active_customers / cs.active_customers AS retention_pct
    FROM cohort_activity ca
    JOIN cohort_activity cs
        ON cs.cohort_month = ca.cohort_month AND cs.month_number = 0
    WHERE cs.active_customers >= 100      -- skip tiny cohorts
)
SELECT
    cohort_month,
    ROUND(MAX(retention_pct) FILTER (WHERE month_number = 0), 2) AS month_0,
    ROUND(MAX(retention_pct) FILTER (WHERE month_number = 1), 2) AS month_1,
    ROUND(MAX(retention_pct) FILTER (WHERE month_number = 2), 2) AS month_2,
    ROUND(MAX(retention_pct) FILTER (WHERE month_number = 3), 2) AS month_3,
    ROUND(MAX(retention_pct) FILTER (WHERE month_number = 4), 2) AS month_4,
    ROUND(MAX(retention_pct) FILTER (WHERE month_number = 5), 2) AS month_5,
    ROUND(MAX(retention_pct) FILTER (WHERE month_number = 6), 2) AS month_6
FROM retention
GROUP BY cohort_month
ORDER BY cohort_month;


-- F) Time between purchases (delivered orders, LAG)
--    Reports average AND median: the average is pulled up by a few very
--    late repeat buyers, the median is the typical customer.
WITH ordered AS (
    SELECT
        customer_unique_id,
        order_purchase_timestamp,
        LAG(order_purchase_timestamp) OVER (
            PARTITION BY customer_unique_id
            ORDER BY order_purchase_timestamp
        ) AS previous_purchase
    FROM ecommerce.v_customer_orders
    WHERE order_status = 'delivered'
),
gaps AS (
    SELECT
        customer_unique_id,
        order_purchase_timestamp::DATE - previous_purchase::DATE AS days_between
    FROM ordered
    WHERE previous_purchase IS NOT NULL
)
SELECT
    COUNT(*) AS repeat_intervals,
    COUNT(DISTINCT customer_unique_id) AS repeat_customers,
    ROUND(AVG(days_between), 1) AS avg_days,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_between))::NUMERIC, 1) AS median_days,
    COUNT(*) FILTER (WHERE days_between = 0) AS same_day_repeat_orders
FROM gaps;


-- G) Segment summary: size, behaviour, revenue
SELECT
    customer_segment,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS customer_pct,
    ROUND(AVG(recency_days), 0) AS avg_recency_days,
    ROUND(AVG(frequency), 2) AS avg_orders,
    ROUND(AVG(monetary), 2) AS avg_spend,
    ROUND(SUM(monetary), 0) AS product_sales,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 2) AS product_sales_pct
FROM ecommerce.v_customer_segments
GROUP BY customer_segment
ORDER BY product_sales DESC;


-- H) One-time vs repeat customers
SELECT
    CASE WHEN frequency = 1 THEN 'One-Time' ELSE 'Repeat' END AS customer_group,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS customer_pct,
    ROUND(SUM(monetary), 0) AS product_sales,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 2) AS product_sales_pct,
    ROUND(AVG(monetary), 2) AS avg_spend
FROM ecommerce.v_customer_rfm
GROUP BY 1
ORDER BY product_sales DESC;


-- I) Frequency groups: orders vs spend
SELECT
    CASE WHEN frequency >= 5 THEN '5+' ELSE frequency::TEXT END AS orders_placed,
    COUNT(*) AS customers,
    ROUND(AVG(monetary), 2) AS avg_spend,
    ROUND(SUM(monetary), 0) AS product_sales
FROM ecommerce.v_customer_rfm
GROUP BY 1
ORDER BY 1;


-- J) Top 20 customers by spend, with segment
SELECT customer_unique_id, customer_segment, recency_days, frequency, monetary
FROM ecommerce.v_customer_segments
ORDER BY monetary DESC
LIMIT 20;


-- K) Sanity check: every customer has exactly one segment
SELECT
    COUNT(*) AS customers_in_rfm,
    COUNT(DISTINCT customer_unique_id) AS distinct_customers,
    COUNT(*) FILTER (WHERE customer_segment IS NULL) AS unsegmented
FROM ecommerce.v_customer_segments;
