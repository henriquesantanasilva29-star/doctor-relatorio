-- Acesso (dfvmuqxjdcvwskrrdbfm). "Quem pagou no período" da aba Canais, lido na hora pela painel-canais
-- (action "rastro"). Copiado do banco em 12/10/2026, depois do patch que trouxe o nome do paciente.
-- Igual à da Doctor (rastro_periodo_doctor.sql), menos a unidade, que aqui vem da feegow_dim_unidade.
CREATE OR REPLACE FUNCTION public.rastro_periodo(p_de date, p_ate date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
-- 12/10/2026: NOME do paciente no fim (mesma fonte do aberto_periodo v4: Feegow e, na falta, CRM pela identidade do Feegow).
-- 15/10/2026: canal/ag/aid/dc/via pela v_atribuicao_segmento (quem voltou pelo anúncio: via 'reativacao').
-- [d, conta, pago, fat, canal, ag, aid, dc, via, reat_ag, reat_d, procs, uni, desde, base, nome]
with pag as (
  select f.conta_id, p.data_pagamento d, sum(p.valor_brl) pago,
         array_agg(distinct f.invoice_id) inv, min(f.unidade_id) uni
  from feegow_invoice_payments p join feegow_invoices f on f.invoice_id = p.invoice_id
  where p.data_pagamento between p_de and p_ate group by 1,2
),
fat as (
  select f.conta_id, f.data_invoice d, sum(f.valor_brl) fat,
         array_agg(distinct f.invoice_id) inv, min(f.unidade_id) uni
  from feegow_invoices f
  where f.data_invoice between p_de and least(p_ate, current_date) group by 1,2
),
dia as (
  select coalesce(p.conta_id, f.conta_id) conta, coalesce(p.d, f.d) d,
         coalesce(p.pago,0) pago, coalesce(f.fat,0) fat,
         array(select distinct unnest(coalesce(p.inv,'{}') || coalesce(f.inv,'{}'))) inv,
         coalesce(p.uni, f.uni) uni
  from pag p full join fat f on f.conta_id = p.conta_id and f.d = p.d
),
sel as (
  -- 15/10/2026: dono do dia pela v_atribuicao_segmento (a regra de origem do dash em um lugar só):
  -- a partir do clique de reativação, canal 'Meta Ads' e a agência do clique, via 'reativacao' e
  -- dc = dia do clique; antes dele, por onde o paciente chegou.
  select x.*, s.canal, s.agencia, s.anuncio_id, s.dia dc, s.via, m.reat_agencia, m.reat_dia, m.era_da_base
  from dia x
  left join v_atribuicao_segmento s on s.conta_id = x.conta
       and ((not s.reat and (s.ate is null or x.d < s.ate)) or (s.reat and x.d >= s.dia))
  left join mv_atribuicao_unica m on m.conta_id = x.conta
  where x.pago > 0 or (x.fat > 0 and s.canal in ('Meta Ads','Meta sem id do anúncio','Google Ads'))
),
procs as (
  select s.conta, s.d, string_agg(distinct coalesce(classifica_procedimento(o.nome),'Outros'), ', ') cats
  from sel s
  join feegow_invoice_items it on it.invoice_id = any(s.inv) and not coalesce(it.is_cancelado,false)
  left join feegow_procedures_official o on o.procedimento_id = it.procedimento_id
  group by 1,2
),
desde as (
  select z.conta, min(z.d) d from (
    select f.conta_id conta, f.data_invoice d from feegow_invoices f where f.conta_id in (select conta from sel)
    union all
    select p.feegow_patient_id, p.proposal_date from feegow_proposals p where p.feegow_patient_id in (select conta from sel)
  ) z group by 1
),
alvo_n as (select distinct conta from sel where conta is not null),
n_fp as (select p.feegow_patient_id conta, min(nullif(btrim(p.nome),'')) nome
         from feegow_pacientes p where p.feegow_patient_id in (select conta from alvo_n) group by 1),
n_f1 as (select p.paciente_id conta, min(nullif(btrim(p.nome),'')) nome
         from feegow_paciente p where p.paciente_id in (select conta from alvo_n) group by 1),
n_cp as (select cp.conta_id conta, min(nullif(btrim(pt.full_name),'')) nome
         from mv_conta_paciente cp join patients pt on pt.id::text = cp.patient_id
         where cp.conta_id in (select conta from alvo_n) group by 1),
n_pc as (select (pt.custom->>'feegow_patient_id') fid, min(nullif(btrim(pt.full_name),'')) nome
         from patients pt where pt.custom->>'feegow_patient_id' in (select conta::text from alvo_n) group by 1),
nm as (
  select a.conta, coalesce(fp.nome, f1.nome, cp.nome, pc.nome) nome
  from alvo_n a
  left join n_fp fp on fp.conta = a.conta
  left join n_f1 f1 on f1.conta = a.conta
  left join n_cp cp on cp.conta = a.conta
  left join n_pc pc on pc.fid = a.conta::text
)
select coalesce(jsonb_agg(jsonb_build_array(
  to_char(s.d,'YYYY-MM-DD'), s.conta, round(s.pago,2)::float8, round(s.fat,2)::float8,
  coalesce(s.canal, 'Sem rastreio (pré-CRM)'), s.agencia, s.anuncio_id, to_char(s.dc,'YYYY-MM-DD'),
  s.via, s.reat_agencia, to_char(s.reat_dia,'YYYY-MM-DD'), left(coalesce(pc.cats,''), 120),
  coalesce(replace(u.nome, 'Acesso Saúde ', ''), s.uni::text, ''),
  to_char(ds.d,'YYYY-MM-DD'), coalesce(s.era_da_base,false), nm.nome
) order by s.d desc, s.pago desc), '[]'::jsonb)
from sel s
left join procs pc on pc.conta = s.conta and pc.d = s.d
left join desde ds on ds.conta = s.conta
left join nm on nm.conta = s.conta
left join feegow_dim_unidade u on u.unidade_id = s.uni::text;
$function$
