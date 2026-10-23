-- 05-fornecedores.sql — Entregas de fornecedores
-- Lakeflow Spark Declarative Pipelines · schema padrão = silver

CREATE OR REFRESH MATERIALIZED VIEW entregas_fornecedor
COMMENT 'Entregas das consultorias contratadas: prometido × entregue. CodeForge normalizada (4 grafias). Inclui prazos, atraso e flags em_aberto / em_atraso (hoje = 16/10/2026).'
AS
WITH tipada AS (
    SELECT
        entrega_id,
        projeto_id,
        fornecedor,
        item,
        CAST(valor AS DECIMAL(18,2))      AS valor,
        CAST(data_pedido    AS DATE)      AS data_pedido,
        CAST(data_prometida AS DATE)      AS data_prometida,
        -- data_entrega vazia = em aberto (não é sujeira)
        CAST(data_entrega   AS DATE)      AS data_entrega,
        CAST(prazo_contratado_dias AS INT) AS prazo_contratado_dias,
        status
    FROM lakehouse_vertice.bronze.entregas_fornecedor
)
SELECT
    entrega_id,
    projeto_id,

    -- Sujeira #15: CodeForge com 4 grafias → 'CodeForge Consultoria Ltda' (CLAUDE.md)
    CASE
        WHEN REPLACE(LOWER(fornecedor), ' ', '') LIKE '%codeforge%'
        THEN 'CodeForge Consultoria Ltda'
        ELSE fornecedor
    END AS fornecedor,
    fornecedor AS fornecedor_como_veio,

    item,
    valor,
    status,
    data_pedido,
    data_prometida,
    data_entrega,
    prazo_contratado_dias,

    -- Prazos calculados a partir do pedido
    DATEDIFF(data_prometida, data_pedido) AS prazo_prometido_dias,
    DATEDIFF(data_entrega,   data_pedido) AS prazo_real_dias,          -- nulo se em aberto
    DATEDIFF(data_entrega,   data_prometida) AS dias_de_atraso_na_entrega,  -- nulo se em aberto

    -- Flags
    data_entrega IS NULL AS em_aberto,
    (data_entrega IS NULL AND data_prometida < DATE'2026-10-16') AS em_atraso
FROM tipada
