-- Aplicada nas duas bases (Doctor myiqdeonxuznvhtsvfxg e Acesso dfvmuqxjdcvwskrrdbfm) em 08/10/2026 (v2).
CREATE OR REPLACE FUNCTION public.aberto_periodo(p_de date, p_ate date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
-- 08/10/2026 — "Em aberto, paciente por paciente" da aba Canais (lido na hora pela painel-canais).
-- Uma linha por paciente com conta aberta no Feegow, pela MESMA régua do cartão:
--   'c' = chegou no período (mv_atribuicao_unica.dia), qualquer canal; contas desde o dia em que chegou.
--   'r' = chegou antes e foi REATIVADO por anúncio no período; contas desde o dia do clique.
-- aberto = valor - pago (pago limitado ao valor), somado nas contas desde o dia de referência — é o
-- "Falta pagar" do cartão da agência. Situação pelos itens das contas abertas (nesta ordem):
--   realizado = há item com valor já realizado e a conta não foi paga (cobrar)
--   marcado   = há item pendente com data de hoje em diante
--   passou    = há item pendente, com valor e com AGENDAMENTO, cuja data já passou (horário passou sem
--               atendimento). Item de valor zero (o horário de uma sessão de pacote) não conta.
--   sem_data  = o resto: conta aberta sem horário marcado (agendar). Item sem agendamento carrega
--               a data da própria conta no Feegow, que NÃO é horário — por isso não conta como "passou"
--               (v1 contava, e 40 pacientes apareciam como falta sem nunca terem tido horário).
-- [conta, tipo, agencia, canal, dia_ref, fechado, pago, aberto, situacao, data, unidade, anuncio,
--  reat_agencia, reat_dia, itens_pendentes]
with hoje as (select (now() at time zone 'America/Manaus')::date as d),
c as (
  select m.conta_id conta, 'c'::text tipo, m.agencia ag, m.canal, m.dia ref, m.anuncio_id aid,
         case when m.reat_dia between p_de and p_ate and m.reat_agencia is distinct from m.agencia
              then m.reat_agencia end rag,
         case when m.reat_dia between p_de and p_ate and m.reat_agencia is distinct from m.agencia
              then m.reat_dia end rdia
  from mv_atribuicao_unica m where m.dia between p_de and p_ate
),
r as (
  select m.conta_id, 'r'::text, m.reat_agencia, m.canal, m.reat_dia, m.reat_anuncio, m.reat_agencia, m.reat_dia
  from mv_atribuicao_unica m
  where m.reat_agencia is not null and m.reat_agencia is distinct from m.agencia
    and m.reat_dia between p_de and p_ate
    and m.conta_id not in (select conta from c)
),
base as (select * from c union all select * from r),
inv as (
  select b.conta, f.invoice_id, f.unidade_id, f.data_invoice, f.valor_brl v,
         least(coalesce(f.valor_pago_brl,0), f.valor_brl) pg
  from base b join feegow_invoices f on f.conta_id = b.conta and f.data_invoice >= b.ref
),
tot as (
  select conta, round(sum(v),2) v, round(sum(pg),2) pg, round(sum(v - pg),2) ab,
         min(unidade_id::text) filter (where v - pg > 0.005) uni
  from inv group by 1
),
itens as (
  select i.conta,
         count(*) filter (where it.is_executado and it.valor_brl > 0) n_exec,
         count(*) filter (where not coalesce(it.is_executado,false) and it.valor_brl > 0) n_pend,
         min(it.data_execucao::date) filter (where not coalesce(it.is_executado,false)
                                               and it.data_execucao::date >= h.d) prox,
         max(it.data_execucao::date) filter (where not coalesce(it.is_executado,false)
                                               and it.valor_brl > 0 and it.agendamento_id is not null
                                               and it.data_execucao::date < h.d) falta,
         max(it.data_execucao::date) filter (where it.is_executado and it.valor_brl > 0) ult_exec,
         min(i.data_invoice) aberta_em
  from inv i cross join hoje h
  join feegow_invoice_items it on it.invoice_id = i.invoice_id and not coalesce(it.is_cancelado,false)
  where i.v - i.pg > 0.005
  group by 1
)
select coalesce(jsonb_agg(jsonb_build_array(
  b.conta, b.tipo, b.ag, b.canal, to_char(b.ref,'YYYY-MM-DD'),
  t.v::float8, t.pg::float8, t.ab::float8,
  case when coalesce(it.n_exec,0) > 0 then 'realizado'
       when it.prox is not null then 'marcado'
       when it.falta is not null then 'passou'
       else 'sem_data' end,
  to_char(case when coalesce(it.n_exec,0) > 0 then it.ult_exec
               when it.prox is not null then it.prox
               when it.falta is not null then it.falta
               else it.aberta_em end,'YYYY-MM-DD'),
  coalesce(regexp_replace(u.nome, '^Unidade\s+', ''), t.uni, ''),
  b.aid, b.rag, to_char(b.rdia,'YYYY-MM-DD'), coalesce(it.n_pend,0)
) order by t.ab desc, b.conta), '[]'::jsonb)
from base b
join tot t on t.conta = b.conta
left join itens it on it.conta = b.conta
left join feegow_dim_unidade u on u.unidade_id::text = t.uni
where t.ab > 0.005;
$function$;
