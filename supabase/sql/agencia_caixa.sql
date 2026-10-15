-- agencia_caixa(dias) — igual nas duas bases (Doctor e Acesso). Lida pela publica-relatorio
-- (bloco `agencia_caixa` do dados.json) e pela aba Canais.
CREATE OR REPLACE FUNCTION public.agencia_caixa(dias integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
-- v5, 15/10/2026 — o dono do pagamento sai da v_atribuicao_segmento (a regra de origem do dash em
-- um lugar só, a mesma da canal_serie): a partir do clique, quem já era da base e voltou pelo
-- anúncio é da agência do clique (linha com `reat` = true, `dc` = dia do clique); antes do
-- clique, da chegada. Soma de pgd por agência + "Anúncio não identificado" = canal Meta Ads +
-- Meta sem id + Google Ads da canal_serie, no centavo.
-- v4, 14/10/2026 — mesma regra, escrita aqui dentro (com `ch`, que saiu).
-- v3, 07/10/2026 — o dono do pagamento sai da mv_atribuicao_unica (régua única):
-- paciente de anúncio identificado vai para a agência que operava a conta no
-- dia em que ele chegou; "Meta sem id do anúncio" e Google Ads vão para
-- "Anúncio não identificado". `dc` = dia em que o paciente chegou. `fora` vai sempre 0.
with janela as (select (current_date - dias)::date as de),
z as (
  select p.data_pagamento as dia, p.valor_brl as v, s.reat,
         case when s.canal = 'Meta Ads' then coalesce(s.agencia, 'Não identificada')
              else 'Anúncio não identificado' end as ag,
         case when s.canal = 'Meta Ads' then s.dia end as dc
  from feegow_invoice_payments p
  join feegow_invoices f on f.invoice_id = p.invoice_id
  join v_atribuicao_segmento s on s.conta_id = f.conta_id
       and ((not s.reat and (s.ate is null or p.data_pagamento < s.ate))
            or (s.reat and p.data_pagamento >= s.dia))
  cross join janela w
  where p.data_pagamento is not null and p.data_pagamento >= w.de
    and s.canal in ('Meta Ads', 'Meta sem id do anúncio', 'Google Ads')
)
select coalesce(jsonb_agg(
         case when reat
              then jsonb_build_object('d', to_char(dia,'YYYY-MM-DD'), 'ag', ag, 'dc', to_char(dc,'YYYY-MM-DD'),
                                      'pgd', v, 'fora', 0, 'reat', true)
              else jsonb_build_object('d', to_char(dia,'YYYY-MM-DD'), 'ag', ag, 'dc', to_char(dc,'YYYY-MM-DD'),
                                      'pgd', v, 'fora', 0)
         end order by dia, ag, dc, reat), '[]'::jsonb)
from (
  select dia, ag, dc, reat, round(sum(v), 2)::float8 as v
  from z group by 1, 2, 3, 4
) t
where v <> 0;
$function$;
