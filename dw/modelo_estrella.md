# Modelo estrella

Generado por `run_sql.py` a partir de las tablas de `warehouse.duckdb`.

```mermaid
erDiagram
    dim_address ||--o{ fact_orders : "billing_address_key"
    dim_address ||--o{ fact_orders : "shipping_address_key"
    dim_address ||--o{ fact_sales : "shipping_address_key"
    dim_address ||--o{ fact_shipments : "shipping_address_key"
    dim_carrier ||--o{ fact_shipments : "carrier_key"
    dim_channel ||--o{ fact_nps : "channel_key"
    dim_channel ||--o{ fact_orders : "channel_key"
    dim_channel ||--o{ fact_payments : "channel_key"
    dim_channel ||--o{ fact_sales : "channel_key"
    dim_channel ||--o{ fact_shipments : "channel_key"
    dim_channel ||--o{ fact_web_sessions : "channel_key"
    dim_customer ||--o{ fact_nps : "customer_key"
    dim_customer ||--o{ fact_orders : "customer_key"
    dim_customer ||--o{ fact_payments : "customer_key"
    dim_customer ||--o{ fact_sales : "customer_key"
    dim_customer ||--o{ fact_shipments : "customer_key"
    dim_customer ||--o{ fact_web_sessions : "customer_key"
    dim_date ||--o{ fact_nps : "date_key"
    dim_date ||--o{ fact_orders : "date_key"
    dim_date ||--o{ fact_payments : "order_date_key"
    dim_date ||--o{ fact_payments : "paid_date_key"
    dim_date ||--o{ fact_sales : "date_key"
    dim_date ||--o{ fact_shipments : "delivered_date_key"
    dim_date ||--o{ fact_shipments : "order_date_key"
    dim_date ||--o{ fact_shipments : "shipped_date_key"
    dim_date ||--o{ fact_web_sessions : "date_key"
    dim_device ||--o{ fact_web_sessions : "device_key"
    dim_nps_category ||--o{ fact_nps : "nps_category_key"
    dim_order_status ||--o{ fact_orders : "status_key"
    dim_order_status ||--o{ fact_sales : "status_key"
    dim_payment_method ||--o{ fact_orders : "payment_method_key"
    dim_payment_method ||--o{ fact_payments : "payment_method_key"
    dim_payment_status ||--o{ fact_payments : "payment_status_key"
    dim_product ||--o{ fact_sales : "product_key"
    dim_province ||--o{ fact_orders : "province_key"
    dim_province ||--o{ fact_sales : "province_key"
    dim_province ||--o{ fact_shipments : "province_key"
    dim_shipment_status ||--o{ fact_shipments : "shipment_status_key"
    dim_store ||--o{ fact_orders : "store_key"
    dim_store ||--o{ fact_sales : "store_key"
    dim_store ||--o{ fact_shipments : "store_key"
    dim_traffic_source ||--o{ fact_web_sessions : "source_key"
    dim_address {
        INTEGER address_key PK
        BIGINT address_id
        VARCHAR line1
        VARCHAR line2
        VARCHAR city
        VARCHAR postal_code
        VARCHAR country_code
        VARCHAR province_name
        VARCHAR province_code
        VARCHAR address_type
        TIMESTAMP created_at
    }
    dim_carrier {
        INTEGER carrier_key PK
        VARCHAR name
    }
    dim_channel {
        INTEGER channel_key PK
        INTEGER channel_id
        VARCHAR code
        VARCHAR name
    }
    dim_customer {
        INTEGER customer_key PK
        INTEGER customer_id
        VARCHAR email
        VARCHAR first_name
        VARCHAR last_name
        VARCHAR full_name
        VARCHAR phone
        VARCHAR status_code
        VARCHAR status
        TIMESTAMP created_at
        DATE created_date
        VARCHAR cohort_month
    }
    dim_date {
        INTEGER date_key PK
        DATE full_date
        INTEGER year
        INTEGER quarter
        VARCHAR year_quarter
        INTEGER month
        VARCHAR month_name
        VARCHAR year_month
        DATE month_start
        INTEGER iso_week
        INTEGER day_of_month
        INTEGER day_of_week
        VARCHAR day_name
        BOOLEAN is_weekend
    }
    dim_device {
        INTEGER device_key PK
        VARCHAR device_code
        VARCHAR description
    }
    dim_nps_category {
        INTEGER nps_category_key PK
        VARCHAR name
        SMALLINT min_score
        SMALLINT max_score
        INTEGER nps_points
    }
    dim_order_status {
        INTEGER status_key PK
        VARCHAR status_code
        VARCHAR description
        BOOLEAN is_sale
    }
    dim_payment_method {
        INTEGER payment_method_key PK
        VARCHAR method_code
        VARCHAR description
    }
    dim_payment_status {
        INTEGER payment_status_key PK
        VARCHAR status_code
        VARCHAR description
        BOOLEAN is_collected
    }
    dim_product {
        INTEGER product_key PK
        INTEGER product_id
        VARCHAR sku
        VARCHAR name
        VARCHAR category
        VARCHAR family
        DECIMAL list_price
        VARCHAR status
    }
    dim_province {
        INTEGER province_key PK
        INTEGER province_id
        VARCHAR name
        VARCHAR code
        VARCHAR iso_3166_2
    }
    dim_shipment_status {
        INTEGER shipment_status_key PK
        VARCHAR status_code
        VARCHAR description
        BOOLEAN is_delivered
    }
    dim_store {
        INTEGER store_key PK
        INTEGER store_id
        VARCHAR name
        VARCHAR address_line
        VARCHAR city
        VARCHAR province_name
        VARCHAR province_code
    }
    dim_traffic_source {
        INTEGER source_key PK
        VARCHAR source_code
        VARCHAR description
        VARCHAR marketing_type
    }
    fact_nps {
        BIGINT nps_id PK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER nps_category_key FK
        SMALLINT score
        INTEGER is_promoter
        INTEGER is_passive
        INTEGER is_detractor
        INTEGER nps_points
        BOOLEAN has_comment
        VARCHAR comment
    }
    fact_orders {
        BIGINT order_id PK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER store_key FK
        INTEGER province_key FK
        INTEGER shipping_address_key FK
        INTEGER billing_address_key FK
        INTEGER status_key FK
        INTEGER payment_method_key FK
        BOOLEAN is_sale
        BOOLEAN has_shipment
        INTEGER item_lines
        INTEGER units
        DECIMAL subtotal
        DECIMAL discount_amount
        DECIMAL tax_amount
        DECIMAL shipping_fee
        DECIMAL total_amount
    }
    fact_payments {
        BIGINT payment_id PK
        BIGINT order_id
        INTEGER order_date_key FK
        INTEGER paid_date_key FK
        INTEGER payment_method_key FK
        INTEGER payment_status_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        VARCHAR transaction_ref
        DECIMAL amount
        INTEGER minutes_to_pay
    }
    fact_sales {
        BIGINT order_item_id PK
        BIGINT order_id
        INTEGER date_key FK
        INTEGER product_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER store_key FK
        INTEGER province_key FK
        INTEGER shipping_address_key FK
        INTEGER status_key FK
        BOOLEAN is_sale
        INTEGER quantity
        DECIMAL unit_price
        DECIMAL gross_amount
        DECIMAL discount_amount
        DECIMAL line_total
        DECIMAL total_amount_allocated
    }
    fact_shipments {
        BIGINT shipment_id PK
        BIGINT order_id
        INTEGER order_date_key FK
        INTEGER shipped_date_key FK
        INTEGER delivered_date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER store_key FK
        INTEGER province_key FK
        INTEGER shipping_address_key FK
        INTEGER carrier_key FK
        INTEGER shipment_status_key FK
        VARCHAR tracking_number
        BOOLEAN is_delivered
        DECIMAL hours_to_ship
        DECIMAL days_in_transit
        DECIMAL days_to_deliver
    }
    fact_web_sessions {
        BIGINT session_id PK
        INTEGER date_key FK
        INTEGER customer_key FK
        INTEGER channel_key FK
        INTEGER source_key FK
        INTEGER device_key FK
        VARCHAR active_user_id
        BOOLEAN is_logged_in
        INTEGER duration_seconds
    }
    mart_calendario_mes {
        VARCHAR year_month PK
        DATE month_start
        INTEGER year
        INTEGER month
        VARCHAR year_quarter
        VARCHAR month_label
        VARCHAR month_long
    }
    mart_entregas_mes {
        VARCHAR year_month PK
        VARCHAR year_quarter
        INTEGER channel_key PK
        VARCHAR channel_name
        INTEGER province_key PK
        VARCHAR province_code
        VARCHAR province_name
        INTEGER envios_entregados
        DECIMAL suma_dias_entrega
    }
    mart_entregas_producto_mes {
        VARCHAR year_month PK
        VARCHAR year_quarter
        INTEGER channel_key PK
        VARCHAR channel_name
        INTEGER province_key PK
        VARCHAR province_code
        VARCHAR province_name
        INTEGER product_key PK
        VARCHAR product_name
        INTEGER envios_entregados
        DECIMAL suma_dias_entrega
    }
    mart_nps_mes {
        VARCHAR year_month PK
        VARCHAR year_quarter
        INTEGER channel_key PK
        VARCHAR channel_name
        INTEGER respuestas
        INTEGER promotores
        INTEGER pasivos
        INTEGER detractores
        INTEGER puntos_nps
    }
    mart_ranking_producto_mes {
        VARCHAR year_month PK
        INTEGER channel_key PK
        INTEGER province_key PK
        INTEGER product_key PK
        VARCHAR product_name
        INTEGER puesto
        DECIMAL ventas_netas
        INTEGER unidades
        DECIMAL ventas_netas_mes_anterior
        DECIMAL variacion_pct
    }
    mart_usuarios_activos_rango {
        VARCHAR desde_mes PK
        VARCHAR hasta_mes PK
        INTEGER meses
        INTEGER usuarios_activos
        INTEGER usuarios_logueados
        INTEGER sesiones
    }
    mart_ventas_mes {
        VARCHAR year_month PK
        VARCHAR year_quarter
        INTEGER channel_key PK
        VARCHAR channel_name
        INTEGER province_key PK
        VARCHAR province_code
        VARCHAR province_name
        DECIMAL ventas
        INTEGER pedidos
    }
    mart_ventas_producto_mes {
        VARCHAR year_month PK
        VARCHAR year_quarter
        INTEGER channel_key PK
        VARCHAR channel_name
        INTEGER province_key PK
        VARCHAR province_code
        VARCHAR province_name
        INTEGER product_key PK
        VARCHAR product_name
        DECIMAL ventas
        INTEGER pedidos
        DECIMAL ventas_netas
        INTEGER unidades
    }
```
