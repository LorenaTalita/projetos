-- status_estruturado.sql — Estruturação do texto livre de status_semanal (regras + regex + IA v2.0)
-- Roda como sql_task no warehouse. A tabela é incremental (CREATE TABLE IF NOT EXISTS + MERGE INTO).

-- ============================================================
-- a. Criação da tabela incremental (nunca CREATE OR REPLACE)
-- ============================================================
CREATE TABLE IF NOT EXISTS lakehouse_vertice.gold.status_estruturado (
    projeto_id       STRING    COMMENT 'Identificador único do projeto (ex.: PRJ-011).',
    data_status      DATE      COMMENT 'Data de referência do relatório de status semanal (sexta-feira).',
    farol            STRING    COMMENT 'Farol reportado pelo gerente no status semanal (verde, amarelo, vermelho).',
    causa_bloqueio   STRING    COMMENT 'Causa principal do bloqueio: change_freeze, falta_sre, dependencia_fornecedor, rotatividade, mudanca_escopo, bug_retrabalho, aprovacao_cliente, sem_bloqueio ou nao_reportado.',
    bloqueio         STRING    COMMENT 'Resumo objetivo do bloqueio extraído pela IA nos status dos últimos 90 dias.',
    quem_destrava    STRING    COMMENT 'Área, papel ou fornecedor responsável por destravar o bloqueio (extraído pela IA).',
    dias_impacto     DOUBLE    COMMENT 'Impacto estimado em dias corridos (1 semana = 7 dias).',
    metodo           STRING    COMMENT 'Método de classificação aplicado: regra, ia ou palavra_chave.',
    texto_status     STRING    COMMENT 'Texto livre original do relatório de status semanal.',
    _classificado_em TIMESTAMP COMMENT 'Data e hora em que o registro foi classificado e inserido.'
)
COMMENT 'Status semanais estruturados: classifica a causa de bloqueio e extrai resumo, responsável por destravar e dias de impacto usando regras, palavras-chave no histórico e IA (ai_classify + ai_extract v2.0) nos últimos 90 dias.';

-- ============================================================
-- b. MERGE incremental (só processa o que ainda não está na tabela)
-- ============================================================
MERGE INTO lakehouse_vertice.gold.status_estruturado AS destino
USING (
    WITH novos_status AS (
        SELECT
            s.projeto_id,
            s.data_status,
            s.farol,
            s.texto_status,
            s.status_vazio,
            CASE
                WHEN s.status_vazio
                  OR LOWER(s.texto_status) LIKE '%bloqueios: nenhum%'
                  OR LOWER(s.texto_status) LIKE '%sem bloqueios%'
                  OR LOWER(s.texto_status) LIKE '%nada relevante%'
                THEN 'regra'
                WHEN s.data_status >= DATE'2026-07-18'
                THEN 'ia'
                ELSE 'palavra_chave'
            END AS metodo
        FROM lakehouse_vertice.silver.status_semanal s
        LEFT ANTI JOIN lakehouse_vertice.gold.status_estruturado g
            ON g.projeto_id  = s.projeto_id
           AND g.data_status = s.data_status
    ),
    -- Subconjunto 1: Regra e Palavra-Chave (sem chamadas de IA)
    classificados_sem_ia AS (
        SELECT
            projeto_id,
            data_status,
            farol,
            CASE
                WHEN metodo = 'regra' AND status_vazio THEN 'nao_reportado'
                WHEN metodo = 'regra'                  THEN 'sem_bloqueio'
                WHEN LOWER(texto_status) RLIKE 'freeze|congelamento|janela de deploy'             THEN 'change_freeze'
                WHEN LOWER(texto_status) RLIKE 'sre|infraestrutura|ambiente de homologa[çc][ãa]o' THEN 'falta_sre'
                WHEN LOWER(texto_status) RLIKE 'forge|consultoria|fornecedor'                     THEN 'dependencia_fornecedor'
                WHEN LOWER(texto_status) RLIKE 'sa[íi]da de|rotatividade|onboarding'              THEN 'rotatividade'
                WHEN LOWER(texto_status) RLIKE 'escopo|change request|regra de neg[óo]cio'        THEN 'mudanca_escopo'
                WHEN LOWER(texto_status) RLIKE 'bugs|regress[ãa]o|refazendo'                      THEN 'bug_retrabalho'
                WHEN LOWER(texto_status) RLIKE 'aprova[çc][ãa]o do cliente|homologa[çc][ãa]o do cliente' THEN 'aprovacao_cliente'
                ELSE 'sem_bloqueio'
            END AS causa_bloqueio,
            CAST(NULL AS STRING) AS bloqueio,
            CAST(NULL AS STRING) AS quem_destrava,
            CASE
                WHEN metodo = 'regra' THEN CAST(NULL AS DOUBLE)
                WHEN LOWER(texto_status) RLIKE 'impacto estimado:?\\s*1\\s*semana' THEN 7.0
                WHEN regexp_extract(LOWER(texto_status), 'impacto estimado de\\s+([0-9]+)\\s+dias?', 1) <> ''
                THEN CAST(regexp_extract(LOWER(texto_status), 'impacto estimado de\\s+([0-9]+)\\s+dias?', 1) AS DOUBLE)
                ELSE CAST(NULL AS DOUBLE)
            END AS dias_impacto,
            metodo,
            texto_status
        FROM novos_status
        WHERE metodo <> 'ia'
    ),
    -- Subconjunto 2: Últimos 90 dias com bloqueio (invoca ai_classify e ai_extract v2.0)
    chamadas_ia AS (
        SELECT
            projeto_id,
            data_status,
            farol,
            metodo,
            texto_status,
            ai_classify(
                texto_status,
                '["change_freeze","falta_sre","dependencia_fornecedor","rotatividade","mudanca_escopo","bug_retrabalho","aprovacao_cliente","sem_bloqueio"]',
                map('version', '2.0')
            ) AS cls,
            ai_extract(
                texto_status,
                '{"bloqueio":{"type":"string","description":"Resumo objetivo do bloqueio em poucas palavras"},"quem_destrava":{"type":"string","description":"Quem, qual área ou fornecedor destrava o bloqueio"},"dias_impacto":{"type":"number","description":"Dias corridos de impacto estimado (1 semana = 7)"}}',
                map('version', '2.0')
            ) AS ext
        FROM novos_status
        WHERE metodo = 'ia'
    ),
    classificados_com_ia AS (
        SELECT
            projeto_id,
            data_status,
            farol,
            COALESCE(cls:response[0]::STRING, cls:response::STRING) AS causa_bloqueio,
            ext:response:bloqueio::STRING                           AS bloqueio,
            ext:response:quem_destrava::STRING                      AS quem_destrava,
            ext:response:dias_impacto::DOUBLE                       AS dias_impacto,
            metodo,
            texto_status
        FROM chamadas_ia
    )
    SELECT
        *,
        current_timestamp() AS _classificado_em
    FROM (
        SELECT * FROM classificados_sem_ia
        UNION ALL
        SELECT * FROM classificados_com_ia
    )
) AS origem
ON destino.projeto_id  = origem.projeto_id
AND destino.data_status = origem.data_status
WHEN NOT MATCHED THEN INSERT (
    projeto_id,
    data_status,
    farol,
    causa_bloqueio,
    bloqueio,
    quem_destrava,
    dias_impacto,
    metodo,
    texto_status,
    _classificado_em
) VALUES (
    origem.projeto_id,
    origem.data_status,
    origem.farol,
    origem.causa_bloqueio,
    origem.bloqueio,
    origem.quem_destrava,
    origem.dias_impacto,
    origem.metodo,
    origem.texto_status,
    origem._classificado_em
);

-- ============================================================
-- c. Leitura final: contagem de status por metodo e causa
-- ============================================================
SELECT
    metodo,
    causa_bloqueio,
    COUNT(*) AS qtd_status,
    ROUND(SUM(COALESCE(dias_impacto, 0)), 1) AS soma_dias_impacto
FROM lakehouse_vertice.gold.status_estruturado
GROUP BY metodo, causa_bloqueio
ORDER BY metodo, qtd_status DESC

