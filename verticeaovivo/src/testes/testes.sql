-- testes.sql — 10 testes de qualidade e reconciliação (bronze → silver → gold)
-- Roda como sql_task no warehouse. Cada teste dispara raise_error() se falhar.

WITH
-- 1. Os 60 projetos têm cronograma na silver.tarefas
t1 AS (
    SELECT
        '01_60_projetos_com_tarefas' AS teste,
        COUNT(DISTINCT projeto_id) = 60 AS passou,
        CONCAT('projetos distintos em silver.tarefas = ', CAST(COUNT(DISTINCT projeto_id) AS STRING)) AS detalhe
    FROM lakehouse_vertice.silver.tarefas
),
-- 2. Cada projeto veio de UMA ferramenta, a do cadastro do PMO
t2_por_projeto AS (
    SELECT
        p.projeto_id,
        p.ferramenta AS ferramenta_pmo,
        COUNT(DISTINCT t.ferramenta) AS qtd_ferramentas,
        MIN(t.ferramenta) AS ferramenta_tarefas
    FROM lakehouse_vertice.silver.projetos p
    LEFT JOIN lakehouse_vertice.silver.tarefas t
        ON t.projeto_id = p.projeto_id
    GROUP BY p.projeto_id, p.ferramenta
),
t2 AS (
    SELECT
        '02_uma_ferramenta_por_projeto_igual_pmo' AS teste,
        COUNT_IF(qtd_ferramentas <> 1 OR ferramenta_tarefas <> ferramenta_pmo) = 0 AS passou,
        CONCAT('projetos divergentes = ', CAST(COUNT_IF(qtd_ferramentas <> 1 OR ferramenta_tarefas <> ferramenta_pmo) AS STRING)) AS detalhe
    FROM t2_por_projeto
),
-- 3. As horas do Excel na silver = a soma das linhas de TOTAL das planilhas
t3_totais AS (
    SELECT
        (SELECT ROUND(SUM(horas), 2) FROM lakehouse_vertice.silver.tarefas WHERE ferramenta = 'excel') AS horas_silver,
        (SELECT ROUND(SUM(CAST(REPLACE(horas_previstas, 'h', '') AS DOUBLE)), 2)
         FROM lakehouse_vertice.bronze.excel_tarefas
         WHERE tarefa = 'TOTAL') AS horas_total_bronze
),
t3 AS (
    SELECT
        '03_horas_excel_silver_igual_total_planilhas' AS teste,
        horas_silver = horas_total_bronze AS passou,
        CONCAT('silver=', CAST(horas_silver AS STRING), ' vs total_bronze=', CAST(horas_total_bronze AS STRING)) AS detalhe
    FROM t3_totais
),
-- 4. Uma linha por pessoa na silver
t4 AS (
    SELECT
        '04_uma_linha_por_pessoa_silver' AS teste,
        (COUNT(*) = COUNT(DISTINCT colaborador_id) AND COUNT(*) = 520) AS passou,
        CONCAT('linhas=', CAST(COUNT(*) AS STRING), ', distintos=', CAST(COUNT(DISTINCT colaborador_id) AS STRING)) AS detalhe
    FROM lakehouse_vertice.silver.colaboradores
),
-- 5. A CodeForge virou um fornecedor só
t5 AS (
    SELECT
        '05_codeforge_um_fornecedor_so' AS teste,
        (COUNT(DISTINCT fornecedor) = 1 AND MIN(fornecedor) = 'CodeForge Consultoria Ltda') AS passou,
        CONCAT('distintos=', CAST(COUNT(DISTINCT fornecedor) AS STRING), ' (', COALESCE(MIN(fornecedor), 'NULL'), ')') AS detalhe
    FROM lakehouse_vertice.silver.entregas_fornecedor
    WHERE REPLACE(LOWER(fornecedor_como_veio), ' ', '') LIKE '%codeforge%'
),
-- 6. A limpeza não mudou o custo total (bronze com replace = silver)
t6_totais AS (
    SELECT
        (SELECT ROUND(SUM(CAST(REPLACE(valor, ',', '.') AS DOUBLE)), 2) FROM lakehouse_vertice.bronze.custos) AS custo_bronze,
        (SELECT ROUND(SUM(valor), 2) FROM lakehouse_vertice.silver.custos) AS custo_silver
),
t6 AS (
    SELECT
        '06_custo_total_bronze_igual_silver' AS teste,
        ABS(custo_bronze - custo_silver) < 0.01 AS passou,
        CONCAT('bronze=', CAST(custo_bronze AS STRING), ' vs silver=', CAST(custo_silver AS STRING)) AS detalhe
    FROM t6_totais
),
-- 7. Os 60 projetos têm fotografia de hoje
t7 AS (
    SELECT
        '07_60_projetos_na_situacao_atual' AS teste,
        (COUNT(*) = 60 AND COUNT(DISTINCT projeto_id) = 60) AS passou,
        CONCAT('linhas=', CAST(COUNT(*) AS STRING), ', distintos=', CAST(COUNT(DISTINCT projeto_id) AS STRING)) AS detalhe
    FROM lakehouse_vertice.gold.projeto_situacao_atual
),
-- 8. Todo projeto em andamento tem SPI e CPI
t8 AS (
    SELECT
        '08_em_andamento_com_spi_e_cpi' AS teste,
        (COUNT_IF(status = 'em_andamento' AND (spi IS NULL OR cpi IS NULL)) = 0
         AND COUNT_IF(status = 'em_andamento') = 41) AS passou,
        CONCAT(
            'em_andamento=', CAST(COUNT_IF(status = 'em_andamento') AS STRING),
            ', sem_spi_ou_cpi=', CAST(COUNT_IF(status = 'em_andamento' AND (spi IS NULL OR cpi IS NULL)) AS STRING)
        ) AS detalhe
    FROM lakehouse_vertice.gold.projeto_situacao_atual
),
-- 9. O EV de hoje do status semanal bate com o das ferramentas (diferença < 1%)
t9_totais AS (
    SELECT
        (SELECT ROUND(SUM(ev), 2) FROM lakehouse_vertice.gold.fato_projeto_semana WHERE semana = DATE'2026-10-16') AS ev_status,
        (SELECT ROUND(SUM(ev), 2) FROM lakehouse_vertice.gold.projeto_situacao_atual) AS ev_ferramentas
),
t9 AS (
    SELECT
        '09_ev_hoje_status_bate_com_ferramentas' AS teste,
        ABS(ev_status - ev_ferramentas) / ev_ferramentas < 0.01 AS passou,
        CONCAT(
            'ev_status=', CAST(ev_status AS STRING),
            ' vs ev_ferramentas=', CAST(ev_ferramentas AS STRING),
            ' (diff=', CAST(ROUND(ABS(ev_status - ev_ferramentas) / ev_ferramentas * 100, 4) AS STRING), '%)'
        ) AS detalhe
    FROM t9_totais
),
-- 10. AC de hoje no fato = soma dos lançamentos até hoje
t10_comp AS (
    SELECT
        f.projeto_id,
        f.ac AS ac_fato,
        COALESCE(c.ac_custos, 0.0) AS ac_custos,
        ABS(f.ac - COALESCE(c.ac_custos, 0.0)) AS diff_abs
    FROM lakehouse_vertice.gold.fato_projeto_semana f
    LEFT JOIN (
        SELECT projeto_id, ROUND(SUM(valor), 2) AS ac_custos
        FROM lakehouse_vertice.silver.custos
        WHERE data <= DATE'2026-10-16'
        GROUP BY projeto_id
    ) c ON c.projeto_id = f.projeto_id
    WHERE f.semana = DATE'2026-10-16'
),
t10 AS (
    SELECT
        '10_ac_hoje_fato_igual_soma_custos' AS teste,
        (COUNT(*) = 60 AND COUNT_IF(diff_abs >= 0.01) = 0) AS passou,
        CONCAT('divergentes=', CAST(COUNT_IF(diff_abs >= 0.01) AS STRING), ', max_diff=', CAST(ROUND(MAX(diff_abs), 4) AS STRING)) AS detalhe
    FROM t10_comp
),
todos AS (
    SELECT * FROM t1
    UNION ALL SELECT * FROM t2
    UNION ALL SELECT * FROM t3
    UNION ALL SELECT * FROM t4
    UNION ALL SELECT * FROM t5
    UNION ALL SELECT * FROM t6
    UNION ALL SELECT * FROM t7
    UNION ALL SELECT * FROM t8
    UNION ALL SELECT * FROM t9
    UNION ALL SELECT * FROM t10
),
falhas AS (
    SELECT * FROM todos WHERE NOT passou OR passou IS NULL
)
SELECT
    CASE
        WHEN (SELECT COUNT(*) FROM falhas) > 0
        THEN raise_error(
            CONCAT(
                'Testes de qualidade FALHARAM: ',
                (SELECT concat_ws('; ', collect_list(CONCAT(teste, ' [', detalhe, ']'))) FROM falhas)
            )
        )
        ELSE 'OK'
    END AS resultado,
    t.*
FROM todos t
ORDER BY t.teste

