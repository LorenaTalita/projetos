-- 01-fato-projeto-semana.sql — Histórico semanal de valor agregado (EVM) e alocação por projeto
-- Lakeflow Spark Declarative Pipelines · lê silver pelo nome curto, grava em lakehouse_vertice.gold

CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.fato_projeto_semana (
    CONSTRAINT pv_nao_negativo  EXPECT (pv >= 0)          ON VIOLATION FAIL UPDATE,
    CONSTRAINT ev_ate_orcamento EXPECT (ev <= orcamento)  ON VIOLATION FAIL UPDATE
)
COMMENT 'Histórico semanal por projeto (toda sexta-feira, do início até 2026-10-16): PV, EV, AC, SPI, CPI, EAC, farol do gerente e horas do timesheet.'
AS
WITH semanas_projeto AS (
    -- Uma linha por projeto e sexta-feira, da semana do início até 2026-10-16
    SELECT
        p.projeto_id,
        p.orcamento_custo AS orcamento,
        explode(
            sequence(
                date_add(date_trunc('WEEK', p.data_inicio), 4),
                DATE'2026-10-16',
                INTERVAL 1 WEEK
            )
        ) AS semana
    FROM projetos p
),
pv_por_semana AS (
    -- PV = orçamento × Σ(horas × fração decorrida do baseline até a semana) ÷ Σ horas
    SELECT
        s.projeto_id,
        s.semana,
        ROUND(
            s.orcamento * SUM(
                t.horas * GREATEST(
                    0.0,
                    LEAST(
                        1.0,
                        COALESCE(
                            try_divide(
                                CAST(datediff(s.semana, t.inicio_baseline) AS DOUBLE),
                                CAST(datediff(t.fim_baseline, t.inicio_baseline) AS DOUBLE)
                            ),
                            CASE WHEN s.semana >= t.fim_baseline THEN 1.0 ELSE 0.0 END
                        )
                    )
                )
            ) / SUM(t.horas),
            2
        ) AS pv
    FROM semanas_projeto s
    INNER JOIN tarefas t
        ON t.projeto_id = s.projeto_id
    GROUP BY s.projeto_id, s.semana, s.orcamento
),
status_propagado AS (
    -- Projeto concluído não publica mais status: propaga o último % e o último farol com last_value
    SELECT
        s.projeto_id,
        s.semana,
        s.orcamento,
        last_value(st.pct_concluido, true) OVER (
            PARTITION BY s.projeto_id
            ORDER BY s.semana
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS pct_concluido,
        last_value(st.farol, true) OVER (
            PARTITION BY s.projeto_id
            ORDER BY s.semana
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS farol_do_gerente
    FROM semanas_projeto s
    LEFT JOIN status_semanal st
        ON st.projeto_id = s.projeto_id
        AND st.data_status = s.semana
),
custos_por_semana AS (
    SELECT
        projeto_id,
        semana,
        SUM(valor) AS custo_semana
    FROM custos
    GROUP BY projeto_id, semana
),
ac_acumulado AS (
    -- Soma acumulada de custos por semana (isolada em CTE sem agregação aninhada)
    SELECT
        s.projeto_id,
        s.semana,
        ROUND(
            SUM(COALESCE(c.custo_semana, 0.0)) OVER (
                PARTITION BY s.projeto_id
                ORDER BY s.semana
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ),
            2
        ) AS ac
    FROM semanas_projeto s
    LEFT JOIN custos_por_semana c
        ON c.projeto_id = s.projeto_id
        AND c.semana = s.semana
),
timesheet_por_semana AS (
    SELECT
        projeto_id,
        semana,
        ROUND(SUM(horas_disponiveis), 2) AS horas_disponiveis,
        ROUND(SUM(horas_apontadas), 2)   AS horas_apontadas,
        ROUND(SUM(horas_disponiveis - horas_apontadas), 2) AS horas_ociosas
    FROM apontamentos
    GROUP BY projeto_id, semana
),
metricas_base AS (
    SELECT
        sp.projeto_id,
        sp.semana,
        sp.orcamento,
        pv.pv,
        ROUND(sp.orcamento * COALESCE(sp.pct_concluido, 0) / 100.0, 2) AS ev,
        ac.ac,
        sp.farol_do_gerente,
        COALESCE(ts.horas_disponiveis, 0.0) AS horas_disponiveis,
        COALESCE(ts.horas_apontadas, 0.0)   AS horas_apontadas,
        COALESCE(ts.horas_ociosas, 0.0)     AS horas_ociosas
    FROM status_propagado sp
    INNER JOIN pv_por_semana pv
        ON pv.projeto_id = sp.projeto_id
        AND pv.semana = sp.semana
    INNER JOIN ac_acumulado ac
        ON ac.projeto_id = sp.projeto_id
        AND ac.semana = sp.semana
    LEFT JOIN timesheet_por_semana ts
        ON ts.projeto_id = sp.projeto_id
        AND ts.semana = sp.semana
)
SELECT
    projeto_id,
    semana,
    orcamento,
    pv,
    ev,
    ac,
    ROUND(try_divide(ev, pv), 4) AS spi,
    ROUND(try_divide(ev, ac), 4) AS cpi,
    ROUND(try_divide(orcamento, ROUND(try_divide(ev, ac), 4)), 2) AS eac,
    farol_do_gerente,
    horas_disponiveis,
    horas_apontadas,
    horas_ociosas
FROM metricas_base

