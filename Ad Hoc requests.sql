use rp;

select * from dim_city;
select * from dim_ad_category;
select * from fact_ad_revenue;
select * from fact_city_readiness;
select * from fact_print_sales;
select * from fact_digital_pilot;


-- Business Request – 1: Monthly Circulation Drop Check 
-- Generate a report showing the top 3 months (2019–2024) where any city recorded the 
-- sharpest month-over-month decline in net_circulation.
with circulation as (
select city_id, month, net_circulation,
lag(net_circulation)over(partition by city_id order by month) as prev_net_circulation,
(net_circulation - lag(net_circulation)over(partition by city_id order by month)) as mom
from fact_print_sales
)
select city_id, month, prev_net_circulation,
    net_circulation AS current_net_circulation,
    mom AS decline_value
FROM circulation
WHERE mom < 0
ORDER BY mom ASC 
LIMIT 3;

drop table fact_ad_revenue;
use rp;
select * from fact_ad_revenue;

with cte as (
    select year,
           ad_category as category_name,
           sum(ad_revenue) as total_revenue,
           sum(sum(ad_revenue)) over (partition by year) as total_revenue_by_year
    from fact_ad_revenue
    group by year, ad_category
),
cte1 as (
    select year,
           category_name,
           total_revenue,
           total_revenue_by_year,
           (total_revenue * 100.0 / total_revenue_by_year) as pct_of_year
    from cte
)
select year, category_name, total_revenue
from cte1
where pct_of_year > 50
order by year;

-- Business Request – 3: 2024 Print Efficiency Leaderboard 
-- For 2024, rank cities by print efficiency = net_circulation / copies_printed. Return top 5.

select * from dim_city;
select * from fact_print_sales ;


SELECT 
    d.city AS city_name,
    SUM(f.copies_sold - f.copies_returned) AS copies_printed_2024,
    SUM(f.net_circulation) AS net_circulation_2024,
    ROUND(SUM(f.net_circulation) * 1.0 / SUM(f.copies_sold - f.copies_returned), 2) AS efficiency_ratio,
    RANK() OVER (ORDER BY SUM(f.net_circulation) * 1.0 / SUM(f.copies_sold - f.copies_returned) DESC) AS efficiency_rank_2024
FROM fact_print_sales f
JOIN dim_city d 
    ON f.city_id = d.city_id
WHERE f.month LIKE '%24'
GROUP BY d.city
ORDER BY efficiency_rank_2024
LIMIT 5;


-- Business Request – 4 : Internet Readiness Growth (2021) 
-- For each city, compute the change in internet penetration from Q1-2021 to Q4-2021 
-- and identify the city with the highest improvement. 

select 
    c.city as city_name,
    q1.internet_penetration as internet_rate_q1_2021,
    q4.internet_penetration as internet_rate_q4_2021,
    (q4.internet_penetration - q1.internet_penetration) as delta_internet_rate
from dim_city c
join fact_city_readiness q1 
    on c.city_id = q1.city_id and q1.quarter = '2021-Q1'
join fact_city_readiness q4 
    on c.city_id = q4.city_id and q4.quarter = '2021-Q4'
order by delta_internet_rate desc
limit 1;

use rp;

-- Print Circulation Trends 
-- What is the trend in copies printed, copies sold, and net circulation across all 
-- cities from 2019 to 2024? How has this changed year-over-year?


select month from fact_print_sales;
WITH yearly_summary AS (
    SELECT 
        RIGHT(month, 4) AS year,
        SUM(copies_sold + copies_returned) AS total_copies_printed,
        SUM(copies_sold) AS total_copies_sold,
        SUM(net_circulation) AS total_net_circulation
    FROM fact_print_sales
    GROUP BY RIGHT(month, 4) 
)
SELECT
    year,
    total_copies_printed,
    total_copies_sold,
    total_net_circulation,
    ROUND(
        (total_net_circulation - LAG(total_net_circulation) OVER (ORDER BY year)) 
        / NULLIF(LAG(total_net_circulation) OVER (ORDER BY year), 0) * 100, 
        2
    ) AS yoy_change_percent
FROM yearly_summary
ORDER BY year;


-- Which cities contributed the highest to net circulation and copies sold in 2024? 
-- Are these cities still profitable to operate in? 
SELECT 
    d.city,
    SUM(fps.net_circulation) AS total_net_circulation,
    SUM(fps.copies_sold) AS total_copies_sold
FROM fact_print_sales fps
JOIN dim_city d 
  ON fps.city_id = d.city_id
WHERE month like '%2024%'
GROUP BY d.city
ORDER BY total_net_circulation DESC
LIMIT 10;



-- Print Waste Analysis 
-- Which cities have the largest gap between copies printed and net circulation, and 
-- how has that gap changed over time?
SELECT 
    d.city,
    RIGHT(month, 4) AS year,
    SUM((fps.copies_returned+fps.copies_sold) - fps.net_circulation) AS total_print_waste,
    ROUND(SUM((fps.copies_returned+fps.copies_sold) - fps.net_circulation)
          / NULLIF(SUM(fps.copies_returned+fps.copies_sold), 0) * 100, 2) AS waste_percent
FROM fact_print_sales fps
JOIN dim_city d 
  ON fps.city_id = d.city_id
GROUP BY d.city, year
ORDER BY total_print_waste DESC;

-- Ad Revenue Trends by Category (2019–2024)
SELECT 
    year,
    dac.standard_ad_category,
    SUM(far.ad_revenue) AS total_revenue,
    ROUND(
        (SUM(far.ad_revenue) 
         - LAG(SUM(far.ad_revenue)) OVER (PARTITION BY dac.standard_ad_category ORDER BY year))
        / NULLIF(LAG(SUM(far.ad_revenue)) OVER (PARTITION BY dac.standard_ad_category ORDER BY year), 0) * 100, 2
    ) AS yoy_growth_percent
FROM fact_ad_revenue far
LEFT JOIN dim_ad_category dac 
  ON far.ad_category = dac.ad_category_id
GROUP BY year, dac.standard_ad_category
ORDER BY dac.standard_ad_category, year;

-- 7. Ad Revenue vs Circulation ROI (Yearly)

SELECT 
    d.city,
    year,
    SUM(far.ad_revenue) AS total_revenue,
    SUM(fps.net_circulation) AS total_circulation,
    ROUND(
        SUM(far.ad_revenue) / NULLIF(SUM(fps.net_circulation), 0), 
        2
    ) AS revenue_per_copy
FROM fact_ad_revenue far
JOIN dim_city d 
    ON far.edition_id = d.city_id
LEFT JOIN fact_print_sales fps 
    ON far.edition_id = fps.city_id
    AND year = RIGHT(month, 4)
GROUP BY d.city, year
ORDER BY revenue_per_copy DESC;

