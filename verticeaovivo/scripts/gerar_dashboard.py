#!/usr/bin/env python3
"""Gera o arquivo resources/dashboard-portfolio.lvdash.json para o Projeto Farol · Portfólio."""

from __future__ import annotations

import json
from pathlib import Path


def sql_lines(sql: str) -> list[str]:
    """Converte uma query SQL em lista de linhas preservando quebras de linha para queryLines."""
    lines = sql.strip().splitlines()
    return [line + ("\n" if idx < len(lines) - 1 else "") for idx, line in enumerate(lines)]


def text_widget(name: str, lines: list[str], x: int, y: int, width: int, height: int) -> dict:
    return {
        "widget": {
            "name": name,
            "multilineTextboxSpec": {
                "lines": lines,
            },
        },
        "position": {"x": x, "y": y, "width": width, "height": height},
    }


def counter_widget(
    name: str,
    dataset_name: str,
    field_name: str,
    title: str,
    display_name: str,
    x: int,
    y: int,
    width: int,
    height: int,
    value_format: dict | None = None,
    target_field: str | None = None,
    target_display_name: str | None = None,
    description: str | None = None,
) -> dict:
    fields = [{"name": field_name, "expression": f"`{field_name}`"}]
    if target_field:
        fields.append({"name": target_field, "expression": f"`{target_field}`"})

    value_encoding: dict = {
        "fieldName": field_name,
        "displayName": display_name,
    }
    if value_format:
        value_encoding["format"] = value_format

    encodings: dict = {"value": value_encoding}
    if target_field:
        encodings["target"] = {
            "fieldName": target_field,
            "displayName": target_display_name or target_field,
        }

    frame: dict = {"showTitle": True, "title": title}
    if description:
        frame["showDescription"] = True
        frame["description"] = description

    return {
        "widget": {
            "name": name,
            "queries": [
                {
                    "name": "main_query",
                    "query": {
                        "datasetName": dataset_name,
                        "fields": fields,
                        "disaggregated": True,
                    },
                }
            ],
            "spec": {
                "version": 2,
                "widgetType": "counter",
                "encodings": encodings,
                "frame": frame,
            },
        },
        "position": {"x": x, "y": y, "width": width, "height": height},
    }


def build_dashboard() -> dict:
    datasets = [
        {
            "name": "ds_portfolio_kpis",
            "displayName": "KPIs do Portfólio em Andamento",
            "queryLines": sql_lines(
                """
SELECT
  ROUND(SUM(valor_contrato), 2) AS carteira,
  ROUND(SUM(ev) / NULLIF(SUM(pv), 0), 2) AS spi_carteira,
  ROUND(SUM(ev) / NULLIF(SUM(ac), 0), 2) AS cpi_carteira,
  ROUND(SUM(estouro_previsto), 2) AS estouro_previsto,
  COUNT(*) AS projetos_em_andamento,
  COUNT_IF(situacao IN ('atenção', 'crítico')) AS projetos_em_risco,
  COUNT_IF(situacao = 'crítico') AS projetos_criticos,
  COUNT_IF(melancia = true) AS melancias
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
"""
            ),
        },
        {
            "name": "ds_portfolio_projetos",
            "displayName": "Projetos em Andamento",
            "queryLines": sql_lines(
                """
SELECT
  projeto_id,
  projeto,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,
  ferramenta,
  gerente_projeto,
  situacao,
  farol_do_gerente,
  farol_calculado,
  melancia,
  valor_contrato,
  orcamento,
  pv,
  ev,
  ac,
  spi,
  cpi,
  eac,
  estouro_previsto,
  margem_projetada,
  atraso_projetado_dias,
  termino_projetado
FROM projeto_situacao_atual
WHERE status = 'em_andamento'
ORDER BY estouro_previsto DESC
"""
            ),
        },
        {
            "name": "ds_spi_cpi_semanal",
            "displayName": "SPI e CPI Semanal da Carteira",
            "queryLines": sql_lines(
                """
SELECT
  semana,
  ROUND(SUM(ev) / NULLIF(SUM(pv), 0), 3) AS spi,
  ROUND(SUM(ev) / NULLIF(SUM(ac), 0), 3) AS cpi
FROM fato_projeto_semana
WHERE semana >= DATE'2025-03-07'
GROUP BY semana
ORDER BY semana
"""
            ),
        },
        {
            "name": "ds_top_ociosos",
            "displayName": "Top 15 Pessoas por Custo de Hora Ociosa (12 semanas)",
            "queryLines": sql_lines(
                """
SELECT
  colaborador_id,
  nome,
  papel,
  senioridade,
  projeto_id,
  CONCAT(colaborador_id, ' · ', nome, ' (', papel, ')') AS colaborador,
  ROUND(SUM(horas_disponiveis), 1) AS horas_disponiveis,
  ROUND(SUM(horas_apontadas), 1) AS horas_apontadas,
  ROUND(SUM(horas_ociosas), 1) AS horas_ociosas,
  ROUND(SUM(horas_apontadas) / NULLIF(SUM(horas_disponiveis), 0), 4) AS utilizacao,
  ROUND(SUM(custo_ocioso), 2) AS custo_ocioso
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY colaborador_id, nome, papel, senioridade, projeto_id
ORDER BY custo_ocioso DESC
LIMIT 15
"""
            ),
        },
        {
            "name": "ds_utilizacao_pessoas",
            "displayName": "Utilização por Pessoa e Projeto (12 semanas)",
            "queryLines": sql_lines(
                """
SELECT
  colaborador_id,
  nome,
  papel,
  senioridade,
  custo_hora,
  projeto_id,
  ROUND(SUM(horas_disponiveis), 1) AS horas_disponiveis,
  ROUND(SUM(horas_apontadas), 1) AS horas_apontadas,
  ROUND(SUM(horas_ociosas), 1) AS horas_ociosas,
  ROUND(SUM(horas_apontadas) / NULLIF(SUM(horas_disponiveis), 0), 4) AS utilizacao,
  ROUND(SUM(custo_ocioso), 2) AS custo_ocioso,
  ROUND(MAX(spi_do_projeto), 2) AS spi_do_projeto
FROM utilizacao_pessoa_semana
WHERE semana > DATE'2026-07-24'
GROUP BY colaborador_id, nome, papel, senioridade, custo_hora, projeto_id
ORDER BY utilizacao ASC, custo_ocioso DESC
"""
            ),
        },
        {
            "name": "ds_bloqueios_projeto",
            "displayName": "Causas de Bloqueio por Projeto (90 dias)",
            "queryLines": sql_lines(
                """
SELECT
  projeto_id,
  causa_bloqueio,
  COUNT(*) AS qtd_bloqueios,
  SUM(COALESCE(dias_impacto, 0)) AS dias_impacto_total
FROM status_estruturado
WHERE data_status >= DATE'2026-07-18'
  AND causa_bloqueio NOT IN ('sem_bloqueio', 'nao_reportado')
GROUP BY projeto_id, causa_bloqueio
ORDER BY qtd_bloqueios DESC, projeto_id
"""
            ),
        },
        {
            "name": "ds_fornecedores_resumo",
            "displayName": "Resumo por Fornecedor",
            "queryLines": sql_lines(
                """
SELECT
  fornecedor,
  COUNT(DISTINCT fornecedor_como_veio) AS grafias_distintas,
  COUNT(*) AS total_entregas,
  ROUND(
    SUM(CASE WHEN NOT em_aberto THEN prazo_real_dias END) * 1.0
    / NULLIF(SUM(CASE WHEN NOT em_aberto THEN prazo_prometido_dias END), 0),
    2
  ) AS razao_prazo_real_prometido,
  ROUND(
    COUNT_IF(NOT em_aberto AND dias_de_atraso_na_entrega <= 0) * 1.0
    / NULLIF(COUNT_IF(NOT em_aberto), 0),
    4
  ) AS pct_no_prazo,
  COUNT_IF(em_atraso = true) AS entregas_em_atraso,
  ROUND(SUM(valor), 2) AS valor_total
FROM lakehouse_vertice.silver.entregas_fornecedor
GROUP BY fornecedor
ORDER BY entregas_em_atraso DESC, razao_prazo_real_prometido DESC
"""
            ),
        },
        {
            "name": "ds_entregas_atrasadas",
            "displayName": "Entregas de Fornecedores em Atraso Hoje",
            "queryLines": sql_lines(
                """
SELECT
  entrega_id,
  projeto_id,
  fornecedor,
  fornecedor_como_veio,
  item,
  valor,
  status,
  data_pedido,
  data_prometida,
  prazo_contratado_dias,
  prazo_prometido_dias,
  COALESCE(dias_de_atraso_na_entrega, datediff(DATE'2026-10-16', data_prometida)) AS dias_em_atraso_hoje
FROM lakehouse_vertice.silver.entregas_fornecedor
WHERE em_atraso = true
ORDER BY dias_em_atraso_hoje DESC, valor DESC
"""
            ),
        },
    ]

    brl_compact = {
        "type": "number-currency",
        "currencyCode": "BRL",
        "abbreviation": "compact",
        "decimalPlaces": {"type": "max", "places": 2},
    }
    brl_full = {
        "type": "number-currency",
        "currencyCode": "BRL",
        "decimalPlaces": {"type": "max", "places": 2},
    }
    decimal_2 = {
        "type": "number-plain",
        "decimalPlaces": {"type": "max", "places": 2},
    }
    percent_1 = {
        "type": "number-percent",
        "decimalPlaces": {"type": "max", "places": 1},
    }

    situacao_color_mappings = [
        {"value": "crítico", "color": "#FF5F46"},
        {"value": "atenção", "color": "#F6C344"},
        {"value": "ok", "color": "#22C2F4"},
    ]

    page_portfolio = {
        "name": "portfolio",
        "displayName": "Portfólio",
        "pageType": "PAGE_TYPE_CANVAS",
        "layoutVersion": "GRID_V1",
        "layout": [
            text_widget(
                name="titulo-portfolio",
                lines=[
                    "## Projeto Farol · Portfólio em Andamento\n",
                    "\n",
                    "**Perguntas do dono da Vértice:** *1. Quais projetos estão atrasados, e de quais clientes? · 2. Quanto esse atraso vai me custar?*",
                ],
                x=0,
                y=0,
                width=12,
                height=2,
            ),
            counter_widget(
                name="kpi-carteira",
                dataset_name="ds_portfolio_kpis",
                field_name="carteira",
                title="Carteira (Em Andamento)",
                display_name="Carteira Contratada",
                x=0,
                y=2,
                width=2,
                height=3,
                value_format=brl_compact,
                description="41 projetos ativos",
            ),
            counter_widget(
                name="kpi-estouro-previsto",
                dataset_name="ds_portfolio_kpis",
                field_name="estouro_previsto",
                title="Estouro Previsto",
                display_name="Estouro Previsto (EAC - Orçamento)",
                x=2,
                y=2,
                width=2,
                height=3,
                value_format=brl_compact,
                description="Acima do orçamento baseline",
            ),
            counter_widget(
                name="kpi-spi-carteira",
                dataset_name="ds_portfolio_kpis",
                field_name="spi_carteira",
                title="SPI da Carteira",
                display_name="SPI (SUM EV / SUM PV)",
                x=4,
                y=2,
                width=2,
                height=3,
                value_format=decimal_2,
                description="Prazo: meta >= 1,00",
            ),
            counter_widget(
                name="kpi-cpi-carteira",
                dataset_name="ds_portfolio_kpis",
                field_name="cpi_carteira",
                title="CPI da Carteira",
                display_name="CPI (SUM EV / SUM AC)",
                x=6,
                y=2,
                width=2,
                height=3,
                value_format=decimal_2,
                description="Custo: meta >= 1,00",
            ),
            counter_widget(
                name="kpi-em-risco",
                dataset_name="ds_portfolio_kpis",
                field_name="projetos_em_risco",
                title="Projetos em Risco",
                display_name="Em Risco (Atenção + Crítico)",
                x=8,
                y=2,
                width=2,
                height=3,
                description="Atenção (10) + Críticos (7)",
            ),
            counter_widget(
                name="kpi-criticos-melancias",
                dataset_name="ds_portfolio_kpis",
                field_name="projetos_criticos",
                title="Críticos & Melancias",
                display_name="Projetos Críticos",
                x=10,
                y=2,
                width=2,
                height=3,
                description="Críticos: 7 | Melancias (verdes por fora, vermelhos por dentro): 4",
            ),
            {
                "widget": {
                    "name": "bar-estouro-por-projeto",
                    "queries": [
                        {
                            "name": "main_query",
                            "query": {
                                "datasetName": "ds_portfolio_projetos",
                                "fields": [
                                    {"name": "projeto", "expression": "`projeto`"},
                                    {"name": "estouro_previsto", "expression": "`estouro_previsto`"},
                                    {"name": "situacao", "expression": "`situacao`"},
                                ],
                                "disaggregated": True,
                            },
                        }
                    ],
                    "spec": {
                        "version": 3,
                        "widgetType": "bar",
                        "encodings": {
                            "x": {
                                "fieldName": "projeto",
                                "displayName": "Projeto",
                                "scale": {"type": "categorical"},
                            },
                            "y": {
                                "fieldName": "estouro_previsto",
                                "displayName": "Estouro Previsto (R$)",
                                "scale": {"type": "quantitative"},
                                "format": brl_compact,
                            },
                            "color": {
                                "fieldName": "situacao",
                                "displayName": "Situação",
                                "scale": {
                                    "type": "categorical",
                                    "mappings": situacao_color_mappings,
                                },
                            },
                        },
                        "frame": {
                            "showTitle": True,
                            "title": "Estouro Previsto de Custo por Projeto (EAC − Orçamento)",
                            "showDescription": True,
                            "description": "Colorido por situação calculada via EVM (crítico #FF5F46, atenção #F6C344, ok #22C2F4)",
                        },
                    },
                },
                "position": {"x": 0, "y": 5, "width": 12, "height": 6},
            },
            {
                "widget": {
                    "name": "scatter-spi-vs-cpi",
                    "queries": [
                        {
                            "name": "main_query",
                            "query": {
                                "datasetName": "ds_portfolio_projetos",
                                "fields": [
                                    {"name": "spi", "expression": "`spi`"},
                                    {"name": "cpi", "expression": "`cpi`"},
                                    {"name": "situacao", "expression": "`situacao`"},
                                    {"name": "valor_contrato", "expression": "`valor_contrato`"},
                                    {"name": "projeto", "expression": "`projeto`"},
                                ],
                                "disaggregated": True,
                            },
                        }
                    ],
                    "spec": {
                        "version": 3,
                        "widgetType": "scatter",
                        "encodings": {
                            "x": {
                                "fieldName": "spi",
                                "displayName": "SPI (Prazo)",
                                "scale": {"type": "quantitative"},
                            },
                            "y": {
                                "fieldName": "cpi",
                                "displayName": "CPI (Custo)",
                                "scale": {"type": "quantitative"},
                            },
                            "color": {
                                "fieldName": "situacao",
                                "displayName": "Situação",
                                "scale": {
                                    "type": "categorical",
                                    "mappings": situacao_color_mappings,
                                },
                            },
                            "size": {
                                "fieldName": "valor_contrato",
                                "displayName": "Valor do Contrato (R$)",
                                "scale": {"type": "quantitative"},
                            },
                        },
                        "frame": {
                            "showTitle": True,
                            "title": "Dispersão SPI × CPI por Projeto em Andamento",
                            "showDescription": True,
                            "description": "Um ponto por projeto em andamento (tamanho = valor do contrato)",
                        },
                    },
                },
                "position": {"x": 0, "y": 11, "width": 6, "height": 6},
            },
            {
                "widget": {
                    "name": "line-spi-cpi-semanal",
                    "queries": [
                        {
                            "name": "main_query",
                            "query": {
                                "datasetName": "ds_spi_cpi_semanal",
                                "fields": [
                                    {"name": "semana", "expression": "`semana`"},
                                    {"name": "spi", "expression": "`spi`"},
                                    {"name": "cpi", "expression": "`cpi`"},
                                ],
                                "disaggregated": True,
                            },
                        }
                    ],
                    "spec": {
                        "version": 3,
                        "widgetType": "line",
                        "encodings": {
                            "x": {
                                "fieldName": "semana",
                                "displayName": "Semana",
                                "scale": {"type": "temporal"},
                            },
                            "y": {
                                "scale": {"type": "quantitative"},
                                "fields": [
                                    {"fieldName": "spi", "displayName": "SPI da Carteira"},
                                    {"fieldName": "cpi", "displayName": "CPI da Carteira"},
                                ],
                            },
                        },
                        "frame": {
                            "showTitle": True,
                            "title": "Evolução Semanal de SPI e CPI da Carteira (desde 2025-03-07)",
                            "showDescription": True,
                            "description": "Calculado como SUM(ev)/SUM(pv) e SUM(ev)/SUM(ac) por semana",
                        },
                    },
                },
                "position": {"x": 6, "y": 11, "width": 6, "height": 6},
            },
            {
                "widget": {
                    "name": "tabela-projetos-em-andamento",
                    "queries": [
                        {
                            "name": "main_query",
                            "query": {
                                "datasetName": "ds_portfolio_projetos",
                                "fields": [
                                    {"name": "projeto", "expression": "`projeto`"},
                                    {"name": "cliente", "expression": "`cliente`"},
                                    {"name": "gerente_projeto", "expression": "`gerente_projeto`"},
                                    {"name": "situacao", "expression": "`situacao`"},
                                    {"name": "farol_do_gerente", "expression": "`farol_do_gerente`"},
                                    {"name": "farol_calculado", "expression": "`farol_calculado`"},
                                    {"name": "melancia", "expression": "`melancia`"},
                                    {"name": "spi", "expression": "`spi`"},
                                    {"name": "cpi", "expression": "`cpi`"},
                                    {"name": "valor_contrato", "expression": "`valor_contrato`"},
                                    {"name": "orcamento", "expression": "`orcamento`"},
                                    {"name": "eac", "expression": "`eac`"},
                                    {"name": "estouro_previsto", "expression": "`estouro_previsto`"},
                                    {"name": "atraso_projetado_dias", "expression": "`atraso_projetado_dias`"},
                                    {"name": "termino_projetado", "expression": "`termino_projetado`"},
                                ],
                                "disaggregated": True,
                            },
                        }
                    ],
                    "spec": {
                        "version": 2,
                        "widgetType": "table",
                        "encodings": {
                            "columns": [
                                {"fieldName": "projeto", "displayName": "Projeto"},
                                {"fieldName": "cliente", "displayName": "Cliente"},
                                {"fieldName": "gerente_projeto", "displayName": "Gerente"},
                                {"fieldName": "situacao", "displayName": "Situação"},
                                {"fieldName": "farol_do_gerente", "displayName": "Farol do Gerente"},
                                {"fieldName": "farol_calculado", "displayName": "Farol Calculado"},
                                {"fieldName": "melancia", "displayName": "Melancia 🍉"},
                                {"fieldName": "spi", "displayName": "SPI", "format": decimal_2},
                                {"fieldName": "cpi", "displayName": "CPI", "format": decimal_2},
                                {"fieldName": "valor_contrato", "displayName": "Contrato (R$)", "format": brl_full},
                                {"fieldName": "orcamento", "displayName": "Orçamento (R$)", "format": brl_full},
                                {"fieldName": "eac", "displayName": "EAC (R$)", "format": brl_full},
                                {"fieldName": "estouro_previsto", "displayName": "Estouro Previsto (R$)", "format": brl_full},
                                {"fieldName": "atraso_projetado_dias", "displayName": "Atraso Projetado (dias)"},
                                {"fieldName": "termino_projetado", "displayName": "Término Projetado"},
                            ]
                        },
                        "frame": {
                            "showTitle": True,
                            "title": "Projetos em Andamento — Farol do Gerente vs. Farol Calculado e Melancias",
                        },
                    },
                },
                "position": {"x": 0, "y": 17, "width": 12, "height": 7},
            },
        ],
    }

    page_pessoas = {
        "name": "pessoas",
        "displayName": "Pessoas",
        "pageType": "PAGE_TYPE_CANVAS",
        "layoutVersion": "GRID_V1",
        "layout": [
            text_widget(
                name="titulo-pessoas",
                lines=[
                    "## Projeto Farol · Alocação, Ociosidade e Bloqueios\n",
                    "\n",
                    "**Pergunta do dono da Vértice:** *3. Tenho gente parada enquanto outro projeto pede gente?*",
                ],
                x=0,
                y=0,
                width=12,
                height=2,
            ),
            {
                "widget": {
                    "name": "bar-top-15-custo-ocioso",
                    "queries": [
                        {
                            "name": "main_query",
                            "query": {
                                "datasetName": "ds_top_ociosos",
                                "fields": [
                                    {"name": "colaborador", "expression": "`colaborador`"},
                                    {"name": "custo_ocioso", "expression": "`custo_ocioso`"},
                                    {"name": "papel", "expression": "`papel`"},
                                ],
                                "disaggregated": True,
                            },
                        }
                    ],
                    "spec": {
                        "version": 3,
                        "widgetType": "bar",
                        "encodings": {
                            "x": {
                                "fieldName": "custo_ocioso",
                                "displayName": "Custo Ocioso (R$)",
                                "scale": {"type": "quantitative"},
                                "format": brl_compact,
                            },
                            "y": {
                                "fieldName": "colaborador",
                                "displayName": "Colaborador",
                                "scale": {"type": "categorical"},
                            },
                            "color": {
                                "fieldName": "papel",
                                "displayName": "Papel",
                                "scale": {"type": "categorical"},
                            },
                        },
                        "frame": {
                            "showTitle": True,
                            "title": "Top 15 Pessoas por Custo de Hora Ociosa (Últimas 12 Semanas)",
                            "showDescription": True,
                            "description": "Janela: semana > 2026-07-24",
                        },
                    },
                },
                "position": {"x": 0, "y": 2, "width": 6, "height": 6},
            },
            {
                "widget": {
                    "name": "bar-causas-bloqueio-por-projeto",
                    "queries": [
                        {
                            "name": "main_query",
                            "query": {
                                "datasetName": "ds_bloqueios_projeto",
                                "fields": [
                                    {"name": "projeto_id", "expression": "`projeto_id`"},
                                    {"name": "causa_bloqueio", "expression": "`causa_bloqueio`"},
                                    {"name": "qtd_bloqueios", "expression": "`qtd_bloqueios`"},
                                ],
                                "disaggregated": True,
                            },
                        }
                    ],
                    "spec": {
                        "version": 3,
                        "widgetType": "bar",
                        "encodings": {
                            "x": {
                                "fieldName": "projeto_id",
                                "displayName": "Projeto",
                                "scale": {"type": "categorical"},
                            },
                            "y": {
                                "fieldName": "qtd_bloqueios",
                                "displayName": "Reportes com Bloqueio",
                                "scale": {"type": "quantitative"},
                            },
                            "color": {
                                "fieldName": "causa_bloqueio",
                                "displayName": "Causa do Bloqueio",
                                "scale": {"type": "categorical"},
                            },
                        },
                        "frame": {
                            "showTitle": True,
                            "title": "Causas de Bloqueio por Projeto (Últimos 90 Dias)",
                            "showDescription": True,
                            "description": "Extraído via ai_query em status_estruturado (data_status >= 2026-07-18, excluindo sem_bloqueio e nao_reportado)",
                        },
                    },
                },
                "position": {"x": 6, "y": 2, "width": 6, "height": 6},
            },
            {
                "widget": {
                    "name": "tabela-utilizacao-pessoa-projeto",
                    "queries": [
                        {
                            "name": "main_query",
                            "query": {
                                "datasetName": "ds_utilizacao_pessoas",
                                "fields": [
                                    {"name": "colaborador_id", "expression": "`colaborador_id`"},
                                    {"name": "nome", "expression": "`nome`"},
                                    {"name": "papel", "expression": "`papel`"},
                                    {"name": "senioridade", "expression": "`senioridade`"},
                                    {"name": "projeto_id", "expression": "`projeto_id`"},
                                    {"name": "utilizacao", "expression": "`utilizacao`"},
                                    {"name": "horas_disponiveis", "expression": "`horas_disponiveis`"},
                                    {"name": "horas_apontadas", "expression": "`horas_apontadas`"},
                                    {"name": "horas_ociosas", "expression": "`horas_ociosas`"},
                                    {"name": "custo_ocioso", "expression": "`custo_ocioso`"},
                                    {"name": "spi_do_projeto", "expression": "`spi_do_projeto`"},
                                ],
                                "disaggregated": True,
                            },
                        }
                    ],
                    "spec": {
                        "version": 2,
                        "widgetType": "table",
                        "encodings": {
                            "columns": [
                                {"fieldName": "colaborador_id", "displayName": "ID"},
                                {"fieldName": "nome", "displayName": "Colaborador"},
                                {"fieldName": "papel", "displayName": "Papel"},
                                {"fieldName": "senioridade", "displayName": "Senioridade"},
                                {"fieldName": "projeto_id", "displayName": "Projeto"},
                                {"fieldName": "utilizacao", "displayName": "Utilização (%)", "format": percent_1},
                                {"fieldName": "horas_disponiveis", "displayName": "Horas Disponíveis"},
                                {"fieldName": "horas_apontadas", "displayName": "Horas Apontadas"},
                                {"fieldName": "horas_ociosas", "displayName": "Horas Ociosas"},
                                {"fieldName": "custo_ocioso", "displayName": "Custo Ocioso (R$)", "format": brl_full},
                                {"fieldName": "spi_do_projeto", "displayName": "SPI do Projeto", "format": decimal_2},
                            ]
                        },
                        "frame": {
                            "showTitle": True,
                            "title": "Utilização por Pessoa e Projeto (Últimas 12 Semanas — Mais Ocioso para Mais Ocupado)",
                        },
                    },
                },
                "position": {"x": 0, "y": 8, "width": 12, "height": 7},
            },
        ],
    }

    page_fornecedores = {
        "name": "fornecedores",
        "displayName": "Fornecedores",
        "pageType": "PAGE_TYPE_CANVAS",
        "layoutVersion": "GRID_V1",
        "layout": [
            text_widget(
                name="titulo-fornecedores",
                lines=[
                    "## Projeto Farol · Entregas e Desempenho de Fornecedores\n",
                    "\n",
                    "**Pergunta do dono da Vértice:** *4. O que vai dar errado no próximo mês? (Entregas de consultoria e fornecedores)*",
                ],
                x=0,
                y=0,
                width=12,
                height=2,
            ),
            {
                "widget": {
                    "name": "tabela-resumo-fornecedores",
                    "queries": [
                        {
                            "name": "main_query",
                            "query": {
                                "datasetName": "ds_fornecedores_resumo",
                                "fields": [
                                    {"name": "fornecedor", "expression": "`fornecedor`"},
                                    {"name": "grafias_distintas", "expression": "`grafias_distintas`"},
                                    {"name": "total_entregas", "expression": "`total_entregas`"},
                                    {"name": "razao_prazo_real_prometido", "expression": "`razao_prazo_real_prometido`"},
                                    {"name": "pct_no_prazo", "expression": "`pct_no_prazo`"},
                                    {"name": "entregas_em_atraso", "expression": "`entregas_em_atraso`"},
                                    {"name": "valor_total", "expression": "`valor_total`"},
                                ],
                                "disaggregated": True,
                            },
                        }
                    ],
                    "spec": {
                        "version": 2,
                        "widgetType": "table",
                        "encodings": {
                            "columns": [
                                {"fieldName": "fornecedor", "displayName": "Fornecedor (Normalizado)"},
                                {"fieldName": "grafias_distintas", "displayName": "Grafias Distintas na Origem"},
                                {"fieldName": "total_entregas", "displayName": "Total de Entregas"},
                                {
                                    "fieldName": "razao_prazo_real_prometido",
                                    "displayName": "Prazo Real ÷ Prometido",
                                    "format": decimal_2,
                                },
                                {"fieldName": "pct_no_prazo", "displayName": "% No Prazo", "format": percent_1},
                                {"fieldName": "entregas_em_atraso", "displayName": "Em Atraso Hoje"},
                                {"fieldName": "valor_total", "displayName": "Valor Total (R$)", "format": brl_full},
                            ]
                        },
                        "frame": {
                            "showTitle": True,
                            "title": "Desempenho por Fornecedor (Consolidação de Grafias, Prazo Real ÷ Prometido e Entregas em Atraso)",
                        },
                    },
                },
                "position": {"x": 0, "y": 2, "width": 12, "height": 5},
            },
            {
                "widget": {
                    "name": "tabela-entregas-atrasadas",
                    "queries": [
                        {
                            "name": "main_query",
                            "query": {
                                "datasetName": "ds_entregas_atrasadas",
                                "fields": [
                                    {"name": "entrega_id", "expression": "`entrega_id`"},
                                    {"name": "projeto_id", "expression": "`projeto_id`"},
                                    {"name": "fornecedor", "expression": "`fornecedor`"},
                                    {"name": "fornecedor_como_veio", "expression": "`fornecedor_como_veio`"},
                                    {"name": "item", "expression": "`item`"},
                                    {"name": "valor", "expression": "`valor`"},
                                    {"name": "status", "expression": "`status`"},
                                    {"name": "data_pedido", "expression": "`data_pedido`"},
                                    {"name": "data_prometida", "expression": "`data_prometida`"},
                                    {"name": "prazo_contratado_dias", "expression": "`prazo_contratado_dias`"},
                                    {"name": "prazo_prometido_dias", "expression": "`prazo_prometido_dias`"},
                                    {"name": "dias_em_atraso_hoje", "expression": "`dias_em_atraso_hoje`"},
                                ],
                                "disaggregated": True,
                            },
                        }
                    ],
                    "spec": {
                        "version": 2,
                        "widgetType": "table",
                        "encodings": {
                            "columns": [
                                {"fieldName": "entrega_id", "displayName": "Entrega"},
                                {"fieldName": "projeto_id", "displayName": "Projeto"},
                                {"fieldName": "fornecedor", "displayName": "Fornecedor"},
                                {"fieldName": "fornecedor_como_veio", "displayName": "Grafia na Origem"},
                                {"fieldName": "item", "displayName": "Item"},
                                {"fieldName": "valor", "displayName": "Valor (R$)", "format": brl_full},
                                {"fieldName": "status", "displayName": "Status"},
                                {"fieldName": "data_pedido", "displayName": "Data do Pedido"},
                                {"fieldName": "data_prometida", "displayName": "Data Prometida"},
                                {"fieldName": "prazo_contratado_dias", "displayName": "Prazo Contratado (dias)"},
                                {"fieldName": "prazo_prometido_dias", "displayName": "Prazo Prometido (dias)"},
                                {"fieldName": "dias_em_atraso_hoje", "displayName": "Dias em Atraso Hoje"},
                            ]
                        },
                        "frame": {
                            "showTitle": True,
                            "title": "Entregas Atualmente em Atraso (WHERE em_atraso = true)",
                        },
                    },
                },
                "position": {"x": 0, "y": 7, "width": 12, "height": 6},
            },
        ],
    }

    return {
        "datasets": datasets,
        "pages": [page_portfolio, page_pessoas, page_fornecedores],
        "uiSettings": {
            "theme": {
                "canvasBackgroundColor": {"light": "#F5F7FA", "dark": "#14141A"},
                "widgetBackgroundColor": {"light": "#FFFFFF", "dark": "#1C1C24"},
                "widgetBorderColor": {"light": "#E2E8F0", "dark": "#2A2A36"},
                "fontColor": {"light": "#14141A", "dark": "#F0F4F8"},
                "selectionColor": {"light": "#0059DB", "dark": "#22C2F4"},
                "visualizationColors": [
                    "#0059DB",
                    "#22C2F4",
                    "#F6C344",
                    "#FF5F46",
                    "#2FB344",
                    "#8B5CF6",
                    "#EC4899",
                ],
                "widgetHeaderAlignment": "LEFT",
            }
        },
    }


def main() -> None:
    root_dir = Path(__file__).resolve().parent.parent
    output_path = root_dir / "resources" / "dashboard-portfolio.lvdash.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    dashboard = build_dashboard()
    output_path.write_text(
        json.dumps(dashboard, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    total_widgets = sum(len(p["layout"]) for p in dashboard["pages"])
    print(f"Dashboard gerado com sucesso em: {output_path}")
    print(f"Datasets: {len(dashboard['datasets'])} | Páginas: {len(dashboard['pages'])} | Widgets: {total_widgets}")


if __name__ == "__main__":
    main()

