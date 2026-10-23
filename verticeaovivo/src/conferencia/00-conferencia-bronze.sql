-- Conferência da Bronze: verifica contagens das 9 tabelas (seed 42).
-- Roda como sql_task no warehouse. Se alguma divergir, raise_error().

WITH conferencia AS (
  SELECT 'projetos'            AS tabela,    60 AS esperado, (SELECT COUNT(*) FROM lakehouse_vertice.bronze.projetos)            AS obtido
  UNION ALL
  SELECT 'status_semanal',               3911,              (SELECT COUNT(*) FROM lakehouse_vertice.bronze.status_semanal)
  UNION ALL
  SELECT 'excel_tarefas',                1663,              (SELECT COUNT(*) FROM lakehouse_vertice.bronze.excel_tarefas)
  UNION ALL
  SELECT 'clickup_tarefas',              2119,              (SELECT COUNT(*) FROM lakehouse_vertice.bronze.clickup_tarefas)
  UNION ALL
  SELECT 'msproject_tarefas',            1260,              (SELECT COUNT(*) FROM lakehouse_vertice.bronze.msproject_tarefas)
  UNION ALL
  SELECT 'colaboradores',                 523,              (SELECT COUNT(*) FROM lakehouse_vertice.bronze.colaboradores)
  UNION ALL
  SELECT 'apontamentos',               30883,              (SELECT COUNT(*) FROM lakehouse_vertice.bronze.apontamentos)
  UNION ALL
  SELECT 'custos',                      23640,              (SELECT COUNT(*) FROM lakehouse_vertice.bronze.custos)
  UNION ALL
  SELECT 'entregas_fornecedor',           640,              (SELECT COUNT(*) FROM lakehouse_vertice.bronze.entregas_fornecedor)
),
divergentes AS (
  SELECT * FROM conferencia WHERE esperado <> obtido
)
SELECT
  CASE
    WHEN (SELECT COUNT(*) FROM divergentes) > 0
    THEN raise_error(
      CONCAT(
        'Conferência da bronze FALHOU. Tabelas divergentes: ',
        (SELECT concat_ws(', ',
           collect_list(
             CONCAT(tabela, ' (esperado=', CAST(esperado AS STRING), ', obtido=', CAST(obtido AS STRING), ')')
           )
         ) FROM divergentes),
        '. Verifique a saída da tarefa ingestao_data_lake.'
      )
    )
    ELSE 'OK'
  END AS resultado,
  c.*
FROM conferencia c
ORDER BY c.tabela
