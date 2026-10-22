-- E-COMMERCE CUSTOMER RETENTION & RFM ANALYTICS
-- ================================================================
-- Scope and interpretation notes:
-- 1) Customer identity is customer_unique_id (actual customer across order records).
-- 2) RFM and the later repeat-purchase checks use delivered orders only.
-- 3) Early general order/monthly activity queries intentionally use all statuses;
--    compare them only with metrics using the same order-status scope.
-- 4) Current monetary calculations sum order_items.price (product prices only);
--    they exclude freight_value and are labelled product sales/spending where possible.
-- 5) The RFM reference date below is fixed at 2018-08-29 for reproducibility.
--    Change it only after validating the desired analysis cutoff.
-- 6) Exploratory queries may overlap. The final dashboard should use one validated
--    version of each KPI, not every exploratory query in this file.
-- 7) Run 02Data_quality_checks.sql and validate the output before final reporting.
-- ================================================================

SELECT 
	COUNT(*) AS total_orders,
	COUNT(DISTINCT o.customer_id) AS unique_customer_records,
	COUNT(DISTINCT c.customer_unique_id) AS unique_actual_customer
FROM ecommerce.orders o
JOIN ecommerce.customers c
	ON o.customer_id = c.customer_id;


--Join orders with customers, combine all orders belonging to the same actual customer,
--count their orders, keep only customers who ordered more than once, and show the customers
--with the highest number of orders first.--
SELECT 
	c.customer_unique_id,
	COUNT(o.order_id) AS total_orders
FROM ecommerce.orders o
JOIN ecommerce.customers c
	ON o.customer_id = c.customer_id
GROUP BY c.customer_unique_id
HAVING COUNT(o.order_id)>1
ORDER BY total_orders DESC;



--First, find every actual customer and count how many orders each customer
--has placed. Then use those results to calculate the total number of customers,
--how many customers purchased more than once, how many purchased exactly once,
--and what percentage of all customers are repeat customers.

WITH customer_orders AS (
	SELECT 
		c.customer_unique_id,
		COUNT(o.order_id) AS total_orders
	FROM ecommerce.orders o
	JOIN ecommerce.customers c
		ON o.customer_id = c.customer_id
	GROUP BY c.customer_unique_id
)

--SELECT * FROM customer_orders
--WHERE total_orders>1
--ORDER BY total_orders DESC;

SELECT 
	COUNT(*) AS total_customers,
	COUNT(*) FILTER(
		WHERE total_orders >1
	) AS repeat_customers,
	COUNT(*) FILTER(
		WHERE total_orders = 1
	) AS one_time_customers,

	ROUND(100.0 * COUNT(*) FILTER (WHERE total_orders > 1) / NULLIF(COUNT(*), 0), 2) AS repeat_customers_percentage

FROM customer_orders;
	

--First, count how many orders each actual customer placed. Then group customers
--according to their number of orders and count how many customers belong to each
--group. Finally, show the results from the lowest number of orders to the highest.

WITH customer_orders AS (
	SELECT 
		c.customer_unique_id,
		COUNT(o.order_id) AS total_orders
	FROM ecommerce.orders o
	JOIN ecommerce.customers c
		ON o.customer_id = c.customer_id
	GROUP BY c.customer_unique_id
)

SELECT 
	total_orders,
	COUNT(*) AS number_of_customers
FROM customer_orders
GROUP BY total_orders
ORDER BY total_orders;

--First, calculate the total number of orders for every actual customer.
--Then use those customer-level results to find the average, minimum,
--and maximum number of orders across all customers.

WITH customer_orders AS(
	SELECT 
		c.customer_unique_id,
		COUNT(o.order_id) AS total_orders
	FROM ecommerce.orders o
	JOIN ecommerce.customers c
		ON o.customer_id = c.customer_id
	GROUP BY c.customer_unique_id
)

SELECT 
	ROUND(AVG(total_orders),2) AS avg_orders_per_customer,
	MIN(total_orders) AS minimum_orders,
	MAX(total_orders) AS maximum_orders
FROM customer_orders;


--Take all orders, group them by the month in which they were purchased,
--count the total number of orders each month, and count how many unique
--actual customers made purchases during each month. Then show the months
--in chronological order.

SELECT
	DATE_TRUNC('month', o.order_purchase_timestamp) AS purchase_month,
	COUNT(o.order_id) AS total_orders,
	COUNT(DISTINCT c.customer_unique_id) AS unique_customers
FROM ecommerce.orders o
JOIN ecommerce.customers c
	ON o.customer_id = c.customer_id
WHERE o.order_purchase_timestamp IS NOT NULL
GROUP BY DATE_TRUNC('month', o.order_purchase_timestamp)
ORDER BY purchase_month;


--First, find the first month in which each customer made a purchase.
--Then look at every month they made purchases. If a customer's purchase
--happened in their first purchase month, count them as a new customer.
--If they purchased in a later month, count them as a returning customer.
--Finally, show the number of new and returning customers for each month.

WITH customer_first_purchase AS(
	SELECT 
		c.customer_unique_id,
		MIN(
			DATE_TRUNC('month', o.order_purchase_timestamp) 
		) AS first_purchase_month
	FROM ecommerce.orders o
	JOIN ecommerce.customers c
		ON o.customer_id = c.customer_id
	WHERE o.order_purchase_timestamp IS NOT NULL
	GROUP BY c.customer_unique_id
),

customer_monthly_activity AS(
	SELECT DISTINCT
		c.customer_unique_id,
		DATE_TRUNC('month', o.order_purchase_timestamp) AS purchase_month
	FROM ecommerce.orders o
	JOIN ecommerce.customers c
		ON o.customer_id = c.customer_id
	WHERE o.order_purchase_timestamp IS NOT NULL
)

SELECT 
	cma.purchase_month,
	COUNT(
		CASE 
			WHEN cma.purchase_month = cfp.first_purchase_month
			THEN 1
		END
	) AS new_customers,
	COUNT(
		CASE
			WHEN cma.purchase_month > cfp.first_purchase_month
			THEN 1
		END
	) AS returning_customers
FROM customer_monthly_activity cma
JOIN customer_first_purchase cfp
	ON cma.customer_unique_id = cfp.customer_unique_id
GROUP BY cma.purchase_month
ORDER BY cma.purchase_month;


--First, identify each customer's first purchase month and every month they were active.
--Then, for each month, count the total active customers and count how many of them were
--returning customers. Finally, calculate what percentage of active customers were
--returning customers.

WITH customer_first_purchase AS(
	SELECT 
		c.customer_unique_id,
		MIN(
			DATE_TRUNC('month', o.order_purchase_timestamp) 
		) AS first_purchase_month
	FROM ecommerce.orders o
	JOIN ecommerce.customers c
		ON o.customer_id = c.customer_id
	WHERE o.order_purchase_timestamp IS NOT NULL
	GROUP BY c.customer_unique_id
),

customer_monthly_activity AS(
	SELECT DISTINCT
		c.customer_unique_id,
		DATE_TRUNC('month', o.order_purchase_timestamp) AS purchase_month
	FROM ecommerce.orders o
	JOIN ecommerce.customers c
		ON o.customer_id = c.customer_id
	WHERE o.order_purchase_timestamp IS NOT NULL
)

SELECT 
	cma.purchase_month,
	COUNT(*) AS active_customers,
	COUNT(*) FILTER (
		WHERE cma.purchase_month > cfp.first_purchase_month
	) AS returniing_customers,
	ROUND(
		100.0 *
		COUNT(*) FILTER (
			WHERE cma.purchase_month > cfp.first_purchase_month
		)
		/COUNT(*), 2
		) AS returning_customer_rate
		
FROM customer_monthly_activity cma
JOIN customer_first_purchase cfp
	ON cma.customer_unique_id = cfp.customer_unique_id
GROUP BY cma.purchase_month
ORDER BY cma.purchase_month;



--For every customer who placed multiple orders, arrange their purchases from
--earliest to latest. Find their first purchase and the next purchase, calculate
--how many days passed between them, and then calculate the average time customers
--take to purchase again.

WITH customer_purchase AS (
	SELECT c.customer_unique_id,
	o.order_purchase_timestamp,

	ROW_NUMBER() OVER(
		PARTITION BY c.customer_unique_id
		ORDER BY o.order_purchase_timestamp
	) AS purchase_number
	FROM ecommerce.orders o
	JOIN ecommerce.customers c
		ON o.customer_id = c.customer_id
	WHERE o.order_purchase_timestamp IS NOT NULL
),
first_second_purchase AS(
	SELECT customer_unique_id,

	MIN(order_purchase_timestamp)
		FILTER (WHERE purchase_number = 1)
		AS first_purchase,
	MIN(order_purchase_timestamp)
		FILTER (WHERE purchase_number = 2)
		AS second_purchase
	FROM customer_purchase
	GROUP BY customer_unique_id
	HAVING COUNT(*)>=2
)

SELECT 
	COUNT(*) AS repeat_customers,

	ROUND(AVG(EXTRACT(DAY FROM(second_purchase - first_purchase))), 2) AS average_days_to_second_purchase,
	MIN(EXTRACT(DAY FROM(second_purchase - first_purchase))) AS minimum_days,
	MAX(EXTRACT(DAY FROM(second_purchase - first_purchase))) AS maximum_days
FROM first_second_purchase;



--First, arrange every customer's purchases from earliest to latest and identify their first
--and second purchases. Then calculate exactly how many days passed between those two purchases.
--Finally, put each repeat customer into a time category and count how many customers fall into each category.

WITH customer_purchase AS (
	SELECT c.customer_unique_id,
	o.order_purchase_timestamp,

	ROW_NUMBER() OVER(
		PARTITION BY c.customer_unique_id
		ORDER BY o.order_purchase_timestamp
	) AS purchase_number
	FROM ecommerce.orders o
	JOIN ecommerce.customers c
		ON o.customer_id = c.customer_id
	WHERE o.order_purchase_timestamp IS NOT NULL
),
first_second_purchase AS(
	SELECT customer_unique_id,

	MIN(order_purchase_timestamp)
		FILTER (WHERE purchase_number = 1)
		AS first_purchase,
	MIN(order_purchase_timestamp)
		FILTER (WHERE purchase_number = 2)
		AS second_purchase
	FROM customer_purchase
	GROUP BY customer_unique_id
	HAVING COUNT(*)>=2
),
purchase_gap AS(
	SELECT customer_unique_id,
		EXTRACT(
			EPOCH FROM(
				second_purchase - first_purchase
			)
		)/86400.0 AS days_to_second_purchase
	FROM first_second_purchase
)

SELECT 
	CASE 
		WHEN days_to_second_purchase <= 30 THEN '0-30 days'
		WHEN days_to_second_purchase <= 60 THEN '31-60 days'
		WHEN days_to_second_purchase <= 90 THEN '61-90 days'
		WHEN days_to_second_purchase <= 180 THEN '91-180 days'
		ELSE 'More than 180 days'
	END AS repurchase_time_category,
	COUNT(*) AS repeat_customers
FROM purchase_gap
GROUP BY repurchase_time_category
ORDER BY MIN(days_to_second_purchase);



--Find each customer's first purchase month and assign them to that month's cohort.
--Then track every month in which they made a purchase and calculate how many months
--have passed since their first purchase.

WITH customer_orders AS (
	SELECT DISTINCT 
	c.customer_unique_id,
	DATE_TRUNC('month', o.order_purchase_timestamp)AS purchase_month
	FROM ecommerce.orders o
	JOIN ecommerce.customers c
		ON o.customer_id = c.customer_id
	WHERE o.order_purchase_timestamp IS NOT NULL
),
customer_cohorts AS(
	SELECT 
		customer_unique_id,
		MIN(purchase_month) AS cohort_month
	FROM customer_orders
	GROUP BY customer_unique_id
)

SELECT 
	co.cohort_month,
	coo.purchase_month,
	(
    EXTRACT(YEAR FROM purchase_month) * 12
    + EXTRACT(MONTH FROM purchase_month)
	)
	-
	(
    EXTRACT(YEAR FROM cohort_month) * 12
    + EXTRACT(MONTH FROM cohort_month)
	) AS month_number,
	COUNT(DISTINCT coo.customer_unique_id) AS active_customers
FROM customer_orders coo
JOIN customer_cohorts co
	ON coo.customer_unique_id = co.customer_unique_id
GROUP BY co.cohort_month,
	coo.purchase_month
ORDER BY co.cohort_month,
	coo.purchase_month;



--First, find every month when each customer made a purchase. Then find each customer's
--first purchase month and assign them to a cohort. Calculate how many months later each
--purchase happened. Count the active customers for every cohort and month. Finally, divide
--the active customers by the original number of customers in that cohort to calculate the
--retention percentage.

WITH customer_orders AS(
	SELECT DISTINCT
	c.customer_unique_id,
	DATE_TRUNC(
		'month', o.order_purchase_timestamp
	) AS purchase_month
	FROM ecommerce.orders o
	JOIN ecommerce.customers c
		ON o.customer_id = c.customer_id
	WHERE o.order_purchase_timestamp IS NOT NULL
),

customer_cohorts AS(
	SELECT 
		customer_unique_id,
		MIN(purchase_month) AS cohort_month
	FROM customer_orders
	GROUP BY customer_unique_id
),

cohort_activity AS(
	SELECT 
		cc.cohort_month,
		co.purchase_month,
		(
			EXTRACT(YEAR FROM co.purchase_month)*12
			+
			EXTRACT(MONTH FROM co.purchase_month)
		)
		-
		(
			EXTRACT(YEAR FROM cc.cohort_month)*12
			+
			EXTRACT(MONTH FROM cc.cohort_month)
		) AS month_number,
		COUNT(DISTINCT co.customer_unique_id) AS active_customers
	FROM customer_orders co
	JOIN customer_cohorts cc
		ON co.customer_unique_id = cc.customer_unique_id
	GROUP BY
		cc.cohort_month,
		co.purchase_month
),

cohort_size AS(
	SELECT 
		cohort_month,
		active_customers AS cohort_customers
	FROM cohort_activity 
	WHERE month_number = 0
)

SELECT
	ca.cohort_month,
	ca.month_number,
	ca.active_customers,
	cs.cohort_customers,

	ROUND(100.0 * ca.active_customers / cs.cohort_customers, 2) AS retention_percentage
FROM cohort_activity ca
JOIN cohort_size cs
	ON ca.cohort_month = cs.cohort_month
ORDER BY 
	ca.cohort_month,
	ca.month_number;

	

--Take the customer retention data for each cohort and convert it from multiple rows
--into a matrix where each row represents one cohort and each column represents a month
--after the customer's first purchase.

WITH customer_orders AS(
	SELECT DISTINCT
	c.customer_unique_id,
	DATE_TRUNC(
		'month', o.order_purchase_timestamp
	) AS purchase_month
	FROM ecommerce.orders o
	JOIN ecommerce.customers c
		ON o.customer_id = c.customer_id
	WHERE o.order_purchase_timestamp IS NOT NULL
),

customer_cohorts AS(
	SELECT 
		customer_unique_id,
		MIN(purchase_month) AS cohort_month
	FROM customer_orders
	GROUP BY customer_unique_id
),

cohort_activity AS(
	SELECT 
		cc.cohort_month,
		co.purchase_month,
		(
			EXTRACT(YEAR FROM co.purchase_month)*12
			+
			EXTRACT(MONTH FROM co.purchase_month)
		)
		-
		(
			EXTRACT(YEAR FROM cc.cohort_month)*12
			+
			EXTRACT(MONTH FROM cc.cohort_month)
		) AS month_number,
		COUNT(DISTINCT co.customer_unique_id) AS active_customers
	FROM customer_orders co
	JOIN customer_cohorts cc
		ON co.customer_unique_id = cc.customer_unique_id
	GROUP BY
		cc.cohort_month,
		co.purchase_month
),

cohort_size AS(
	SELECT 
		cohort_month,
		active_customers AS cohort_customers
	FROM cohort_activity 
	WHERE month_number = 0
),	

cohort_retention AS(
	SELECT 
		ca.cohort_month,
		ca.month_number,
		ROUND(100.0 * ca.active_customers / cs.cohort_customers, 2) AS retention_percentage
	FROM cohort_activity ca
	JOIN cohort_size cs
		ON ca.cohort_month = cs.cohort_month
)

SELECT 
	cohort_month,

	ROUND(MAX(retention_percentage)
		FILTER (WHERE month_number = 0), 2) AS month_0,
	ROUND(MAX(retention_percentage)
		FILTER (WHERE month_number = 1), 2) AS month_1,
	ROUND(MAX(retention_percentage)
		FILTER (WHERE month_number = 2), 2) AS month_2,
	ROUND(MAX(retention_percentage)
		FILTER (WHERE month_number = 3), 2) AS month_3,
	ROUND(MAX(retention_percentage)
		FILTER (WHERE month_number = 4), 2) AS month_4,
	ROUND(MAX(retention_percentage)
		FILTER (WHERE month_number = 5), 2) AS month_5,
	ROUND(MAX(retention_percentage)
		FILTER (WHERE month_number = 6), 2) AS month_6
FROM cohort_retention
GROUP BY cohort_month
ORDER BY cohort_month;



--For every customer, find their most recent delivered purchase, count how many
--different orders they made, and calculate the total amount they spent on products.

SELECT
	c.customer_unique_id,
	MAX(o.order_purchase_timestamp) AS latest_purchase_date,
	COUNT(DISTINCT o.order_id) AS frequency,
	ROUND(SUM(oi.price),2) AS monetary
FROM ecommerce.customers c
JOIN ecommerce.orders o
	ON c.customer_id = o.customer_id
JOIN ecommerce.order_items oi
	ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id
ORDER BY frequency DESC;



SELECT
    MAX(order_purchase_timestamp) AS dataset_latest_purchase
FROM ecommerce.orders
WHERE order_status = 'delivered';


--First, create a temporary customer summary containing each customer's latest
--purchase date, number of orders, and total spending. Then calculate how many
--days passed between their latest purchase and the last purchase date in our dataset.

WITH customer_rfm AS (
	SELECT
		c.customer_unique_id,
		MAX(o.order_purchase_timestamp) AS latest_purchase_date,
		COUNT(DISTINCT o.order_id) AS frequency,
		ROUND(SUM (oi.price),2) AS monetary
	FROM ecommerce.customers c
	JOIN ecommerce.orders o
		ON c.customer_id = o.customer_id
	JOIN ecommerce.order_items oi
		ON o.order_id = oi.order_id
	WHERE o.order_status = 'delivered'
	GROUP BY c.customer_unique_id
)

SELECT 
	customer_unique_id,
	latest_purchase_date,
	(DATE '2018-08-29' - DATE(latest_purchase_date)) AS recency_days,
	frequency,
	monetary
FROM customer_rfm
ORDER BY recency_days DESC;



--Create one row for every customer containing their latest purchase date, number
--of purchases, and total spending. Calculate how many days ago each customer's latest
--purchase happened. Divide all customers into 5 groups based on Recency, Frequency, and Monetary value.

WITH customer_rfm AS (
	SELECT
		c.customer_unique_id,
		MAX(o.order_purchase_timestamp) AS latest_purchase_date,
		COUNT(DISTINCT o.order_id) AS frequency,
		ROUND(SUM (oi.price),2) AS monetary
	FROM ecommerce.customers c
	JOIN ecommerce.orders o
		ON c.customer_id = o.customer_id
	JOIN ecommerce.order_items oi
		ON o.order_id = oi.order_id
	WHERE o.order_status = 'delivered'
	GROUP BY c.customer_unique_id
),

rfm_values AS (
	SELECT 
		customer_unique_id,
		latest_purchase_date,
		(DATE '2018-08-29' - DATE(latest_purchase_date)) AS recency_days,
		frequency,
		monetary
	FROM customer_rfm
)

SELECT
	customer_unique_id,
	latest_purchase_date,
	recency_days,
	frequency,
	monetary,

	NTILE(5)OVER (
		ORDER BY recency_days DESC
	) AS recenc_score,
	NTILE(5) OVER (
		ORDER BY frequency ASC
	) AS frequency_score,
	NTILE(5) OVER (
		ORDER BY monetary ASC
	) AS monetary_score
FROM rfm_values;

--Calculate how many delivered orders each customer made. Then group customers according
--to their number of orders and count how many customers fall into each group.

WITH customer_rfm AS (
	SELECT
		c.customer_unique_id,
		MAX(o.order_purchase_timestamp) AS latest_purchase_date,
		COUNT(DISTINCT o.order_id) AS frequency,
		ROUND(SUM (oi.price),2) AS monetary
	FROM ecommerce.customers c
	JOIN ecommerce.orders o
		ON c.customer_id = o.customer_id
	JOIN ecommerce.order_items oi
		ON o.order_id = oi.order_id
	WHERE o.order_status = 'delivered'
	GROUP BY c.customer_unique_id
)

SELECT 
	frequency,
	COUNT(*) AS number_of_customers
FROM customer_rfm
GROUP BY frequency
ORDER BY frequency;



WITH customer_rfm AS (
	SELECT
		c.customer_unique_id,
		MAX(o.order_purchase_timestamp) AS latest_purchase_date,
		COUNT(DISTINCT o.order_id) AS frequency,
		ROUND(SUM (oi.price),2) AS monetary
	FROM ecommerce.customers c
	JOIN ecommerce.orders o
		ON c.customer_id = o.customer_id
	JOIN ecommerce.order_items oi
		ON o.order_id = oi.order_id
	WHERE o.order_status = 'delivered'
	GROUP BY c.customer_unique_id
),

rfm_scores AS(
	SELECT 
		customer_unique_id,
		latest_purchase_date,
		frequency,
		monetary,
		NTILE(4) OVER (
			ORDER BY DATE '2018-08-29' - DATE(latest_purchase_date) DESC
		) AS recency_score,
		NTILE(4) OVER (
			ORDER BY frequency
		) AS frequency_score,
		NTILE(4) OVER (
			ORDER BY monetary
		) AS monetary_score
	FROM customer_rfm
)

SELECT 
	customer_unique_id,

	CASE 
		WHEN recency_score >=3
			AND frequency_score	>=3
			AND monetary_score >=3
		THEN 'Champions'

		WHEN frequency_score >=3
			AND monetary_score >=3
		THEN 'Loyal Customers'

		WHEN recency_score >=3
			AND frequency_score <=2
		THEN 'Potential Customers'

		WHEN recency_score <=2
			AND frequency_score >=2
		THEN 'At Risk'

		WHEN recency_score <=2
			AND frequency_score =1
		THEN 'Lost Customers'

		ELSE 'Other Customers'
	END AS customer_segment
FROM rfm_scores;
	



WITH customer_rfm AS (
	SELECT
		c.customer_unique_id,
		MAX(o.order_purchase_timestamp) AS latest_purchase_date,
		COUNT(DISTINCT o.order_id) AS frequency,
		ROUND(SUM (oi.price),2) AS monetary
	FROM ecommerce.customers c
	JOIN ecommerce.orders o
		ON c.customer_id = o.customer_id
	JOIN ecommerce.order_items oi
		ON o.order_id = oi.order_id
	WHERE o.order_status = 'delivered'
	GROUP BY c.customer_unique_id
),

rfm_scores AS(
	SELECT 
		customer_unique_id,
		latest_purchase_date,
		frequency,
		monetary,
		NTILE(4) OVER (
			ORDER BY DATE '2018-08-29' - DATE(latest_purchase_date) DESC
		) AS recency_score,
		NTILE(4) OVER (
			ORDER BY frequency
		) AS frequency_score,
		NTILE(4) OVER (
			ORDER BY monetary
		) AS monetary_score
	FROM customer_rfm
),

customer_segments AS (
	SELECT 
		customer_unique_id,
	
		CASE 
			WHEN recency_score >=3
				AND frequency_score	>=3
				AND monetary_score >=3
			THEN 'Champions'
	
			WHEN frequency_score >=3
				AND monetary_score >=3
			THEN 'Loyal Customers'
	
			WHEN recency_score >=3
				AND frequency_score <=2
			THEN 'Potential Customers'
	
			WHEN recency_score <=2
				AND frequency_score >=2
			THEN 'At Risk'
	
			WHEN recency_score <=2
				AND frequency_score =1
			THEN 'Lost Customers'
	
			ELSE 'Other Customers'
		END AS customer_segment
	FROM rfm_scores
)

SELECT
    customer_segment,
    COUNT(*) AS number_of_customers
FROM customer_segments
GROUP BY customer_segment
ORDER BY number_of_customers DESC;


--For each customer segment, let’s find out how many customers it contains, what
--percentage of all customers they represent, how recently they purchased, how often
--they purchase, and how much they spend.

WITH customer_rfm AS  (
	SELECT 
		c.customer_unique_id,
		MAX(o.order_purchase_timestamp) AS latest_purchase_date,
		COUNT(DISTINCT o.order_id) AS frequency,
		ROUND(SUM(oi.price), 2) AS monetary
	FROM ecommerce.customers c
	JOIN ecommerce.orders o
		ON c.customer_id = o.customer_id
	JOIN ecommerce.order_items oi
		ON o.order_id = oi.order_id
	WHERE o.order_status = 'delivered'
	GROUP BY c.customer_unique_id
),

rfm_scores AS (
	SELECT
		customer_unique_id,
		latest_purchase_date,
		DATE '2018-08-29' - DATE(latest_purchase_date) AS recency_days,
		frequency,
		monetary,
		NTILE(4) OVER (
			ORDER BY DATE '2018-08-29' - DATE(latest_purchase_date) DESC
		) AS recency_score,
		NTILE(4) OVER (
			ORDER BY frequency
		) AS frequency_score,
		NTILE(4) OVER (
			ORDER BY monetary
		) AS monetary_score
	FROM customer_rfm
),

customer_segments AS (
	SELECT
		customer_unique_id,
		recency_days,
		frequency,
		monetary,

		CASE 
			WHEN recency_score >= 3
                AND frequency_score >= 3
                AND monetary_score >= 3
            THEN 'Champions'

            WHEN frequency_score >= 3
                AND monetary_score >= 3
            THEN 'Loyal Customers'

            WHEN recency_score >= 3
                AND frequency_score <= 2
            THEN 'Potential Customers'

            WHEN recency_score <= 2
                AND frequency_score >= 2
            THEN 'At Risk'

            WHEN recency_score <= 2
                AND frequency_score = 1
            THEN 'Lost Customers'

            ELSE 'Other Customers'
		END AS customer_segment
	FROM rfm_scores
)

SELECT 
	customer_segment,
	COUNT(*) AS number_of_customers,
	ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS customer_percentage,
	ROUND(AVG(recency_days), 2) AS avg_recency_days,
    ROUND(AVG(frequency), 2) AS avg_purchase_frequency,
    ROUND(AVG(monetary), 2) AS avg_customer_spending

FROM customer_segments
GROUP BY customer_segment
ORDER BY number_of_customers DESC;



--Calculating Total revenue by customer_segment	

WITH customer_rfm AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp) AS latest_purchase_date,
        COUNT(DISTINCT o.order_id) AS frequency,
        ROUND(SUM(oi.price), 2) AS monetary
    FROM ecommerce.customers c
    JOIN ecommerce.orders o
        ON c.customer_id = o.customer_id
    JOIN ecommerce.order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),

rfm_scores AS (
    SELECT
        customer_unique_id,
        latest_purchase_date,
        frequency,
        monetary,

        NTILE(4) OVER (
            ORDER BY
                DATE '2018-08-29'
                - DATE(latest_purchase_date) DESC
        ) AS recency_score,

        NTILE(4) OVER (
            ORDER BY frequency
        ) AS frequency_score,

        NTILE(4) OVER (
            ORDER BY monetary
        ) AS monetary_score

    FROM customer_rfm
),

customer_segments AS (
    SELECT
        customer_unique_id,
        monetary,

        CASE
            WHEN recency_score >= 3
                AND frequency_score >= 3
                AND monetary_score >= 3
            THEN 'Champions'

            WHEN frequency_score >= 3
                AND monetary_score >= 3
            THEN 'Loyal Customers'

            WHEN recency_score >= 3
                AND frequency_score <= 2
            THEN 'Potential Customers'

            WHEN recency_score <= 2
                AND frequency_score >= 2
            THEN 'At Risk'

            WHEN recency_score <= 2
                AND frequency_score = 1
            THEN 'Lost Customers'

            ELSE 'Other Customers'
        END AS customer_segment

    FROM rfm_scores
)

SELECT 
	customer_segment,
	COUNT(*) AS number_of_customers,
	ROUND(SUM(monetary), 2) AS total_revenue,
	ROUND(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER(), 2) AS revenue_percentage,
	ROUND(AVG(monetary), 2) AS avg_revenue_per_customer
FROM customer_segments
GROUP BY customer_segment
ORDER BY total_revenue DESC;


-- NOTE: monetary is SUM(order_items.price) for delivered orders, excluding freight.
-- Treat it as product spending/product sales value, not payment collections or
-- freight-inclusive revenue. Keep this definition consistent in comparisons.

--High Value Customer Identification

WITH customer_rfm AS  (
	SELECT 
		c.customer_unique_id,
		MAX(o.order_purchase_timestamp) AS latest_purchase_date,
		COUNT(DISTINCT o.order_id) AS frequency,
		ROUND(SUM(oi.price), 2) AS monetary
	FROM ecommerce.customers c
	JOIN ecommerce.orders o
		ON c.customer_id = o.customer_id
	JOIN ecommerce.order_items oi
		ON o.order_id = oi.order_id
	WHERE o.order_status = 'delivered'
	GROUP BY c.customer_unique_id
),

rfm_scores AS (
	SELECT
		customer_unique_id,
		latest_purchase_date,
		DATE '2018-08-29' - DATE(latest_purchase_date) AS recency_days,
		frequency,
		monetary,
		NTILE(4) OVER (
			ORDER BY DATE '2018-08-29' - DATE(latest_purchase_date) DESC
		) AS recency_score,
		NTILE(4) OVER (
			ORDER BY frequency
		) AS frequency_score,
		NTILE(4) OVER (
			ORDER BY monetary
		) AS monetary_score
	FROM customer_rfm
),

customer_segments AS (
    SELECT
        *,
        CASE
            WHEN recency_score >= 3
                AND frequency_score >= 3
                AND monetary_score >= 3
            THEN 'Champions'

            WHEN frequency_score >= 3
                AND monetary_score >= 3
            THEN 'Loyal Customers'

            WHEN recency_score >= 3
                AND frequency_score <= 2
            THEN 'Potential Customers'

            WHEN recency_score <= 2
                AND frequency_score >= 2
            THEN 'At Risk'

            WHEN recency_score <= 2
                AND frequency_score = 1
            THEN 'Lost Customers'

            ELSE 'Other Customers'
        END AS customer_segment
    FROM rfm_scores
)

SELECT 
	customer_unique_id,
	customer_segment,
	recency_days,
	frequency,
	monetary
FROM customer_segments
ORDER BY monetary DESC
LIMIT 20;
	

WITH customer_rfm AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp) AS latest_purchase_date,
        COUNT(DISTINCT o.order_id) AS frequency,
        ROUND(SUM(oi.price), 2) AS monetary
    FROM ecommerce.customers c
    JOIN ecommerce.orders o
        ON c.customer_id = o.customer_id
    JOIN ecommerce.order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),

rfm_scores AS (
    SELECT
        customer_unique_id,
        latest_purchase_date,
        frequency,
        monetary,
        NTILE(4) OVER (
            ORDER BY
                DATE '2018-08-29' - DATE(latest_purchase_date) DESC,
                customer_unique_id
        ) AS recency_score,
        NTILE(4) OVER (
            ORDER BY frequency, customer_unique_id
        ) AS frequency_score,
        NTILE(4) OVER (
            ORDER BY monetary, customer_unique_id
        ) AS monetary_score
    FROM customer_rfm
),

customer_segments AS (
    SELECT
        customer_unique_id,
		monetary,
        CASE
            WHEN recency_score >= 3
                AND frequency_score >= 3
                AND monetary_score >= 3
            THEN 'Champions'
            WHEN frequency_score >= 3
                AND monetary_score >= 3
            THEN 'Loyal Customers'
            WHEN recency_score >= 3
                AND frequency_score <= 2
            THEN 'Potential Customers'
            WHEN recency_score <= 2
                AND frequency_score >= 2
            THEN 'At Risk'
            WHEN recency_score <= 2
                AND frequency_score = 1
            THEN 'Lost Customers'

            ELSE 'Other Customers'
        END AS customer_segment
    FROM rfm_scores
)

SELECT
    customer_segment,
	COUNT(*) AS number_of_customers,
	ROUND(SUM(monetary), 2) AS total_revenue,
	ROUND(SUM(monetary) *100.0 / SUM(SUM(monetary)) OVER(), 2) AS revenue_percentage,
	ROUND(AVG(monetary), 2) AS avg_revenue_per_customer
FROM customer_segments
GROUP BY customer_segment
ORDER BY total_revenue DESC;


---Find out how many customers placed 1, 2, 3, 4, or 5+ delivered orders,
--and what percentage of the customer base each group represents.

WITH customer_frequency AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS frequency
    FROM ecommerce.customers c
    JOIN ecommerce.orders o
        ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),

frequency_groups AS (
    SELECT
        CASE
            WHEN frequency = 1 THEN '1 Order'
            WHEN frequency = 2 THEN '2 Orders'
            WHEN frequency = 3 THEN '3 Orders'
            WHEN frequency = 4 THEN '4 Orders'
            ELSE '5+ Orders'
        END AS frequency_group
    FROM customer_frequency
)

SELECT
    frequency_group,

    COUNT(*) AS number_of_customers,

    ROUND(
        COUNT(*) * 100.0
        / SUM(COUNT(*)) OVER (),
        2
    ) AS customer_percentage

FROM frequency_groups

GROUP BY frequency_group

ORDER BY
    CASE frequency_group
        WHEN '1 Order' THEN 1
        WHEN '2 Orders' THEN 2
        WHEN '3 Orders' THEN 3
        WHEN '4 Orders' THEN 4
        WHEN '5+ Orders' THEN 5
    END;


--Compare customers who made only one purchase with customers who made two or
--more purchases, and see how much revenue each group contributes.

WITH customer_rfm AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS frequency,
        ROUND(SUM(oi.price), 2) AS monetary
    FROM ecommerce.customers c
    JOIN ecommerce.orders o
        ON c.customer_id = o.customer_id
    JOIN ecommerce.order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),

customer_groups AS (
    SELECT
        customer_unique_id,
        frequency,
        monetary,

        CASE
            WHEN frequency = 1
                THEN 'One-Time Customers'
            ELSE 'Repeat Customers'
        END AS customer_group

    FROM customer_rfm
)

SELECT
    customer_group,

    COUNT(*) AS number_of_customers,

    ROUND(
        COUNT(*) * 100.0
        / SUM(COUNT(*)) OVER (),
        2
    ) AS customer_percentage,

    ROUND(
        SUM(monetary),
        2
    ) AS total_revenue,

    ROUND(
        SUM(monetary) * 100.0
        / SUM(SUM(monetary)) OVER (),
        2
    ) AS revenue_percentage,

    ROUND(
        AVG(monetary),
        2
    ) AS avg_revenue_per_customer

FROM customer_groups

GROUP BY customer_group

ORDER BY total_revenue DESC;


--Calculate what percentage of customers made at least one repeat purchase after
--their first delivered order.

WITH customer_frequency AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS frequency
    FROM ecommerce.customers c
    JOIN ecommerce.orders o
        ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)

SELECT
    COUNT(*) AS total_customers,
    COUNT(*) FILTER (
        WHERE frequency >= 2
    ) AS repeat_customers,
    COUNT(*) FILTER (
        WHERE frequency = 1
    ) AS one_time_customers,
    ROUND(
        COUNT(*) FILTER (WHERE frequency >= 2) * 100.0
        / COUNT(*),
        2
    ) AS repeat_purchase_rate,
    ROUND(
        COUNT(*) FILTER (WHERE frequency = 1) * 100.0
        / COUNT(*),
        2
    ) AS one_time_customer_rate
FROM customer_frequency;



--Calculate the number of days between consecutive delivered purchases for each customer
--who made multiple purchases, and find the average time between their purchases.

WITH customer_orders AS (
	SELECT
		c.customer_unique_id,
		o.order_id,
		o.order_purchase_timestamp,

		LAG(o.order_purchase_timestamp) OVER (
			PARTITION BY c.customer_unique_id
			ORDER BY o.order_purchase_timestamp
			) AS previous_purchase_date

	FROM ecommerce.customers c
	JOIN ecommerce.orders o
		ON c.customer_id = o.customer_id
	WHERE o.order_status = 'delivered'
),

purchase_interval AS(
	SELECT
		customer_unique_id,
		order_id,
		order_purchase_timestamp,
		previous_purchase_date,
		DATE(order_purchase_timestamp) - DATE(previous_purchase_date) AS days_between_purchase
	FROM customer_orders
	WHERE previous_purchase_date IS NOT NULL
)

SELECT 
	COUNT(*) AS repeat_purchase_intervals,
	COUNT(DISTINCT customer_unique_id) AS repeat_customers,
	ROUND(AVG(days_between_purchase), 2) AS avg_days_between_purchase,
	MIN(days_between_purchase) AS minimum_days,
	MAX(days_between_purchase) AS maximum_days
FROM purchase_interval;



--Group repeat-purchase intervals into day ranges to find out what percentage occur
--within 30 days, 31–60 days, 61–90 days, 91–180 days, and more than 180 days.

WITH customer_orders AS (
	SELECT
		c.customer_unique_id,
		o.order_purchase_timestamp,

		LAG(o.order_purchase_timestamp) OVER (
			PARTITION BY c.customer_unique_id
			ORDER BY o.order_purchase_timestamp
			) AS previous_purchase_date

	FROM ecommerce.customers c
	JOIN ecommerce.orders o
		ON c.customer_id = o.customer_id
	WHERE o.order_status = 'delivered'
),

purchase_intervals AS(
	SELECT
		customer_unique_id,
		DATE(order_purchase_timestamp) - DATE(previous_purchase_date) AS days_between_purchase
	FROM customer_orders
	WHERE previous_purchase_date IS NOT NULL
),

interval_groups AS(
	SELECT
		CASE
			WHEN days_between_purchase<=30
				THEN '0-30 Days'
			WHEN days_between_purchase<=60
				THEN '31-60 Days'
			WHEN days_between_purchase<=90
				THEN '61-90 Days'
			WHEN days_between_purchase<=180
				THEN '91-180 Days'
			ELSE '180+ Days'

		END AS purchase_interval_group

	FROM purchase_intervals
)

SELECT 
	purchase_interval_group,
	COUNT(*) AS number_of_intervals,
	ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS interval_percantage
FROM interval_groups 	
GROUP BY purchase_interval_group
ORDER BY 
	CASE purchase_interval_group
		WHEN '0-30 Days' THEN 1
		WHEN '31-60 Days' THEN 2
		WHEN '61-90 Days' THEN 3
		WHEN '91-180 Days' THEN 4
		WHEN '180+ Days' THEN 5
	END;


--Calculate each repeat customer's average, shortest, and longest time between consecutive
--delivered purchases, and identify customers who return quickly versus those who take longer
--to purchase again.

WITH customer_orders AS (
	SELECT
		c.customer_unique_id,
		o.order_id,
		o.order_purchase_timestamp,

		LAG(o.order_purchase_timestamp) OVER (
			PARTITION BY c.customer_unique_id
			ORDER BY o.order_purchase_timestamp
			) AS previous_purchase_date

	FROM ecommerce.customers c
	JOIN ecommerce.orders o
		ON c.customer_id = o.customer_id
	WHERE o.order_status = 'delivered'
),

purchase_intervals AS(
	SELECT
		customer_unique_id,
		DATE(order_purchase_timestamp) - DATE(previous_purchase_date) AS days_between_purchase
	FROM customer_orders
	WHERE previous_purchase_date IS NOT NULL
)

SELECT
	customer_unique_id,
	COUNT(*) AS purchase_intervals,
	ROUND(AVG(days_between_purchase), 2) AS avg_days_between_purchase,
	MIN(days_between_purchase) AS minimum_days,
	MAX(days_between_purchase) AS maximum_days
FROM purchase_intervals
GROUP BY customer_unique_id
ORDER BY purchase_intervals DESC, avg_days_between_purchase ASC
LIMIT 20;



--Analyze how the number of delivered orders relates to customers' total spending
--and average spending per customer.

WITH customer_spending AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS purchase_frequency,
        ROUND(SUM(oi.price), 2) AS total_spending
    FROM ecommerce.customers c
    JOIN ecommerce.orders o
        ON c.customer_id = o.customer_id
    JOIN ecommerce.order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),

frequency_groups AS (
    SELECT
        customer_unique_id,
        purchase_frequency,
        total_spending,
        CASE
            WHEN purchase_frequency = 1 THEN '1 Order'
            WHEN purchase_frequency = 2 THEN '2 Orders'
            WHEN purchase_frequency = 3 THEN '3 Orders'
            WHEN purchase_frequency = 4 THEN '4 Orders'
            ELSE '5+ Orders'
        END AS frequency_group
    FROM customer_spending
)

SELECT
    frequency_group,
    COUNT(*) AS number_of_customers,
    ROUND(AVG(purchase_frequency), 2)
        AS avg_purchase_frequency,
    ROUND(SUM(total_spending), 2)
        AS total_revenue,
    ROUND(AVG(total_spending), 2)
        AS avg_spending_per_customer
FROM frequency_groups
GROUP BY frequency_group
ORDER BY
    CASE frequency_group
        WHEN '1 Order' THEN 1
        WHEN '2 Orders' THEN 2
        WHEN '3 Orders' THEN 3
        WHEN '4 Orders' THEN 4
        WHEN '5+ Orders' THEN 5
    END;

-- ================================================================
-- DIAGNOSTIC: TIED FREQUENCY VALUES SPLIT ACROSS NTILE BUCKETS
-- If a frequency value receives multiple scores, NTILE is splitting customers
-- with identical order counts across score buckets. Review before finalizing RFM.
-- This is a diagnostic query; it does not alter the canonical RFM scoring.
-- ================================================================
WITH customer_frequency AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS frequency
    FROM ecommerce.customers c
    JOIN ecommerce.orders o ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
frequency_scores AS (
    SELECT
        customer_unique_id,
        frequency,
        NTILE(4) OVER (ORDER BY frequency, customer_unique_id) AS frequency_score
    FROM customer_frequency
)
SELECT
    frequency,
    COUNT(*) AS number_of_customers,
    COUNT(DISTINCT frequency_score) AS scores_assigned
FROM frequency_scores
GROUP BY frequency
HAVING COUNT(DISTINCT frequency_score) > 1
ORDER BY frequency;


--Meaningful purchasing behavior

WITH customer_frequency AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS frequency
    FROM ecommerce.customers c
    JOIN ecommerce.orders o
        ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
frequency_scores AS (
    SELECT
        customer_unique_id,
        frequency,
        CASE
            WHEN frequency = 1 THEN 1
            WHEN frequency = 2 THEN 2
            WHEN frequency = 3 THEN 3
            ELSE 4
        END AS frequency_score
    FROM customer_frequency
)
SELECT
    frequency,
    frequency_score,
    COUNT(*) AS number_of_customers
FROM frequency_scores
GROUP BY frequency, frequency_score
ORDER BY frequency, frequency_score;


--Updated RFM

WITH customer_rfm AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp) AS latest_purchase_date,
        COUNT(DISTINCT o.order_id) AS frequency,
        ROUND(SUM(oi.price), 2) AS monetary
    FROM ecommerce.customers c
    JOIN ecommerce.orders o
        ON c.customer_id = o.customer_id
    JOIN ecommerce.order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),

rfm_scores AS (
    SELECT
        customer_unique_id,
        latest_purchase_date,
        frequency,
        monetary,

        NTILE(4) OVER (
            ORDER BY
                DATE '2018-08-29' - DATE(latest_purchase_date) DESC,
                customer_unique_id
        ) AS recency_score,

        CASE
            WHEN frequency = 1 THEN 1
            WHEN frequency = 2 THEN 2
            WHEN frequency = 3 THEN 3
            ELSE 4
        END AS frequency_score,

        NTILE(4) OVER (
            ORDER BY monetary, customer_unique_id
        ) AS monetary_score

    FROM customer_rfm
),

customer_segments AS (
    SELECT
        customer_unique_id,
        monetary,
        CASE
            WHEN recency_score >= 3
                AND frequency_score >= 3
                AND monetary_score >= 3
            THEN 'Champions'

            WHEN frequency_score >= 3
                AND monetary_score >= 3
            THEN 'Loyal Customers'

            WHEN recency_score >= 3
                AND frequency_score <= 2
            THEN 'Potential Customers'

            WHEN recency_score <= 2
                AND frequency_score >= 2
            THEN 'At Risk'

            WHEN recency_score <= 2
                AND frequency_score = 1
            THEN 'Lost Customers'

            ELSE 'Other Customers'
        END AS customer_segment
    FROM rfm_scores
)

SELECT
    customer_segment,
    COUNT(*) AS number_of_customers,
    ROUND(SUM(monetary), 2) AS total_revenue,
    ROUND(
        SUM(monetary) * 100.0
        / NULLIF(SUM(SUM(monetary)) OVER (), 0),
        2
    ) AS revenue_percentage,
    ROUND(AVG(monetary), 2) AS avg_revenue_per_customer
FROM customer_segments
GROUP BY customer_segment
ORDER BY total_revenue DESC;