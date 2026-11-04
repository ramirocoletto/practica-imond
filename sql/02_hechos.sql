-- =====================================================================
-- 02_hechos.sql — Tablas de HECHOS del modelo estrella
-- =====================================================================
-- Se ejecuta después de 01_dimensiones.sql porque los hechos apuntan a
-- las dimensiones con FOREIGN KEY (REFERENCES).
--
-- Hechos (y su GRANO = qué representa UNA fila):
--   fact_sales        un producto dentro de un pedido   (sales_order_item)
--   fact_orders       un pedido                          (sales_order)
--   fact_payments     un pago                            (payment)
--   fact_shipments    un envío por correo                (shipment)
--   fact_web_sessions una visita a la web                (web_session)
--   fact_nps          una respuesta a la encuesta NPS    (nps_response)
--
-- Reglas comunes:
--   * Las fechas se guardan como date_key (AAAAMMDD) -> dim_date.
--   * Se cargan TODOS los pedidos (también cancelados, reembolsados, etc.)
--     y se marca is_sale = TRUE solo para PAID y FULFILLED. Así el tablero
--     puede filtrar ventas y, al mismo tiempo, analizar cancelaciones.
--   * La provincia de un pedido es la de su dirección de ENVÍO
--     (shipping_address_id -> address.province_id). En compras en tienda la
--     dirección de envío es la de la tienda.
-- =====================================================================


-- ---------------------------------------------------------------------
-- fact_sales — GRANO: una línea de pedido (un producto dentro de un pedido)
-- ---------------------------------------------------------------------
-- Base del "Ranking mensual por producto" (line_total) y de las ventas
-- filtradas por producto.
--
-- total_amount_allocated: el total del pedido (con IVA y envío) repartido
-- entre sus líneas en proporción a line_total. Sumado por pedido da el
-- total_amount del pedido, así "Ventas" se puede filtrar por producto sin
-- cambiar la definición del KPI (SUM(total_amount)).
CREATE TABLE fact_sales (
    order_item_id           BIGINT  PRIMARY KEY,
    order_id                BIGINT  NOT NULL,          -- dimensión degenerada
    date_key                INTEGER NOT NULL REFERENCES dim_date (date_key),
    product_key             INTEGER NOT NULL REFERENCES dim_product (product_key),
    customer_key            INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key             INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    store_key               INTEGER NOT NULL REFERENCES dim_store (store_key),
    province_key            INTEGER NOT NULL REFERENCES dim_province (province_key),
    status_key              INTEGER NOT NULL REFERENCES dim_order_status (status_key),
    is_sale                 BOOLEAN NOT NULL,
    quantity                INTEGER NOT NULL,
    unit_price              DECIMAL(12, 2) NOT NULL,
    gross_amount            DECIMAL(12, 2) NOT NULL,   -- quantity * unit_price
    discount_amount         DECIMAL(12, 2) NOT NULL,
    line_total              DECIMAL(12, 2) NOT NULL,   -- gross_amount - discount_amount (sin IVA)
    total_amount_allocated  DECIMAL(12, 2) NOT NULL    -- parte del total del pedido (con IVA y envío)
);

INSERT INTO fact_sales
SELECT
    i.order_item_id,
    i.order_id,
    CAST(strftime(o.order_date, '%Y%m%d') AS INTEGER)         AS date_key,
    dp.product_key,
    dc.customer_key,
    ch.channel_key,
    COALESCE(ds.store_key, -1)                                AS store_key,
    pr.province_key,
    st.status_key,
    st.is_sale,
    i.quantity,
    i.unit_price,
    i.quantity * i.unit_price                                 AS gross_amount,
    i.discount_amount,
    i.line_total,
    ROUND(o.total_amount * i.line_total / NULLIF(o.subtotal, 0), 2) AS total_amount_allocated
FROM raw.sales_order_item   AS i
JOIN raw.sales_order        AS o  ON o.order_id     = i.order_id
JOIN raw.address            AS a  ON a.address_id   = o.shipping_address_id
JOIN dim_product            AS dp ON dp.product_id  = i.product_id
JOIN dim_customer           AS dc ON dc.customer_id = o.customer_id
JOIN dim_channel            AS ch ON ch.channel_id  = o.channel_id
LEFT JOIN dim_store         AS ds ON ds.store_id    = o.store_id
JOIN dim_province           AS pr ON pr.province_id = a.province_id
JOIN dim_order_status       AS st ON st.status_code = o.status;


-- ---------------------------------------------------------------------
-- fact_orders — GRANO: un pedido
-- ---------------------------------------------------------------------
-- Base de "Total Ventas" y "Ticket Promedio". Cada pedido tiene un único
-- pago, por eso el medio de pago se guarda acá como dimensión.
CREATE TABLE fact_orders (
    order_id             BIGINT  PRIMARY KEY,
    date_key             INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key         INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key          INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    store_key            INTEGER NOT NULL REFERENCES dim_store (store_key),
    province_key         INTEGER NOT NULL REFERENCES dim_province (province_key),
    status_key           INTEGER NOT NULL REFERENCES dim_order_status (status_key),
    payment_method_key   INTEGER REFERENCES dim_payment_method (payment_method_key),
    is_sale              BOOLEAN NOT NULL,
    has_shipment         BOOLEAN NOT NULL,             -- viajó por correo
    item_lines           INTEGER NOT NULL,             -- cantidad de líneas
    units                INTEGER NOT NULL,             -- unidades totales
    subtotal             DECIMAL(12, 2) NOT NULL,      -- sin IVA
    discount_amount      DECIMAL(12, 2) NOT NULL,
    tax_amount           DECIMAL(12, 2) NOT NULL,      -- IVA 21 %
    shipping_fee         DECIMAL(12, 2) NOT NULL,
    total_amount         DECIMAL(12, 2) NOT NULL       -- subtotal + IVA + envío
);

INSERT INTO fact_orders
SELECT
    o.order_id,
    CAST(strftime(o.order_date, '%Y%m%d') AS INTEGER)  AS date_key,
    dc.customer_key,
    ch.channel_key,
    COALESCE(ds.store_key, -1)                         AS store_key,
    pr.province_key,
    st.status_key,
    pm.payment_method_key,
    st.is_sale,
    sh.order_id IS NOT NULL                            AS has_shipment,
    it.item_lines,
    it.units,
    o.subtotal,
    it.discount_amount,
    o.tax_amount,
    o.shipping_fee,
    o.total_amount
FROM raw.sales_order        AS o
JOIN raw.address            AS a  ON a.address_id   = o.shipping_address_id
JOIN dim_customer           AS dc ON dc.customer_id = o.customer_id
JOIN dim_channel            AS ch ON ch.channel_id  = o.channel_id
LEFT JOIN dim_store         AS ds ON ds.store_id    = o.store_id
JOIN dim_province           AS pr ON pr.province_id = a.province_id
JOIN dim_order_status       AS st ON st.status_code = o.status
LEFT JOIN raw.payment       AS pa ON pa.order_id    = o.order_id
LEFT JOIN dim_payment_method AS pm ON pm.method_code = pa.method
LEFT JOIN (SELECT DISTINCT order_id FROM raw.shipment) AS sh ON sh.order_id = o.order_id
JOIN (
    SELECT order_id,
           COUNT(*)             AS item_lines,
           SUM(quantity)        AS units,
           SUM(discount_amount) AS discount_amount
    FROM raw.sales_order_item
    GROUP BY order_id
) AS it ON it.order_id = o.order_id;


-- ---------------------------------------------------------------------
-- fact_payments — GRANO: un pago
-- ---------------------------------------------------------------------
-- Permite conciliar ventas vs. cobros (pagos fallidos, pendientes, reembolsos).
CREATE TABLE fact_payments (
    payment_id           BIGINT  PRIMARY KEY,
    order_id             BIGINT  NOT NULL,             -- dimensión degenerada
    order_date_key       INTEGER NOT NULL REFERENCES dim_date (date_key),
    paid_date_key        INTEGER REFERENCES dim_date (date_key),   -- NULL si no se cobró
    payment_method_key   INTEGER NOT NULL REFERENCES dim_payment_method (payment_method_key),
    customer_key         INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key          INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    payment_status       VARCHAR NOT NULL,             -- PENDING / PAID / FAILED / REFUNDED
    transaction_ref      VARCHAR,
    amount               DECIMAL(12, 2) NOT NULL,
    minutes_to_pay       INTEGER                       -- del pedido al cobro
);

INSERT INTO fact_payments
SELECT
    pa.payment_id,
    pa.order_id,
    CAST(strftime(o.order_date, '%Y%m%d') AS INTEGER)  AS order_date_key,
    CAST(strftime(pa.paid_at,   '%Y%m%d') AS INTEGER)  AS paid_date_key,
    pm.payment_method_key,
    dc.customer_key,
    ch.channel_key,
    pa.status                                          AS payment_status,
    pa.transaction_ref,
    pa.amount,
    date_diff('minute', o.order_date, pa.paid_at)      AS minutes_to_pay
FROM raw.payment             AS pa
JOIN raw.sales_order         AS o  ON o.order_id     = pa.order_id
JOIN dim_payment_method      AS pm ON pm.method_code = pa.method
JOIN dim_customer            AS dc ON dc.customer_id = o.customer_id
JOIN dim_channel             AS ch ON ch.channel_id  = o.channel_id;


-- ---------------------------------------------------------------------
-- fact_shipments — GRANO: un envío por correo
-- ---------------------------------------------------------------------
-- Traza la logística: tiempos de despacho y de entrega por provincia.
-- Sirve para la meta "reducir tiempos de entrega en Mendoza".
CREATE TABLE fact_shipments (
    shipment_id          BIGINT  PRIMARY KEY,
    order_id             BIGINT  NOT NULL,             -- dimensión degenerada
    order_date_key       INTEGER NOT NULL REFERENCES dim_date (date_key),
    shipped_date_key     INTEGER REFERENCES dim_date (date_key),
    delivered_date_key   INTEGER REFERENCES dim_date (date_key),
    customer_key         INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key          INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    store_key            INTEGER NOT NULL REFERENCES dim_store (store_key),
    province_key         INTEGER NOT NULL REFERENCES dim_province (province_key),
    carrier              VARCHAR,
    tracking_number      VARCHAR,
    shipment_status      VARCHAR NOT NULL,             -- READY / SHIPPED / DELIVERED / CANCELLED
    is_delivered         BOOLEAN NOT NULL,
    hours_to_ship        DECIMAL(8, 2),                -- pedido -> despacho
    days_in_transit      DECIMAL(8, 2),                -- despacho -> entrega
    days_to_deliver      DECIMAL(8, 2)                 -- pedido -> entrega (lo que vive el cliente)
);

INSERT INTO fact_shipments
SELECT
    s.shipment_id,
    s.order_id,
    CAST(strftime(o.order_date,   '%Y%m%d') AS INTEGER)              AS order_date_key,
    CAST(strftime(s.shipped_at,   '%Y%m%d') AS INTEGER)              AS shipped_date_key,
    CAST(strftime(s.delivered_at, '%Y%m%d') AS INTEGER)              AS delivered_date_key,
    dc.customer_key,
    ch.channel_key,
    COALESCE(ds.store_key, -1)                                       AS store_key,
    pr.province_key,
    s.carrier,
    s.tracking_number,
    s.status                                                         AS shipment_status,
    s.status = 'DELIVERED'                                           AS is_delivered,
    ROUND(date_diff('second', o.order_date, s.shipped_at)   / 3600.0,  2) AS hours_to_ship,
    ROUND(date_diff('second', s.shipped_at, s.delivered_at) / 86400.0, 2) AS days_in_transit,
    ROUND(date_diff('second', o.order_date, s.delivered_at) / 86400.0, 2) AS days_to_deliver
FROM raw.shipment            AS s
JOIN raw.sales_order         AS o  ON o.order_id     = s.order_id
JOIN raw.address             AS a  ON a.address_id   = o.shipping_address_id
JOIN dim_customer            AS dc ON dc.customer_id = o.customer_id
JOIN dim_channel             AS ch ON ch.channel_id  = o.channel_id
LEFT JOIN dim_store          AS ds ON ds.store_id    = o.store_id
JOIN dim_province            AS pr ON pr.province_id = a.province_id;


-- ---------------------------------------------------------------------
-- fact_web_sessions — GRANO: una visita a la web
-- ---------------------------------------------------------------------
-- Base de "Usuarios Activos". active_user_id identifica a la persona:
--   'C-<customer_id>' si inició sesión, 'S-<session_id>' si es anónimo
--   (cada sesión anónima cuenta como un usuario distinto, como pide la consigna).
-- Usuarios activos = COUNT(DISTINCT active_user_id) en el período.
-- Todas las sesiones son del canal ONLINE (la web).
CREATE TABLE fact_web_sessions (
    session_id         BIGINT  PRIMARY KEY,
    date_key           INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key       INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key        INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    source_key         INTEGER NOT NULL REFERENCES dim_traffic_source (source_key),
    device_key         INTEGER NOT NULL REFERENCES dim_device (device_key),
    active_user_id     VARCHAR NOT NULL,
    is_logged_in       BOOLEAN NOT NULL,
    duration_seconds   INTEGER                         -- NULL si la sesión no tiene fin registrado
);

INSERT INTO fact_web_sessions
SELECT
    w.session_id,
    CAST(strftime(w.started_at, '%Y%m%d') AS INTEGER)            AS date_key,
    COALESCE(dc.customer_key, -1)                                AS customer_key,
    (SELECT channel_key FROM dim_channel WHERE code = 'ONLINE')  AS channel_key,
    COALESCE(ts.source_key, -1)                                  AS source_key,
    COALESCE(dv.device_key, -1)                                  AS device_key,
    CASE WHEN w.customer_id IS NOT NULL
         THEN 'C-' || w.customer_id
         ELSE 'S-' || w.session_id
    END                                                          AS active_user_id,
    w.customer_id IS NOT NULL                                    AS is_logged_in,
    date_diff('second', w.started_at, w.ended_at)                AS duration_seconds
FROM raw.web_session          AS w
LEFT JOIN dim_customer        AS dc ON dc.customer_id = w.customer_id
LEFT JOIN dim_traffic_source  AS ts ON ts.source_code = w.source
LEFT JOIN dim_device          AS dv ON dv.device_code = w.device;


-- ---------------------------------------------------------------------
-- fact_nps — GRANO: una respuesta a la encuesta NPS
-- ---------------------------------------------------------------------
-- nps_points vale +100 (promotor 9-10), 0 (pasivo 7-8) o -100 (detractor 0-6).
-- Así el NPS de cualquier período o canal es simplemente AVG(nps_points),
-- que es lo mismo que (%promotores - %detractores) * 100.
CREATE TABLE fact_nps (
    nps_id         BIGINT  PRIMARY KEY,
    date_key       INTEGER NOT NULL REFERENCES dim_date (date_key),
    customer_key   INTEGER NOT NULL REFERENCES dim_customer (customer_key),
    channel_key    INTEGER NOT NULL REFERENCES dim_channel (channel_key),
    score          SMALLINT NOT NULL CHECK (score BETWEEN 0 AND 10),
    nps_category   VARCHAR NOT NULL,                  -- Promotor / Pasivo / Detractor
    is_promoter    INTEGER NOT NULL,                  -- 1 / 0
    is_passive     INTEGER NOT NULL,
    is_detractor   INTEGER NOT NULL,
    nps_points     INTEGER NOT NULL,                  -- +100 / 0 / -100
    has_comment    BOOLEAN NOT NULL,
    comment        VARCHAR
);

INSERT INTO fact_nps
SELECT
    n.nps_id,
    CAST(strftime(n.responded_at, '%Y%m%d') AS INTEGER)  AS date_key,
    COALESCE(dc.customer_key, -1)                        AS customer_key,
    ch.channel_key,
    n.score,
    CASE WHEN n.score >= 9 THEN 'Promotor'
         WHEN n.score >= 7 THEN 'Pasivo'
         ELSE 'Detractor' END                            AS nps_category,
    CAST(n.score >= 9 AS INTEGER)                        AS is_promoter,
    CAST(n.score BETWEEN 7 AND 8 AS INTEGER)             AS is_passive,
    CAST(n.score <= 6 AS INTEGER)                        AS is_detractor,
    CASE WHEN n.score >= 9 THEN 100
         WHEN n.score <= 6 THEN -100
         ELSE 0 END                                      AS nps_points,
    n.comment IS NOT NULL                                AS has_comment,
    n.comment
FROM raw.nps_response   AS n
LEFT JOIN dim_customer  AS dc ON dc.customer_id = n.customer_id
JOIN dim_channel        AS ch ON ch.channel_id  = n.channel_id;
