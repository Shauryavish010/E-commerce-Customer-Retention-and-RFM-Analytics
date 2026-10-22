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