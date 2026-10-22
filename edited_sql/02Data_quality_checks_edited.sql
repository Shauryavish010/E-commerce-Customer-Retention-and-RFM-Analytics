SELECT 'customers' AS table_name, COUNT(*) AS row_count
FROM ecommerce.customers

UNION ALL

SELECT 'orders', COUNT(*)
FROM ecommerce.orders

UNION ALL

SELECT 'products', COUNT(*)
FROM ecommerce.products

UNION ALL

SELECT 'sellers', COUNT(*)
FROM ecommerce.sellers

UNION ALL

SELECT 'order_items', COUNT(*)
FROM ecommerce.order_items

UNION ALL

SELECT 'payments', COUNT(*)
FROM ecommerce.payments

UNION ALL

SELECT 'reviews', COUNT(*)
FROM ecommerce.reviews;


SELECT
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS missing_customer_id,
    COUNT(*) FILTER (WHERE customer_unique_id IS NULL) AS missing_unique_id,
    COUNT(*) FILTER (WHERE customer_city IS NULL) AS missing_city,
    COUNT(*) FILTER (WHERE customer_state IS NULL) AS missing_state
FROM ecommerce.customers;


SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS missing_customer_id,
    COUNT(*) FILTER (WHERE order_status IS NULL) AS missing_status,
    COUNT(*) FILTER (
        WHERE order_purchase_timestamp IS NULL
    ) AS missing_purchase_date
FROM ecommerce.orders;


SELECT
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id,
    COUNT(*) FILTER (WHERE product_id IS NULL) AS missing_product_id,
    COUNT(*) FILTER (WHERE seller_id IS NULL) AS missing_seller_id,
    COUNT(*) FILTER (WHERE price IS NULL) AS missing_price
FROM ecommerce.order_items;

-- ================================================================
-- ADDITIONAL REFERENTIAL-INTEGRITY CHECKS
-- Expected result for each orphan check: 0 rows/count.
-- Run these before adding foreign-key constraints to the schema.
-- ================================================================

SELECT COUNT(*) AS orphan_orders_without_customer
FROM ecommerce.orders o
LEFT JOIN ecommerce.customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL;

SELECT COUNT(*) AS order_items_without_order
FROM ecommerce.order_items oi
LEFT JOIN ecommerce.orders o ON o.order_id = oi.order_id
WHERE o.order_id IS NULL;

SELECT COUNT(*) AS order_items_without_product
FROM ecommerce.order_items oi
LEFT JOIN ecommerce.products p ON p.product_id = oi.product_id
WHERE p.product_id IS NULL;

SELECT COUNT(*) AS order_items_without_seller
FROM ecommerce.order_items oi
LEFT JOIN ecommerce.sellers s ON s.seller_id = oi.seller_id
WHERE s.seller_id IS NULL;

SELECT COUNT(*) AS payments_without_order
FROM ecommerce.payments p
LEFT JOIN ecommerce.orders o ON o.order_id = p.order_id
WHERE o.order_id IS NULL;

SELECT COUNT(*) AS reviews_without_order
FROM ecommerce.reviews r
LEFT JOIN ecommerce.orders o ON o.order_id = r.order_id
WHERE o.order_id IS NULL;

-- ================================================================
-- VALUE / DATE QUALITY CHECKS
-- These checks report issues; they do not modify or delete data.
-- ================================================================

SELECT
    COUNT(*) FILTER (WHERE price IS NULL) AS missing_price,
    COUNT(*) FILTER (WHERE price < 0) AS negative_price,
    COUNT(*) FILTER (WHERE freight_value IS NULL) AS missing_freight,
    COUNT(*) FILTER (WHERE freight_value < 0) AS negative_freight
FROM ecommerce.order_items;

SELECT
    COUNT(*) FILTER (WHERE review_score IS NULL) AS missing_review_score,
    COUNT(*) FILTER (WHERE review_score NOT BETWEEN 1 AND 5) AS invalid_review_score
FROM ecommerce.reviews;

SELECT
    COUNT(*) FILTER (WHERE order_purchase_timestamp IS NULL) AS missing_purchase_timestamp,
    COUNT(*) FILTER (
        WHERE order_delivered_customer_date < order_purchase_timestamp
    ) AS delivered_before_purchase,
    COUNT(*) FILTER (
        WHERE order_delivered_carrier_date < order_purchase_timestamp
    ) AS carrier_before_purchase,
    COUNT(*) FILTER (
        WHERE order_delivered_customer_date > order_estimated_delivery_date
    ) AS delivered_after_estimate
FROM ecommerce.orders;

-- Check review_id uniqueness before considering it as a primary key.
SELECT
    COUNT(*) FILTER (WHERE review_id IS NULL) AS null_review_ids,
    COUNT(*) - COUNT(DISTINCT review_id) AS duplicate_review_id_rows
FROM ecommerce.reviews;
