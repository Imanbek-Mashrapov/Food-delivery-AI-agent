-- =============================================================
--  Views & Stored Procedures  –  food_delivery
-- =============================================================
USE food_delivery;

-- View 1: Full order summary (denormalised for easy reporting)
CREATE OR REPLACE VIEW vw_order_summary AS
SELECT
    o.order_id,
    o.order_time,
    o.order_value,
    o.delivery_method,
    c.customer_id,
    c.age,
    c.gender,
    l.city                  AS customer_city,
    c.loyalty_program,
    cu.cuisine_name         AS preferred_cuisine,
    r.restaurant_id,
    d.delivery_distance,
    d.delivery_delay,
    d.traffic_condition,
    d.weather_condition,
    rt.route_name,
    rt.route_type,
    d.route_efficiency,
    f.customer_rating,
    f.customer_satisfaction,
    f.food_temperature,
    f.food_freshness,
    f.packaging_quality,
    f.food_condition
FROM orders o
JOIN customers  c  ON c.customer_id   = o.customer_id
JOIN locations  l  ON l.location_id   = c.location_id
LEFT JOIN cuisines cu ON cu.cuisine_id = c.cuisine_id
JOIN restaurants r  ON r.restaurant_id = o.restaurant_id
LEFT JOIN deliveries d  ON d.order_id  = o.order_id
LEFT JOIN routes     rt ON rt.route_id = d.route_id
LEFT JOIN feedback   f  ON f.order_id  = o.order_id;


-- View 2: Average delay and rating per traffic + weather combo
CREATE OR REPLACE VIEW vw_traffic_weather_impact AS
SELECT
    d.traffic_condition,
    d.weather_condition,
    COUNT(*)                          AS total_deliveries,
    ROUND(AVG(d.delivery_delay), 2)   AS avg_delay_min,
    ROUND(AVG(f.customer_rating), 2)  AS avg_rating,
    ROUND(AVG(d.route_efficiency), 4) AS avg_route_efficiency
FROM deliveries d
LEFT JOIN feedback f ON f.order_id = d.order_id
GROUP BY d.traffic_condition, d.weather_condition;


-- View 3: Customer loyalty vs spend
CREATE OR REPLACE VIEW vw_loyalty_analysis AS
SELECT
    c.loyalty_program,
    COUNT(DISTINCT o.customer_id)     AS customers,
    COUNT(o.order_id)                 AS total_orders,
    ROUND(AVG(o.order_value), 2)      AS avg_order_value,
    ROUND(AVG(f.customer_rating), 2)  AS avg_rating,
    ROUND(AVG(f.customer_satisfaction), 2) AS avg_satisfaction
FROM customers c
JOIN orders   o ON o.customer_id = c.customer_id
LEFT JOIN feedback f ON f.order_id = o.order_id
GROUP BY c.loyalty_program;


-- View 4: Top performing routes
CREATE OR REPLACE VIEW vw_route_performance AS
SELECT
    rt.route_name,
    rt.route_type,
    rt.small_route,
    rt.bike_friendly,
    COUNT(d.order_id)                  AS deliveries,
    ROUND(AVG(d.delivery_delay), 2)    AS avg_delay_min,
    ROUND(AVG(d.route_efficiency), 4)  AS avg_efficiency,
    ROUND(AVG(f.customer_rating), 2)   AS avg_rating
FROM routes rt
JOIN deliveries d ON d.route_id  = rt.route_id
LEFT JOIN feedback f ON f.order_id = d.order_id
GROUP BY rt.route_id;


-- View 5: City-level order and satisfaction metrics
CREATE OR REPLACE VIEW vw_city_metrics AS
SELECT
    l.city,
    COUNT(o.order_id)                      AS total_orders,
    ROUND(SUM(o.order_value), 2)           AS total_revenue,
    ROUND(AVG(o.order_value), 2)           AS avg_order_value,
    ROUND(AVG(d.delivery_delay), 2)        AS avg_delay_min,
    ROUND(AVG(f.customer_satisfaction), 2) AS avg_satisfaction
FROM locations l
JOIN customers c ON c.location_id = l.location_id
JOIN orders    o ON o.customer_id  = c.customer_id
LEFT JOIN deliveries d ON d.order_id = o.order_id
LEFT JOIN feedback   f ON f.order_id = o.order_id
GROUP BY l.city
ORDER BY total_revenue DESC;


-- ===============================================================
--  STORED PROCEDURES
-- ===============================================================

DROP PROCEDURE IF EXISTS sp_restaurant_report;
DROP PROCEDURE IF EXISTS sp_late_deliveries;
DROP PROCEDURE IF EXISTS sp_customer_profile;
DROP PROCEDURE IF EXISTS sp_delivery_stats_by_method;
DROP PROCEDURE IF EXISTS sp_top_food_items;

DELIMITER //

-- Procedure 1: Restaurant performance report
--   Returns: orders, revenue, avg delay, avg rating
CREATE PROCEDURE sp_restaurant_report(IN p_restaurant_id INT)
BEGIN
    IF p_restaurant_id IS NULL THEN
        -- All restaurants
        SELECT
            o.restaurant_id,
            COUNT(o.order_id)                     AS total_orders,
            ROUND(SUM(o.order_value), 2)           AS total_revenue,
            ROUND(AVG(o.order_value), 2)           AS avg_order_value,
            ROUND(AVG(d.delivery_delay), 2)        AS avg_delay_min,
            ROUND(AVG(f.customer_rating), 2)       AS avg_rating,
            ROUND(AVG(f.customer_satisfaction), 2) AS avg_satisfaction
        FROM orders o
        LEFT JOIN deliveries d ON d.order_id = o.order_id
        LEFT JOIN feedback   f ON f.order_id = o.order_id
        GROUP BY o.restaurant_id
        ORDER BY total_revenue DESC;
    ELSE
        SELECT
            o.restaurant_id,
            COUNT(o.order_id)                     AS total_orders,
            ROUND(SUM(o.order_value), 2)           AS total_revenue,
            ROUND(AVG(o.order_value), 2)           AS avg_order_value,
            ROUND(AVG(d.delivery_delay), 2)        AS avg_delay_min,
            ROUND(AVG(f.customer_rating), 2)       AS avg_rating,
            ROUND(AVG(f.customer_satisfaction), 2) AS avg_satisfaction
        FROM orders o
        LEFT JOIN deliveries d ON d.order_id = o.order_id
        LEFT JOIN feedback   f ON f.order_id = o.order_id
        WHERE o.restaurant_id = p_restaurant_id
        GROUP BY o.restaurant_id;
    END IF;
END //


-- Procedure 2: Get late deliveries (delay > threshold)
CREATE PROCEDURE sp_late_deliveries(IN p_threshold_min DECIMAL(8,2))
BEGIN
    SET p_threshold_min = COALESCE(p_threshold_min, 20.00);
    SELECT
        d.order_id,
        o.order_time,
        d.delivery_time,
        d.delivery_delay,
        d.traffic_condition,
        d.weather_condition,
        l.city        AS customer_city,
        f.customer_rating
    FROM deliveries d
    JOIN orders    o ON o.order_id   = d.order_id
    JOIN customers c ON c.customer_id = o.customer_id
    JOIN locations l ON l.location_id = c.location_id
    LEFT JOIN feedback f ON f.order_id = d.order_id
    WHERE d.delivery_delay > p_threshold_min
    ORDER BY d.delivery_delay DESC;
END //


-- Procedure 3: Full customer profile
CREATE PROCEDURE sp_customer_profile(IN p_customer_id VARCHAR(20))
BEGIN
    -- Customer info
    SELECT
        c.customer_id,
        c.age,
        c.gender,
        l.city,
        c.order_history,
        c.order_frequency,
        c.loyalty_program,
        cu.cuisine_name AS preferred_cuisine
    FROM customers c
    JOIN locations l ON l.location_id = c.location_id
    LEFT JOIN cuisines cu ON cu.cuisine_id = c.cuisine_id
    WHERE c.customer_id = p_customer_id;

    -- Order history
    SELECT
        o.order_id,
        o.order_time,
        o.order_value,
        o.delivery_method,
        d.delivery_delay,
        f.customer_rating
    FROM orders o
    LEFT JOIN deliveries d ON d.order_id = o.order_id
    LEFT JOIN feedback   f ON f.order_id = o.order_id
    WHERE o.customer_id = p_customer_id
    ORDER BY o.order_time DESC
    LIMIT 20;
END //


-- Procedure 4: Delivery stats broken down by delivery method
CREATE PROCEDURE sp_delivery_stats_by_method()
BEGIN
    SELECT
        o.delivery_method,
        COUNT(o.order_id)                     AS total_orders,
        ROUND(AVG(d.delivery_distance), 2)    AS avg_distance_km,
        ROUND(AVG(d.delivery_delay), 2)       AS avg_delay_min,
        ROUND(AVG(d.route_efficiency), 4)     AS avg_efficiency,
        ROUND(AVG(f.customer_rating), 2)      AS avg_rating,
        ROUND(AVG(f.customer_satisfaction), 2) AS avg_satisfaction
    FROM orders o
    LEFT JOIN deliveries d ON d.order_id = o.order_id
    LEFT JOIN feedback   f ON f.order_id = o.order_id
    GROUP BY o.delivery_method
    ORDER BY avg_rating DESC;
END //


-- Procedure 5: Top N most-ordered food items
CREATE PROCEDURE sp_top_food_items(IN p_limit INT)
BEGIN
    SET p_limit = COALESCE(p_limit, 10);
    SELECT
        oi.food_item,
        COUNT(*)                          AS times_ordered,
        ROUND(AVG(o.order_value), 2)      AS avg_order_value,
        ROUND(AVG(f.customer_rating), 2)  AS avg_rating
    FROM order_items oi
    JOIN orders   o ON o.order_id = oi.order_id
    LEFT JOIN feedback f ON f.order_id = o.order_id
    GROUP BY oi.food_item
    ORDER BY times_ordered DESC
    LIMIT p_limit;
END //

DELIMITER ;
