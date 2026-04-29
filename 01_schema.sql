DROP DATABASE IF EXISTS food_delivery;
CREATE DATABASE food_delivery
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
USE food_delivery;

CREATE TABLE locations (
    location_id INT AUTO_INCREMENT PRIMARY KEY,
    city        VARCHAR(100) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE cuisines (
    cuisine_id   INT AUTO_INCREMENT PRIMARY KEY,
    cuisine_name VARCHAR(100) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE routes (
    route_id      INT AUTO_INCREMENT PRIMARY KEY,
    route_name    VARCHAR(50) NOT NULL UNIQUE,       
    route_type    VARCHAR(50) NOT NULL,               
    small_route   BOOLEAN NOT NULL DEFAULT FALSE,
    bike_friendly BOOLEAN NOT NULL DEFAULT FALSE
) ENGINE=InnoDB;



CREATE TABLE restaurants (
    restaurant_id INT PRIMARY KEY                     
) ENGINE=InnoDB;

CREATE TABLE customers (
    customer_id     VARCHAR(20) PRIMARY KEY,          
    age             INT,
    gender          VARCHAR(20),
    location_id     INT,
    order_history   INT,
    order_frequency VARCHAR(50),
    loyalty_program BOOLEAN NOT NULL DEFAULT FALSE,
    cuisine_id      INT,
    CONSTRAINT fk_customer_location
        FOREIGN KEY (location_id) REFERENCES locations(location_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT fk_customer_cuisine
        FOREIGN KEY (cuisine_id) REFERENCES cuisines(cuisine_id)
        ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE orders (
    order_id        VARCHAR(20) PRIMARY KEY,          
    customer_id     VARCHAR(20) NOT NULL,
    restaurant_id   INT NOT NULL,
    order_time      DATETIME NOT NULL,
    order_value     DECIMAL(10,2) NOT NULL,
    delivery_method VARCHAR(50) NOT NULL,             
    CONSTRAINT fk_order_customer
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_order_restaurant
        FOREIGN KEY (restaurant_id) REFERENCES restaurants(restaurant_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE order_items (
    order_item_id INT AUTO_INCREMENT PRIMARY KEY,
    order_id      VARCHAR(20) NOT NULL,
    food_item     VARCHAR(150) NOT NULL,
    CONSTRAINT fk_orderitem_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE deliveries (
    order_id          VARCHAR(20) PRIMARY KEY,        
    delivery_time     DATETIME,
    delivery_distance DECIMAL(8,2),
    delivery_delay    DECIMAL(8,2),
    traffic_condition VARCHAR(50),                    
    weather_condition VARCHAR(50),                    
    route_id          INT,
    route_efficiency  DECIMAL(8,4),                   
    traffic_avoidance BOOLEAN,                        
    CONSTRAINT fk_delivery_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_delivery_route
        FOREIGN KEY (route_id) REFERENCES routes(route_id)
        ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE feedback (
    order_id              VARCHAR(20) PRIMARY KEY,    
    customer_rating       INT,                        
    customer_satisfaction INT,                        
    food_temperature      VARCHAR(50),                
    food_freshness        INT,                        
    packaging_quality     INT,                        
    food_condition        VARCHAR(50),                
    CONSTRAINT fk_feedback_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE INDEX idx_orders_customer        ON orders(customer_id);
CREATE INDEX idx_orders_restaurant      ON orders(restaurant_id);
CREATE INDEX idx_orders_time            ON orders(order_time);

CREATE INDEX idx_deliveries_delay       ON deliveries(delivery_delay);
CREATE INDEX idx_deliveries_traffic     ON deliveries(traffic_condition);
CREATE INDEX idx_deliveries_weather     ON deliveries(weather_condition);

CREATE INDEX idx_feedback_rating        ON feedback(customer_rating);
CREATE INDEX idx_customers_location     ON customers(location_id);
