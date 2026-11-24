USE n01sport_dev;

-- Dòng ghi sổ theo giờ Việt Nam. Các khoản thu đang đối soát được theo dõi ở payments.
CREATE SQL SECURITY INVOKER VIEW vw_revenue
(facility_id,posting_date,category,source_key,signed_amount) AS
WITH recognized_court_payments AS (
    SELECT p.id,p.amount,p.received_at,c.facility_id
    FROM payments p JOIN bookings b ON b.id=p.booking_id JOIN courts c ON c.id=b.court_id
    WHERE p.status='SUCCEEDED' AND p.received_at<b.expires_at
      AND EXISTS (SELECT 1 FROM booking_status_history h WHERE h.booking_id=b.id AND h.to_status='CONFIRMED')
)
SELECT facility_id,DATE(received_at+INTERVAL 7 HOUR),'COURT',CONCAT('payment:',id),amount
FROM recognized_court_payments
UNION ALL
SELECT p.facility_id,DATE(r.settled_at+INTERVAL 7 HOUR),'COURT',CONCAT('refund:',r.id),-r.amount
FROM refunds r JOIN refund_requests q ON q.id=r.request_id AND q.status='APPROVED'
JOIN recognized_court_payments p ON p.id=q.payment_id WHERE r.status='SUCCEEDED'
UNION ALL
SELECT o.facility_id,DATE(p.paid_at+INTERVAL 7 HOUR),'SALE',CONCAT('sale:',p.id),p.amount
FROM sales_payments p JOIN sales_orders o ON o.id=p.order_id
WHERE p.status='SUCCEEDED' AND o.status='PAID'
UNION ALL
SELECT o.facility_id,DATE(r.posted_at+INTERVAL 7 HOUR),r.kind,CONCAT('rental:',r.id),r.amount
FROM rental_transactions r JOIN rental_orders o ON o.id=r.rental_id
WHERE r.status='SUCCEEDED' AND r.kind IN ('RENT','DAMAGE_COMPENSATION');

-- Các khoảng bị chặn được gom hợp trước khi trừ, để bảo trì và tạm ngừng không bị trừ hai lần.
CREATE SQL SECURITY INVOKER VIEW vw_court_utilization
(court_id,usage_date,used_minutes,available_minutes,booking_count) AS
WITH RECURSIVE
report_limit AS (
    SELECT DATE(UTC_TIMESTAMP()+INTERVAL 7 HOUR) AS last_day
), source_dates AS (
    SELECT MIN(valid_from) AS first_day FROM court_hours
    UNION ALL SELECT DATE(MIN(start_at)+INTERVAL 7 HOUR) FROM bookings
), months (first_of_month) AS (
    SELECT CAST(DATE_FORMAT(MIN(first_day),'%Y-%m-01') AS DATE) FROM source_dates
    UNION ALL
    SELECT DATE_ADD(first_of_month,INTERVAL 1 MONTH) FROM months,report_limit
    WHERE DATE_ADD(first_of_month,INTERVAL 1 MONTH)<=last_day
), digits (n) AS (
    SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
), day_offsets AS (
    SELECT a.n+10*b.n AS n FROM digits a CROSS JOIN digits b WHERE a.n+10*b.n<=30
), candidate_days AS (
    SELECT DATE_ADD(m.first_of_month,INTERVAL d.n DAY) AS day
    FROM months m CROSS JOIN day_offsets d
    WHERE d.n<DAY(LAST_DAY(m.first_of_month))
), report_days AS (
    SELECT day,CAST(day AS DATETIME)-INTERVAL 7 HOUR AS begin_utc,
           CAST(day AS DATETIME)+INTERVAL 17 HOUR AS end_utc
    FROM candidate_days,report_limit WHERE day<=last_day
), open_hours AS (
    SELECT h.id,h.court_id,c.facility_id,d.day,
           TIMESTAMP(d.day,h.opens_at)-INTERVAL 7 HOUR AS opens_utc,
           TIMESTAMP(d.day,h.closes_at)-INTERVAL 7 HOUR AS closes_utc
    FROM court_hours h JOIN courts c ON c.id=h.court_id JOIN report_days d
      ON d.day>=h.valid_from AND (h.valid_to IS NULL OR d.day<h.valid_to)
      AND WEEKDAY(d.day)+1=h.weekday
), status_events AS (
    SELECT entity_type,entity_key,created_at AS starts,
           LEAD(created_at) OVER(PARTITION BY entity_type,entity_key ORDER BY created_at,id) AS ends,
           ROW_NUMBER() OVER(PARTITION BY entity_type,entity_key ORDER BY created_at,id) AS ordinal,
           JSON_UNQUOTE(JSON_EXTRACT(details,'$.status')) AS state
    FROM audit_logs WHERE action='AVAILABILITY_STATUS' AND entity_type IN ('courts','facilities')
), unavailable AS (
    SELECT court_id,NULL AS facility_id,starts_at AS starts,
           LEAST(ends_at,COALESCE(released_at,ends_at)) AS ends
    FROM court_blocks
    UNION ALL SELECT NULL,facility_id,starts_at,ends_at FROM facility_suspensions
    UNION ALL
    SELECT CASE WHEN entity_type='courts' THEN CAST(entity_key AS UNSIGNED) END,
           CASE WHEN entity_type='facilities' THEN CAST(entity_key AS UNSIGNED) END,starts,ends
    FROM status_events WHERE state<>'ACTIVE'
    UNION ALL
    SELECT CASE WHEN entity_type='courts' THEN CAST(entity_key AS UNSIGNED) END,
           CASE WHEN entity_type='facilities' THEN CAST(entity_key AS UNSIGNED) END,
           CAST('1000-01-01' AS DATETIME),starts
    FROM status_events WHERE ordinal=1
), clipped_outages AS (
    SELECT h.id,h.day,GREATEST(h.opens_utc,u.starts) AS starts,
           LEAST(h.closes_utc,COALESCE(u.ends,h.closes_utc)) AS ends
    FROM open_hours h JOIN unavailable u ON (u.court_id=h.court_id OR u.facility_id=h.facility_id)
      AND u.starts<h.closes_utc AND (u.ends IS NULL OR h.opens_utc<u.ends)
      AND (u.ends IS NULL OR u.starts<u.ends)
), previous_end AS (
    SELECT id,day,starts,ends,MAX(ends) OVER(PARTITION BY id,day ORDER BY starts,ends
             ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS previous_max
    FROM clipped_outages
), outage_duration AS (
    SELECT id,day,SUM(GREATEST(0,TIMESTAMPDIFF(MICROSECOND,
            GREATEST(starts,COALESCE(previous_max,starts)),ends))) AS micros
    FROM previous_end GROUP BY id,day
), capacity AS (
    SELECT h.court_id,h.day,FLOOR(SUM(TIMESTAMPDIFF(MICROSECOND,h.opens_utc,h.closes_utc)
            -COALESCE(u.micros,0))/60000000) AS mins
    FROM open_hours h LEFT JOIN outage_duration u ON u.id=h.id AND u.day=h.day
    GROUP BY h.court_id,h.day
), actual AS (
    SELECT b.court_id,d.day,FLOOR(SUM(CASE WHEN b.status='COMPLETED'
          THEN TIMESTAMPDIFF(MICROSECOND,GREATEST(b.start_at,d.begin_utc),LEAST(b.end_at,d.end_utc))
          ELSE 0 END)/60000000) AS mins,
          SUM(b.start_at>=d.begin_utc AND b.start_at<d.end_utc) AS bookings
    FROM bookings b JOIN report_days d ON b.start_at<d.end_utc AND d.begin_utc<b.end_at
    WHERE b.status IN ('CONFIRMED','CHECKED_IN','COMPLETED','NO_SHOW')
    GROUP BY b.court_id,d.day
), result_days AS (
    SELECT court_id,day FROM capacity
    UNION SELECT court_id,day FROM actual
)
SELECT d.court_id,d.day,COALESCE(a.mins,0),COALESCE(c.mins,0),COALESCE(a.bookings,0)
FROM result_days d LEFT JOIN actual a ON a.court_id=d.court_id AND a.day=d.day
LEFT JOIN capacity c ON c.court_id=d.court_id AND c.day=d.day;

CREATE SQL SECURITY INVOKER VIEW vw_customer_metrics
(customer_id,created_at,facility_id,booking_count,court_spend,points_balance,tier_code) AS
WITH booking_counts AS (
    SELECT customer_id,COUNT(*) AS total FROM bookings
    WHERE status IN ('CONFIRMED','CHECKED_IN','COMPLETED','NO_SHOW') GROUP BY customer_id
), customer_transaction_keys AS (
    SELECT b.customer_id,CONCAT('payment:',p.id) AS source_key FROM payments p JOIN bookings b ON b.id=p.booking_id
    UNION ALL
    SELECT b.customer_id,CONCAT('refund:',r.id) FROM refunds r JOIN refund_requests q ON q.id=r.request_id
    JOIN payments p ON p.id=q.payment_id JOIN bookings b ON b.id=p.booking_id
), customer_spend AS (
    SELECT k.customer_id,SUM(v.signed_amount) AS net
    FROM vw_revenue v JOIN customer_transaction_keys k ON k.source_key=v.source_key
    WHERE v.category='COURT' GROUP BY k.customer_id
)
SELECT c.id,c.created_at,c.home_facility_id,COALESCE(b.total,0),COALESCE(s.net,0),COALESCE(a.balance,0),t.code
FROM customers c
LEFT JOIN booking_counts b ON b.customer_id=c.id LEFT JOIN customer_spend s ON s.customer_id=c.id
LEFT JOIN loyalty_accounts a ON a.customer_id=c.id LEFT JOIN loyalty_tiers t ON t.id=a.tier_id;
