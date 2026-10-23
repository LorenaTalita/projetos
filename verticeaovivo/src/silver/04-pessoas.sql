-- 04-pessoas.sql — Colaboradores e apontamentos
-- Lakeflow Spark Declarative Pipelines · schema padrão = silver

-- ============================================================
-- Colaboradores (deduplica 3 registros em CAIXA ALTA)
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW colaboradores
COMMENT 'Cadastro de colaboradores da Vértice. Deduplica COL0102, COL0257 e COL0433 (mantém o registro com papel em minúsculas).'
AS
WITH ranqueados AS (
    SELECT
        *,
        -- Sujeira #16: 3 pessoas cadastradas duas vezes (nome/papel em CAIXA ALTA).
        -- Manter o registro com papel em minúsculas (row_number ordena: minúsculas antes de MAIÚSCULAS).
        ROW_NUMBER() OVER (
            PARTITION BY colaborador_id
            ORDER BY
                CASE WHEN papel = LOWER(papel) THEN 0 ELSE 1 END
        ) AS rn
    FROM lakehouse_vertice.bronze.colaboradores
)
SELECT
    colaborador_id,
    nome,
    papel,
    senioridade,
    CAST(custo_hora AS DOUBLE) AS custo_hora,
    TRY_TO_DATE(data_admissao) AS data_admissao,
    TRY_TO_DATE(data_desligamento) AS data_desligamento
FROM ranqueados
WHERE rn = 1
;

-- ============================================================
-- Apontamentos (timesheet semanal)
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW apontamentos
COMMENT 'Timesheet semanal: horas disponíveis e apontadas por colaborador e projeto. Semana = sexta (semana_inicio + 4 dias).'
AS
SELECT
    colaborador_id,
    projeto_id,
    CAST(semana_inicio AS DATE) AS semana_inicio,
    -- semana = sexta: semana_inicio + 4 dias
    date_add(CAST(semana_inicio AS DATE), 4) AS semana,
    CAST(horas_disponiveis AS DOUBLE) AS horas_disponiveis,
    CAST(horas_apontadas AS DOUBLE) AS horas_apontadas
FROM lakehouse_vertice.bronze.apontamentos
