-- ============================================================
--   FOOD DELIVERY — VIEWS & STORED PROCEDURES
--   Run AFTER 01_schema.sql + etl_load.py have populated data
-- ============================================================
USE food_delivery;

-- ============================================================
--   VIEWS — one per problem statement (plus a denormalized one)
-- ============================================================

-- 0. Master denormalized view (used as the agent's main "table")
DROP VIEW IF EXISTS vw_order_summary;
CREATE VIEW vw_order_summary AS
SELECT
    o.order_id,
    o.order_time,
    o.order_value,
    o.delivery_method,
    -- restaurant + items
    o.restaurant_id,
    oi.food_item,
    -- customer
    c.customer_id,
    c.age,
    c.gender,
    c.loyalty_program,
    c.order_history,
    c.order_frequency,
    loc.city,
    cui.cuisine_name AS preferred_cuisine,
    -- delivery
    d.delivery_distance,
    d.delivery_delay,
    d.traffic_condition,
    d.weather_condition,
    d.route_efficiency,
    r.route_name,
    r.route_type,
    -- feedback
    f.customer_rating,
    f.customer_satisfaction,
    f.food_temperature,
    f.food_freshness,
    f.packaging_quality,
    f.food_condition
FROM orders o
LEFT JOIN order_items oi ON o.order_id     = oi.order_id
LEFT JOIN customers   c  ON o.customer_id  = c.customer_id
LEFT JOIN locations   loc ON c.location_id = loc.location_id
LEFT JOIN cuisines    cui ON c.cuisine_id  = cui.cuisine_id
LEFT JOIN deliveries  d  ON o.order_id     = d.order_id
LEFT JOIN routes      r  ON d.route_id     = r.route_id
LEFT JOIN feedback    f  ON o.order_id     = f.order_id;


-- 1. PROBLEM 1: delay drivers — average delay by traffic × weather × method
DROP VIEW IF EXISTS vw_delay_drivers;
CREATE VIEW vw_delay_drivers AS
SELECT
    o.delivery_method,
    d.traffic_condition,
    d.weather_condition,
    COUNT(*)                       AS n_orders,
    ROUND(AVG(d.delivery_delay),2) AS avg_delay_min,
    ROUND(MAX(d.delivery_delay),2) AS max_delay_min,
    ROUND(AVG(f.customer_rating),2) AS avg_rating
FROM orders o
JOIN deliveries d ON o.order_id = d.order_id
LEFT JOIN feedback f ON o.order_id = f.order_id
GROUP BY o.delivery_method, d.traffic_condition, d.weather_condition
ORDER BY avg_delay_min DESC;


-- 2. PROBLEM 2: route efficiency validity — does score predict delay?
DROP VIEW IF EXISTS vw_route_performance;
CREATE VIEW vw_route_performance AS
SELECT
    r.route_name,
    r.route_type,
    COUNT(*)                          AS n_deliveries,
    ROUND(AVG(d.route_efficiency),3)  AS avg_efficiency,
    ROUND(AVG(d.delivery_delay),2)    AS avg_delay_min,
    ROUND(AVG(d.delivery_distance),2) AS avg_distance_km,
    ROUND(AVG(f.customer_rating),2)   AS avg_rating
FROM deliveries d
JOIN routes r   ON d.route_id  = r.route_id
JOIN orders o   ON d.order_id  = o.order_id
LEFT JOIN feedback f ON o.order_id = f.order_id
GROUP BY r.route_name, r.route_type
ORDER BY avg_delay_min DESC;


-- 3. PROBLEM 3: satisfaction drivers — feedback dimensions vs. satisfaction
DROP VIEW IF EXISTS vw_satisfaction_drivers;
CREATE VIEW vw_satisfaction_drivers AS
SELECT
    f.food_temperature,
    f.food_condition,
    COUNT(*)                              AS n_orders,
    ROUND(AVG(f.customer_satisfaction),2) AS avg_satisfaction,
    ROUND(AVG(f.customer_rating),2)       AS avg_rating,
    ROUND(AVG(f.food_freshness),2)        AS avg_freshness,
    ROUND(AVG(f.packaging_quality),2)     AS avg_packaging
FROM feedback f
GROUP BY f.food_temperature, f.food_condition
ORDER BY avg_satisfaction DESC;


-- 4. PROBLEM 4: loyalty programme ROI
DROP VIEW IF EXISTS vw_loyalty_analysis;
CREATE VIEW vw_loyalty_analysis AS
SELECT
    c.loyalty_program,
    COUNT(DISTINCT c.customer_id)    AS n_customers,
    COUNT(o.order_id)                AS n_orders,
    ROUND(AVG(o.order_value),2)      AS avg_order_value,
    ROUND(SUM(o.order_value),2)      AS total_revenue,
    ROUND(AVG(f.customer_rating),2)  AS avg_rating,
    ROUND(AVG(c.order_history),2)    AS avg_order_history
FROM customers c
LEFT JOIN orders   o ON c.customer_id = o.customer_id
LEFT JOIN feedback f ON o.order_id    = f.order_id
GROUP BY c.loyalty_program;


-- 5. Bonus: per-city KPIs (used by the AI agent for "Which city ___?" questions)
DROP VIEW IF EXISTS vw_city_metrics;
CREATE VIEW vw_city_metrics AS
SELECT
    loc.city,
    COUNT(o.order_id)                     AS n_orders,
    ROUND(SUM(o.order_value),2)           AS total_revenue,
    ROUND(AVG(o.order_value),2)           AS avg_order_value,
    ROUND(AVG(d.delivery_delay),2)        AS avg_delay_min,
    ROUND(AVG(f.customer_satisfaction),2) AS avg_satisfaction
FROM customers c
JOIN locations loc ON c.location_id = loc.location_id
LEFT JOIN orders     o ON c.customer_id = o.customer_id
LEFT JOIN deliveries d ON o.order_id    = d.order_id
LEFT JOIN feedback   f ON o.order_id    = f.order_id
GROUP BY loc.city
ORDER BY total_revenue DESC;


-- ============================================================
--   STORED PROCEDURES — parameterized analyses
-- ============================================================

DROP PROCEDURE IF EXISTS sp_restaurant_report;
DELIMITER $$
CREATE PROCEDURE sp_restaurant_report(IN p_restaurant_id INT)
BEGIN
    SELECT
        o.restaurant_id,
        COUNT(o.order_id)                     AS n_orders,
        ROUND(SUM(o.order_value),2)           AS total_revenue,
        ROUND(AVG(o.order_value),2)           AS avg_order_value,
        ROUND(AVG(d.delivery_delay),2)        AS avg_delay_min,
        ROUND(AVG(f.customer_rating),2)       AS avg_rating,
        ROUND(AVG(f.customer_satisfaction),2) AS avg_satisfaction
    FROM orders o
    LEFT JOIN deliveries d ON o.order_id = d.order_id
    LEFT JOIN feedback   f ON o.order_id = f.order_id
    WHERE o.restaurant_id = p_restaurant_id
    GROUP BY o.restaurant_id;
END$$
DELIMITER ;


DROP PROCEDURE IF EXISTS sp_late_deliveries;
DELIMITER $$
CREATE PROCEDURE sp_late_deliveries(IN p_min_delay DECIMAL(8,2))
BEGIN
    SELECT
        o.order_id,
        o.order_time,
        d.delivery_delay,
        d.traffic_condition,
        d.weather_condition,
        o.delivery_method,
        loc.city,
        f.customer_rating
    FROM orders o
    JOIN deliveries d ON o.order_id = d.order_id
    JOIN customers  c ON o.customer_id = c.customer_id
    LEFT JOIN locations loc ON c.location_id = loc.location_id
    LEFT JOIN feedback  f   ON o.order_id    = f.order_id
    WHERE d.delivery_delay >= p_min_delay
    ORDER BY d.delivery_delay DESC
    LIMIT 100;
END$$
DELIMITER ;


DROP PROCEDURE IF EXISTS sp_customer_profile;
DELIMITER $$
CREATE PROCEDURE sp_customer_profile(IN p_customer_id VARCHAR(20))
BEGIN
    SELECT
        c.customer_id,
        c.age, c.gender,
        loc.city,
        cui.cuisine_name AS preferred_cuisine,
        c.loyalty_program,
        c.order_frequency,
        COUNT(o.order_id)               AS n_orders,
        ROUND(SUM(o.order_value),2)     AS total_spend,
        ROUND(AVG(o.order_value),2)     AS avg_order_value,
        ROUND(AVG(f.customer_rating),2) AS avg_rating
    FROM customers c
    LEFT JOIN locations loc ON c.location_id = loc.location_id
    LEFT JOIN cuisines  cui ON c.cuisine_id  = cui.cuisine_id
    LEFT JOIN orders    o   ON c.customer_id = o.customer_id
    LEFT JOIN feedback  f   ON o.order_id    = f.order_id
    WHERE c.customer_id = p_customer_id
    GROUP BY c.customer_id, c.age, c.gender, loc.city, cui.cuisine_name,
             c.loyalty_program, c.order_frequency;
END$$
DELIMITER ;


DROP PROCEDURE IF EXISTS sp_delivery_stats_by_method;
DELIMITER $$
CREATE PROCEDURE sp_delivery_stats_by_method()
BEGIN
    SELECT
        o.delivery_method,
        COUNT(o.order_id)                  AS n_orders,
        ROUND(AVG(d.delivery_delay),2)     AS avg_delay_min,
        ROUND(MIN(d.delivery_delay),2)     AS min_delay_min,
        ROUND(MAX(d.delivery_delay),2)     AS max_delay_min,
        ROUND(AVG(d.delivery_distance),2)  AS avg_distance_km,
        ROUND(AVG(f.customer_rating),2)    AS avg_rating
    FROM orders o
    JOIN deliveries d ON o.order_id = d.order_id
    LEFT JOIN feedback f ON o.order_id = f.order_id
    GROUP BY o.delivery_method
    ORDER BY avg_delay_min DESC;
END$$
DELIMITER ;


DROP PROCEDURE IF EXISTS sp_top_food_items;
DELIMITER $$
CREATE PROCEDURE sp_top_food_items(IN p_limit INT)
BEGIN
    SELECT
        oi.food_item,
        COUNT(*)                       AS n_orders,
        ROUND(SUM(o.order_value),2)    AS total_revenue,
        ROUND(AVG(o.order_value),2)    AS avg_order_value
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    GROUP BY oi.food_item
    ORDER BY n_orders DESC
    LIMIT p_limit;
END$$
DELIMITER ;

-- ============================================================
--   QUICK-CHECK QUERIES (run these after deployment)
-- ============================================================
-- SELECT * FROM vw_loyalty_analysis;
-- SELECT * FROM vw_route_performance;
-- SELECT * FROM vw_city_metrics LIMIT 10;
-- CALL sp_restaurant_report(1);
-- CALL sp_late_deliveries(15);
-- CALL sp_customer_profile('CUST000001');
-- CALL sp_delivery_stats_by_method();
-- CALL sp_top_food_items(10);
