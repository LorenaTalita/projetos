-- 02-tarefas.sql — As três ferramentas viram uma só tabela
-- Lakeflow Spark Declarative Pipelines · schema padrão = silver

-- ============================================================
-- TEMPORARY VIEW 1: tarefas do Excel
-- ============================================================
CREATE TEMPORARY VIEW tarefas_excel AS
SELECT
    -- Projeto pelo de-para: codigo_ferramenta = arquivo.
    -- Fallback: o PRJ-xxx que está no nome do arquivo.
    COALESCE(p.projeto_id, regexp_extract(e.arquivo, 'PRJ-[0-9]{3}', 0)) AS projeto_id,
    'excel' AS ferramenta,
    CAST(e.id AS STRING) AS id_na_ferramenta,
    e.fase,
    e.tarefa,
    e.responsavel,

    -- Sujeira #4: datas em dd/MM/yyyy ou número de série do Excel
    CASE
        WHEN e.inicio_previsto LIKE '%/%'
        THEN TRY_TO_DATE(e.inicio_previsto, 'dd/MM/yyyy')
        ELSE date_add(DATE'1899-12-30', CAST(e.inicio_previsto AS INT))
    END AS inicio_baseline,
    CASE
        WHEN e.termino_previsto LIKE '%/%'
        THEN TRY_TO_DATE(e.termino_previsto, 'dd/MM/yyyy')
        ELSE date_add(DATE'1899-12-30', CAST(e.termino_previsto AS INT))
    END AS fim_baseline,
    CASE
        WHEN e.inicio_real LIKE '%/%'
        THEN TRY_TO_DATE(e.inicio_real, 'dd/MM/yyyy')
        ELSE date_add(DATE'1899-12-30', CAST(e.inicio_real AS INT))
    END AS inicio_real,
    CASE
        WHEN e.termino_real LIKE '%/%'
        THEN TRY_TO_DATE(e.termino_real, 'dd/MM/yyyy')
        ELSE date_add(DATE'1899-12-30', CAST(e.termino_real AS INT))
    END AS fim_real,

    -- Sujeira #5: % em '45%', '10,5%' ou 0.45
    -- (instr em vez de LIKE '%\%%': evita depender do escape do backslash)
    CASE
        WHEN instr(e.pct_concluido, '%') > 0
        THEN CAST(REPLACE(REPLACE(e.pct_concluido, '%', ''), ',', '.') AS DOUBLE)
        ELSE CAST(e.pct_concluido AS DOUBLE) * 100
    END AS pct_como_veio,

    -- Sujeira #7: horas com 'h'
    CAST(REPLACE(e.horas_previstas, 'h', '') AS DOUBLE) AS horas,

    CAST(NULL AS STRING) AS status_na_ferramenta
FROM lakehouse_vertice.bronze.excel_tarefas e
LEFT JOIN projetos p
    ON p.codigo_ferramenta = e.arquivo
    AND p.ferramenta = 'excel'
-- Sujeira #6: tirar a linha TOTAL (coalesce: tarefa nula não pode sumir pelo <>)
WHERE COALESCE(e.tarefa, '') <> 'TOTAL'
;

-- ============================================================
-- TEMPORARY VIEW 2: tarefas do ClickUp
-- ============================================================
CREATE TEMPORARY VIEW tarefas_clickup AS
SELECT
    -- Projeto pelo de-para: codigo_ferramenta = list_id; fallback pelo list_name
    COALESCE(
        p1.projeto_id,
        p2.projeto_id
    ) AS projeto_id,
    'clickup' AS ferramenta,
    CAST(c.id AS STRING) AS id_na_ferramenta,

    -- Sujeira #8: Fase dentro de custom_fields
    filter(c.custom_fields, f -> f.name = 'Fase')[0].value AS fase,

    c.name AS tarefa,
    -- assignees é uma lista de struct com um campo só: username
    c.assignees[0].username AS responsavel,

    -- Sujeira #8: baseline dentro de custom_fields, em milissegundos (ex.: '1745150400000')
    to_date(timestamp_millis(CAST(
        filter(c.custom_fields, f -> f.name = 'Início baseline')[0].value AS BIGINT
    ))) AS inicio_baseline,
    to_date(timestamp_millis(CAST(
        filter(c.custom_fields, f -> f.name = 'Fim baseline')[0].value AS BIGINT
    ))) AS fim_baseline,

    -- Datas reais em milissegundos: start_date = início; date_done = quando concluiu
    -- (due_date é o prazo planejado, não o fim real)
    to_date(timestamp_millis(CAST(c.start_date AS BIGINT))) AS inicio_real,
    to_date(timestamp_millis(CAST(c.date_done  AS BIGINT))) AS fim_real,

    -- Sujeira #8: % dentro de custom_fields
    CAST(
        filter(c.custom_fields, f -> f.name = 'Progresso (%)')[0].value AS DOUBLE
    ) AS pct_como_veio,

    -- Horas: time_estimate em milissegundos → horas
    CAST(c.time_estimate AS DOUBLE) / 3600000.0 AS horas,

    -- Sujeira #9: os 12 jeitos de escrever o status (conferidos na bronze) → 3 valores
    CASE
        WHEN LOWER(TRIM(c.status.status)) IN ('done', 'closed', 'concluído', 'concluido', 'concluída', 'concluida')
        THEN 'concluida'
        WHEN LOWER(TRIM(c.status.status)) IN ('to do', 'a fazer', 'backlog')
        THEN 'a_fazer'
        WHEN LOWER(TRIM(c.status.status)) IN ('doing', 'in progress', 'em andamento', 'review')
        THEN 'em_andamento'
    END AS status_na_ferramenta
FROM lakehouse_vertice.bronze.clickup_tarefas c
LEFT JOIN projetos p1
    ON p1.codigo_ferramenta = c.list_id
    AND p1.ferramenta = 'clickup'
-- Sujeira #3: código vazio no PMO (ex.: PRJ-009) → casa pelo nome da lista = nome do projeto
LEFT JOIN projetos p2
    ON p2.nome_projeto = c.list_name
    AND p2.ferramenta = 'clickup'
    AND p2.codigo_ferramenta IS NULL
;

-- ============================================================
-- TEMPORARY VIEW 3: tarefas do MS Project
-- ============================================================
CREATE TEMPORARY VIEW tarefas_msproject AS
WITH tarefas_com_fase AS (
    SELECT
        m.*,
        -- Sujeira #11: a fase é a última tarefa-resumo de OutlineLevel 1
        last_value(
            CASE WHEN m.OutlineLevel = 1 THEN m.Name END, true
        ) OVER (PARTITION BY m.arquivo ORDER BY m.UID) AS fase_calculada
    FROM lakehouse_vertice.bronze.msproject_tarefas m
)
SELECT
    p.projeto_id,
    'msproject' AS ferramenta,
    CAST(t.UID AS STRING) AS id_na_ferramenta,
    t.fase_calculada AS fase,
    t.Name AS tarefa,
    CAST(NULL AS STRING) AS responsavel,

    -- Baseline.Start/Finish vêm como texto ISO ('2025-01-11T08:00:00.000Z')
    to_date(CAST(t.`Baseline`.Start  AS TIMESTAMP)) AS inicio_baseline,
    to_date(CAST(t.`Baseline`.Finish AS TIMESTAMP)) AS fim_baseline,

    -- ActualStart / ActualFinish já são TIMESTAMP na bronze
    to_date(t.ActualStart)  AS inicio_real,
    to_date(t.ActualFinish) AS fim_real,

    CAST(t.PercentComplete AS DOUBLE) AS pct_como_veio,

    -- Sujeira #12: horas em 'PT40H0M0S'
    CAST(regexp_extract(t.Work, 'PT([0-9]+)H', 1) AS DOUBLE) AS horas,

    CAST(NULL AS STRING) AS status_na_ferramenta
FROM tarefas_com_fase t
LEFT JOIN projetos p
    ON p.codigo_ferramenta = t.arquivo
    AND p.ferramenta = 'msproject'
-- Sujeira #10: só tarefas-folha (Summary = 0)
WHERE t.Summary = 0
;

-- ============================================================
-- MATERIALIZED VIEW: tarefas (UNION ALL das três)
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW tarefas (
    CONSTRAINT achou_o_projeto            EXPECT (projeto_id IS NOT NULL) ON VIOLATION FAIL UPDATE,
    CONSTRAINT pct_entre_0_e_100          EXPECT (pct_concluido BETWEEN 0 AND 100) ON VIOLATION FAIL UPDATE,
    CONSTRAINT horas_positivas            EXPECT (horas > 0) ON VIOLATION FAIL UPDATE
)
COMMENT 'Tarefas das três ferramentas (Excel, ClickUp, MS Project) integradas num modelo só. Uma linha por tarefa.'
AS
SELECT
    CONCAT(projeto_id, '-', ferramenta, '-', id_na_ferramenta) AS tarefa_id,
    projeto_id,
    ferramenta,
    id_na_ferramenta,
    fase,
    tarefa,
    responsavel,
    inicio_baseline,
    fim_baseline,
    inicio_real,
    fim_real,
    pct_como_veio,
    LEAST(pct_como_veio, 100) AS pct_concluido,
    CASE WHEN pct_como_veio > 100 THEN true ELSE false END AS pct_veio_acima_de_100,
    horas,
    status_na_ferramenta
FROM (
    SELECT * FROM tarefas_excel
    UNION ALL
    SELECT * FROM tarefas_clickup
    UNION ALL
    SELECT * FROM tarefas_msproject
)
