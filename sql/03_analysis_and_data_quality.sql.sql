-- =====================================================================
-- MEADOW & CO — Analysis Queries & Data Quality Checks
-- Runs against the views in 02_views.sql. These are the queries used to
-- validate/cross-check the Power BI numbers, plus QA checks run during
-- the build to confirm the cleaning logic worked as intended.
-- =====================================================================

USE meadowco;

-- =====================================================================
-- SECTION 1: CHANNEL ROI (Business Question 1)
-- =====================================================================

-- Monthly trend for the 4 paid channels only
SELECT month, channel, revenue, spend, roas, roi_pct
FROM vw_channel_performance
WHERE channel IN ('Google Search', 'Google Shopping', 'Meta Ads', 'Affiliate')
ORDER BY channel, month;

-- Full-period summary by channel — source-of-truth query behind the
-- Power BI Page 1 table (Affiliate 5.30, Meta Ads 0.75, etc.)
SELECT
    channel,
    SUM(revenue)                                                              AS total_revenue,
    SUM(orders)                                                               AS total_orders,
    SUM(spend)                                                                AS total_spend,
    CASE WHEN SUM(spend) > 0 THEN ROUND(SUM(revenue) / SUM(spend), 2) END        AS roas,
    CASE WHEN SUM(spend) > 0 THEN ROUND((SUM(revenue) - SUM(spend)) / SUM(spend) * 100, 1) END AS roi_pct
FROM vw_channel_performance
GROUP BY channel
ORDER BY total_revenue DESC;


-- =====================================================================
-- SECTION 2: FUNNEL LEAKAGE (Business Question 3)
-- =====================================================================

-- Device-level funnel conversion rates — source-of-truth for Power BI Page 3
SELECT
    COALESCE(device, 'Unknown') AS device,
    SUM(sessions)       AS sessions,
    SUM(add_to_cart)    AS add_to_cart,
    SUM(begin_checkout) AS begin_checkout,
    SUM(purchases)      AS purchases,
    ROUND(SUM(add_to_cart)    / NULLIF(SUM(sessions), 0)       * 100, 1) AS pct_session_to_cart,
    ROUND(SUM(begin_checkout) / NULLIF(SUM(add_to_cart), 0)    * 100, 1) AS pct_cart_to_checkout,
    ROUND(SUM(purchases)      / NULLIF(SUM(begin_checkout), 0) * 100, 1) AS pct_checkout_to_purchase,
    ROUND(SUM(purchases)      / NULLIF(SUM(sessions), 0)       * 100, 1) AS overall_conversion_pct
FROM vw_web_funnel
GROUP BY device
ORDER BY sessions DESC;

-- Device x channel breakdown, worst 15 combinations by conversion rate.
-- Tiny cells (<30 sessions) are dropped so one lucky/unlucky session
-- doesn't show up as a misleading 100% or 0% conversion rate.
SELECT
    COALESCE(device, 'Unknown') AS device,
    channel,
    SUM(sessions)  AS sessions,
    SUM(purchases) AS purchases,
    ROUND(SUM(purchases) / NULLIF(SUM(sessions), 0) * 100, 1) AS conversion_pct
FROM vw_web_funnel
GROUP BY device, channel
HAVING SUM(sessions) >= 30
ORDER BY conversion_pct ASC
LIMIT 15;


-- =====================================================================
-- SECTION 3: CUSTOMER SEGMENTATION (Business Question 2)
-- =====================================================================

-- RFM segment summary — customer count, avg lifetime revenue, avg orders,
-- avg recency, per behavioural segment
SELECT
    rfm_segment,
    COUNT(*)                    AS customers,
    ROUND(AVG(monetary), 2)     AS avg_lifetime_revenue,
    ROUND(AVG(frequency), 1)    AS avg_orders,
    ROUND(AVG(recency_days), 0) AS avg_days_since_last_order
FROM vw_customer_rfm
GROUP BY rfm_segment
ORDER BY avg_lifetime_revenue DESC;

-- Cross-tab: skincare persona (who they are) x RFM segment (how valuable
-- they are) — two different segment concepts that must not be conflated.
SELECT
    COALESCE(c.segment, 'Unspecified') AS skincare_segment,
    r.rfm_segment,
    COUNT(*)                  AS customers,
    ROUND(AVG(r.monetary), 2) AS avg_lifetime_revenue
FROM vw_customer_rfm r
JOIN vw_customers c ON c.customer_id = r.customer_id
GROUP BY skincare_segment, r.rfm_segment
ORDER BY skincare_segment, avg_lifetime_revenue DESC;


-- =====================================================================
-- SECTION 4: DATA QUALITY CHECKS
-- Sanity checks run during the build to confirm the cleaning logic in
-- 02_views.sql worked as intended.
-- =====================================================================

-- Any orders where the date couldn't be parsed by either expected format?
SELECT
    o.order_id,
    s.order_date AS raw_order_date_string
FROM vw_orders o
JOIN stg_orders_raw s ON o.order_id = s.order_id
WHERE o.order_date IS NULL;

-- Any customers on file with zero orders? (Would break RFM scoring if so.)
SELECT c.customer_id, c.first_order_date
FROM vw_customers c
LEFT JOIN vw_orders o ON o.customer_id = c.customer_id
WHERE o.customer_id IS NULL;