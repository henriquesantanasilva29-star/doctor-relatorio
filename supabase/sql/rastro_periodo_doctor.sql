-- Doctor (myiqdeonxuznvhtsvfxg). "Quem pagou no período" da aba Canais, lido na hora pela painel-canais
-- (action "rastro"). Copiado do banco em 12/10/2026, depois do patch que trouxe o nome do paciente.
-- A Acesso tem a mesma função com a unidade pela feegow_dim_unidade: ver rastro_periodo_acesso.sql.
CREATE OR REPLACE FUNCTION public.rastro_periodo(p_de date, p_ate date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
-- 19/10/2026: PAGO = a régua do Resumo faturamento (o "SEM DOC" da meta). Crédito do caixa
-- (feegow_movimento, cd 'C', forma sem DOC) pela data do movimento — antes eram os pagamentos das
-- faturas (feegow_invoice_payments), que traziam o DOC pelo valor do Feegow e pagamento sem caixa.
-- O dono do dinheiro é o paciente da fatura que o movimento quita (numero_invoice); movimento sem
-- fatura no espelho fica sem paciente ('Sem rastreio'), mas não sai da soma.
-- 12/10/2026: NOME do paciente no fim (mesma fonte do aberto_periodo v4: Feegow e, na falta, CRM pela identidade do Feegow).
-- 15/10/2026: canal/ag/aid/dc/via pela v_atribuicao_segmento (quem voltou pelo anúncio: via 'reativacao').
-- [d, conta, pago, fat, canal, ag, aid, dc, via, reat_ag, reat_d, procs, uni, desde, base, nome, itens]
-- 16/10/2026: ITENS = com o que foi recebido, só nas linhas de anúncio (Meta Ads, Meta sem id, Google
-- Ads): cada pagamento do dia rateado pelos itens não cancelados da fatura que ele paga, pelo valor da
-- linha (valor × quantidade − desconto + acréscimo; fatura com itens sem valor: partes iguais).
-- [[categoria, procedimento, valor], ...] — a soma fecha com o `pago` da linha.
-- adrow/peso/itens MATERIALIZED: sem isso o plano refazia o rateio linha a linha (10 s; assim, 0,5 s).
-- 15/10/2026 (tarde): o pagamento segue a FATURA — fatura aberta a partir do clique de reativação
-- é do trecho de reativação; a de antes, mesmo paga depois, é da chegada. Uma linha por
-- (paciente, dia, trecho).
with mov as materialized (
  -- o caixa SEM DOC do Resumo faturamento (fn_feegow_dia.cx_sem_doc), linha a linha
  select m.data d, m.valor, m.unidade_id,
         case when m.numero_invoice ~ '^[0-9]+$' then m.numero_invoice::bigint end invoice_id
  from feegow_movimento m
  where m.cd = 'C' and coalesce(m.forma, '') !~* 'doc' and m.data between p_de and p_ate
),
pag as (
  select f.conta_id, mv.d, (s.conta_id is not null) reat, sum(mv.valor) pago,
         array_agg(distinct f.invoice_id) filter (where f.invoice_id is not null) inv, min(mv.unidade_id) uni
  from mov mv left join feegow_invoices f on f.invoice_id = mv.invoice_id
  left join v_atribuicao_segmento s on s.conta_id = f.conta_id and s.reat and f.data_invoice >= s.dia
  group by 1,2,3
),
fat as (
  select f.conta_id, f.data_invoice d, (s.conta_id is not null) reat, sum(f.valor_brl) fat,
         array_agg(distinct f.invoice_id) inv, min(f.unidade_id) uni
  from feegow_invoices f
  left join v_atribuicao_segmento s on s.conta_id = f.conta_id and s.reat and f.data_invoice >= s.dia
  where f.data_invoice between p_de and least(p_ate, current_date) group by 1,2,3
),
dia as (
  select coalesce(p.conta_id, f.conta_id) conta, coalesce(p.d, f.d) d, coalesce(p.reat, f.reat) reat,
         coalesce(p.pago,0) pago, coalesce(f.fat,0) fat,
         array(select distinct unnest(coalesce(p.inv,'{}') || coalesce(f.inv,'{}'))) inv,
         coalesce(p.uni, f.uni) uni
  from pag p full join fat f on f.conta_id = p.conta_id and f.d = p.d and f.reat = p.reat
),
sel as (
  -- 15/10/2026: dono do dia pela v_atribuicao_segmento (a regra de origem do dash em um lugar só):
  -- a partir do clique de reativação, canal 'Meta Ads' e a agência do clique, via 'reativacao' e
  -- dc = dia do clique; antes dele, por onde o paciente chegou.
  select x.*, s.canal, s.agencia, s.anuncio_id, s.dia dc, s.via, m.reat_agencia, m.reat_dia, m.era_da_base
  from dia x
  left join v_atribuicao_segmento s on s.conta_id = x.conta and s.reat = x.reat
  left join mv_atribuicao_unica m on m.conta_id = x.conta
  where x.pago > 0 or (x.fat > 0 and s.canal in ('Meta Ads','Meta sem id do anúncio','Google Ads'))
),
procs as (
  select s.conta, s.d, s.reat, string_agg(distinct coalesce(classifica_procedimento(o.nome),'Outros'), ', ') cats
  from sel s
  join feegow_invoice_items it on it.invoice_id = any(s.inv) and not coalesce(it.is_cancelado,false)
  left join feegow_procedures_official o on o.procedimento_id = it.procedimento_id
  group by 1,2,3
),
adrow as materialized (
  select s.conta, s.d, s.reat, s.inv from sel s
  where s.pago > 0 and s.canal in ('Meta Ads','Meta sem id do anúncio','Google Ads')
),
peso as materialized (
  select it.invoice_id, coalesce(classifica_procedimento(o.nome),'Outros') cat,
         coalesce(o.nome, nullif(btrim(it.descricao),''), 'Item sem nome') nome,
         case when sum(greatest(it.valor_brl*coalesce(it.quantidade,1) - coalesce(it.desconto_brl,0) + coalesce(it.acrescimo_brl,0), 0))
                     over (partition by it.invoice_id) > 0
              then greatest(it.valor_brl*coalesce(it.quantidade,1) - coalesce(it.desconto_brl,0) + coalesce(it.acrescimo_brl,0), 0)
                   / sum(greatest(it.valor_brl*coalesce(it.quantidade,1) - coalesce(it.desconto_brl,0) + coalesce(it.acrescimo_brl,0), 0))
                     over (partition by it.invoice_id)
              else 1.0 / count(*) over (partition by it.invoice_id) end fr
  from (select distinct unnest(inv) invoice_id from adrow) v
  join feegow_invoice_items it on it.invoice_id = v.invoice_id and not coalesce(it.is_cancelado,false)
  left join feegow_procedures_official o on o.procedimento_id = it.procedimento_id
),
itens as materialized (
  -- os créditos do caixa do dia das faturas da linha são exatamente o `pago` dela: as faturas de `inv` são
  -- todas do mesmo trecho (chegada ou reativação), que é como a linha foi montada.
  select z.conta, z.d, z.reat, jsonb_agg(jsonb_build_array(z.cat, z.nome, round(z.valor,2)::float8) order by z.valor desc) it
  from (
    select a.conta, a.d, a.reat, coalesce(w.cat,'Sem item') cat, coalesce(w.nome,'Pagamento sem item na fatura') nome,
           sum(p.valor * coalesce(w.fr,1)) valor
    from adrow a
    cross join lateral unnest(a.inv) i(invoice_id)
    join mov p on p.invoice_id = i.invoice_id and p.d = a.d
    left join peso w on w.invoice_id = p.invoice_id
    group by 1,2,3,4,5
  ) z
  group by 1,2,3
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
  case s.uni when 0 then 'Centro' when 2 then 'Grande Circular' when 4 then 'Vieiralves'
             else coalesce(s.uni::text,'') end,
  to_char(ds.d,'YYYY-MM-DD'), coalesce(s.era_da_base,false), nm.nome, itn.it
) order by s.d desc, s.pago desc), '[]'::jsonb)
from sel s
left join procs pc on pc.conta = s.conta and pc.d = s.d and pc.reat = s.reat
left join desde ds on ds.conta = s.conta
left join itens itn on itn.conta = s.conta and itn.d = s.d and itn.reat = s.reat
left join nm on nm.conta = s.conta;
$function$
