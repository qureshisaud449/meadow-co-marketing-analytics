-- =====================================================================
-- MEADOW & CO — MySQL Phase
-- Schema v1: Staging Layer + Target Production Model
-- Built from actual column-level audit of the 5 raw CSVs (Aug 2026)
-- =====================================================================

CREATE DATABASE IF NOT EXISTS meadowco
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE meadowco;

-- =====================================================================
-- LAYER 1 — STAGING TABLES
-- Mirrors each CSV's real header names, in the real header order.
-- Anything the audit found to be inconsistent (dates, spend, booleans)
-- is typed as VARCHAR here on purpose — a staging table's only job is
-- to guarantee the import cannot fail on a data-type mismatch. All
-- cleaning happens afterwards, in SQL, where you can see what you're
-- doing and re-run it if you get it wrong.
-- =====================================================================

DROP TABLE IF EXISTS stg_customers;
CREATE TABLE stg_customers (
    customer_id       VARCHAR(20),
    segment           VARCHAR(30),   -- 18 blank rows in source
    region            VARCHAR(20),   -- some values have trailing spaces
    first_order_date  VARCHAR(20)    -- confirmed clean ISO, staged as text anyway for consistency
);

DROP TABLE IF EXISTS stg_orders_raw;
CREATE TABLE stg_orders_raw (
    order_id          VARCHAR(20),
    customer_id       VARCHAR(20),   -- 9 blank rows (guest/anonymous orders)
    order_date        VARCHAR(20),   -- MIXED formats: 784 rows 'YYYY-MM-DD', 333 rows 'DD/MM/YYYY'
    channel           VARCHAR(50),   -- 29 raw spellings of 7 real channels
    device            VARCHAR(20),
    region            VARCHAR(20),
    segment           VARCHAR(30),   -- values padded with trailing double-space
    product_category  VARCHAR(50),
    quantity          INT,           -- verified 100% numeric across all 1,117 rows
    gross_revenue     DECIMAL(10,2), -- verified clean
    discount_amount   DECIMAL(10,2), -- verified clean
    net_revenue       DECIMAL(10,2), -- verified clean, INCLUDES NEGATIVE VALUES (refunds)
    is_new_customer   VARCHAR(10)    -- text 'True'/'False', not 0/1
);

DROP TABLE IF EXISTS stg_web_funnel_raw;
CREATE TABLE stg_web_funnel_raw (
    `date`          VARCHAR(20),   -- verified clean ISO, staged as text for consistency
    channel         VARCHAR(50),   -- same 29-variant messiness as orders_raw
    device          VARCHAR(20),   -- 25 blank rows
    sessions        INT,           -- verified numeric
    add_to_cart     INT,
    begin_checkout  INT,
    purchases       INT
);

DROP TABLE IF EXISTS stg_marketing_spend_raw;
CREATE TABLE stg_marketing_spend_raw (
    `date`        VARCHAR(20),   -- verified clean ISO
    channel       VARCHAR(50),   -- same messy-channel problem, paid channels only
    campaign      VARCHAR(100),
    impressions   INT,           -- verified numeric
    clicks        INT,           -- verified numeric
    spend         VARCHAR(20)    -- 317 rows prefixed '£', 6 rows blank -> must stage as text
);

DROP TABLE IF EXISTS stg_email_ab_test;
CREATE TABLE stg_email_ab_test (
    campaign     VARCHAR(120),
    segment      VARCHAR(30),
    variant      VARCHAR(5),
    emails_sent  INT,
    opens        INT,
    clicks       INT,
    conversions  INT,
    revenue      DECIMAL(10,2)
);

-- =====================================================================
-- CHANNEL MAPPING TABLE — the MySQL equivalent of your Excel XLOOKUP
-- mapping table. Pre-populated from a full audit of every distinct
-- raw channel string found across orders_raw, web_funnel_raw and
-- marketing_spend_raw (29 variants -> 7 real channels).
-- You will JOIN against this inside a VIEW in Phase 3 — this just gets
-- it ready now so nothing blocks the import today.
-- =====================================================================

DROP TABLE IF EXISTS dim_channel_map;
CREATE TABLE dim_channel_map (
    channel_raw    VARCHAR(50) PRIMARY KEY,
    channel_clean  VARCHAR(30) NOT NULL
);

INSERT INTO dim_channel_map (channel_raw, channel_clean) VALUES
('(direct)','Direct'), ('DIRECT','Direct'), ('Direct','Direct'), ('direct','Direct'),
('AFFILIATE','Affiliate'), ('Affiliate','Affiliate'), ('Affiliate ','Affiliate'), ('affiliate','Affiliate'),
('EMAIL','Email'), ('Email','Email'), ('Email Marketing','Email'), ('email','Email'),
('FB/IG Ads','Meta Ads'), ('Facebook/Instagram Ads','Meta Ads'), ('Meta Ads','Meta Ads'), ('Meta_Ads','Meta Ads'), ('meta ads','Meta Ads'),
('GOOGLE SEARCH','Google Search'), ('Google  Search','Google Search'), ('Google Search','Google Search'), ('Google_Search','Google Search'), ('google search','Google Search'),
('GOOGLE SHOPPING','Google Shopping'), ('Google Shopping','Google Shopping'), ('Google_Shopping','Google Shopping'), ('google shopping','Google Shopping'),
('Organic Search','Organic Search'), ('Organic_Search','Organic Search'), ('SEO','Organic Search');

-- =====================================================================
-- LAYER 2 — TARGET PRODUCTION MODEL (preview only — build in Phase 3)
-- This is where staging data lands once cleaned. Do not create these
-- yet; they're here so you can see where the staging types are heading
-- and confirm the plan before we build the cleaning VIEWs/INSERTs.
-- =====================================================================

-- customers            (customer_id PK, segment, region TRIM'd, first_order_date DATE)
-- orders                (order_id PK, customer_id FK NULL-able, order_date DATE, channel_clean,
--                         device, region, segment TRIM'd, product_category, quantity INT,
--                         gross_revenue/discount_amount/net_revenue DECIMAL(10,2) SIGNED,
--                         is_new_customer TINYINT(1))
-- web_funnel            (session_date DATE, channel_clean, device NULL-able, sessions,
--                         add_to_cart, begin_checkout, purchases)
-- marketing_spend       (spend_date DATE, channel_clean, campaign, impressions, clicks,
--                         spend DECIMAL(10,2) with '£' stripped)
-- email_ab_test         (campaign, segment, variant, emails_sent, opens, clicks,
--                         conversions, revenue DECIMAL(10,2))

DROP TABLE IF EXISTS dim_channel_map;
CREATE TABLE dim_channel_map (
    channel_raw    VARCHAR(50) COLLATE utf8mb4_bin PRIMARY KEY,
    channel_clean  VARCHAR(30) NOT NULL
);

INSERT INTO dim_channel_map (channel_raw, channel_clean) VALUES
('(direct)','Direct'), ('DIRECT','Direct'), ('Direct','Direct'), ('direct','Direct'),
('AFFILIATE','Affiliate'), ('Affiliate','Affiliate'), ('Affiliate ','Affiliate'), ('affiliate','Affiliate'),
('EMAIL','Email'), ('Email','Email'), ('Email Marketing','Email'), ('email','Email'),
('FB/IG Ads','Meta Ads'), ('Facebook/Instagram Ads','Meta Ads'), ('Meta Ads','Meta Ads'), ('Meta_Ads','Meta Ads'), ('meta ads','Meta Ads'),
('GOOGLE SEARCH','Google Search'), ('Google  Search','Google Search'), ('Google Search','Google Search'), ('Google_Search','Google Search'), ('google search','Google Search'),
('GOOGLE SHOPPING','Google Shopping'), ('Google Shopping','Google Shopping'), ('Google_Shopping','Google Shopping'), ('google shopping','Google Shopping'),
('Organic Search','Organic Search'), ('Organic_Search','Organic Search'), ('SEO','Organic Search');



INSERT INTO dim_channel_map (channel_raw, channel_clean) VALUES
('(direct)','Direct'), ('DIRECT','Direct'), ('Direct','Direct'), ('direct','Direct'),
('AFFILIATE','Affiliate'), ('Affiliate','Affiliate'), ('affiliate','Affiliate'),
('EMAIL','Email'), ('Email','Email'), ('Email Marketing','Email'), ('email','Email'),
('FB/IG Ads','Meta Ads'), ('Facebook/Instagram Ads','Meta Ads'), ('Meta Ads','Meta Ads'), ('Meta_Ads','Meta Ads'), ('meta ads','Meta Ads'),
('GOOGLE SEARCH','Google Search'), ('Google  Search','Google Search'), ('Google Search','Google Search'), ('Google_Search','Google Search'), ('google search','Google Search'),
('GOOGLE SHOPPING','Google Shopping'), ('Google Shopping','Google Shopping'), ('Google_Shopping','Google Shopping'), ('google shopping','Google Shopping'),
('Organic Search','Organic Search'), ('Organic_Search','Organic Search'), ('SEO','Organic Search');


SELECT DISTINCT o.channel
FROM stg_orders_raw o
LEFT JOIN dim_channel_map m 
    ON TRIM(o.channel) COLLATE utf8mb4_bin = m.channel_raw
WHERE m.channel_raw IS NULL;

SELECT *
FROM dim_channel_map
WHERE channel_raw LIKE '%organic%';

INSERT INTO dim_channel_map (channel_raw, channel_clean)
VALUES ('organic search', 'Organic Search');

SELECT DISTINCT o.channel
FROM stg_orders_raw o
LEFT JOIN dim_channel_map m 
    ON TRIM(o.channel) COLLATE utf8mb4_bin = m.channel_raw
WHERE m.channel_raw IS NULL;

SELECT DISTINCT f.channel
FROM stg_web_funnel_raw f
LEFT JOIN dim_channel_map m ON TRIM(f.channel) COLLATE utf8mb4_bin = m.channel_raw
WHERE m.channel_raw IS NULL;



DROP VIEW IF EXISTS vw_customers;
CREATE VIEW vw_customers AS
SELECT
    customer_id,
    NULLIF(TRIM(segment), '')                  AS segment,     -- 18 blanks -> real NULL
    TRIM(region)                                AS region,     -- strips trailing-space variants
    STR_TO_DATE(first_order_date, '%Y-%m-%d')   AS first_order_date
FROM stg_customers;

DROP VIEW IF EXISTS vw_orders;
CREATE VIEW vw_orders AS
SELECT
    o.order_id,
    NULLIF(TRIM(o.customer_id), '')             AS customer_id,   -- 9 blanks -> NULL FK
    CASE
        WHEN o.order_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
            THEN STR_TO_DATE(o.order_date, '%Y-%m-%d')
        WHEN o.order_date REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$'
            THEN STR_TO_DATE(o.order_date, '%d/%m/%Y')
        ELSE NULL   -- safety net; STEP 0-style check confirmed no third format exists
    END                                          AS order_date,
    COALESCE(m.channel_clean, 'Unmapped')       AS channel,       -- 'Unmapped' is a visible
                                                                    -- sentinel, not a silent NULL —
                                                                    -- any join miss shows up in a
                                                                    -- GROUP BY instead of hiding
    o.device,
    TRIM(o.region)                               AS region,
    TRIM(o.segment)                              AS segment,
    o.product_category,
    o.quantity,
    o.gross_revenue,
    o.discount_amount,
    o.net_revenue,                                                -- can be negative (refunds) — by design
    CASE o.is_new_customer
        WHEN 'True'  THEN 1
        WHEN 'False' THEN 0
        ELSE NULL
    END                                          AS is_new_customer
FROM stg_orders_raw o
LEFT JOIN dim_channel_map m
    ON TRIM(o.channel) COLLATE utf8mb4_bin = m.channel_raw;
    
    DROP VIEW IF EXISTS vw_web_funnel;
CREATE VIEW vw_web_funnel AS
SELECT
    STR_TO_DATE(f.`date`, '%Y-%m-%d')           AS session_date,
    COALESCE(m.channel_clean, 'Unmapped')       AS channel,
    NULLIF(TRIM(f.device), '')                  AS device,       -- 25 blanks -> NULL
    f.sessions,
    f.add_to_cart,
    f.begin_checkout,
    f.purchases
FROM stg_web_funnel_raw f
LEFT JOIN dim_channel_map m
    ON TRIM(f.channel) COLLATE utf8mb4_bin = m.channel_raw;
    
    DROP VIEW IF EXISTS vw_marketing_spend;
CREATE VIEW vw_marketing_spend AS
SELECT
    STR_TO_DATE(s.`date`, '%Y-%m-%d')           AS spend_date,
    COALESCE(m.channel_clean, 'Unmapped')       AS channel,
    s.campaign,
    s.impressions,
    s.clicks,
    CASE
        WHEN TRIM(s.spend) = '' THEN NULL
        ELSE CAST(REPLACE(s.spend, '£', '') AS DECIMAL(10,2))
    END                                          AS spend
FROM stg_marketing_spend_raw s
LEFT JOIN dim_channel_map m
    ON TRIM(s.channel) COLLATE utf8mb4_bin = m.channel_raw;
    
    DROP VIEW IF EXISTS vw_email_ab_test;
CREATE VIEW vw_email_ab_test AS
SELECT campaign, segment, variant, emails_sent, opens, clicks, conversions, revenue
FROM stg_email_ab_test;

SELECT * FROM vw_orders          WHERE channel = 'Unmapped';
SELECT * FROM vw_web_funnel      WHERE channel = 'Unmapped';
SELECT * FROM vw_marketing_spend WHERE channel = 'Unmapped';

SELECT
  (SELECT COUNT(*) FROM stg_orders_raw) AS stg_orders,
  (SELECT COUNT(*) FROM vw_orders)      AS vw_orders,
  (SELECT COUNT(*) FROM stg_web_funnel_raw) AS stg_funnel,
  (SELECT COUNT(*) FROM vw_web_funnel)      AS vw_funnel,
  (SELECT COUNT(*) FROM stg_marketing_spend_raw) AS stg_spend,
  (SELECT COUNT(*) FROM vw_marketing_spend)      AS vw_spend;


SELECT MIN(order_date), MAX(order_date), SUM(order_date IS NULL) FROM vw_orders;
SELECT MIN(session_date), MAX(session_date) FROM vw_web_funnel;
SELECT MIN(spend_date), MAX(spend_date) FROM vw_marketing_spend;

SELECT channel, COUNT(*) FROM vw_orders GROUP BY channel ORDER BY channel;

SELECT COUNT(*) FROM vw_marketing_spend WHERE spend IS NULL;
