-- =====================================================================
-- 03_consultas.sql — Controles del modelo y consultas de los KPIs
-- =====================================================================
-- Parte A: controles de calidad (que el modelo "cierre" contra raw).
-- Parte B: los KPIs del tablero, calculados SOLO con el modelo estrella.
-- Parte C: consultas para las metas del trimestre y hallazgos extra.
-- =====================================================================


-- =====================================================================
-- PARTE A — CONTROLES DE CALIDAD
-- =====================================================================

-- A1. Cantidad de filas: cada hecho debe tener las mismas filas que su tabla de origen
SELECT 'fact_sales'        AS tabla, (SELECT COUNT(*) FROM fact_sales)        AS filas_dw, (SELECT COUNT(*) FROM raw.sales_order_item) AS filas_raw
UNION ALL SELECT 'fact_orders',       (SELECT COUNT(*) FROM fact_orders),       (SELECT COUNT(*) FROM raw.sales_order)
UNION ALL SELECT 'fact_payments',     (SELECT COUNT(*) FROM fact_payments),     (SELECT COUNT(*) FROM raw.payment)
UNION ALL SELECT 'fact_shipments',    (SELECT COUNT(*) FROM fact_shipments),    (SELECT COUNT(*) FROM raw.shipment)
UNION ALL SELECT 'fact_web_sessions', (SELECT COUNT(*) FROM fact_web_sessions), (SELECT COUNT(*) FROM raw.web_session)
UNION ALL SELECT 'fact_nps',          (SELECT COUNT(*) FROM fact_nps),          (SELECT COUNT(*) FROM raw.nps_response);

-- A2. Los importes cierran: ventas del DW = ventas calculadas directo en raw
SELECT
    (SELECT SUM(total_amount) FROM fact_orders WHERE is_sale)                               AS ventas_dw,
    (SELECT SUM(total_amount) FROM raw.sales_order WHERE status IN ('PAID', 'FULFILLED'))   AS ventas_raw,
    (SELECT SUM(total_amount_allocated) FROM fact_sales WHERE is_sale)                      AS ventas_dw_por_linea,
    (SELECT SUM(line_total) FROM fact_sales) = (SELECT SUM(subtotal) FROM fact_orders)      AS lineas_igual_subtotal;

-- A3. Claves "desconocidas" (-1): cuántas filas no tienen cliente / tienda
SELECT 'nps anónimas' AS caso, COUNT(*) AS filas FROM fact_nps WHERE customer_key = -1
UNION ALL SELECT 'sesiones sin login', COUNT(*) FROM fact_web_sessions WHERE customer_key = -1
UNION ALL SELECT 'pedidos online (sin tienda)', COUNT(*) FROM fact_orders WHERE store_key = -1;


-- =====================================================================
-- PARTE B — KPIs DEL TABLERO
-- =====================================================================

-- B1. $M Total Ventas — SUM(total_amount) de pedidos PAID/FULFILLED, por canal
SELECT
    COALESCE(c.name, 'TOTAL')                  AS canal,
    COUNT(*)                                   AS pedidos,
    ROUND(SUM(f.total_amount) / 1e6, 2)        AS ventas_millones
FROM fact_orders AS f
JOIN dim_channel AS c USING (channel_key)
WHERE f.is_sale
GROUP BY ROLLUP (c.name)
ORDER BY c.name NULLS LAST;

-- B2. Ventas y Ticket Promedio por mes (serie temporal)
--     Ticket promedio = SUM(total_amount) / COUNT(*) con el mismo filtro que Ventas
SELECT
    d.year_month                                         AS mes,
    COUNT(*)                                             AS pedidos,
    ROUND(SUM(f.total_amount) / 1e6, 2)                  AS ventas_millones,
    ROUND(SUM(f.total_amount) / COUNT(*) / 1e3, 1)       AS ticket_promedio_miles
FROM fact_orders AS f
JOIN dim_date    AS d USING (date_key)
WHERE f.is_sale
GROUP BY d.year_month
ORDER BY d.year_month;

-- B3. $K Ticket Promedio total y por canal
SELECT
    COALESCE(c.name, 'TOTAL')                            AS canal,
    ROUND(SUM(f.total_amount) / COUNT(*), 0)             AS ticket_promedio,
    ROUND(SUM(f.total_amount) / COUNT(*) / 1e3, 1)       AS ticket_promedio_miles
FROM fact_orders AS f
JOIN dim_channel AS c USING (channel_key)
WHERE f.is_sale
GROUP BY ROLLUP (c.name)
ORDER BY c.name NULLS LAST;

-- B4. nK Usuarios Activos por mes — COUNT(DISTINCT cliente o sesión anónima)
SELECT
    d.year_month                                         AS mes,
    COUNT(*)                                             AS sesiones,
    COUNT(DISTINCT f.active_user_id)                     AS usuarios_activos,
    COUNT(DISTINCT f.active_user_id) FILTER (WHERE f.is_logged_in) AS usuarios_logueados
FROM fact_web_sessions AS f
JOIN dim_date          AS d USING (date_key)
GROUP BY d.year_month
ORDER BY d.year_month;

-- B5. Usuarios activos de todo el período (tarjeta nK)
SELECT
    COUNT(DISTINCT active_user_id)                       AS usuarios_activos,
    ROUND(COUNT(DISTINCT active_user_id) / 1e3, 1)       AS usuarios_activos_miles
FROM fact_web_sessions;

-- B6. NPS total y por canal — ((%9-10) - (%0-6)) * 100
SELECT
    COALESCE(c.name, 'TOTAL')                            AS canal,
    COUNT(*)                                             AS respuestas,
    ROUND(100.0 * SUM(f.is_promoter)  / COUNT(*), 1)     AS pct_promotores,
    ROUND(100.0 * SUM(f.is_detractor) / COUNT(*), 1)     AS pct_detractores,
    ROUND((SUM(f.is_promoter) - SUM(f.is_detractor)) * 100.0 / COUNT(*), 1) AS nps
FROM fact_nps    AS f
JOIN dim_channel AS c USING (channel_key)
GROUP BY ROLLUP (c.name)
ORDER BY c.name NULLS LAST;

-- B7. NPS por trimestre y canal (tendencia)
SELECT
    d.year_quarter                                       AS trimestre,
    ROUND(AVG(f.nps_points) FILTER (WHERE c.code = 'ONLINE'),  1) AS nps_online,
    ROUND(AVG(f.nps_points) FILTER (WHERE c.code = 'OFFLINE'), 1) AS nps_offline,
    ROUND(AVG(f.nps_points), 1)                          AS nps_total
FROM fact_nps    AS f
JOIN dim_date    AS d USING (date_key)
JOIN dim_channel AS c USING (channel_key)
GROUP BY d.year_quarter
ORDER BY d.year_quarter;

-- B8. Ventas por provincia (dirección de envío -> provincia)
SELECT
    p.name                                               AS provincia,
    COUNT(*)                                             AS pedidos,
    ROUND(SUM(f.total_amount) / 1e6, 2)                  AS ventas_millones,
    ROUND(100.0 * SUM(f.total_amount) / SUM(SUM(f.total_amount)) OVER (), 1) AS participacion_pct
FROM fact_orders  AS f
JOIN dim_province AS p USING (province_key)
WHERE f.is_sale
GROUP BY p.name
ORDER BY ventas_millones DESC;

-- B9. Ranking mensual por producto — SUM(line_total) por producto y mes
SELECT
    d.year_month                                         AS mes,
    RANK() OVER (PARTITION BY d.year_month ORDER BY SUM(f.line_total) DESC) AS puesto,
    p.name                                               AS producto,
    SUM(f.quantity)                                      AS unidades,
    ROUND(SUM(f.line_total) / 1e6, 2)                    AS ventas_netas_millones
FROM fact_sales  AS f
JOIN dim_date    AS d USING (date_key)
JOIN dim_product AS p USING (product_key)
WHERE f.is_sale
GROUP BY d.year_month, p.name
ORDER BY d.year_month DESC, puesto
LIMIT 12;   -- últimos 6 meses (2 productos por mes)


-- =====================================================================
-- PARTE C — METAS DEL TRIMESTRE Y HALLAZGOS
-- =====================================================================

-- C1. Meta: crecer 15 % las ventas en Córdoba. Ventas por trimestre y provincia,
--     con variación contra el trimestre anterior y contra el mismo trimestre del año anterior.
WITH t AS (
    SELECT p.name AS provincia, d.year_quarter AS trimestre, SUM(f.total_amount) AS ventas
    FROM fact_orders  AS f
    JOIN dim_date     AS d USING (date_key)
    JOIN dim_province AS p USING (province_key)
    WHERE f.is_sale
    GROUP BY ALL
)
SELECT
    provincia,
    trimestre,
    ROUND(ventas / 1e6, 2)                                                           AS ventas_millones,
    ROUND(100.0 * (ventas / LAG(ventas, 1) OVER w - 1), 1)                           AS var_vs_trim_anterior_pct,
    ROUND(100.0 * (ventas / LAG(ventas, 4) OVER w - 1), 1)                           AS var_vs_anio_anterior_pct
FROM t
WINDOW w AS (PARTITION BY provincia ORDER BY trimestre)
QUALIFY provincia = 'Córdoba'
ORDER BY trimestre;

-- C2. Meta: reducir tiempos de entrega en Mendoza. Días promedio del pedido a la
--     entrega por provincia y trimestre (solo envíos entregados).
SELECT
    p.name                                               AS provincia,
    d.year_quarter                                       AS trimestre,
    COUNT(*)                                             AS envios_entregados,
    ROUND(AVG(f.days_to_deliver), 2)                     AS dias_promedio_entrega,
    ROUND(MEDIAN(f.days_to_deliver), 2)                  AS dias_mediana_entrega,
    ROUND(AVG(f.days_in_transit), 2)                     AS dias_en_viaje
FROM fact_shipments AS f
JOIN dim_province   AS p ON p.province_key = f.province_key
JOIN dim_date       AS d ON d.date_key     = f.order_date_key
WHERE f.is_delivered
  AND d.year_quarter IN ('2025-T2', '2025-T3')
GROUP BY ALL
ORDER BY provincia, trimestre;

-- C3. Tasa de cancelación y reembolso por canal (pedidos que no llegan a ser venta)
SELECT
    c.name                                               AS canal,
    s.status_code                                        AS estado,
    COUNT(*)                                             AS pedidos,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY c.name), 1) AS pct_del_canal
FROM fact_orders      AS f
JOIN dim_channel      AS c USING (channel_key)
JOIN dim_order_status AS s USING (status_key)
GROUP BY c.name, s.status_code
ORDER BY canal, pedidos DESC;

-- C4. Conversión web por origen de tráfico: usuarios logueados que compraron online
--     el mismo día de su visita
WITH visitas AS (
    SELECT DISTINCT f.customer_key, f.date_key, t.description AS origen
    FROM fact_web_sessions  AS f
    JOIN dim_traffic_source AS t USING (source_key)
    WHERE f.is_logged_in
),
compras AS (
    SELECT DISTINCT o.customer_key, o.date_key
    FROM fact_orders AS o
    JOIN dim_channel AS c USING (channel_key)
    WHERE o.is_sale AND c.code = 'ONLINE'
)
SELECT
    v.origen,
    COUNT(*)                                             AS visitas_cliente_dia,
    COUNT(c.customer_key)                                AS con_compra,
    ROUND(100.0 * COUNT(c.customer_key) / COUNT(*), 2)   AS conversion_pct
FROM visitas AS v
LEFT JOIN compras AS c USING (customer_key, date_key)
GROUP BY v.origen
ORDER BY conversion_pct DESC;

-- C5. Medios de pago: participación en las ventas y tasa de pagos fallidos
SELECT
    m.description                                        AS medio_de_pago,
    COUNT(*)                                             AS pagos,
    ROUND(100.0 * COUNT(*) FILTER (WHERE f.payment_status = 'FAILED') / COUNT(*), 1) AS pct_fallidos,
    ROUND(SUM(f.amount) FILTER (WHERE f.payment_status = 'PAID') / 1e6, 2)          AS cobrado_millones
FROM fact_payments      AS f
JOIN dim_payment_method AS m USING (payment_method_key)
GROUP BY m.description
ORDER BY pagos DESC;
