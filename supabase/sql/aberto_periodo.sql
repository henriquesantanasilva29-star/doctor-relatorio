-- Aplicada nas duas bases (Doctor myiqdeonxuznvhtsvfxg e Acesso dfvmuqxjdcvwskrrdbfm) em 09/10/2026 (v4).
CREATE OR REPLACE FUNCTION public.aberto_periodo(p_de date, p_ate date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
-- v4, 09/10/2026 — NOME do paciente no fim da linha (decisão do Henrique: a aba só abre com login
--   de administrador, e cobrar exige saber quem é). Fonte, nesta ordem: feegow_pacientes,
--   feegow_paciente, CRM pela identidade do Feegow (mv_conta_paciente -> patients) e CRM pelo
--   feegow_patient_id do cadastro. Na Acesso o feegow_paciente só tem quem passou pela agenda;
--   o CRM cobre o resto. Nada disso vai para o dados.json publicado.
-- v3, 08/10/2026 — "Em aberto, paciente por paciente" da aba Canais (lido na hora pela painel-canais).
-- Uma linha por paciente com conta aberta no Feegow, pela MESMA régua do cartão:
--   'c' = chegou no período (mv_atribuicao_unica.dia), qualquer canal; contas desde o dia em que chegou.
--   'r' = chegou antes por OUTRO caminho e foi REATIVADO por anúncio no período; contas desde o clique.
--         Quem chegou por "Meta sem id do anúncio" (anúncio pago de agência desconhecida) não é
--         reativação: não dá para dizer que veio por outro caminho.
-- aberto = valor - pago (pago limitado ao valor), somado nas contas desde o dia de referência — é o
-- "Falta pagar" do cartão da agência.
-- SITUAÇÃO, nesta ordem, pelos itens das contas abertas e pela AGENDA (últimos eventos de agendamento
-- em `events`, os mesmos da v_feegow_agendamento_atual):
--   realizado = item com valor já feito, ou item cujo agendamento foi atendido (check-in/atendido)
--               sem a baixa no item -> cobrar
--   marcado   = o paciente tem horário de hoje em diante (agenda: marcado, confirmado, remarcado,
--               aguardando pagamento, ou já na clínica hoje) -> confirmar presença
--   passou    = item com valor e com agendamento cuja data passou sem atendimento -> remarcar.
--               `st` diz o que a agenda registra: nao_compareceu, desmarcado, cancelado ou sem_baixa
--               (ficou "marcado/confirmado" depois da data: faltou ou ninguém deu baixa)
--   sem_data  = o resto: conta aberta sem nenhum horário (agendar). Item sem agendamento carrega a data
--               da própria conta, que NÃO é horário — v1 contava como falta; v2 contava como "marcado"
--               quando a conta era de hoje.
-- [conta, tipo, agencia, canal, dia_ref, fechado, pago, aberto, situacao, data, unidade, anuncio,
--  reat_agencia, reat_dia, itens_pendentes, st, nome]
with hoje as (select (now() at time zone 'America/Manaus')::date as d),
c as (
  select m.conta_id conta, 'c'::text tipo, m.agencia ag, m.canal, m.dia ref, m.anuncio_id aid,
         case when m.reat_dia between p_de and p_ate and m.reat_agencia is distinct from m.agencia
                   and m.canal is distinct from 'Meta sem id do anúncio'
              then m.reat_agencia end rag,
         case when m.reat_dia between p_de and p_ate and m.reat_agencia is distinct from m.agencia
                   and m.canal is distinct from 'Meta sem id do anúncio'
              then m.reat_dia end rdia
  from mv_atribuicao_unica m where m.dia between p_de and p_ate
),
r as (
  select m.conta_id, 'r'::text, m.reat_agencia, m.canal, m.reat_dia, m.reat_anuncio, m.reat_agencia, m.reat_dia
  from mv_atribuicao_unica m
  where m.reat_agencia is not null and m.reat_agencia is distinct from m.agencia
    and m.canal is distinct from 'Meta sem id do anúncio'
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
-- nome: uma leitura por fonte, só das contas que ficam na lista
alvo as (select conta from tot where ab > 0.005),
n_fp as (select p.feegow_patient_id conta, min(nullif(btrim(p.nome),'')) nome
         from feegow_pacientes p where p.feegow_patient_id in (select conta from alvo) group by 1),
n_f1 as (select p.paciente_id conta, min(nullif(btrim(p.nome),'')) nome
         from feegow_paciente p where p.paciente_id in (select conta from alvo) group by 1),
n_cp as (select cp.conta_id conta, min(nullif(btrim(pt.full_name),'')) nome
         from mv_conta_paciente cp join patients pt on pt.id::text = cp.patient_id
         where cp.conta_id in (select conta from alvo) group by 1),
n_pc as (select (pt.custom->>'feegow_patient_id') fid, min(nullif(btrim(pt.full_name),'')) nome
         from patients pt where pt.custom->>'feegow_patient_id' in (select conta::text from alvo) group by 1),
nm as (
  select a.conta, coalesce(fp.nome, f1.nome, cp.nome, pc.nome) nome
  from alvo a
  left join n_fp fp on fp.conta = a.conta
  left join n_f1 f1 on f1.conta = a.conta
  left join n_cp cp on cp.conta = a.conta
  left join n_pc pc on pc.fid = a.conta::text
),
it as (
  select i.conta, i.data_invoice, x.agendamento_id::text ag_id, x.valor_brl valor,
         coalesce(x.is_executado,false) feito, x.data_execucao::date dex
  from inv i
  join feegow_invoice_items x on x.invoice_id = i.invoice_id and not coalesce(x.is_cancelado,false)
  where i.v - i.pg > 0.005
),
abertas as (select distinct conta from it),
-- agenda: todo agendamento do paciente (pelo paciente_id do Feegow) e os ligados aos itens
ag_ids as (
  select distinct e.payload->>'agendamento_id' ag_id
  from events e
  where e.type in ('appointment_created','appointment_canceled','consultation_done','check_in_done')
    and e.payload->>'paciente_id' in (select conta::text from abertas)
  union
  select ag_id from it where ag_id is not null
),
ev as (
  select distinct on (e.payload->>'agendamento_id')
         e.payload->>'agendamento_id' ag_id, e.payload->>'status_id' st,
         parse_feegow_date(e.payload->>'data') dt
  from events e join ag_ids a on a.ag_id = e.payload->>'agendamento_id'
  where e.type in ('appointment_created','appointment_canceled','consultation_done','check_in_done')
  order by e.payload->>'agendamento_id', e.occurred_at desc
),
ev_pac as (
  select distinct (e.payload->>'paciente_id') pac, e.payload->>'agendamento_id' ag_id
  from events e
  where e.type in ('appointment_created','appointment_canceled','consultation_done','check_in_done')
    and e.payload->>'paciente_id' in (select conta::text from abertas)
),
prox_ag as (
  select p.pac, min(v2.dt) dt
  from ev_pac p join ev v2 on v2.ag_id = p.ag_id cross join hoje h
  where v2.dt >= h.d and v2.st in ('1','7','15','208','2','4','5')
  group by 1
),
sit as (
  select a.conta,
    count(*) filter (where (t.feito and t.valor > 0)
                        or (not t.feito and v.st in ('2','3','4','5'))) n_real,
    max(case when t.feito and t.valor > 0 then t.dex
             when not t.feito and v.st in ('2','3','4','5') then coalesce(v.dt, t.dex) end) dt_real,
    count(*) filter (where not t.feito and t.valor > 0) n_pend,
    -- horário de hoje em diante: na agenda (qualquer agendamento do paciente) ou no item agendado
    least(
      pa.dt,
      min(t.dex) filter (where not t.feito and t.ag_id is not null and t.dex >= (select d from hoje)
                           and coalesce(v.st,'1') in ('1','7','15','208','2','4','5'))
    ) prox,
    max(coalesce(v.dt, t.dex)) filter (where not t.feito and t.valor > 0 and t.ag_id is not null
                                         and coalesce(v.dt, t.dex) < (select d from hoje)
                                         and coalesce(v.st,'') not in ('2','3','4','5')) falta,
    (array_agg(case when v.st = '6' then 'nao_compareceu'
                    when v.st = '11' then 'desmarcado'
                    when v.st in ('22','900') then 'cancelado'
                    else 'sem_baixa' end
               order by coalesce(v.dt, t.dex) desc)
       filter (where not t.feito and t.valor > 0 and t.ag_id is not null
                 and coalesce(v.dt, t.dex) < (select d from hoje)
                 and coalesce(v.st,'') not in ('2','3','4','5')))[1] st_falta,
    min(t.data_invoice) aberta_em
  from abertas a
  join it t on t.conta = a.conta
  left join ev v on v.ag_id = t.ag_id
  left join prox_ag pa on pa.pac = a.conta::text
  group by a.conta, pa.dt
)
select coalesce(jsonb_agg(jsonb_build_array(
  b.conta, b.tipo, b.ag, b.canal, to_char(b.ref,'YYYY-MM-DD'),
  t.v::float8, t.pg::float8, t.ab::float8,
  case when coalesce(s.n_real,0) > 0 then 'realizado'
       when s.prox is not null then 'marcado'
       when s.falta is not null then 'passou'
       else 'sem_data' end,
  to_char(case when coalesce(s.n_real,0) > 0 then s.dt_real
               when s.prox is not null then s.prox
               when s.falta is not null then s.falta
               else s.aberta_em end,'YYYY-MM-DD'),
  coalesce(regexp_replace(u.nome, '^Unidade\s+', ''), t.uni, ''),
  b.aid, b.rag, to_char(b.rdia,'YYYY-MM-DD'), coalesce(s.n_pend,0),
  case when coalesce(s.n_real,0) = 0 and s.prox is null and s.falta is not null then s.st_falta end,
  nm.nome
) order by t.ab desc, b.conta), '[]'::jsonb)
from base b
join tot t on t.conta = b.conta
left join sit s on s.conta = b.conta
left join nm on nm.conta = b.conta
left join feegow_dim_unidade u on u.unidade_id::text = t.uni
where t.ab > 0.005;
$function$;
