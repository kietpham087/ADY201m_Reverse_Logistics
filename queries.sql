-- ============================================================
-- queries.sql
-- Project : Reverse Logistics & Circular Economy in E-commerce
-- Dataset : Olist Brazilian E-Commerce (2016–2018)
-- Table   : olist_analytical_table  (99,441 rows × 46 cols)
-- ============================================================


-- ══════════════════════════════════════════════════════════════
-- RQ1 – CONSUMER BEHAVIOR
-- Research Question: How does consumer perception of "sustainable
-- return" policies and refurbished/recycled products in e-commerce
-- affect their purchasing decisions and brand loyalty?
-- Proxy: repeat-purchase rate, review scores, late-delivery impact
-- ══════════════════════════════════════════════════════════════

-- ── Query 1: Tỉ lệ khách hàng quay lại (Brand Loyalty Proxy) ──
-- Phân loại khách hàng thành "Loyal (Repeat buyer)" vs "One-time buyer"
-- dựa trên số đơn hàng đã giao thành công.
-- Loyal customers = customers who would continue buying after positive experience
-- → Circular economy / sustainable return policy có thể tăng nhóm này.
SELECT
    customer_type,
    COUNT(*)                               AS customer_count,
    ROUND(AVG(total_orders), 2)            AS avg_orders_per_customer,
    ROUND(AVG(avg_review_score), 2)        AS avg_satisfaction_score
FROM (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id)           AS total_orders,
        AVG(avg_review_score)              AS avg_review_score,
        CASE
            WHEN COUNT(DISTINCT order_id) > 1 THEN 'Loyal (Repeat buyer)'
            ELSE 'One-time buyer'
        END                                AS customer_type
    FROM olist_analytical_table
    WHERE order_status = 'delivered'
    GROUP BY customer_unique_id
) sub
GROUP BY customer_type;


-- ── Query 2: Tác động giao hàng trễ đến sự hài lòng khách hàng ──
-- Giao trễ = trải nghiệm tiêu cực → nguy cơ không mua lại + review thấp.
-- Đây là nguyên nhân gián tiếp dẫn đến hành vi trả hàng (reverse logistics trigger).
-- Cột low_score_pct = % đơn bị đánh giá ≤2 sao (proxy cho khả năng trả hàng).
SELECT
    CASE WHEN is_late_delivery = 1 THEN 'Giao trễ' ELSE 'Đúng hạn' END  AS delivery_status,
    COUNT(*)                                                              AS order_count,
    ROUND(AVG(avg_review_score), 2)                                       AS avg_review_score,
    ROUND(AVG(delay_days), 1)                                             AS avg_delay_days,
    SUM(CASE WHEN avg_review_score <= 2 THEN 1 ELSE 0 END)               AS low_score_count,
    ROUND(
        100.0 * SUM(CASE WHEN avg_review_score <= 2 THEN 1 ELSE 0 END)
        / COUNT(*), 2
    )                                                                     AS low_score_pct
FROM olist_analytical_table
WHERE is_late_delivery IS NOT NULL
GROUP BY is_late_delivery;


-- ══════════════════════════════════════════════════════════════
-- RQ2 – FINANCIAL IMPACT
-- Research Question: How does the transition from traditional
-- reverse logistics to a closed-loop supply chain impact the
-- cost structure and profit margins of e-commerce businesses?
-- Proxy: freight ratio, cancellation revenue loss, monthly trends
-- ══════════════════════════════════════════════════════════════

-- ── Query 3: Chi phí logistics theo danh mục sản phẩm (Freight Ratio) ──
-- freight_ratio_pct = tỉ lệ chi phí vận chuyển / giá sản phẩm.
-- Categories với freight ratio cao → gánh nặng chi phí logistics lớn
-- → Ưu tiên đầu tư tối ưu hóa trong closed-loop supply chain.
SELECT
    product_category_name_english                                           AS category,
    COUNT(*)                                                                AS order_count,
    ROUND(AVG(total_price), 2)                                              AS avg_product_price,
    ROUND(AVG(total_freight), 2)                                            AS avg_freight_cost,
    ROUND(
        100.0 * AVG(total_freight) / NULLIF(AVG(total_price), 0), 2
    )                                                                       AS freight_ratio_pct
FROM olist_analytical_table
WHERE order_status     = 'delivered'
  AND product_category_name_english IS NOT NULL
GROUP BY product_category_name_english
HAVING COUNT(*) > 50
ORDER BY freight_ratio_pct DESC
LIMIT 15;


-- ── Query 4: Tác động tài chính của từng trạng thái đơn hàng ──
-- Đơn "canceled" và "unavailable" = doanh thu bị mất + chi phí logistics lãng phí.
-- total_value_impact cho thấy quy mô tài chính của các đơn không thành công.
-- → Đây là chi phí trực tiếp mà closed-loop supply chain cần giảm thiểu.
SELECT
    order_status,
    COUNT(*)                              AS order_count,
    ROUND(AVG(total_order_value), 2)      AS avg_order_value,
    ROUND(SUM(total_order_value), 2)      AS total_value_impact,
    ROUND(AVG(total_freight), 2)          AS avg_freight_cost,
    ROUND(AVG(avg_review_score), 2)       AS avg_review_score
FROM olist_analytical_table
GROUP BY order_status
ORDER BY order_count DESC;


-- ── Query 5: Xu hướng doanh thu và tỉ lệ hủy đơn theo tháng ──
-- Xác định mùa cao điểm để lập kế hoạch đầu tư hạ tầng reverse logistics.
-- delivered_revenue = tổng doanh thu thực thu được mỗi tháng.
-- cancel_rate_pct   = % đơn bị hủy — chỉ số sức khỏe tài chính theo thời gian.
SELECT
    purchase_year,
    purchase_month,
    COUNT(*)                                                                AS total_orders,
    SUM(CASE WHEN order_status = 'canceled' THEN 1 ELSE 0 END)             AS canceled_orders,
    ROUND(
        100.0 * SUM(CASE WHEN order_status = 'canceled' THEN 1 ELSE 0 END)
        / COUNT(*), 2
    )                                                                       AS cancel_rate_pct,
    ROUND(
        SUM(CASE WHEN order_status = 'delivered' THEN total_order_value ELSE 0 END), 2
    )                                                                       AS delivered_revenue
FROM olist_analytical_table
GROUP BY purchase_year, purchase_month
ORDER BY purchase_year, purchase_month;


-- ══════════════════════════════════════════════════════════════
-- RQ3 – TECHNOLOGY INTEGRATION
-- Research Question: What role do digital technologies (AI, IoT,
-- Blockchain) play in enhancing transparency of product recovery
-- and improving sorting efficiency in reverse logistics?
-- Proxy: logistics timing accuracy, seller performance risk
-- ══════════════════════════════════════════════════════════════

-- ── Query 6: Phân tích thời gian các giai đoạn logistics ──
-- So sánh actual_delivery_days vs estimated_delivery_days.
-- Khoảng cách lớn giữa ước tính và thực tế = hệ thống dự báo kém chính xác
-- → Đây là điểm cần ứng dụng AI/ML để dự đoán tốt hơn (RQ3 technology gap).
SELECT
    order_status,
    COUNT(*)                                      AS order_count,
    ROUND(AVG(actual_delivery_days),    1)        AS avg_actual_days,
    ROUND(AVG(estimated_delivery_days), 1)        AS avg_estimated_days,
    ROUND(AVG(delay_days),              1)        AS avg_delay_days,
    ROUND(MIN(actual_delivery_days),    0)        AS min_days,
    ROUND(MAX(actual_delivery_days),    0)        AS max_days
FROM olist_analytical_table
WHERE actual_delivery_days IS NOT NULL
GROUP BY order_status
ORDER BY order_count DESC;


-- ── Query 7: Nhận diện Seller có hiệu suất logistics kém (High-Risk Nodes) ──
-- Seller với late_rate_pct cao và avg_review thấp = "nút rủi ro" trong supply chain.
-- Đây là đối tượng cần ứng dụng:
--   • IoT  → theo dõi hàng hóa thời gian thực
--   • Blockchain → minh bạch hóa lịch sử vận chuyển
--   • AI  → phát hiện sớm nguy cơ giao trễ
-- Chỉ lấy seller có ≥20 đơn để đảm bảo thống kê đáng tin cậy.
SELECT
    seller_id,
    seller_state,
    COUNT(*)                                                               AS total_orders,
    SUM(CASE WHEN is_late_delivery = 1 THEN 1 ELSE 0 END)                 AS late_orders,
    ROUND(
        100.0 * SUM(CASE WHEN is_late_delivery = 1 THEN 1 ELSE 0 END)
        / COUNT(*), 2
    )                                                                      AS late_rate_pct,
    ROUND(AVG(avg_review_score), 2)                                        AS avg_review_score,
    ROUND(AVG(delay_days),       1)                                        AS avg_delay_days
FROM olist_analytical_table
WHERE seller_id        IS NOT NULL
  AND is_late_delivery IS NOT NULL
GROUP BY seller_id, seller_state
HAVING COUNT(*) >= 20
ORDER BY late_rate_pct DESC
LIMIT 20;
