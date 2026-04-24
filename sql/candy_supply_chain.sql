CREATE SCHEMA IF NOT EXISTS candy;
SET search_path TO candy;

-- Raw tables

DROP TABLE IF EXISTS raw_sales CASCADE;
CREATE TABLE raw_sales (
    row_id          INT,
    order_id        VARCHAR(60),
    order_date      DATE,
    ship_date       DATE,
    ship_mode       VARCHAR(30),
    customer_id     INT,
    country         VARCHAR(50),
    city            VARCHAR(80),
    state           VARCHAR(80),
    postal_code     VARCHAR(20),
    division        VARCHAR(30),
    region          VARCHAR(30),
    product_id      VARCHAR(30),
    product_name    VARCHAR(100),
    sales           NUMERIC(10, 2),
    units           INT,
    gross_profit    NUMERIC(10, 2),
    cost            NUMERIC(10, 2)
);
SELECT COUNT(*) FROM raw_sales;

DROP TABLE IF EXISTS raw_products CASCADE;
CREATE TABLE raw_products (
    division        VARCHAR(30),
    product_name    VARCHAR(100),
    factory         VARCHAR(60),
    product_id      VARCHAR(30),
    unit_price      NUMERIC(10, 2),
    unit_cost       NUMERIC(10, 2)
);
SELECT * FROM raw_products;

DROP TABLE IF EXISTS raw_factories CASCADE;
CREATE TABLE raw_factories (
    factory         VARCHAR(60),
    latitude        NUMERIC(10, 6),
    longitude       NUMERIC(10, 6)
);

DROP TABLE IF EXISTS raw_targets CASCADE;
CREATE TABLE raw_targets (
    division        VARCHAR(30),
    annual_target   NUMERIC(12, 2)
);

DROP TABLE IF EXISTS raw_expected_delivery CASCADE;
CREATE TABLE raw_expected_delivery (
    factory                  VARCHAR(60),
    expected_delivery_days   INT
);

DROP TABLE IF EXISTS raw_supplier_performance CASCADE;
CREATE TABLE raw_supplier_performance (
    factory             VARCHAR(60),
    avg_lead_time       NUMERIC(5, 1),
    delay_pct           NUMERIC(5, 1),
    reliability_score   NUMERIC(5, 1)
);

DROP TABLE IF EXISTS raw_inventory_staging;
CREATE TABLE raw_inventory_staging (
    product         VARCHAR(100),
    inventory_date  VARCHAR(20),   -- load as text, parse in cleaning step
    opening_stock   INT,
    closing_stock   INT,
    reorder_point   INT,
    safety_stock    INT,
    replenishment   INT
);
SELECT * FROM raw_inventory_staging;      --180 ROWS- 15 products x 12 months

-- Quick row-count sanity check

SELECT 'raw_sales' AS table_name, COUNT(*) AS row_count FROM raw_sales
UNION ALL
SELECT 'raw_products', COUNT(*) FROM raw_products
UNION ALL
SELECT 'raw_factories',  COUNT(*) FROM raw_factories
UNION ALL
SELECT 'raw_targets', COUNT(*) FROM raw_targets
UNION ALL
SELECT 'raw_expected_delivery', COUNT(*) FROM raw_expected_delivery
UNION ALL
SELECT 'raw_supplier_performance', COUNT(*) FROM raw_supplier_performance
UNION ALL
SELECT 'raw_inventory_staging', COUNT(*) FROM raw_inventory_staging
ORDER BY table_name;

-- Data Cleaning & Cleaned Table Creation

-- A) SALES CLEANING

-- A1. Inspect before cleaning

-- Null check
SELECT COUNT(*) AS total_rows,
COUNT(*) FILTER (WHERE order_id IS NULL) AS null_order_id,
COUNT(*) FILTER (WHERE order_date IS NULL) AS null_order_date,
COUNT(*) FILTER (WHERE ship_date IS NULL) AS null_ship_date,
COUNT(*) FILTER (WHERE product_id IS NULL) AS null_product_id,
COUNT(*) FILTER (WHERE sales IS NULL) AS null_sales,
COUNT(*) FILTER (WHERE units IS NULL) AS null_units,
COUNT(*) FILTER (WHERE gross_profit IS NULL) AS null_gross_profit,
COUNT(*) FILTER (WHERE cost IS NULL) AS null_cost
FROM raw_sales;

-- Lead time distribution (should be 5–30 days per project spec)
SELECT MIN(ship_date - order_date) AS min_lead_days,
MAX(ship_date - order_date) AS max_lead_days,
ROUND(AVG(ship_date - order_date), 1) AS avg_lead_days
FROM raw_sales;

-- Negative or zero sales / profit check
SELECT COUNT(*) AS suspect_rows
FROM raw_sales
WHERE sales <= 0 OR cost <= 0 OR units <= 0;

-- Duplicate order_id + product_id combinations
SELECT order_id, product_id, COUNT(*) AS count
FROM raw_sales
GROUP BY order_id, product_id
HAVING COUNT(*) > 1;                   -- there are 1000 rows

-- True duplicates
SELECT COUNT(*) AS true_duplicates
FROM raw_sales s1
WHERE EXISTS (
    SELECT 1 
    FROM raw_sales s2
    WHERE s1.order_id   = s2.order_id
    AND   s1.product_id = s2.product_id
    AND   s1.ship_date  = s2.ship_date
    AND   s1.sales      = s2.sales
    AND   s1.units      = s2.units
    AND   s1.row_id    != s2.row_id
);                                        -- Result : 104 rows


-- A2. Create clean sales table
DROP TABLE IF EXISTS clean_sales CASCADE;
CREATE TABLE clean_sales AS
SELECT MIN(row_id),
 order_id, order_date, ship_date, 
 (ship_date - order_date) AS lead_days,
 ship_mode, customer_id, country, city, state, postal_code, division, region, 
 product_id, product_name, sales, units, gross_profit, cost,
ROUND(gross_profit / NULLIF(sales, 0) * 100, 2) AS margin_pct,      -- margin percentage
EXTRACT(YEAR  FROM order_date)::INT AS order_year,
EXTRACT(MONTH FROM order_date)::INT AS order_month,
EXTRACT(QUARTER FROM order_date)::INT AS order_quarter,
TO_CHAR(order_date, 'YYYY-MM') AS year_month
FROM raw_sales
WHERE
    sales        > 0
    AND cost     > 0
    AND units    > 0
    AND order_date IS NOT NULL
    AND ship_date  IS NOT NULL
    AND ship_date >= order_date             -- guard against inverted dates
GROUP BY
    order_id, order_date, ship_date, ship_mode, customer_id, country, city, state, 
	postal_code, division, region, product_id, product_name, sales, units, gross_profit, cost;
	
-- Verify
SELECT COUNT (*) AS clean_sales_rows FROM clean_sales;        -- Result : 10140
SELECT * FROM clean_sales;

--A3. Final Verification
SELECT 
    COUNT(*)                    AS total_rows,
    MIN(order_date)             AS earliest_order,
    MAX(order_date)             AS latest_order,
    MIN(lead_days)              AS min_lead_days,
    MAX(lead_days)              AS max_lead_days,
    ROUND(AVG(margin_pct), 2)   AS avg_margin_pct
FROM clean_sales;

-- B) PRODUCT & FACTORY CLEANING

--B1. Check for product IDs in sales that don't exist in products master
SELECT DISTINCT s.product_id
FROM raw_sales s
LEFT JOIN raw_products p ON s.product_id = p.product_id
WHERE p.product_id IS NULL;                       -- Result : no rows (Every product sold in raw_sales exists in raw_products)

--B2. Check for factory names in products that don't exist in factories master
SELECT DISTINCT p.factory
FROM raw_products p
LEFT JOIN raw_factories f ON p.factory = f.factory
WHERE f.factory IS NULL;                         -- Result : no rows (Every factory in raw_products exists in raw_factories)

--B3. Clean products — add margin column
DROP TABLE IF EXISTS clean_products CASCADE;
CREATE TABLE clean_products AS
SELECT
    division,
    product_name,
    factory,
    product_id,
    unit_price,
    unit_cost,
    ROUND((unit_price - unit_cost) / NULLIF(unit_price, 0) * 100, 2) AS unit_margin_pct    --Unit margin percentage
FROM raw_products;
SELECT * FROM clean_products;

-- C) SUPPLIER & DELIVERY CLEANING

--C1. Check: all factories in supplier table exist in factories master
SELECT s.factory
FROM raw_supplier_performance s
LEFT JOIN raw_factories f ON s.factory = f.factory
WHERE f.factory IS NULL;

--C2. Check: all factories in expected_delivery exist in supplier table
SELECT e.factory
FROM raw_expected_delivery e
LEFT JOIN raw_supplier_performance s ON e.factory = s.factory
WHERE s.factory IS NULL;

--C3. Clean supplier — merge with expected delivery and derive gap metrics
DROP TABLE IF EXISTS clean_supplier CASCADE;
CREATE TABLE clean_supplier AS
SELECT
    sp.factory,
    sp.avg_lead_time,
    sp.delay_pct,
    sp.reliability_score,
    ed.expected_delivery_days,
    ROUND(sp.avg_lead_time - ed.expected_delivery_days, 1) AS lead_time_gap,
    CASE
        WHEN sp.avg_lead_time > ed.expected_delivery_days THEN 'Over SLA'
        ELSE 'Within SLA'
    END AS sla_status,
    CASE
        WHEN sp.reliability_score >= 85 THEN 'High'
        WHEN sp.reliability_score >= 75 THEN 'Medium'
        ELSE 'Low'
    END AS reliability_tier
FROM raw_supplier_performance sp
JOIN raw_expected_delivery ed ON sp.factory = ed.factory;

SELECT * FROM clean_supplier ORDER BY reliability_score DESC;

-- D) INVENTORY CLEANING

-- D1. Parse DD-MM-YYYY date string and cast to proper DATE
DROP TABLE IF EXISTS clean_inventory CASCADE;
CREATE TABLE clean_inventory AS
SELECT
    product,
    TO_DATE(inventory_date, 'DD-MM-YYYY') AS inventory_date,
    EXTRACT(MONTH FROM TO_DATE(inventory_date, 'DD-MM-YYYY'))::INT AS inv_month,
    EXTRACT(YEAR  FROM TO_DATE(inventory_date, 'DD-MM-YYYY'))::INT AS inv_year,
    opening_stock,
    closing_stock,
    reorder_point,
    safety_stock,
    replenishment,
    -- Derived risk flags
    CASE WHEN closing_stock < reorder_point  THEN TRUE ELSE FALSE END AS below_reorder_point,
    CASE WHEN closing_stock < safety_stock   THEN TRUE ELSE FALSE END AS below_safety_stock,
    -- Net stock change in the period
    (closing_stock - opening_stock) AS net_stock_change
FROM raw_inventory_staging;

SELECT * FROM clean_inventory;

-- D2. Validate the logical hierarchy holds (should all return 0 after the fix)
SELECT
    COUNT(*) FILTER (WHERE safety_stock   >= reorder_point) AS ss_above_rop,
    COUNT(*) FILTER (WHERE reorder_point  >= opening_stock)  AS rop_above_opening,
    COUNT(*) FILTER (WHERE safety_stock   >= opening_stock)  AS ss_above_opening
FROM clean_inventory;

-- E) MASTER JOIN VIEW

-- E.1) Used throughout analysis files to avoid repeated joins
DROP VIEW IF EXISTS v_sales_enriched CASCADE;
CREATE VIEW v_sales_enriched AS
SELECT
    cs.*,
    p.factory,
    p.unit_price,
    p.unit_cost,
    p.unit_margin_pct,
    sup.avg_lead_time,
    sup.delay_pct,
    sup.reliability_score,
    sup.lead_time_gap,
    sup.sla_status,
    sup.reliability_tier,
    f.latitude,
    f.longitude
FROM clean_sales cs
JOIN clean_products p ON cs.product_id = p.product_id
JOIN clean_supplier sup ON p.factory = sup.factory
JOIN raw_factories f ON p.factory = f.factory;

SELECT * FROM v_sales_enriched;

-- E.2) Quick check — should match clean_sales row count
SELECT COUNT(*) AS enriched_rows FROM v_sales_enriched;


-- SECTION 1- Sales Performance Analysis (2021–2024)

SET search_path TO candy;

-- 1.1  BUSINESS-LEVEL KPIs
SELECT
    COUNT (*) AS total_transactions,
    COUNT (DISTINCT customer_id) AS unique_customers,
    COUNT (DISTINCT product_id) AS unique_products,
    SUM(sales) AS total_revenue,
    SUM(gross_profit) AS total_gross_profit,
    ROUND(SUM(gross_profit) / SUM(sales) * 100, 1) AS overall_margin_pct,
    SUM(units) AS total_units_sold,
    MIN(order_date) AS earliest_order,
    MAX(order_date) AS latest_order
FROM clean_sales;

-- 1.2  ANNUAL REVENUE TREND & YoY GROWTH

WITH yearly AS (
    SELECT
        order_year,
        SUM(sales) AS revenue,
        SUM(gross_profit) AS gross_profit,
        SUM(units) AS units_sold
    FROM clean_sales
    GROUP BY order_year
)
SELECT
    order_year,
    revenue,
    gross_profit,
    units_sold,
    ROUND(gross_profit / NULLIF(revenue, 0) * 100, 1) AS margin_pct,
    ROUND((revenue - LAG(revenue) OVER (ORDER BY order_year))
        / NULLIF(LAG(revenue) OVER (ORDER BY order_year), 0) * 100, 1) AS yoy_growth_pct
FROM yearly
ORDER BY order_year;

-- 1.3  REVENUE CAGR (2021 → 2024)
WITH endpoints AS (
    SELECT
        MIN(CASE WHEN order_year = 2021 THEN revenue END) AS rev_2021,
        MIN(CASE WHEN order_year = 2024 THEN revenue END) AS rev_2024
    FROM (
        SELECT order_year, SUM(sales) AS revenue
        FROM clean_sales
        GROUP BY order_year
    ) y
)
SELECT
    rev_2021,
    rev_2024,
    ROUND((POWER(rev_2024::NUMERIC / rev_2021, 1.0/3) - 1) * 100, 2) AS cagr_pct
FROM endpoints;

-- 1.4  DIVISION PERFORMANCE vs ANNUAL TARGETS
WITH div_sales AS (
    SELECT
        division,
        order_year,
        SUM(sales)        AS revenue,
        SUM(gross_profit) AS gross_profit,
        SUM(units)        AS units
    FROM clean_sales
    GROUP BY division, order_year
),
div_totals AS (
    SELECT division,
        SUM(revenue)      AS total_revenue,
        SUM(gross_profit) AS total_gp,
        SUM(units)        AS total_units
    FROM div_sales
    GROUP BY division
)
SELECT
    dt.division,
    dt.total_revenue,
    dt.total_gp,
    dt.total_units,
    ROUND(dt.total_gp / NULLIF(dt.total_revenue, 0) * 100, 1) AS margin_pct,
    t.annual_target,
    t.annual_target* 4 AS four_yr_target,
    ROUND((dt.total_revenue - t.annual_target * 4)/ NULLIF(t.annual_target * 4, 0) * 100, 1) AS vs_target_pct,
    CASE WHEN dt.total_revenue >= t.annual_target * 4 THEN 'Target Met'
        ELSE 'Below Target'
    END AS target_status
FROM div_totals dt
JOIN raw_targets t ON dt.division = t.division
ORDER BY dt.total_revenue DESC;

-- 1.5  PRODUCT PERFORMANCE — RANKED
SELECT
    product_name,
    division,
    SUM(sales) AS revenue,
    SUM(gross_profit) AS gross_profit,
    SUM(units) AS units_sold,
    ROUND(SUM(gross_profit) / NULLIF(SUM(sales), 0) * 100, 1)    AS margin_pct,
    ROUND(SUM(sales) / SUM(SUM(sales)) OVER () * 100, 1)         AS revenue_share_pct,
    RANK() OVER (ORDER BY SUM(sales) DESC)                       AS revenue_rank
FROM clean_sales
GROUP BY product_name, division
ORDER BY revenue_rank;

-- 1.6  PRODUCT REVENUE TREND BY YEAR
SELECT product_name, 
	   order_year,
       SUM(sales) AS revenue,
       SUM(units) AS units
FROM clean_sales
GROUP BY product_name, order_year
ORDER BY product_name, order_year;


-- 1.7  REGIONAL PERFORMANCE
SELECT
    region,
    COUNT(DISTINCT customer_id) AS customers,
    COUNT(DISTINCT order_id) AS orders,
    SUM(sales) AS revenue,
    SUM(gross_profit) AS gross_profit,
    ROUND(SUM(gross_profit) / NULLIF(SUM(sales), 0) * 100, 1) AS margin_pct,
    ROUND(SUM(sales) / SUM(SUM(sales)) OVER () * 100, 1) AS revenue_share_pct,
    RANK() OVER (ORDER BY SUM(sales) DESC) AS revenue_rank
FROM clean_sales
GROUP BY region
ORDER BY revenue_rank;

-- 1.8  MONTHLY SEASONALITY (average sales per calendar month across all years)
SELECT
    order_month,
    TO_CHAR(TO_DATE(order_month::TEXT, 'MM'), 'Month') AS month_name,
    ROUND(AVG(monthly_revenue), 2) AS avg_monthly_revenue,
    ROUND(SUM(monthly_revenue), 2) AS total_revenue
FROM (
    SELECT
        order_year,
        order_month,
        SUM(sales) AS monthly_revenue
    FROM clean_sales
    GROUP BY order_year, order_month
) m
GROUP BY order_month
ORDER BY order_month;

-- 1.9  SHIP MODE ANALYSIS
SELECT
    ship_mode,
    COUNT(*) AS transactions,
    ROUND((COUNT(*) * 100.0 )/ SUM(COUNT(*)) OVER (), 1) AS pct_of_orders,
    SUM(sales)               AS revenue,
    ROUND(AVG(lead_days), 1) AS avg_lead_days,
    MIN(lead_days)           AS min_lead_days,
    MAX(lead_days)           AS max_lead_days
FROM clean_sales
GROUP BY ship_mode
ORDER BY transactions DESC;

-- 4.10  TOP 10 CUSTOMERS BY REVENUE
SELECT
    customer_id,
    COUNT(DISTINCT order_id)                                  AS total_orders,
    SUM(sales)                                                AS total_revenue,
    SUM(gross_profit)                                         AS total_gp,
    ROUND(SUM(gross_profit) / NULLIF(SUM(sales), 0) * 100, 1) AS margin_pct,
    MIN(order_date)                                           AS first_order,
    MAX(order_date)                                           AS last_order,
    RANK() OVER (ORDER BY SUM(sales) DESC)                    AS revenue_rank
FROM clean_sales
GROUP BY customer_id
ORDER BY revenue_rank
LIMIT 10;

-- 1.11  MONTHLY REVENUE TIME SERIES — for Power BI line chart
SELECT
    year_month,
    order_year,
    order_month,
    division,
    SUM(sales)        AS revenue,
    SUM(gross_profit) AS gross_profit,
    SUM(units)        AS units
FROM clean_sales
GROUP BY year_month, order_year, order_month, division
ORDER BY year_month, division;

-- SECTION 2 — Supply Chain Diagnostic

SET search_path TO candy;
SELECT * FROM clean_supplier;

-- 2.1  SUPPLIER OVERVIEW — RELIABILITY vs SLA
SELECT
    factory,
    avg_lead_time,
    expected_delivery_days,
    lead_time_gap,
    sla_status,
    delay_pct,
    reliability_score,
    reliability_tier,
    -- Risk score: weighted composite (higher = more concern)
    ROUND((delay_pct * 0.4) + (GREATEST(lead_time_gap, 0) * 2) + ((100 - reliability_score) * 0.3), 1) 
	AS composite_risk_score
FROM clean_supplier
ORDER BY composite_risk_score DESC;

-- 2.2  FACTORY REVENUE CONTRIBUTION
-- Joins sales → products → supplier to link revenue to source factory
SELECT
    p.factory,
    COUNT(DISTINCT s.product_id)  AS products_manufactured,
    COUNT(DISTINCT s.customer_id) AS customers_served,
    SUM(s.sales)                  AS total_revenue,
    SUM(s.gross_profit)           AS total_gp,
    SUM(s.units)                  AS total_units,
    ROUND(SUM(s.gross_profit) / NULLIF(SUM(s.sales), 0) * 100, 1) AS margin_pct,
    ROUND(SUM(s.sales) / SUM(SUM(s.sales)) OVER () * 100, 1)      AS revenue_share_pct,
    sup.reliability_score,
    sup.avg_lead_time,
    sup.lead_time_gap,
    sup.sla_status,
    sup.delay_pct
FROM clean_sales    s
JOIN clean_products p   ON s.product_id = p.product_id
JOIN clean_supplier sup ON p.factory    = sup.factory
GROUP BY
    p.factory,
    sup.reliability_score,
    sup.avg_lead_time,
    sup.lead_time_gap,
    sup.sla_status,
	sup.delay_pct
ORDER BY total_revenue DESC;

-- 2.3  FACTORY REVENUE TREND BY YEAR
-- Tracks whether factory output (in revenue terms) is growing or shrinking
SELECT
    p.factory,
    s.order_year,
    SUM(s.sales) AS revenue,
    SUM(s.units) AS units,
    ROUND(
        (SUM(s.sales) - LAG(SUM(s.sales)) OVER (PARTITION BY p.factory ORDER BY s.order_year))
        / NULLIF(LAG(SUM(s.sales)) OVER (PARTITION BY p.factory ORDER BY s.order_year), 0) * 100, 1)                
			AS yoy_growth_pct
FROM clean_sales    s
JOIN clean_products p ON s.product_id = p.product_id
GROUP BY p.factory, s.order_year
ORDER BY p.factory, s.order_year;

-- 2.4  DELIVERY PERFORMANCE — ACTUAL vs EXPECTED LEAD TIMES
-- Compares actual order lead days from sales to contracted SLA
WITH order_lead AS (
    SELECT
        p.factory,
        s.ship_mode,
        AVG(s.lead_days)    AS avg_actual_lead_days,
        MIN(s.lead_days)    AS min_lead_days,
        MAX(s.lead_days)    AS max_lead_days,
        COUNT(*)            AS order_count
    FROM clean_sales    s
    JOIN clean_products p ON s.product_id = p.product_id
    GROUP BY p.factory, s.ship_mode
)
SELECT
    ol.factory,
    ol.ship_mode,
    ol.order_count,
    ROUND(ol.avg_actual_lead_days, 1)                             AS avg_actual_lead_days,
    cs.expected_delivery_days,
    ROUND(ol.avg_actual_lead_days - cs.expected_delivery_days, 1) AS lead_gap_days,
    CASE
        WHEN ol.avg_actual_lead_days > cs.expected_delivery_days THEN 'Exceeds SLA'
        ELSE 'Within SLA'
    END                                                            AS delivery_status
FROM order_lead     ol
JOIN clean_supplier cs ON ol.factory = cs.factory
ORDER BY ol.factory, ol.ship_mode;

-- 2.5  SUPPLIER RISK MATRIX
-- Quadrant classification: Revenue impact × Reliability risk
-- High revenue + low reliability = highest priority
WITH factory_metrics AS (
    SELECT
        p.factory,
        SUM(s.sales) AS revenue,
        sup.reliability_score,
        sup.delay_pct,
        sup.lead_time_gap,
        sup.sla_status
    FROM clean_sales    s
    JOIN clean_products p   ON s.product_id = p.product_id
    JOIN clean_supplier sup ON p.factory    = sup.factory
    GROUP BY p.factory, sup.reliability_score, sup.delay_pct, sup.lead_time_gap, sup.sla_status
),
medians AS (
    SELECT
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY revenue)           AS median_revenue,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY reliability_score) AS median_reliability
    FROM factory_metrics
)
SELECT
    fm.factory,
    ROUND(fm.revenue, 0) AS revenue,
    fm.reliability_score,
    fm.delay_pct,
    fm.sla_status,
    CASE
        WHEN fm.revenue >= m.median_revenue AND fm.reliability_score <  m.median_reliability
            THEN '🔴 Critical  — High Revenue, Low Reliability'
        WHEN fm.revenue >= m.median_revenue AND fm.reliability_score >= m.median_reliability
            THEN '🟢 Stable    — High Revenue, High Reliability'
        WHEN fm.revenue <  m.median_revenue AND fm.reliability_score <  m.median_reliability
            THEN '🟡 Monitor   — Low Revenue, Low Reliability'
        ELSE '🔵 Efficient — Low Revenue, High Reliability'
    END AS risk_quadrant
FROM factory_metrics fm
CROSS JOIN medians m
ORDER BY fm.revenue DESC;

-- 2.6  PRODUCT-LEVEL FACTORY DEPENDENCY
-- Shows which products are single-sourced (factory dependency risk)
WITH product_factory_count AS (
    SELECT
        product_name,
        COUNT(DISTINCT factory) AS factory_count
    FROM clean_products
    GROUP BY product_name
)
SELECT
    p.product_name,
    p.factory,
    p.division,
    SUM(s.sales)            AS product_revenue,
    sup.reliability_score,
    sup.sla_status,
    CASE
        WHEN pfc.factory_count = 1 THEN '⚠️ Single-Sourced'
        ELSE 'Multi-Sourced'
    END                     AS sourcing_risk
FROM clean_sales    s
JOIN clean_products         p   ON s.product_id  = p.product_id
JOIN clean_supplier         sup ON p.factory      = sup.factory
JOIN product_factory_count  pfc ON p.product_name = pfc.product_name
GROUP BY
    p.product_name,
    p.factory,
    p.division,
    sup.reliability_score,
    sup.sla_status,
    pfc.factory_count
ORDER BY product_revenue DESC;

-- SECTION 4 — Inventory Planning & Stockout Risk Analysis

SET search_path TO candy;
SELECT * FROM clean_inventory;

-- 4.1  OVERALL INVENTORY HEALTH SUMMARY
SELECT
    COUNT(*)                     AS total_records,
    COUNT(DISTINCT product)      AS products_tracked,
    COUNT(DISTINCT inv_month)    AS months_tracked,
    ROUND(AVG(opening_stock), 0) AS avg_opening_stock,
    ROUND(AVG(closing_stock), 0) AS avg_closing_stock,
    ROUND(AVG(safety_stock), 0)  AS avg_safety_stock,
    ROUND(AVG(reorder_point), 0) AS avg_reorder_point,
    -- % of records where stock is below reorder point
    ROUND( COUNT(*) FILTER (WHERE below_reorder_point) * 100.0 / COUNT(*), 1) AS pct_below_reorder,
    -- % of records where stock is below safety stock (critical)
    ROUND( COUNT(*) FILTER (WHERE below_safety_stock) * 100.0 / COUNT(*), 1)  AS pct_below_safety_stock
FROM clean_inventory;

-- 4.2  MONTHLY REORDER TRIGGER SUMMARY
-- How many products fall below their reorder point each month?
SELECT
    inv_month,
    TO_CHAR(TO_DATE(inv_month::TEXT, 'MM'), 'Month') AS month_name,
    COUNT(DISTINCT product)                          AS products_tracked,
    SUM(below_reorder_point::INT)                    AS products_below_reorder,
    SUM(below_safety_stock::INT)                     AS products_below_safety_stock,
    ROUND(AVG(closing_stock), 0)                     AS avg_closing_stock,
    ROUND(AVG(reorder_point), 0)                     AS avg_reorder_point,
    ROUND(AVG(replenishment), 0)                     AS avg_replenishment
FROM clean_inventory
GROUP BY inv_month
ORDER BY inv_month;

-- 4.3  PRODUCT-LEVEL STOCKOUT RISK PROFILE
-- Counts months where closing stock dropped below reorder point
SELECT
    product, 
    COUNT(*)                      AS months_observed,
    SUM(below_reorder_point::INT) AS months_below_reorder,
    SUM(below_safety_stock::INT)  AS months_below_safety_stock,
    ROUND(AVG(closing_stock), 0)  AS avg_closing_stock,
    ROUND(AVG(reorder_point), 0)  AS avg_reorder_point,
    ROUND(AVG(safety_stock), 0)   AS avg_safety_stock,
    ROUND(AVG(replenishment), 0)  AS avg_replenishment,
    ROUND(SUM(below_reorder_point::INT) * 100.0 / COUNT(*), 1) AS pct_months_at_risk,
    CASE
        WHEN SUM(below_reorder_point::INT) >= 6  THEN '🔴 High Risk'
        WHEN SUM(below_reorder_point::INT) >= 3  THEN '🟡 Medium Risk'
        WHEN SUM(below_reorder_point::INT) >= 1  THEN '🟠 Low Risk'
        ELSE '🟢 Stable'
    END AS risk_category
FROM clean_inventory
GROUP BY product
ORDER BY months_below_reorder DESC, pct_months_at_risk DESC;

-- 4.4  REPLENISHMENT ADEQUACY
-- Was replenishment sufficient to cover the stock consumed in each period?
-- Net consumption = opening - closing (negative = stock increased)
SELECT
    product,
    inv_month,
    opening_stock,
    closing_stock,
    replenishment,
    (opening_stock - closing_stock) AS units_consumed,
    CASE
        WHEN (opening_stock - closing_stock) > 0 THEN replenishment - (opening_stock - closing_stock)
        ELSE replenishment
    END AS replenishment_surplus,
    CASE
        WHEN (opening_stock - closing_stock) > replenishment THEN 'Insufficient'
        ELSE 'Adequate'
    END AS replenishment_status
FROM clean_inventory
ORDER BY product, inv_month;

-- 4.5  STOCK TREND OVER TIME PER PRODUCT
-- Tracks closing stock month-by-month with MoM change
-- Useful for the Power BI inventory trend line chart
SELECT
    product,
    inventory_date,
    inv_month,
    closing_stock,
    reorder_point,
    safety_stock,
    LAG(closing_stock) OVER (PARTITION BY product ORDER BY inventory_date) AS prev_closing_stock,
    closing_stock - LAG(closing_stock) OVER (PARTITION BY product ORDER BY inventory_date) AS mom_change,
    below_reorder_point,
    below_safety_stock
FROM clean_inventory
ORDER BY product, inventory_date;

-- 4.6  INVENTORY vs FORECASTED DEMAND
-- Loads Python-generated 2025 forecast output and compares to inventory
-- NOTE: Run this AFTER the Python forecasting notebook has exported:
-- data/forecast_2025.csv  (columns: product, month, forecast_units)

-- Step 1: Create forecast staging table
DROP TABLE IF EXISTS forecast_2025_staging;
CREATE TABLE forecast_2025_staging (
    product         VARCHAR(100),
    forecast_month  INT,
    forecast_units  NUMERIC(10, 2)
);

-- Step 2: Coverage analysis
DROP VIEW IF EXISTS v_inventory_coverage;
CREATE VIEW v_inventory_coverage AS
SELECT
    ci.product,
    ci.inv_month AS month,
    ci.closing_stock,
    ci.reorder_point,
    ci.safety_stock,
    ci.replenishment,
    f.forecast_units,
    (ci.closing_stock - f.forecast_units)                  AS stock_vs_demand,
    ROUND(
        ci.closing_stock / NULLIF(f.forecast_units, 0), 2) AS coverage_ratio,
    CASE WHEN ci.closing_stock < f.forecast_units THEN TRUE ELSE FALSE END AS stockout_risk,
    CASE
        WHEN ci.closing_stock < ci.safety_stock              THEN '🔴 Critical'
        WHEN ci.closing_stock < ci.reorder_point             THEN '🟠 Reorder Now'
        WHEN ci.closing_stock < f.forecast_units             THEN '🟡 Demand Gap'
        ELSE                                                      '🟢 Healthy'
    END AS stock_status
FROM clean_inventory       ci
JOIN forecast_2025_staging  f ON ci.product = f.product AND ci.inv_month = f.forecast_month;

SELECT * FROM v_inventory_coverage ;

-- Step 3: Summary by product
SELECT
    product,
    COUNT(*) FILTER (WHERE stockout_risk)                  AS months_at_stockout_risk,
    COUNT(*) FILTER (WHERE stock_status = '🔴 Critical')   AS critical_months,
    ROUND(AVG(coverage_ratio), 2)                          AS avg_coverage_ratio,
    ROUND(MIN(coverage_ratio), 2)                          AS min_coverage_ratio,
    SUM(GREATEST(0, forecast_units - closing_stock))       AS total_demand_gap_units
FROM v_inventory_coverage
GROUP BY product
ORDER BY months_at_stockout_risk DESC, total_demand_gap_units DESC;




