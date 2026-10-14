-- agencia_caixa(dias) — igual nas duas bases (Doctor e Acesso). Lida pela publica-relatorio
-- (bloco `agencia_caixa` do dados.json) e pela aba Canais.
CREATE OR REPLACE FUNCTION public.agencia_caixa(dias integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
-- v4, 14/10/2026 — regra do Henrique: quem chegou pelo anúncio da agência e fechou é paciente
-- daquela agência, mesmo que já estivesse na base. O pagamento feito A PARTIR DO DIA DO CLIQUE
-- por paciente reativado (chegou antes por outro caminho e depois clicou no anúncio de outra
-- agência; mesma regra da reativação da agencia_serie: quem chegou por "Meta sem id do anúncio"
-- não conta; clique em post da página, agência "Não identificada", também não) passa a ser da
-- agência do clique, e deixa de ser da agência de chegada.
-- Linha da reativação: `reat` = true, `dc` = dia do clique, `ch` = canal por onde o paciente
-- tinha chegado (a aba tira o valor desse canal e põe em "Reativado por anúncio").
-- Antes: em 01-14/10 a FSX mostrava R$ 799 de caixa; com os reativados da hiperbárica, R$ 12,8 mil.
-- v3, 07/10/2026 — o dono do pagamento sai da mv_atribuicao_unica (régua única):
-- paciente de anúncio identificado vai para a agência que operava a conta no
-- dia em que ele chegou; "Meta sem id do anúncio" e Google Ads vão para
-- "Anúncio não identificado". `dc` = dia em que o paciente chegou. `fora` vai sempre 0.
with janela as (select (current_date - dias)::date as de),
cx as (
  select p.data_pagamento as dia, f.conta_id, p.valor_brl
  from feegow_invoice_payments p
  join feegow_invoices f on f.invoice_id = p.invoice_id
  cross join janela w
  where p.data_pagamento is not null and p.data_pagamento >= w.de
),
y as (
  select cx.dia, cx.valor_brl as v, m.canal, m.agencia, m.dia as chegou, m.reat_agencia, m.reat_dia,
         (m.reat_agencia is not null and cx.dia >= m.reat_dia
          and m.reat_agencia <> 'Não identificada'
          and m.reat_agencia is distinct from m.agencia
          and m.canal is distinct from 'Meta sem id do anúncio') as reat
  from cx join mv_atribuicao_unica m on m.conta_id = cx.conta_id
),
z as (
  select dia, v, reat,
         case when reat then reat_agencia
              when canal = 'Meta Ads' then coalesce(agencia, 'Não identificada')
              else 'Anúncio não identificado' end as ag,
         case when reat then reat_dia when canal = 'Meta Ads' then chegou end as dc,
         case when reat then canal end as ch
  from y
  where reat or canal in ('Meta Ads', 'Meta sem id do anúncio', 'Google Ads')
)
select coalesce(jsonb_agg(
         case when reat
              then jsonb_build_object('d', to_char(dia,'YYYY-MM-DD'), 'ag', ag, 'dc', to_char(dc,'YYYY-MM-DD'),
                                      'pgd', v, 'fora', 0, 'reat', true, 'ch', ch)
              else jsonb_build_object('d', to_char(dia,'YYYY-MM-DD'), 'ag', ag, 'dc', to_char(dc,'YYYY-MM-DD'),
                                      'pgd', v, 'fora', 0)
         end order by dia, ag, dc, reat), '[]'::jsonb)
from (
  select dia, ag, dc, reat, ch, round(sum(v), 2)::float8 as v
  from z group by 1, 2, 3, 4, 5
) t
where v <> 0;
$function$;
