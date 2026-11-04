-- =====================================================================
-- 01_dimensiones.sql — Tablas de DIMENSIONES del modelo estrella
-- =====================================================================
-- Modelo dimensional (Kimball) para EcoBottle AR.
--
-- Convenciones:
--   * <x>_key  = clave SUBROGADA (propia del data warehouse). Es la PK de
--                cada dimensión y la que usan las tablas de hechos.
--   * <x>_id   = clave NATURAL (el ID del sistema de origen, raw.<tabla>).
--   * Clave -1 = fila "Desconocido / No aplica". Se usa cuando el dato no
--                existe en el origen (NPS anónimo, sesión sin login, pedido
--                online sin tienda) para no dejar FKs en NULL.
--   * dim_date usa una clave "inteligente" AAAAMMDD (ej. 20240131), que es
--     la práctica habitual para la dimensión fecha.
--
-- Dimensiones:
--   dim_date            calendario día a día (2024-01-01 a 2025-09-30)
--   dim_channel         canal de venta (ONLINE / OFFLINE)
--   dim_province        provincia (BA, CBA, SF, MZA)
--   dim_product         producto con su categoría y familia aplanadas
--   dim_store           tienda física (+ fila -1 "Online / sin tienda")
--   dim_customer        cliente (+ fila -1 "Anónimo / desconocido")
--   dim_order_status    estado del pedido y si cuenta como venta
--   dim_payment_method  medio de pago
--   dim_traffic_source  origen de la visita web (ads, direct, ...)
--   dim_device          dispositivo de la visita web
-- =====================================================================


-- ---------------------------------------------------------------------
-- dim_date — una fila por día
-- ---------------------------------------------------------------------
-- Cubre todo el período de los datos: el primer pedido es del 01/01/2024 y
-- la foto del sistema se tomó el 30/09/2025 a las 23:59:59.
CREATE TABLE dim_date (
    date_key        INTEGER PRIMARY KEY,   -- AAAAMMDD
    full_date       DATE    NOT NULL,
    year            INTEGER NOT NULL,
    quarter         INTEGER NOT NULL,      -- 1..4
    year_quarter    VARCHAR NOT NULL,      -- 2025-T3
    month           INTEGER NOT NULL,      -- 1..12
    month_name      VARCHAR NOT NULL,      -- Enero..Diciembre
    year_month      VARCHAR NOT NULL,      -- 2025-09
    month_start     DATE    NOT NULL,      -- primer día del mes (para DATE_TRUNC)
    iso_week        INTEGER NOT NULL,
    day_of_month    INTEGER NOT NULL,
    day_of_week     INTEGER NOT NULL,      -- 1 = lunes ... 7 = domingo (ISO)
    day_name        VARCHAR NOT NULL,      -- Lunes..Domingo
    is_weekend      BOOLEAN NOT NULL
);

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
);


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
FROM raw.channel;


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
FROM raw.province;


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
LEFT JOIN raw.product_category AS f ON f.category_id = c.parent_id;    -- familia (categoría padre)


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
JOIN raw.province AS p ON p.province_id = a.province_id;


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
FROM raw.customer;


-- ---------------------------------------------------------------------
-- dim_order_status — estado del pedido
-- ---------------------------------------------------------------------
-- Dimensión chica que deja documentada la regla de negocio de qué cuenta
-- como venta: solo PAID y FULFILLED (según la consigna y el README).
CREATE TABLE dim_order_status (
    status_key    INTEGER PRIMARY KEY,
    status_code   VARCHAR NOT NULL UNIQUE,
    description   VARCHAR NOT NULL,
    is_sale       BOOLEAN NOT NULL
);

INSERT INTO dim_order_status VALUES
    (1, 'CREATED',   'Creado, todavía sin pagar',            FALSE),
    (2, 'PAID',      'Pagado, pendiente de entrega',         TRUE),
    (3, 'FULFILLED', 'Entregado / comprado en tienda',       TRUE),
    (4, 'CANCELLED', 'Cancelado',                            FALSE),
    (5, 'REFUNDED',  'Entregado y luego reembolsado',        FALSE);


-- ---------------------------------------------------------------------
-- dim_payment_method — medio de pago
-- ---------------------------------------------------------------------
CREATE TABLE dim_payment_method (
    payment_method_key  INTEGER PRIMARY KEY,
    method_code         VARCHAR NOT NULL UNIQUE,
    description         VARCHAR NOT NULL
);

INSERT INTO dim_payment_method VALUES
    (1, 'CARD',     'Tarjeta'),
    (2, 'GATEWAY',  'Mercado Pago (pasarela)'),
    (3, 'CASH',     'Efectivo'),
    (4, 'TRANSFER', 'Transferencia');


-- ---------------------------------------------------------------------
-- dim_traffic_source — origen de la visita web
-- ---------------------------------------------------------------------
-- Agrupa los orígenes según la acción de marketing que los genera.
CREATE TABLE dim_traffic_source (
    source_key      INTEGER PRIMARY KEY,
    source_code     VARCHAR NOT NULL UNIQUE,
    description     VARCHAR NOT NULL,
    marketing_type  VARCHAR NOT NULL      -- Pago / Propio / Ganado
);

INSERT INTO dim_traffic_source VALUES
    (-1, 'unknown',  'Sin dato',                        'Sin dato'),
    ( 1, 'ads',      'Publicidad en redes',             'Pago'),
    ( 2, 'direct',   'Directo / newsletter',            'Propio'),
    ( 3, 'referral', 'Referidos / newsletter',          'Propio'),
    ( 4, 'organic',  'Buscadores (orgánico)',           'Ganado');


-- ---------------------------------------------------------------------
-- dim_device — dispositivo de la visita web
-- ---------------------------------------------------------------------
CREATE TABLE dim_device (
    device_key   INTEGER PRIMARY KEY,
    device_code  VARCHAR NOT NULL UNIQUE,
    description  VARCHAR NOT NULL
);

INSERT INTO dim_device
SELECT -1, 'unknown', 'Sin dato'
UNION ALL
SELECT
    ROW_NUMBER() OVER (ORDER BY device) AS device_key,
    device                              AS device_code,
    CASE device
        WHEN 'mobile'  THEN 'Celular'
        WHEN 'desktop' THEN 'Computadora'
        WHEN 'tablet'  THEN 'Tablet'
        ELSE device
    END                                 AS description
FROM (SELECT DISTINCT device FROM raw.web_session WHERE device IS NOT NULL);
