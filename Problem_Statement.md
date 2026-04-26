# Problem Statement — Food Delivery AI Agent

**Course:** Databases — Final Project
**Dataset:** Food Delivery (20,000 orders · 10 cities · 100 restaurants · 5 cuisines · 5 routes)

## Background

Online food delivery is a high-volume, low-margin business where small operational
inefficiencies — a few extra minutes of delay, a poorly chosen route, an unhappy
customer — compound into significant revenue loss at scale. The raw operational
data captured by a delivery platform (orders, deliveries, customer profiles,
feedback, and routes) contains the answers to most of these inefficiency questions,
but a flat CSV is the wrong shape to ask them in. This project takes a real-world
food-delivery dataset, normalizes it into a relational schema, and exposes it
through a natural-language AI agent so that any stakeholder — operations manager,
restaurant partner, or analyst — can ask questions in plain English and receive
SQL-grounded, data-backed answers.

## The Four Problems We Address

### Problem 1 — Delivery delay drivers (Operational optimization)

Delivery delays directly hurt customer satisfaction and platform reputation.
Management currently has no systematic way to attribute delay to its underlying
causes. We need to quantify how strongly each operational factor — **traffic
condition, weather condition, delivery method, route choice, and route
efficiency** — contributes to delivery delay. The deliverable is a ranked
breakdown so that operations can target the highest-impact factor first
(e.g. is it worth investing in better routing software, or in weather-aware
dispatching?).

### Problem 2 — Route efficiency vs. real-world delay (Routing optimization)

The platform records a `route_efficiency` score (0–1) for every delivery, but
nobody has validated whether a high score actually translates into shorter
delays. If `route_efficiency` is a leaky indicator, dispatchers shouldn't
trust it. We need to compare average delivery delay across efficiency tiers
(e.g. ≥ 0.8 vs ≤ 0.6) and across the five available routes, and decide whether
the metric is predictive enough to drive routing decisions.

### Problem 3 — Customer satisfaction drivers (Quality optimization)

Customer satisfaction is captured on a 1–5 scale alongside three quality
proxies: **food temperature, food freshness, and packaging quality**. We
need to find the combination of these three factors that maximizes
satisfaction, so that restaurants and packaging vendors can be advised on
exactly which dimension matters most. This is also a feature-importance
question: if packaging only moves the needle by 0.1 points but freshness
moves it by 1.2 points, that completely changes the action plan.

### Problem 4 — Loyalty programme ROI (Revenue optimization)

The platform runs a loyalty programme, but we don't yet know whether members
actually spend more, order more often, or rate higher than non-members.
We need to compute the share of total revenue attributable to loyalty
members vs. non-members, the per-order spend differential, and the rating
differential — and decide whether the programme is justifying its cost.

## Future ER Expansion (Schema scalability)

The schema is designed so the four problems above can be answered on day one,
but it must also accommodate realistic future extensions without redesign:

- **Drivers / couriers table** — to attribute delays and ratings to specific
  riders, not just to delivery method
- **Menu items table** — to separate dish-level pricing from order-level
  totals, enabling per-item profitability analysis
- **Promotions / coupons table** — to measure how discounts affect order
  value and repeat behaviour
- **Restaurant metadata** (name, address, cuisine focus) — currently
  `restaurants` is intentionally minimal; a richer dimension table can be
  added without breaking any existing FK
- **Geospatial coordinates on `locations`** — to support distance-aware
  dispatch and zone-level analytics

The current normalization (3NF, with separate dimension tables for cities,
cuisines, and routes) makes all of these extensions additive rather than
destructive: new tables hang off existing FKs, and no historical query needs
to be rewritten.
