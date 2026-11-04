-- =====================================================================
-- 03_marts.sql — MARTS: una tabla lista para cada visual del tablero
-- =====================================================================
-- Capa de presentación. Cada mart:
--   * lee SOLO tablas fact_ y dim_ (nunca raw.)
--   * ya trae unidos los nombres de sus dimensiones (canal, provincia,
--     producto, mes), así el tablero no tiene que cruzar tablas
--   * guarda medidas ADITIVAS (sumas y conteos) a nivel MES. Los cocientes
--     (ticket, NPS, días promedio, participación) NO se guardan: el tablero
--     suma numerador y denominador del período filtrado y divide al final.
--   * el único conteo DISTINTO (usuarios activos) no se puede sumar entre
--     meses, por eso su mart ya trae calculado cada rango de meses posible.
--
-- Con esto el tablero solo FILTRA filas, SUMA columnas y hace la DIVISIÓN
-- final, igual que una medida de Power BI / Looker Studio.
--
-- Marts:
--   mart_calendario_mes          meses disponibles (opciones del filtro de fecha)
--   mart_ventas_mes              Ventas, Ticket, Ventas por provincia, meta Córdoba
--   mart_ventas_producto_mes     las mismas medidas con el filtro de producto + Ranking por producto
--   mart_usuarios_activos_rango  Usuarios activos para cada rango "desde mes - hasta mes"
--   mart_nps_mes                 NPS (tarjeta y tendencia)
--   mart_entregas_mes            días de entrega por provincia (meta Mendoza)
--   mart_entregas_producto_mes   lo mismo con el filtro de producto
-- =====================================================================


-- ---------------------------------------------------------------------
-- mart_calendario_mes — GRANO: un mes
-- ---------------------------------------------------------------------
CREATE TABLE mart_calendario_mes (
    year_month    VARCHAR PRIMARY KEY,     -- 2025-09
    month_start   DATE    NOT NULL,
    year          INTEGER NOT NULL,
    month         INTEGER NOT NULL,
    year_quarter  VARCHAR NOT NULL,        -- 2025-T3
    month_label   VARCHAR NOT NULL,        -- Sep 25 (eje de los gráficos)
    month_long    VARCHAR NOT NULL         -- Septiembre 2025 (filtro)
);

INSERT INTO mart_calendario_mes
SELECT
    year_month,
    MIN(month_start),
    MIN(year),
    MIN(month),
    MIN(year_quarter),
    ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'][MIN(month)] || ' ' || right(CAST(MIN(year) AS VARCHAR), 2),
    MIN(month_name) || ' ' || MIN(year)
FROM dim_date
WHERE date_key <> -1
GROUP BY year_month
ORDER BY year_month;


-- ---------------------------------------------------------------------
-- mart_ventas_mes — GRANO: mes × canal × provincia (solo pedidos que son venta)
-- ---------------------------------------------------------------------
-- Ventas  = SUM(ventas)
-- Ticket  = SUM(ventas) / SUM(pedidos)
CREATE TABLE mart_ventas_mes (
    year_month      VARCHAR NOT NULL,
    year_quarter    VARCHAR NOT NULL,
    channel_key     INTEGER NOT NULL,
    channel_name    VARCHAR NOT NULL,
    province_key    INTEGER NOT NULL,
    province_code   VARCHAR NOT NULL,
    province_name   VARCHAR NOT NULL,
    ventas          DECIMAL(14, 2) NOT NULL,   -- SUM(total_amount)
    pedidos         INTEGER NOT NULL,          -- COUNT(*)
    PRIMARY KEY (year_month, channel_key, province_key)
);

INSERT INTO mart_ventas_mes
SELECT
    d.year_month,
    d.year_quarter,
    c.channel_key,
    c.name,
    p.province_key,
    p.code,
    p.name,
    SUM(f.total_amount),
    COUNT(*)
FROM fact_orders  AS f
JOIN dim_date     AS d ON d.date_key     = f.date_key
JOIN dim_channel  AS c ON c.channel_key  = f.channel_key
JOIN dim_province AS p ON p.province_key = f.province_key
WHERE f.is_sale
GROUP BY d.year_month, d.year_quarter, c.channel_key, c.name, p.province_key, p.code, p.name
ORDER BY d.year_month, c.channel_key, p.province_key;


-- ---------------------------------------------------------------------
-- mart_ventas_producto_mes — GRANO: mes × canal × provincia × producto
-- ---------------------------------------------------------------------
-- Se usa cuando se elige UN producto (y para el ranking):
--   ventas         = parte del total de los pedidos que corresponde a ese
--                    producto (fact_sales.total_amount_allocated)
--   pedidos        = pedidos que incluyen el producto
--   ventas_netas   = SUM(line_total), base del Ranking por producto (consigna)
-- Ojo: 'pedidos' no se suma ENTRE productos (un pedido con los dos productos
-- aparece en los dos). Sin filtro de producto se usa mart_ventas_mes.
CREATE TABLE mart_ventas_producto_mes (
    year_month      VARCHAR NOT NULL,
    year_quarter    VARCHAR NOT NULL,
    channel_key     INTEGER NOT NULL,
    channel_name    VARCHAR NOT NULL,
    province_key    INTEGER NOT NULL,
    province_code   VARCHAR NOT NULL,
    province_name   VARCHAR NOT NULL,
    product_key     INTEGER NOT NULL,
    product_name    VARCHAR NOT NULL,
    ventas          DECIMAL(14, 2) NOT NULL,   -- SUM(total_amount_allocated)
    pedidos         INTEGER NOT NULL,          -- COUNT(DISTINCT order_id)
    ventas_netas    DECIMAL(14, 2) NOT NULL,   -- SUM(line_total)
    unidades        INTEGER NOT NULL,          -- SUM(quantity)
    PRIMARY KEY (year_month, channel_key, province_key, product_key)
);

INSERT INTO mart_ventas_producto_mes
SELECT
    d.year_month,
    d.year_quarter,
    c.channel_key,
    c.name,
    p.province_key,
    p.code,
    p.name,
    pr.product_key,
    pr.name,
    SUM(f.total_amount_allocated),
    COUNT(DISTINCT f.order_id),
    SUM(f.line_total),
    SUM(f.quantity)
FROM fact_sales   AS f
JOIN dim_date     AS d  ON d.date_key      = f.date_key
JOIN dim_channel  AS c  ON c.channel_key   = f.channel_key
JOIN dim_province AS p  ON p.province_key  = f.province_key
JOIN dim_product  AS pr ON pr.product_key  = f.product_key
WHERE f.is_sale
GROUP BY d.year_month, d.year_quarter, c.channel_key, c.name, p.province_key, p.code, p.name, pr.product_key, pr.name
ORDER BY d.year_month, c.channel_key, p.province_key, pr.product_key;


-- ---------------------------------------------------------------------
-- mart_usuarios_activos_rango — GRANO: un rango de meses (desde, hasta)
-- ---------------------------------------------------------------------
-- COUNT(DISTINCT active_user_id) NO es aditivo: los usuarios de enero más
-- los de febrero no son los usuarios de enero-febrero (hay personas que
-- vuelven). Por eso se precalcula cada rango posible de meses
-- (21 meses -> 231 rangos). Un rango de un solo mes (desde = hasta) es el
-- dato mensual de la serie temporal.
-- Las sesiones son todas del canal ONLINE y no tienen provincia ni producto.
CREATE TABLE mart_usuarios_activos_rango (
    desde_mes            VARCHAR NOT NULL,
    hasta_mes            VARCHAR NOT NULL,
    meses                INTEGER NOT NULL,
    usuarios_activos     INTEGER NOT NULL,   -- COUNT(DISTINCT active_user_id)
    usuarios_logueados   INTEGER NOT NULL,   -- ídem, solo clientes con sesión iniciada
    sesiones             INTEGER NOT NULL,
    PRIMARY KEY (desde_mes, hasta_mes)
);

INSERT INTO mart_usuarios_activos_rango
WITH usuario_mes AS (
    SELECT d.year_month, f.active_user_id, BOOL_OR(f.is_logged_in) AS logueado, COUNT(*) AS sesiones
    FROM fact_web_sessions AS f
    JOIN dim_date          AS d ON d.date_key = f.date_key
    GROUP BY d.year_month, f.active_user_id
),
rangos AS (
    SELECT a.year_month AS desde_mes, b.year_month AS hasta_mes,
           (b.year - a.year) * 12 + b.month - a.month + 1 AS meses
    FROM mart_calendario_mes AS a
    JOIN mart_calendario_mes AS b ON a.year_month <= b.year_month
)
SELECT
    r.desde_mes,
    r.hasta_mes,
    r.meses,
    COUNT(DISTINCT u.active_user_id),
    COUNT(DISTINCT u.active_user_id) FILTER (WHERE u.logueado),
    COALESCE(SUM(u.sesiones), 0)
FROM rangos AS r
LEFT JOIN usuario_mes AS u ON u.year_month BETWEEN r.desde_mes AND r.hasta_mes
GROUP BY r.desde_mes, r.hasta_mes, r.meses
ORDER BY r.desde_mes, r.hasta_mes;


-- ---------------------------------------------------------------------
-- mart_nps_mes — GRANO: mes × canal
-- ---------------------------------------------------------------------
-- NPS = SUM(puntos_nps) / SUM(respuestas)
--     (equivale a (SUM(promotores) - SUM(detractores)) * 100 / SUM(respuestas))
CREATE TABLE mart_nps_mes (
    year_month     VARCHAR NOT NULL,
    year_quarter   VARCHAR NOT NULL,
    channel_key    INTEGER NOT NULL,
    channel_name   VARCHAR NOT NULL,
    respuestas     INTEGER NOT NULL,
    promotores     INTEGER NOT NULL,
    pasivos        INTEGER NOT NULL,
    detractores    INTEGER NOT NULL,
    puntos_nps     INTEGER NOT NULL,   -- SUM(nps_points): +100 por promotor, -100 por detractor
    PRIMARY KEY (year_month, channel_key)
);

INSERT INTO mart_nps_mes
SELECT
    d.year_month,
    d.year_quarter,
    c.channel_key,
    c.name,
    COUNT(*),
    SUM(f.is_promoter),
    SUM(f.is_passive),
    SUM(f.is_detractor),
    SUM(f.nps_points)
FROM fact_nps    AS f
JOIN dim_date    AS d ON d.date_key    = f.date_key
JOIN dim_channel AS c ON c.channel_key = f.channel_key
GROUP BY d.year_month, d.year_quarter, c.channel_key, c.name
ORDER BY d.year_month, c.channel_key;


-- ---------------------------------------------------------------------
-- mart_entregas_mes — GRANO: mes del pedido × canal × provincia
-- ---------------------------------------------------------------------
-- Solo envíos entregados. Días promedio = SUM(suma_dias_entrega) / SUM(envios_entregados)
CREATE TABLE mart_entregas_mes (
    year_month           VARCHAR NOT NULL,     -- mes del PEDIDO
    year_quarter         VARCHAR NOT NULL,
    channel_key          INTEGER NOT NULL,
    channel_name         VARCHAR NOT NULL,
    province_key         INTEGER NOT NULL,
    province_code        VARCHAR NOT NULL,
    province_name        VARCHAR NOT NULL,
    envios_entregados    INTEGER NOT NULL,
    suma_dias_entrega    DECIMAL(14, 2) NOT NULL,   -- SUM(days_to_deliver)
    PRIMARY KEY (year_month, channel_key, province_key)
);

INSERT INTO mart_entregas_mes
SELECT
    d.year_month,
    d.year_quarter,
    c.channel_key,
    c.name,
    p.province_key,
    p.code,
    p.name,
    COUNT(*),
    SUM(f.days_to_deliver)
FROM fact_shipments AS f
JOIN dim_date       AS d ON d.date_key     = f.order_date_key
JOIN dim_channel    AS c ON c.channel_key  = f.channel_key
JOIN dim_province   AS p ON p.province_key = f.province_key
WHERE f.is_delivered
GROUP BY d.year_month, d.year_quarter, c.channel_key, c.name, p.province_key, p.code, p.name
ORDER BY d.year_month, c.channel_key, p.province_key;


-- ---------------------------------------------------------------------
-- mart_entregas_producto_mes — GRANO: mes del pedido × canal × provincia × producto
-- ---------------------------------------------------------------------
-- Envíos entregados de pedidos que INCLUYEN el producto. Un envío con los
-- dos productos aparece en los dos: no se suma entre productos (sin filtro
-- de producto se usa mart_entregas_mes).
CREATE TABLE mart_entregas_producto_mes (
    year_month           VARCHAR NOT NULL,
    year_quarter         VARCHAR NOT NULL,
    channel_key          INTEGER NOT NULL,
    channel_name         VARCHAR NOT NULL,
    province_key         INTEGER NOT NULL,
    province_code        VARCHAR NOT NULL,
    province_name        VARCHAR NOT NULL,
    product_key          INTEGER NOT NULL,
    product_name         VARCHAR NOT NULL,
    envios_entregados    INTEGER NOT NULL,
    suma_dias_entrega    DECIMAL(14, 2) NOT NULL,
    PRIMARY KEY (year_month, channel_key, province_key, product_key)
);

INSERT INTO mart_entregas_producto_mes
SELECT
    d.year_month,
    d.year_quarter,
    c.channel_key,
    c.name,
    p.province_key,
    p.code,
    p.name,
    pr.product_key,
    pr.name,
    COUNT(*),
    SUM(f.days_to_deliver)
FROM fact_shipments AS f
JOIN (SELECT DISTINCT order_id, product_key FROM fact_sales) AS op ON op.order_id = f.order_id
JOIN dim_date       AS d  ON d.date_key     = f.order_date_key
JOIN dim_channel    AS c  ON c.channel_key  = f.channel_key
JOIN dim_province   AS p  ON p.province_key = f.province_key
JOIN dim_product    AS pr ON pr.product_key = op.product_key
WHERE f.is_delivered
GROUP BY d.year_month, d.year_quarter, c.channel_key, c.name, p.province_key, p.code, p.name, pr.product_key, pr.name
ORDER BY d.year_month, c.channel_key, p.province_key, pr.product_key;
