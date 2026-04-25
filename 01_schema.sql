CREATE DATABASE IF NOT EXISTS food_delivery;
USE food_delivery;

DROP TABLE IF EXISTS feedback;
DROP TABLE IF EXISTS deliveries;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS restaurants;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS routes;
DROP TABLE IF EXISTS locations;
DROP TABLE IF EXISTS cuisines;

CREATE TABLE locations (
    location_id   INT AUTO_INCREMENT PRIMARY KEY,
    city          VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE cuisines (
    cuisine_id    INT AUTO_INCREMENT PRIMARY KEY,
    cuisine_name  VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE routes (
    route_id INT AUTO_INCREMENT PRIMARY KEY,
    route_name VARCHAR(100) NOT NULL UNIQUE,   
    route_type VARCHAR(50),                   
    small_route BOOLEAN,
    bike_friendly BOOLEAN
);

CREATE TABLE customers (
    customer_id       VARCHAR(20)  PRIMARY KEY,
    age               INT,
    gender            VARCHAR(20),
    location_id       INT NOT NULL,
    order_history     INT DEFAULT 0,
    order_frequency   VARCHAR(50),
    loyalty_program   BOOLEAN DEFAULT FALSE,
    cuisine_id        TINYINT UNSIGNED,
    CONSTRAINT fk_cust_location FOREIGN KEY (location_id) REFERENCES locations(location_id),
    CONSTRAINT fk_cust_cuisine  FOREIGN KEY (cuisine_id)  REFERENCES cuisines(cuisine_id)
);

CREATE TABLE restaurants (
    restaurant_id     INT PRIMARY KEY
);

CREATE TABLE orders (
    order_id          VARCHAR(20)    PRIMARY KEY,
    customer_id       VARCHAR(20)    NOT NULL,
    restaurant_id     INT            NOT NULL,
    order_time        DATETIME,
    order_value       DECIMAL(10,2),
    delivery_method   VARCHAR(50),
    CONSTRAINT fk_ord_customer    FOREIGN KEY (customer_id)   REFERENCES customers(customer_id),
    CONSTRAINT fk_ord_restaurant  FOREIGN KEY (restaurant_id) REFERENCES restaurants(restaurant_id)
);

CREATE TABLE order_items (
    order_item_id     INT AUTO_INCREMENT PRIMARY KEY,
    order_id          VARCHAR(20) NOT NULL,
    food_item         VARCHAR(150),
    CONSTRAINT fk_oi_order FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE TABLE deliveries (
    order_id              VARCHAR(20)   PRIMARY KEY,
    delivery_time         DATETIME,
    delivery_distance     DECIMAL(8,2),
    delivery_delay        DECIMAL(8,2),
    traffic_condition     VARCHAR(50),
    weather_condition     VARCHAR(50),
    route_id              INT UNSIGNED,
    route_efficiency      DECIMAL(8,4),
    traffic_avoidance     BOOLEAN,
    CONSTRAINT fk_del_order FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT fk_del_route FOREIGN KEY (route_id) REFERENCES routes(route_id)
);

CREATE TABLE feedback (
    order_id              VARCHAR(20)  PRIMARY KEY,
    customer_rating       INT,
    customer_satisfaction INT,
    food_temperature      VARCHAR(50),
    food_freshness        INT,
    packaging_quality     INT,
    food_condition        VARCHAR(50),
    CONSTRAINT fk_fb_order FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_restaurant ON orders(restaurant_id);
CREATE INDEX idx_orders_time ON orders(order_time);
CREATE INDEX idx_deliveries_delay ON deliveries(delivery_delay);
CREATE INDEX idx_deliveries_traffic ON deliveries(traffic_condition);
CREATE INDEX idx_deliveries_weather ON deliveries(weather_condition);
CREATE INDEX idx_feedback_rating ON feedback(customer_rating);
CREATE INDEX idx_customers_location ON customers(location_id);
