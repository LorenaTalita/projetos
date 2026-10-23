-- 02-situacao-e-pessoas.sql — Fotografia atual dos projetos (2026-10-16) e utilização por pessoa/semana
-- Lakeflow Spark Declarative Pipelines · lê silver pelo nome curto, grava em lakehouse_vertice.gold

-- ============================================================
-- 1. Fotografia de hoje (2026-10-16) de cada projeto (60 linhas)
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.projeto_situacao_atual
COMMENT 'Fotografia em 2026-10-16 dos 60 projetos da carteira: cadastro completo do PMO, KPIs de valor agregado (PV, EV, AC, SPI, CPI, EAC, estouro previsto, margem, atraso), situação e melancias.'
AS
WITH evm_tarefas AS (
    -- PV e EV de hoje (2026-10-16) calculados sobre silver.tarefas
    SELECT
        t.projeto_id,
        SUM(
            t.horas * GREATEST(
                0.0,
                LEAST(
                    1.0,
                    COALESCE(
                        try_divide(
                            CAST(datediff(DATE'2026-10-16', t.inicio_baseline) AS DOUBLE),
                            CAST(datediff(t.fim_baseline, t.inicio_baseline) AS DOUBLE)
                        ),
                        CASE WHEN DATE'2026-10-16' >= t.fim_baseline THEN 1.0 ELSE 0.0 END
                    )
                )
            )
        ) / SUM(t.horas) AS fracao_pv,
        SUM(t.horas * (t.pct_concluido / 100.0)) / SUM(t.horas) AS fracao_ev
    FROM tarefas t
    GROUP BY t.projeto_id
),
ac_hoje AS (
    SELECT
        projeto_id,
        ROUND(SUM(valor), 2) AS ac
    FROM custos
    WHERE data <= DATE'2026-10-16'
    GROUP BY projeto_id
),
ultimo_status AS (
    SELECT
        projeto_id,
        farol AS farol_do_gerente,
        ROW_NUMBER() OVER (PARTITION BY projeto_id ORDER BY data_status DESC) AS rn
    FROM status_semanal
    WHERE data_status <= DATE'2026-10-16'
),
base AS (
    SELECT
        p.projeto_id,
        p.nome_projeto,
        CONCAT(p.projeto_id, ' · ', p.nome_projeto) AS projeto,
        p.cliente,
        p.segmento,
        p.tipo_projeto,
        p.ferramenta,
        p.gerente_projeto,
        p.valor_contrato,
        p.orcamento_custo AS orcamento,
        p.data_inicio,
        p.data_fim_baseline,
        datediff(p.data_fim_baseline, p.data_inicio) AS duracao_baseline_dias,
        p.status,
        ROUND(p.orcamento_custo * e.fracao_pv, 2) AS pv,
        ROUND(p.orcamento_custo * e.fracao_ev, 2) AS ev,
        COALESCE(a.ac, 0.0) AS ac,
        us.farol_do_gerente
    FROM projetos p
    INNER JOIN evm_tarefas e
        ON e.projeto_id = p.projeto_id
    LEFT JOIN ac_hoje a
        ON a.projeto_id = p.projeto_id
    LEFT JOIN ultimo_status us
        ON us.projeto_id = p.projeto_id
        AND us.rn = 1
),
kpis AS (
    SELECT
        *,
        ROUND(try_divide(ev, pv), 4) AS spi,
        ROUND(try_divide(ev, ac), 4) AS cpi,
        ROUND(try_divide(orcamento, ROUND(try_divide(ev, ac), 4)), 2) AS eac
    FROM base
)
SELECT
    projeto_id,
    nome_projeto,
    projeto,
    cliente,
    segmento,
    tipo_projeto,
    ferramenta,
    gerente_projeto,
    valor_contrato,
    orcamento,
    data_inicio,
    data_fim_baseline,
    duracao_baseline_dias,
    status,
    pv,
    ev,
    ac,
    spi,
    cpi,
    eac,
    ROUND(GREATEST(eac - orcamento, CAST(0 AS DECIMAL(18,2))), 2) AS estouro_previsto,
    ROUND(try_divide(valor_contrato - eac, valor_contrato), 4) AS margem_projetada,
    CAST(ROUND(try_divide(CAST(duracao_baseline_dias AS DOUBLE), spi) - duracao_baseline_dias) AS INT) AS atraso_projetado_dias,
    date_add(
        data_fim_baseline,
        CAST(GREATEST(ROUND(try_divide(CAST(duracao_baseline_dias AS DOUBLE), spi) - duracao_baseline_dias), 0) AS INT)
    ) AS termino_projetado,
    CASE
        WHEN status <> 'em_andamento' THEN 'concluído'
        WHEN spi < 0.8 OR cpi < 0.8   THEN 'crítico'
        WHEN spi < 0.9 OR cpi < 0.9   THEN 'atenção'
        ELSE 'ok'
    END AS situacao,
    farol_do_gerente,
    CASE
        WHEN spi >= 0.95 THEN 'verde'
        WHEN spi >= 0.90 THEN 'amarelo'
        ELSE 'vermelho'
    END AS farol_calculado,
    (status = 'em_andamento' AND farol_do_gerente = 'verde' AND spi < 0.9) AS melancia
FROM kpis
;

-- ============================================================
-- 2. Utilização por pessoa, projeto e semana
-- ============================================================
CREATE OR REFRESH MATERIALIZED VIEW lakehouse_vertice.gold.utilizacao_pessoa_semana
COMMENT 'Alocação semanal por pessoa e projeto: horas disponíveis, apontadas, ociosas, taxa de utilização, custo ocioso e SPI do projeto naquela semana.'
AS
SELECT
    a.colaborador_id,
    c.nome,
    c.papel,
    c.senioridade,
    c.custo_hora,
    a.projeto_id,
    a.semana,
    a.horas_disponiveis,
    a.horas_apontadas,
    ROUND(a.horas_disponiveis - a.horas_apontadas, 2) AS horas_ociosas,
    ROUND(try_divide(a.horas_apontadas, a.horas_disponiveis), 4) AS utilizacao,
    ROUND((a.horas_disponiveis - a.horas_apontadas) * c.custo_hora, 2) AS custo_ocioso,
    f.spi AS spi_do_projeto
FROM apontamentos a
INNER JOIN colaboradores c
    ON c.colaborador_id = a.colaborador_id
LEFT JOIN lakehouse_vertice.gold.fato_projeto_semana f
    ON f.projeto_id = a.projeto_id
    AND f.semana = a.semana

