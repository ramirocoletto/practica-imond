-- =====================================================================
-- 01_dimensiones.sql — Tablas de DIMENSIONES del modelo estrella
-- =====================================================================
-- Modelo dimensional (Kimball) para EcoBottle AR.
--
-- Convenciones:
--   * <x>_key  = clave SUBROGADA (propia del data warehouse). Es la PK de
--                cada dimensión y la que usan las tablas de hechos.
--   * <x>_id   = clave NATURAL (el ID del sistema de origen, raw.<tabla>).
--   * Clave -1 = miembro "Desconocido / No aplica". Toda dimensión que un
--                hecho puede no tener (cliente anónimo, pedido sin tienda,
--                fecha de un evento que todavía no ocurrió, código nuevo que
--                aparezca en el origen) tiene esta fila, así ninguna FK de
--                los hechos queda en NULL.
--   * dim_date usa una clave "inteligente" AAAAMMDD (ej. 20240131), que es
--     la práctica habitual para la dimensión fecha.
--   * Los catálogos (estados, medios de pago, orígenes, correos...) se cargan
--     con los valores DISTINTOS que hay en raw/, no escritos a mano: si
--     mañana aparece un código nuevo, entra solo a la dimensión.
--
-- Dimensiones:
--   dim_date             calendario día a día (+ fila -1 "Sin fecha")
--   dim_channel          canal de venta (ONLINE / OFFLINE)
--   dim_province         provincia (BA, CBA, SF, MZA)
--   dim_address          dirección (calle, ciudad, CP, provincia) (+ -1)
--   dim_product          producto con su categoría y familia aplanadas
--   dim_store            tienda física (+ fila -1 "Online / sin tienda")
--   dim_customer         cliente (+ fila -1 "Anónimo / desconocido")
--   dim_order_status     estado del pedido y si cuenta como venta (+ -1)
--   dim_payment_method   medio de pago (+ -1)
--   dim_payment_status   estado del pago (+ -1)
--   dim_shipment_status  estado del envío (+ -1)
--   dim_carrier          empresa de correo (+ -1)
--   dim_traffic_source   origen de la visita web (+ -1)
--   dim_device           dispositivo de la visita web (+ -1)
--   dim_nps_category     categoría NPS: Promotor / Pasivo / Detractor
-- =====================================================================


-- ---------------------------------------------------------------------
-- dim_date — una fila por día
-- ---------------------------------------------------------------------
-- Cubre todo el período de los datos: el primer pedido es del 01/01/2024 y
-- la foto del sistema se tomó el 30/09/2025 a las 23:59:59.
-- Fila -1 "Sin fecha": para eventos que no ocurrieron (pago no cobrado,
-- envío no despachado / no entregado).
CREATE TABLE dim_date (
    date_key        INTEGER PRIMARY KEY,   -- AAAAMMDD (-1 = sin fecha)
    full_date       DATE,                  -- NULL solo en la fila -1
    year            INTEGER,
    quarter         INTEGER,               -- 1..4
    year_quarter    VARCHAR NOT NULL,      -- 2025-T3 ('Sin fecha' en la fila -1)
    month           INTEGER,               -- 1..12
    month_name      VARCHAR NOT NULL,      -- Enero..Diciembre
    year_month      VARCHAR NOT NULL,      -- 2025-09
    month_start     DATE,                  -- primer día del mes (= DATE_TRUNC('month', ...))
    iso_week        INTEGER,
    day_of_month    INTEGER,
    day_of_week     INTEGER,               -- 1 = lunes ... 7 = domingo (ISO)
    day_name        VARCHAR NOT NULL,      -- Lunes..Domingo
    is_weekend      BOOLEAN
);

INSERT INTO dim_date VALUES
    (-1, NULL, NULL, NULL, 'Sin fecha', NULL, 'Sin fecha', 'Sin fecha', NULL, NULL, NULL, NULL, 'Sin fecha', NULL);

INSERT INTO dim_date
SELECT
    CAST(strftime(d, '%Y%m%d') AS INTEGER)                                  AS date_key,
    d                                                                       AS full_date,
    year(d)                                                                 AS year,
    quarter(d)                                                              AS quarter,
    year(d) || '-T' || quarter(d)                                           AS year_quarter,
    month(d)                                                                AS month,
    ['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto',
     'Septiembre','Octubre','Noviembre','Diciembre'][month(d)]              AS month_name,
    strftime(d, '%Y-%m')                                                    AS year_month,
    CAST(DATE_TRUNC('month', d) AS DATE)                                    AS month_start,
    weekofyear(d)                                                           AS iso_week,
    day(d)                                                                  AS day_of_month,
    isodow(d)                                                               AS day_of_week,
    ['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'][isodow(d)] AS day_name,
    isodow(d) IN (6, 7)                                                     AS is_weekend
FROM (
    SELECT CAST(range AS DATE) AS d
    FROM range(DATE '2024-01-01', DATE '2025-10-01', INTERVAL 1 DAY)
)
ORDER BY 1;


-- ---------------------------------------------------------------------
-- dim_channel — canal de venta
-- ---------------------------------------------------------------------
CREATE TABLE dim_channel (
    channel_key  INTEGER PRIMARY KEY,
    channel_id   INTEGER NOT NULL UNIQUE,
    code         VARCHAR NOT NULL UNIQUE,   -- ONLINE / OFFLINE
    name         VARCHAR NOT NULL
);

INSERT INTO dim_channel
SELECT
    ROW_NUMBER() OVER (ORDER BY channel_id) AS channel_key,
    channel_id,
    code,
    name
FROM raw.channel
ORDER BY 1;


-- ---------------------------------------------------------------------
-- dim_province — provincia (para análisis geográfico)
-- ---------------------------------------------------------------------
CREATE TABLE dim_province (
    province_key  INTEGER PRIMARY KEY,
    province_id   INTEGER NOT NULL UNIQUE,
    name          VARCHAR NOT NULL,
    code          VARCHAR NOT NULL UNIQUE,  -- BA / CBA / SF / MZA
    iso_3166_2    VARCHAR                   -- código ISO para mapas (AR-B, AR-X, ...)
);

INSERT INTO dim_province
SELECT
    ROW_NUMBER() OVER (ORDER BY province_id) AS province_key,
    province_id,
    name,
    code,
    CASE code
        WHEN 'BA'  THEN 'AR-B'
        WHEN 'CBA' THEN 'AR-X'
        WHEN 'SF'  THEN 'AR-S'
        WHEN 'MZA' THEN 'AR-M'
    END AS iso_3166_2
FROM raw.province
ORDER BY 1;


-- ---------------------------------------------------------------------
-- dim_address — dirección (geografía al nivel más fino)
-- ---------------------------------------------------------------------
-- Conserva ciudad y código postal, que no entran en ninguna otra dimensión.
-- La provincia se aplana (nombre y código) para no tener que encadenar
-- dimensiones (copo de nieve). address_type distingue las direcciones de
-- tiendas de las de clientes.
-- Fila -1: pedidos sin dirección de facturación (billing_address_id NULL).
CREATE TABLE dim_address (
    address_key     INTEGER PRIMARY KEY,
    address_id      BIGINT,                  -- NULL en la fila -1
    line1           VARCHAR,
    line2           VARCHAR,
    city            VARCHAR NOT NULL,
    postal_code     VARCHAR,
    country_code    VARCHAR,
    province_name   VARCHAR NOT NULL,
    province_code   VARCHAR NOT NULL,
    address_type    VARCHAR NOT NULL,        -- Tienda / Cliente / Desconocida
    created_at      TIMESTAMP
);

INSERT INTO dim_address VALUES
    (-1, NULL, NULL, NULL, 'Desconocida', NULL, NULL, 'Desconocida', '?', 'Desconocida', NULL);

INSERT INTO dim_address
SELECT
    ROW_NUMBER() OVER (ORDER BY a.address_id)       AS address_key,
    a.address_id,
    a.line1,
    a.line2,
    a.city,
    CAST(a.postal_code AS VARCHAR)                  AS postal_code,
    a.country_code,
    p.name                                          AS province_name,
    p.code                                          AS province_code,
    CASE WHEN a.address_id IN (SELECT address_id FROM raw.store)
         THEN 'Tienda' ELSE 'Cliente' END           AS address_type,
    a.created_at
FROM raw.address  AS a
JOIN raw.province AS p ON p.province_id = a.province_id
ORDER BY 1;


-- ---------------------------------------------------------------------
-- dim_product — producto (ejemplo resuelto del profesor)
-- ---------------------------------------------------------------------
-- En raw/ la categoría está en otra tabla y tiene jerarquía
-- (Bottles -> Classic / Sport). En la dimensión la "aplanamos":
-- cada producto queda en una sola fila con su categoría y su familia.
CREATE TABLE dim_product (
    product_key INTEGER PRIMARY KEY,
    product_id  INTEGER NOT NULL,
    sku         VARCHAR NOT NULL,
    name        VARCHAR NOT NULL,
    category    VARCHAR,             -- Classic / Sport
    family      VARCHAR,             -- Bottles
    list_price  DECIMAL(12, 2),
    status      VARCHAR              -- Activo / Inactivo
);

INSERT INTO dim_product
SELECT
    ROW_NUMBER() OVER (ORDER BY p.product_id) AS product_key,
    p.product_id,
    p.sku,
    p.name,
    c.name AS category,
    f.name AS family,
    p.list_price,
    CASE p.status WHEN 'A' THEN 'Activo' ELSE 'Inactivo' END AS status
FROM raw.product AS p
LEFT JOIN raw.product_category AS c ON c.category_id = p.category_id   -- categoría
LEFT JOIN raw.product_category AS f ON f.category_id = c.parent_id     -- familia (categoría padre)
ORDER BY 1;


-- ---------------------------------------------------------------------
-- dim_store — tienda física
-- ---------------------------------------------------------------------
-- Se "aplana" la dirección de la tienda (ciudad y provincia).
-- Fila -1: pedidos ONLINE, que no tienen tienda (store_id NULL en origen).
CREATE TABLE dim_store (
    store_key      INTEGER PRIMARY KEY,
    store_id       INTEGER,              -- NULL en la fila -1
    name           VARCHAR NOT NULL,
    address_line   VARCHAR,
    city           VARCHAR,
    province_name  VARCHAR,
    province_code  VARCHAR
);

INSERT INTO dim_store VALUES (-1, NULL, 'Online (sin tienda)', NULL, NULL, NULL, NULL);

INSERT INTO dim_store
SELECT
    ROW_NUMBER() OVER (ORDER BY s.store_id) AS store_key,
    s.store_id,
    s.name,
    a.line1      AS address_line,
    a.city,
    p.name       AS province_name,
    p.code       AS province_code
FROM raw.store    AS s
JOIN raw.address  AS a ON a.address_id  = s.address_id
JOIN raw.province AS p ON p.province_id = a.province_id
ORDER BY 1;


-- ---------------------------------------------------------------------
-- dim_customer — cliente
-- ---------------------------------------------------------------------
-- Fila -1: respuestas NPS anónimas y sesiones web sin login.
CREATE TABLE dim_customer (
    customer_key     INTEGER PRIMARY KEY,
    customer_id      INTEGER,            -- NULL en la fila -1
    email            VARCHAR,
    first_name       VARCHAR,
    last_name        VARCHAR,
    full_name        VARCHAR NOT NULL,
    phone            VARCHAR,
    status_code      VARCHAR NOT NULL,   -- A / I (o '?' en la fila -1)
    status           VARCHAR NOT NULL,   -- Activo / Inactivo (baja) / Desconocido
    created_at       TIMESTAMP,
    created_date     DATE,
    cohort_month     VARCHAR             -- mes de alta AAAA-MM (para cohortes)
);

INSERT INTO dim_customer VALUES
    (-1, NULL, NULL, NULL, NULL, 'Anónimo / desconocido', NULL, '?', 'Desconocido', NULL, NULL, NULL);

INSERT INTO dim_customer
SELECT
    ROW_NUMBER() OVER (ORDER BY customer_id) AS customer_key,
    customer_id,
    email,
    first_name,
    last_name,
    first_name || ' ' || last_name           AS full_name,
    phone,
    status                                   AS status_code,
    CASE status WHEN 'A' THEN 'Activo' ELSE 'Inactivo (baja)' END AS status,
    created_at,
    CAST(created_at AS DATE)                 AS created_date,
    strftime(created_at, '%Y-%m')            AS cohort_month
FROM raw.customer
ORDER BY 1;


-- ---------------------------------------------------------------------
-- dim_order_status — estado del pedido
-- ---------------------------------------------------------------------
-- Documenta la regla de negocio de qué cuenta como venta: solo PAID y
-- FULFILLED (según la consigna). Un estado desconocido NO cuenta como venta.
CREATE TABLE dim_order_status (
    status_key    INTEGER PRIMARY KEY,
    status_code   VARCHAR NOT NULL UNIQUE,
    description   VARCHAR NOT NULL,
    is_sale       BOOLEAN NOT NULL
);

INSERT INTO dim_order_status VALUES (-1, 'UNKNOWN', 'Estado desconocido', FALSE);

INSERT INTO dim_order_status
SELECT
    ROW_NUMBER() OVER (ORDER BY status) AS status_key,
    status                              AS status_code,
    CASE status
        WHEN 'CREATED'   THEN 'Creado, todavía sin pagar'
        WHEN 'PAID'      THEN 'Pagado, pendiente de entrega'
        WHEN 'FULFILLED' THEN 'Entregado / comprado en tienda'
        WHEN 'CANCELLED' THEN 'Cancelado'
        WHEN 'REFUNDED'  THEN 'Entregado y luego reembolsado'
        ELSE status
    END                                 AS description,
    status IN ('PAID', 'FULFILLED')     AS is_sale
FROM (SELECT DISTINCT status FROM raw.sales_order WHERE status IS NOT NULL)
ORDER BY 1;


-- ---------------------------------------------------------------------
-- dim_payment_method — medio de pago
-- ---------------------------------------------------------------------
CREATE TABLE dim_payment_method (
    payment_method_key  INTEGER PRIMARY KEY,
    method_code         VARCHAR NOT NULL UNIQUE,
    description         VARCHAR NOT NULL
);

INSERT INTO dim_payment_method VALUES (-1, 'UNKNOWN', 'Sin dato');

INSERT INTO dim_payment_method
SELECT
    ROW_NUMBER() OVER (ORDER BY method) AS payment_method_key,
    method                              AS method_code,
    CASE method
        WHEN 'CARD'     THEN 'Tarjeta'
        WHEN 'GATEWAY'  THEN 'Mercado Pago (pasarela)'
        WHEN 'CASH'     THEN 'Efectivo'
        WHEN 'TRANSFER' THEN 'Transferencia'
        ELSE method
    END                                 AS description
FROM (SELECT DISTINCT method FROM raw.payment WHERE method IS NOT NULL)
ORDER BY 1;


-- ---------------------------------------------------------------------
-- dim_payment_status — estado del pago
-- ---------------------------------------------------------------------
CREATE TABLE dim_payment_status (
    payment_status_key  INTEGER PRIMARY KEY,
    status_code         VARCHAR NOT NULL UNIQUE,
    description         VARCHAR NOT NULL,
    is_collected        BOOLEAN NOT NULL       -- el dinero ingresó (PAID)
);

INSERT INTO dim_payment_status VALUES (-1, 'UNKNOWN', 'Sin dato', FALSE);

INSERT INTO dim_payment_status
SELECT
    ROW_NUMBER() OVER (ORDER BY status) AS payment_status_key,
    status                              AS status_code,
    CASE status
        WHEN 'PENDING'  THEN 'Pendiente'
        WHEN 'PAID'     THEN 'Cobrado'
        WHEN 'FAILED'   THEN 'Rechazado'
        WHEN 'REFUNDED' THEN 'Reembolsado'
        ELSE status
    END                                 AS description,
    status = 'PAID'                     AS is_collected
FROM (SELECT DISTINCT status FROM raw.payment WHERE status IS NOT NULL)
ORDER BY 1;


-- ---------------------------------------------------------------------
-- dim_shipment_status — estado del envío
-- ---------------------------------------------------------------------
CREATE TABLE dim_shipment_status (
    shipment_status_key  INTEGER PRIMARY KEY,
    status_code          VARCHAR NOT NULL UNIQUE,
    description          VARCHAR NOT NULL,
    is_delivered         BOOLEAN NOT NULL
);

INSERT INTO dim_shipment_status VALUES (-1, 'UNKNOWN', 'Sin dato', FALSE);

INSERT INTO dim_shipment_status
SELECT
    ROW_NUMBER() OVER (ORDER BY status) AS shipment_status_key,
    status                              AS status_code,
    CASE status
        WHEN 'READY'     THEN 'En preparación'
        WHEN 'SHIPPED'   THEN 'En viaje'
        WHEN 'DELIVERED' THEN 'Entregado'
        WHEN 'CANCELLED' THEN 'Cancelado (no salió)'
        ELSE status
    END                                 AS description,
    status = 'DELIVERED'                AS is_delivered
FROM (SELECT DISTINCT status FROM raw.shipment WHERE status IS NOT NULL)
ORDER BY 1;


-- ---------------------------------------------------------------------
-- dim_carrier — empresa de correo
-- ---------------------------------------------------------------------
CREATE TABLE dim_carrier (
    carrier_key   INTEGER PRIMARY KEY,
    name          VARCHAR NOT NULL UNIQUE
);

INSERT INTO dim_carrier VALUES (-1, 'Sin dato');

INSERT INTO dim_carrier
SELECT
    ROW_NUMBER() OVER (ORDER BY carrier) AS carrier_key,
    carrier                              AS name
FROM (SELECT DISTINCT carrier FROM raw.shipment WHERE carrier IS NOT NULL)
ORDER BY 1;


-- ---------------------------------------------------------------------
-- dim_traffic_source — origen de la visita web
-- ---------------------------------------------------------------------
-- marketing_type agrupa los orígenes según quién "paga" el tráfico
-- (clasificación propia, ver README > Supuestos):
--   Pago   = publicidad (ads)         Propio = canales de la marca (direct, referral/newsletter)
--   Ganado = buscadores (organic)
CREATE TABLE dim_traffic_source (
    source_key      INTEGER PRIMARY KEY,
    source_code     VARCHAR NOT NULL UNIQUE,
    description     VARCHAR NOT NULL,
    marketing_type  VARCHAR NOT NULL      -- Pago / Propio / Ganado / Sin dato
);

INSERT INTO dim_traffic_source VALUES (-1, 'unknown', 'Sin dato', 'Sin dato');

INSERT INTO dim_traffic_source
SELECT
    ROW_NUMBER() OVER (ORDER BY source) AS source_key,
    source                              AS source_code,
    CASE source
        WHEN 'ads'      THEN 'Publicidad en redes'
        WHEN 'direct'   THEN 'Directo / newsletter'
        WHEN 'referral' THEN 'Referidos / newsletter'
        WHEN 'organic'  THEN 'Buscadores (orgánico)'
        ELSE source
    END                                 AS description,
    CASE source
        WHEN 'ads'      THEN 'Pago'
        WHEN 'direct'   THEN 'Propio'
        WHEN 'referral' THEN 'Propio'
        WHEN 'organic'  THEN 'Ganado'
        ELSE 'Sin dato'
    END                                 AS marketing_type
FROM (SELECT DISTINCT source FROM raw.web_session WHERE source IS NOT NULL)
ORDER BY 1;


-- ---------------------------------------------------------------------
-- dim_device — dispositivo de la visita web
-- ---------------------------------------------------------------------
CREATE TABLE dim_device (
    device_key   INTEGER PRIMARY KEY,
    device_code  VARCHAR NOT NULL UNIQUE,
    description  VARCHAR NOT NULL
);

INSERT INTO dim_device VALUES (-1, 'unknown', 'Sin dato');

INSERT INTO dim_device
SELECT
    ROW_NUMBER() OVER (ORDER BY device) AS device_key,
    device                              AS device_code,
    CASE device
        WHEN 'mobile'  THEN 'Celular'
        WHEN 'desktop' THEN 'Computadora'
        WHEN 'tablet'  THEN 'Tablet'
        ELSE device
    END                                 AS description
FROM (SELECT DISTINCT device FROM raw.web_session WHERE device IS NOT NULL)
ORDER BY 1;


-- ---------------------------------------------------------------------
-- dim_nps_category — categoría de la respuesta NPS
-- ---------------------------------------------------------------------
-- Rangos fijados por la definición del NPS (consigna): 9-10 promotor,
-- 7-8 pasivo, 0-6 detractor. nps_points es el aporte de cada respuesta:
-- NPS = SUM(nps_points) / cantidad de respuestas.
CREATE TABLE dim_nps_category (
    nps_category_key  INTEGER PRIMARY KEY,
    name              VARCHAR NOT NULL UNIQUE,
    min_score         SMALLINT NOT NULL,
    max_score         SMALLINT NOT NULL,
    nps_points        INTEGER NOT NULL        -- +100 / 0 / -100
);

INSERT INTO dim_nps_category VALUES
    (1, 'Detractor', 0, 6, -100),
    (2, 'Pasivo',    7, 8,    0),
    (3, 'Promotor',  9, 10, 100);
