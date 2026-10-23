-- 03-status-e-custos.sql — Status semanal e custos
-- Lakeflow Spark Declarative Pipelines · schema padrão = silver

-- ============================================================
-- Status semanal
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW status_semanal (
    CONSTRAINT farol_valido EXPECT (farol IN ('verde', 'amarelo', 'vermelho')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Status semanal dos projetos: farol do gerente, % concluído e texto livre. Uma linha por projeto por sexta.'
AS
SELECT
    projeto_id,
    CAST(data_status AS DATE) AS data_status,
    gerente,
    CAST(pct_concluido AS INT) AS pct_concluido,

    -- Sujeira #17: farol em minúsculas
    LOWER(TRIM(farol)) AS farol,

    texto_status,

    -- Sujeira #18: status vazio — NÃO descartar, sinalizar
    CASE
        WHEN TRIM(COALESCE(texto_status, '')) IN ('', 'N/A', 'ver ata da reunião')
        THEN true ELSE false
    END AS status_vazio
FROM lakehouse_vertice.bronze.status_semanal
;

-- ============================================================
-- Custos
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW custos
COMMENT 'Lançamentos de custo real por projeto: pessoal, consultoria, cloud, licenças, despesas. Estornos sinalizados.'
AS
SELECT
    lancamento_id,
    projeto_id,
    CAST(data AS DATE) AS data,
    categoria,
    descricao,
    centro_custo,

    -- Sujeira #13: vírgula decimal (671 registros) — replace ANTES do CAST, nunca try_cast
    CAST(REPLACE(valor, ',', '.') AS DOUBLE) AS valor,

    -- Sujeira #14: estorno (negativo) fica, com flag
    CASE
        WHEN CAST(REPLACE(valor, ',', '.') AS DOUBLE) < 0
        THEN true ELSE false
    END AS estorno,

    -- semana = sexta da semana: date_add(date_trunc('WEEK', data), 4)
    date_add(date_trunc('WEEK', CAST(data AS DATE)), 4) AS semana
FROM lakehouse_vertice.bronze.custos
