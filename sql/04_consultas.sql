-- =====================================================================
-- 04_consultas.sql — Validaciones del modelo y consultas de los KPIs
-- =====================================================================
-- Parte A: controles de calidad (que el modelo y los marts "cierren").
-- Parte B: los KPIs del tablero, calculados SOLO con el modelo estrella.
-- Parte C: consultas para las metas del trimestre y hallazgos extra.
-- Cada SELECT se muestra en la terminal al ejecutar run_sql.py.
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
UNION ALL SELECT 'fact_nps',          (SELECT COUNT(*) FROM fact_nps),          (SELECT COUNT(*) FROM raw.nps_response)
UNION ALL SELECT 'dim_customer (sin -1)', (SELECT COUNT(*) FROM dim_customer WHERE customer_key <> -1), (SELECT COUNT(*) FROM raw.customer)
UNION ALL SELECT 'dim_address (sin -1)',  (SELECT COUNT(*) FROM dim_address  WHERE address_key  <> -1), (SELECT COUNT(*) FROM raw.address);

-- A2. Los importes cierran: ventas del DW = ventas calculadas directo en raw, y el
--     reparto del total por línea suma EXACTAMENTE el total de cada pedido
SELECT
    (SELECT SUM(total_amount) FROM fact_orders WHERE is_sale)                               AS ventas_dw,
    (SELECT SUM(total_amount) FROM raw.sales_order WHERE status IN ('PAID', 'FULFILLED'))   AS ventas_raw,
    (SELECT SUM(total_amount_allocated) FROM fact_sales WHERE is_sale)                      AS ventas_dw_por_linea,
    (SELECT COUNT(*) FROM (
        SELECT o.order_id
        FROM fact_orders AS o JOIN fact_sales AS s USING (order_id)
        GROUP BY o.order_id, o.total_amount
        HAVING SUM(s.total_amount_allocated) <> o.total_amount))                            AS pedidos_reparto_distinto,
    (SELECT SUM(line_total) FROM fact_sales) = (SELECT SUM(subtotal) FROM fact_orders)      AS lineas_igual_subtotal;

-- A3. Miembros -1: cuántas filas apuntan a "desconocido / no aplica"
SELECT 'nps anónimas' AS caso, COUNT(*) AS filas FROM fact_nps WHERE customer_key = -1
UNION ALL SELECT 'sesiones sin login',             COUNT(*) FROM fact_web_sessions WHERE customer_key = -1
UNION ALL SELECT 'pedidos online (sin tienda)',    COUNT(*) FROM fact_orders WHERE store_key = -1
UNION ALL SELECT 'pedidos sin dir. facturación',   COUNT(*) FROM fact_orders WHERE billing_address_key = -1
UNION ALL SELECT 'pagos sin fecha de cobro',       COUNT(*) FROM fact_payments WHERE paid_date_key = -1
UNION ALL SELECT 'envíos sin fecha de despacho',   COUNT(*) FROM fact_shipments WHERE shipped_date_key = -1
UNION ALL SELECT 'envíos sin fecha de entrega',    COUNT(*) FROM fact_shipments WHERE delivered_date_key = -1
UNION ALL SELECT 'estado de pedido desconocido',   COUNT(*) FROM fact_orders WHERE status_key = -1;

-- A4. Integridad referencial: ninguna FK huérfana y ninguna FK en NULL
--     (DuckDB ya rechaza la carga si una FK no existe; esta consulta lo deja a la vista)
SELECT COUNT(*) AS fks_revisadas, SUM(huerfanas) AS fk_huerfanas, SUM(nulas) AS fk_nulas
FROM (
    SELECT 'fact_nps.channel_key' AS fk, COUNT(*) FILTER (WHERE d.channel_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.channel_key IS NULL) AS nulas FROM fact_nps AS f LEFT JOIN dim_channel AS d ON d.channel_key = f.channel_key
    UNION ALL SELECT 'fact_nps.customer_key' AS fk, COUNT(*) FILTER (WHERE d.customer_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.customer_key IS NULL) AS nulas FROM fact_nps AS f LEFT JOIN dim_customer AS d ON d.customer_key = f.customer_key
    UNION ALL SELECT 'fact_nps.date_key' AS fk, COUNT(*) FILTER (WHERE d.date_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.date_key IS NULL) AS nulas FROM fact_nps AS f LEFT JOIN dim_date AS d ON d.date_key = f.date_key
    UNION ALL SELECT 'fact_nps.nps_category_key' AS fk, COUNT(*) FILTER (WHERE d.nps_category_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.nps_category_key IS NULL) AS nulas FROM fact_nps AS f LEFT JOIN dim_nps_category AS d ON d.nps_category_key = f.nps_category_key
    UNION ALL SELECT 'fact_orders.billing_address_key' AS fk, COUNT(*) FILTER (WHERE d.address_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.billing_address_key IS NULL) AS nulas FROM fact_orders AS f LEFT JOIN dim_address AS d ON d.address_key = f.billing_address_key
    UNION ALL SELECT 'fact_orders.channel_key' AS fk, COUNT(*) FILTER (WHERE d.channel_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.channel_key IS NULL) AS nulas FROM fact_orders AS f LEFT JOIN dim_channel AS d ON d.channel_key = f.channel_key
    UNION ALL SELECT 'fact_orders.customer_key' AS fk, COUNT(*) FILTER (WHERE d.customer_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.customer_key IS NULL) AS nulas FROM fact_orders AS f LEFT JOIN dim_customer AS d ON d.customer_key = f.customer_key
    UNION ALL SELECT 'fact_orders.date_key' AS fk, COUNT(*) FILTER (WHERE d.date_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.date_key IS NULL) AS nulas FROM fact_orders AS f LEFT JOIN dim_date AS d ON d.date_key = f.date_key
    UNION ALL SELECT 'fact_orders.payment_method_key' AS fk, COUNT(*) FILTER (WHERE d.payment_method_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.payment_method_key IS NULL) AS nulas FROM fact_orders AS f LEFT JOIN dim_payment_method AS d ON d.payment_method_key = f.payment_method_key
    UNION ALL SELECT 'fact_orders.province_key' AS fk, COUNT(*) FILTER (WHERE d.province_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.province_key IS NULL) AS nulas FROM fact_orders AS f LEFT JOIN dim_province AS d ON d.province_key = f.province_key
    UNION ALL SELECT 'fact_orders.shipping_address_key' AS fk, COUNT(*) FILTER (WHERE d.address_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.shipping_address_key IS NULL) AS nulas FROM fact_orders AS f LEFT JOIN dim_address AS d ON d.address_key = f.shipping_address_key
    UNION ALL SELECT 'fact_orders.status_key' AS fk, COUNT(*) FILTER (WHERE d.status_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.status_key IS NULL) AS nulas FROM fact_orders AS f LEFT JOIN dim_order_status AS d ON d.status_key = f.status_key
    UNION ALL SELECT 'fact_orders.store_key' AS fk, COUNT(*) FILTER (WHERE d.store_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.store_key IS NULL) AS nulas FROM fact_orders AS f LEFT JOIN dim_store AS d ON d.store_key = f.store_key
    UNION ALL SELECT 'fact_payments.channel_key' AS fk, COUNT(*) FILTER (WHERE d.channel_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.channel_key IS NULL) AS nulas FROM fact_payments AS f LEFT JOIN dim_channel AS d ON d.channel_key = f.channel_key
    UNION ALL SELECT 'fact_payments.customer_key' AS fk, COUNT(*) FILTER (WHERE d.customer_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.customer_key IS NULL) AS nulas FROM fact_payments AS f LEFT JOIN dim_customer AS d ON d.customer_key = f.customer_key
    UNION ALL SELECT 'fact_payments.order_date_key' AS fk, COUNT(*) FILTER (WHERE d.date_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.order_date_key IS NULL) AS nulas FROM fact_payments AS f LEFT JOIN dim_date AS d ON d.date_key = f.order_date_key
    UNION ALL SELECT 'fact_payments.paid_date_key' AS fk, COUNT(*) FILTER (WHERE d.date_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.paid_date_key IS NULL) AS nulas FROM fact_payments AS f LEFT JOIN dim_date AS d ON d.date_key = f.paid_date_key
    UNION ALL SELECT 'fact_payments.payment_method_key' AS fk, COUNT(*) FILTER (WHERE d.payment_method_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.payment_method_key IS NULL) AS nulas FROM fact_payments AS f LEFT JOIN dim_payment_method AS d ON d.payment_method_key = f.payment_method_key
    UNION ALL SELECT 'fact_payments.payment_status_key' AS fk, COUNT(*) FILTER (WHERE d.payment_status_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.payment_status_key IS NULL) AS nulas FROM fact_payments AS f LEFT JOIN dim_payment_status AS d ON d.payment_status_key = f.payment_status_key
    UNION ALL SELECT 'fact_sales.channel_key' AS fk, COUNT(*) FILTER (WHERE d.channel_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.channel_key IS NULL) AS nulas FROM fact_sales AS f LEFT JOIN dim_channel AS d ON d.channel_key = f.channel_key
    UNION ALL SELECT 'fact_sales.customer_key' AS fk, COUNT(*) FILTER (WHERE d.customer_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.customer_key IS NULL) AS nulas FROM fact_sales AS f LEFT JOIN dim_customer AS d ON d.customer_key = f.customer_key
    UNION ALL SELECT 'fact_sales.date_key' AS fk, COUNT(*) FILTER (WHERE d.date_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.date_key IS NULL) AS nulas FROM fact_sales AS f LEFT JOIN dim_date AS d ON d.date_key = f.date_key
    UNION ALL SELECT 'fact_sales.product_key' AS fk, COUNT(*) FILTER (WHERE d.product_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.product_key IS NULL) AS nulas FROM fact_sales AS f LEFT JOIN dim_product AS d ON d.product_key = f.product_key
    UNION ALL SELECT 'fact_sales.province_key' AS fk, COUNT(*) FILTER (WHERE d.province_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.province_key IS NULL) AS nulas FROM fact_sales AS f LEFT JOIN dim_province AS d ON d.province_key = f.province_key
    UNION ALL SELECT 'fact_sales.shipping_address_key' AS fk, COUNT(*) FILTER (WHERE d.address_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.shipping_address_key IS NULL) AS nulas FROM fact_sales AS f LEFT JOIN dim_address AS d ON d.address_key = f.shipping_address_key
    UNION ALL SELECT 'fact_sales.status_key' AS fk, COUNT(*) FILTER (WHERE d.status_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.status_key IS NULL) AS nulas FROM fact_sales AS f LEFT JOIN dim_order_status AS d ON d.status_key = f.status_key
    UNION ALL SELECT 'fact_sales.store_key' AS fk, COUNT(*) FILTER (WHERE d.store_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.store_key IS NULL) AS nulas FROM fact_sales AS f LEFT JOIN dim_store AS d ON d.store_key = f.store_key
    UNION ALL SELECT 'fact_shipments.carrier_key' AS fk, COUNT(*) FILTER (WHERE d.carrier_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.carrier_key IS NULL) AS nulas FROM fact_shipments AS f LEFT JOIN dim_carrier AS d ON d.carrier_key = f.carrier_key
    UNION ALL SELECT 'fact_shipments.channel_key' AS fk, COUNT(*) FILTER (WHERE d.channel_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.channel_key IS NULL) AS nulas FROM fact_shipments AS f LEFT JOIN dim_channel AS d ON d.channel_key = f.channel_key
    UNION ALL SELECT 'fact_shipments.customer_key' AS fk, COUNT(*) FILTER (WHERE d.customer_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.customer_key IS NULL) AS nulas FROM fact_shipments AS f LEFT JOIN dim_customer AS d ON d.customer_key = f.customer_key
    UNION ALL SELECT 'fact_shipments.delivered_date_key' AS fk, COUNT(*) FILTER (WHERE d.date_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.delivered_date_key IS NULL) AS nulas FROM fact_shipments AS f LEFT JOIN dim_date AS d ON d.date_key = f.delivered_date_key
    UNION ALL SELECT 'fact_shipments.order_date_key' AS fk, COUNT(*) FILTER (WHERE d.date_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.order_date_key IS NULL) AS nulas FROM fact_shipments AS f LEFT JOIN dim_date AS d ON d.date_key = f.order_date_key
    UNION ALL SELECT 'fact_shipments.province_key' AS fk, COUNT(*) FILTER (WHERE d.province_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.province_key IS NULL) AS nulas FROM fact_shipments AS f LEFT JOIN dim_province AS d ON d.province_key = f.province_key
    UNION ALL SELECT 'fact_shipments.shipment_status_key' AS fk, COUNT(*) FILTER (WHERE d.shipment_status_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.shipment_status_key IS NULL) AS nulas FROM fact_shipments AS f LEFT JOIN dim_shipment_status AS d ON d.shipment_status_key = f.shipment_status_key
    UNION ALL SELECT 'fact_shipments.shipped_date_key' AS fk, COUNT(*) FILTER (WHERE d.date_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.shipped_date_key IS NULL) AS nulas FROM fact_shipments AS f LEFT JOIN dim_date AS d ON d.date_key = f.shipped_date_key
    UNION ALL SELECT 'fact_shipments.shipping_address_key' AS fk, COUNT(*) FILTER (WHERE d.address_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.shipping_address_key IS NULL) AS nulas FROM fact_shipments AS f LEFT JOIN dim_address AS d ON d.address_key = f.shipping_address_key
    UNION ALL SELECT 'fact_shipments.store_key' AS fk, COUNT(*) FILTER (WHERE d.store_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.store_key IS NULL) AS nulas FROM fact_shipments AS f LEFT JOIN dim_store AS d ON d.store_key = f.store_key
    UNION ALL SELECT 'fact_web_sessions.channel_key' AS fk, COUNT(*) FILTER (WHERE d.channel_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.channel_key IS NULL) AS nulas FROM fact_web_sessions AS f LEFT JOIN dim_channel AS d ON d.channel_key = f.channel_key
    UNION ALL SELECT 'fact_web_sessions.customer_key' AS fk, COUNT(*) FILTER (WHERE d.customer_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.customer_key IS NULL) AS nulas FROM fact_web_sessions AS f LEFT JOIN dim_customer AS d ON d.customer_key = f.customer_key
    UNION ALL SELECT 'fact_web_sessions.date_key' AS fk, COUNT(*) FILTER (WHERE d.date_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.date_key IS NULL) AS nulas FROM fact_web_sessions AS f LEFT JOIN dim_date AS d ON d.date_key = f.date_key
    UNION ALL SELECT 'fact_web_sessions.device_key' AS fk, COUNT(*) FILTER (WHERE d.device_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.device_key IS NULL) AS nulas FROM fact_web_sessions AS f LEFT JOIN dim_device AS d ON d.device_key = f.device_key
    UNION ALL SELECT 'fact_web_sessions.source_key' AS fk, COUNT(*) FILTER (WHERE d.source_key IS NULL) AS huerfanas, COUNT(*) FILTER (WHERE f.source_key IS NULL) AS nulas FROM fact_web_sessions AS f LEFT JOIN dim_traffic_source AS d ON d.source_key = f.source_key
);

-- A5. Los marts cierran contra los hechos (misma cifra por los dos caminos)
SELECT 'ventas'              AS medida, (SELECT SUM(ventas) FROM mart_ventas_mes)              AS en_mart, (SELECT SUM(total_amount) FROM fact_orders WHERE is_sale) AS en_hechos
UNION ALL SELECT 'pedidos',             (SELECT SUM(pedidos) FROM mart_ventas_mes),             (SELECT COUNT(*) FROM fact_orders WHERE is_sale)
UNION ALL SELECT 'ventas por producto', (SELECT SUM(ventas) FROM mart_ventas_producto_mes),     (SELECT SUM(total_amount_allocated) FROM fact_sales WHERE is_sale)
UNION ALL SELECT 'ventas netas',        (SELECT SUM(ventas_netas) FROM mart_ventas_producto_mes), (SELECT SUM(line_total) FROM fact_sales WHERE is_sale)
UNION ALL SELECT 'usuarios activos',    (SELECT usuarios_activos FROM mart_usuarios_activos_rango WHERE desde_mes = '2024-01' AND hasta_mes = '2025-09'), (SELECT COUNT(DISTINCT active_user_id) FROM fact_web_sessions)
UNION ALL SELECT 'respuestas nps',      (SELECT SUM(respuestas) FROM mart_nps_mes),            (SELECT COUNT(*) FROM fact_nps)
UNION ALL SELECT 'puntos nps',          (SELECT SUM(puntos_nps) FROM mart_nps_mes),            (SELECT SUM(nps_points) FROM fact_nps)
UNION ALL SELECT 'envíos entregados',   (SELECT SUM(envios_entregados) FROM mart_entregas_mes), (SELECT COUNT(*) FROM fact_shipments WHERE is_delivered)
UNION ALL SELECT 'ranking: ventas netas (todos/todas)', (SELECT SUM(ventas_netas) FROM mart_ranking_producto_mes WHERE channel_key = 0 AND province_key = 0), (SELECT SUM(line_total) FROM fact_sales WHERE is_sale);

-- A6. El puesto del mart de ranking coincide con RANK() calculado sobre los hechos,
--     para todos los meses y todas las combinaciones de canal y provincia
WITH esperado AS (
    SELECT d.year_month, COALESCE(c.channel_key, 0) AS channel_key, COALESCE(p.province_key, 0) AS province_key, f.product_key,
           RANK() OVER (PARTITION BY d.year_month, COALESCE(c.channel_key, 0), COALESCE(p.province_key, 0) ORDER BY SUM(f.line_total) DESC) AS puesto
    FROM fact_sales AS f
    JOIN dim_date AS d ON d.date_key = f.date_key
    CROSS JOIN (SELECT 0 AS k UNION ALL SELECT DISTINCT channel_key  FROM fact_sales) AS cc
    CROSS JOIN (SELECT 0 AS k UNION ALL SELECT DISTINCT province_key FROM fact_sales) AS pp
    LEFT JOIN dim_channel  AS c ON c.channel_key  = cc.k AND cc.k <> 0
    LEFT JOIN dim_province AS p ON p.province_key = pp.k AND pp.k <> 0
    WHERE f.is_sale
      AND (cc.k = 0 OR f.channel_key = cc.k)
      AND (pp.k = 0 OR f.province_key = pp.k)
    GROUP BY d.year_month, COALESCE(c.channel_key, 0), COALESCE(p.province_key, 0), f.product_key
)
SELECT COUNT(*) AS puestos_comparados,
       COUNT(*) FILTER (WHERE e.puesto <> m.puesto) AS puestos_distintos
FROM esperado AS e
JOIN mart_ranking_producto_mes AS m USING (year_month, channel_key, province_key, product_key);


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
    ROUND(100.0 * COUNT(*) FILTER (WHERE s.status_code = 'FAILED') / COUNT(*), 1) AS pct_fallidos,
    ROUND(SUM(f.amount) FILTER (WHERE s.is_collected) / 1e6, 2)                   AS cobrado_millones
FROM fact_payments      AS f
JOIN dim_payment_method AS m USING (payment_method_key)
JOIN dim_payment_status AS s USING (payment_status_key)
GROUP BY m.description
ORDER BY pagos DESC;
