-- =====================================================================
-- MEADOW & CO — Production Views (Cleaning + Analysis Layer)
-- Verified against the live database (Sept 2026) — this is the exact
-- logic currently running, reformatted for readability.
-- =====================================================================

USE meadowco;

-- =====================================================================
-- VIEW: vw_customers
-- Purpose: Cleaned customer dimension (skincare persona segment + region).
-- =====================================================================
DROP VIEW IF EXISTS vw_customers;

CREATE VIEW vw_customers AS
SELECT
    customer_id,
    NULLIF(TRIM(segment), '') AS segment,
    TRIM(region)              AS region,
    STR_TO_DATE(first_order_date, '%Y-%m-%d') AS first_order_date
FROM stg_customers;


-- =====================================================================
-- VIEW: vw_orders
-- Purpose: Cleaned orders fact table. De-duplicates raw rows by order_id
--          (keeps the first occurrence), parses two different raw date
--          formats (ISO and UK DD/MM/YYYY), normalises channel names via
--          dim_channel_map, and converts is_new_customer from text
--          ('True'/'False') to 1/0.
-- =====================================================================
DROP VIEW IF EXISTS vw_orders;

CREATE VIEW vw_orders AS
SELECT
    o.order_id,
    NULLIF(TRIM(o.customer_id), '') AS customer_id,
    CASE
        WHEN o.order_date REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN STR_TO_DATE(o.order_date, '%Y-%m-%d')
        WHEN o.order_date REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' THEN STR_TO_DATE(o.order_date, '%d/%m/%Y')
        ELSE NULL
    END AS order_date,
    COALESCE(m.channel_clean, 'Unmapped') AS channel,
    o.device,
    TRIM(o.region)  AS region,
    TRIM(o.segment) AS segment,
    o.product_category,
    o.quantity,
    o.gross_revenue,
    o.discount_amount,
    o.net_revenue,
    CASE o.is_new_customer
        WHEN 'True'  THEN 1
        WHEN 'False' THEN 0
        ELSE NULL
    END AS is_new_customer
FROM (
    SELECT
        s.order_id,
        s.customer_id,
        s.order_date,
        s.channel,
        s.device,
        s.region,
        s.segment,
        s.product_category,
        s.quantity,
        s.gross_revenue,
        s.discount_amount,
        s.net_revenue,
        s.is_new_customer,
        ROW_NUMBER() OVER (PARTITION BY s.order_id ORDER BY s.order_id) AS rn
    FROM stg_orders_raw s
) o
LEFT JOIN dim_channel_map m
    ON TRIM(o.channel) COLLATE utf8mb4_bin = m.channel_raw
WHERE o.rn = 1;


-- =====================================================================
-- VIEW: vw_marketing_spend
-- Purpose: Cleaned marketing spend by date/channel/campaign. Normalises
--          raw channel names via dim_channel_map and strips the "£"
--          currency symbol from spend so it can be cast to a decimal.
-- =====================================================================
DROP VIEW IF EXISTS vw_marketing_spend;

CREATE VIEW vw_marketing_spend AS
SELECT
    STR_TO_DATE(s.date, '%Y-%m-%d')       AS spend_date,
    COALESCE(m.channel_clean, 'Unmapped') AS channel,
    s.campaign,
    s.impressions,
    s.clicks,
    CASE WHEN TRIM(s.spend) = ''
         THEN NULL
         ELSE CAST(REPLACE(s.spend, '£', '') AS DECIMAL(10,2))
    END AS spend
FROM stg_marketing_spend_raw s
LEFT JOIN dim_channel_map m
    ON TRIM(s.channel) COLLATE utf8mb4_bin = m.channel_raw;


-- =====================================================================
-- VIEW: vw_web_funnel
-- Purpose: Cleaned web funnel (sessions -> cart -> checkout -> purchase)
--          by date/channel/device, with channel names normalised.
-- =====================================================================
DROP VIEW IF EXISTS vw_web_funnel;

CREATE VIEW vw_web_funnel AS
SELECT
    STR_TO_DATE(f.date, '%Y-%m-%d')       AS session_date,
    COALESCE(m.channel_clean, 'Unmapped') AS channel,
    NULLIF(TRIM(f.device), '')            AS device,
    f.sessions,
    f.add_to_cart,
    f.begin_checkout,
    f.purchases
FROM stg_web_funnel_raw f
LEFT JOIN dim_channel_map m
    ON TRIM(f.channel) COLLATE utf8mb4_bin = m.channel_raw;


-- =====================================================================
-- VIEW: vw_email_ab_test
-- Purpose: Pass-through cleaned view of the October restock email
--          subject-line A/B test, pre-aggregated by persona x variant.
-- =====================================================================
DROP VIEW IF EXISTS vw_email_ab_test;

CREATE VIEW vw_email_ab_test AS
SELECT
    campaign,
    segment,
    variant,
    emails_sent,
    opens,
    clicks,
    conversions,
    revenue
FROM stg_email_ab_test;


-- =====================================================================
-- VIEW: vw_channel_performance
-- Purpose: Monthly revenue vs. spend by channel, with derived performance
--          metrics (ROAS, ROI %, CPC, cost per order).
-- Logic: LEFT JOINs revenue (from vw_orders) to spend (from
--        vw_marketing_spend) by year-month + channel, then UNION ALLs in
--        any spend-only rows (channels with ad spend but zero orders that
--        month) so spend is never silently dropped from the picture.
-- =====================================================================
DROP VIEW IF EXISTS vw_channel_performance;

CREATE VIEW vw_channel_performance AS
SELECT
    combined.ym       AS month,
    combined.channel,
    combined.revenue,
    combined.orders,
    combined.spend,
    combined.clicks,
    combined.impressions,
    CASE WHEN combined.spend > 0
         THEN ROUND(combined.revenue / combined.spend, 2) END AS roas,
    CASE WHEN combined.spend > 0
         THEN ROUND((combined.revenue - combined.spend) / combined.spend * 100, 1) END AS roi_pct,
    CASE WHEN combined.clicks > 0
         THEN ROUND(combined.spend / combined.clicks, 2) END AS cpc,
    CASE WHEN combined.orders > 0 AND combined.spend > 0
         THEN ROUND(combined.spend / combined.orders, 2) END AS cost_per_order
FROM (
    -- Revenue rows, left-joined to matching spend (spend defaults to 0 if none)
    SELECT
        r.ym, r.channel, r.revenue, r.orders,
        COALESCE(s.spend, 0)       AS spend,
        COALESCE(s.clicks, 0)      AS clicks,
        COALESCE(s.impressions, 0) AS impressions
    FROM (
        SELECT
            DATE_FORMAT(order_date, '%Y-%m') AS ym,
            channel,
            SUM(net_revenue)         AS revenue,
            COUNT(DISTINCT order_id) AS orders
        FROM vw_orders
        WHERE order_date IS NOT NULL
        GROUP BY ym, channel
    ) r
    LEFT JOIN (
        SELECT
            DATE_FORMAT(spend_date, '%Y-%m') AS ym,
            channel,
            SUM(spend)       AS spend,
            SUM(clicks)      AS clicks,
            SUM(impressions) AS impressions
        FROM vw_marketing_spend
        WHERE spend IS NOT NULL
        GROUP BY ym, channel
    ) s ON r.ym = s.ym AND r.channel = s.channel

    UNION ALL

    -- Spend-only rows: channel/month combos with ad spend but no matching orders
    SELECT
        s.ym, s.channel, 0 AS revenue, 0 AS orders,
        s.spend, s.clicks, s.impressions
    FROM (
        SELECT
            DATE_FORMAT(spend_date, '%Y-%m') AS ym,
            channel,
            SUM(spend)       AS spend,
            SUM(clicks)      AS clicks,
            SUM(impressions) AS impressions
        FROM vw_marketing_spend
        WHERE spend IS NOT NULL
        GROUP BY ym, channel
    ) s
    LEFT JOIN (
        SELECT
            DATE_FORMAT(order_date, '%Y-%m') AS ym,
            channel,
            SUM(net_revenue)         AS revenue,
            COUNT(DISTINCT order_id) AS orders
        FROM vw_orders
        WHERE order_date IS NOT NULL
        GROUP BY ym, channel
    ) r ON r.ym = s.ym AND r.channel = s.channel
    WHERE r.ym IS NULL
) combined;


-- =====================================================================
-- VIEW: vw_customer_rfm
-- Purpose: RFM (Recency, Frequency, Monetary) scoring and segmentation
--          for every customer with at least one order.
-- =====================================================================
DROP VIEW IF EXISTS vw_customer_rfm;

CREATE VIEW vw_customer_rfm AS
WITH customer_orders AS (
    SELECT
        customer_id,
        COUNT(DISTINCT order_id) AS frequency,
        SUM(net_revenue)         AS monetary,
        MAX(order_date)          AS last_order_date
    FROM vw_orders
    WHERE customer_id IS NOT NULL   -- 9 guest-checkout orders excluded; can't segment an anonymous order
    GROUP BY customer_id
),
rfm_base AS (
    SELECT
        customer_id,
        DATEDIFF((SELECT MAX(order_date) FROM vw_orders), last_order_date) AS recency_days,
        frequency,
        monetary
    FROM customer_orders
),
rfm_scored AS (
    SELECT
        customer_id, recency_days, frequency, monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,  -- most recent (lowest days) -> score 5
        -- NOT NTILE for frequency: in this dataset frequency is low-cardinality
        -- and heavily tied (most customers have ordered exactly once -- every
        -- segment's avg order count tops out at 2.2). NTILE forces ties into
        -- 5 equal-sized buckets with no deterministic tiebreaker, so one-time
        -- buyers get scattered across all 5 buckets essentially at random --
        -- verified empirically: the 'Loyal Customers' bucket (f_score>=3)
        -- came back with an average order count of 1.0, identical to
        -- 'Lost/Churned'. Fixed tiers avoid this: NTILE stays appropriate for
        -- recency_days and monetary, which have real spread/cardinality.
        CASE
            WHEN frequency = 1 THEN 1
            WHEN frequency = 2 THEN 3
            WHEN frequency >= 3 THEN 5
        END AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score   -- highest spend -> score 5
    FROM rfm_base
)
SELECT
    customer_id, recency_days, frequency, monetary,
    r_score, f_score, m_score,
    (r_score + f_score + m_score) AS rfm_total,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 4 AND f_score >= 3                  THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Promising'
        WHEN r_score BETWEEN 2 AND 3 AND f_score >= 3       THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2                  THEN 'Lost / Churned'
        ELSE 'Needs Attention'
    END AS rfm_segment
FROM rfm_scored;