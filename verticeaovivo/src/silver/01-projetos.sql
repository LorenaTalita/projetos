-- 01-projetos.sql — Cadastro do PMO (de-para da integração)
-- Lakeflow Spark Declarative Pipelines · schema padrão = silver

CREATE OR REFRESH MATERIALIZED VIEW projetos (
    CONSTRAINT data_inicio_nao_nula   EXPECT (data_inicio IS NOT NULL) ON VIOLATION FAIL UPDATE,
    CONSTRAINT ferramenta_valida      EXPECT (ferramenta IN ('excel', 'clickup', 'msproject')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Cadastro de projetos do PMO. Cada linha é um projeto com cliente, segmento, ferramenta normalizada e código na ferramenta (de-para para integração das tarefas).'
AS
SELECT
    projeto_id,
    nome_projeto,
    cliente,
    segmento,
    tipo_projeto,
    gerente_projeto,

    -- Valores monetários vêm como texto com ponto decimal ('1234567.89')
    CAST(valor_contrato  AS DECIMAL(18,2)) AS valor_contrato,
    CAST(orcamento_custo AS DECIMAL(18,2)) AS orcamento_custo,

    -- Sujeira #1: data em yyyy-MM-dd e dd/MM/yyyy
    COALESCE(
        TRY_TO_DATE(data_inicio, 'yyyy-MM-dd'),
        TRY_TO_DATE(data_inicio, 'dd/MM/yyyy')
    ) AS data_inicio,

    TO_DATE(data_fim_baseline, 'yyyy-MM-dd') AS data_fim_baseline,

    -- Sujeira #2: ferramenta escrita de 8 jeitos → excel, clickup, msproject
    CASE
        WHEN LOWER(TRIM(ferramenta)) LIKE '%excel%'     THEN 'excel'
        WHEN LOWER(TRIM(ferramenta)) LIKE '%planilha%'   THEN 'excel'
        WHEN LOWER(TRIM(ferramenta)) LIKE '%clickup%'    THEN 'clickup'
        WHEN LOWER(TRIM(ferramenta)) LIKE '%click up%'   THEN 'clickup'
        WHEN LOWER(TRIM(ferramenta)) LIKE '%msproject%'  THEN 'msproject'
        WHEN LOWER(TRIM(ferramenta)) LIKE '%ms project%' THEN 'msproject'
        WHEN LOWER(TRIM(ferramenta)) LIKE '%project%'    THEN 'msproject'
        ELSE LOWER(TRIM(ferramenta))
    END AS ferramenta,
    ferramenta AS ferramenta_como_veio,

    -- Sujeira #3: código da ferramenta vazio → NULL
    NULLIF(TRIM(codigo_ferramenta), '') AS codigo_ferramenta,

    status
FROM lakehouse_vertice.bronze.projetos
