WITH sales_2023 AS (
  SELECT region, SUM(amount) as total_sales
  FROM sales
  WHERE extract(year from date) = 2023
  GROUP BY region
),
top_regions AS (
  SELECT region
  FROM (
    -- This inner query is identical to the sales_2023 CTE
    SELECT region, SUM(amount) as total_sales
    FROM sales
    WHERE extract(year from date) = 2023
    GROUP BY region
  ) sub
  WHERE total_sales > 100000
)
SELECT s.region, s.total_sales
FROM sales_2023 s
JOIN top_regions t ON s.region = t.region;
