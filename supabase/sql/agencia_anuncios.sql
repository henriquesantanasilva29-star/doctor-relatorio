-- agencia_anuncios(dias) — só na Doctor. Bloco `agencia_ads` do dados.json (tabela de anúncios da aba Canais).
CREATE OR REPLACE FUNCTION public.agencia_anuncios(dias integer DEFAULT 400)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
-- v4, 14/10/2026 — regra do Henrique (a mesma da agencia_serie v6.2): quem já era da base e
-- voltou pelo anúncio de outra agência é paciente do anúncio do clique. Linhas novas com
-- `reat` = true no dia do clique: xp (voltaram), xc (fecharam), xv/xpg (fechado/pago desde o
-- clique). O fechado do anúncio de chegada vai só até a véspera desse clique.
-- v3, 07/10/2026 — lead pelo telefone no primeiro anúncio (jornada_cache);
-- paciente e dinheiro pela mv_atribuicao_unica, a régua única da aba. Parado na mesa
-- só com proposta aguardando aprovação.
-- v2, 06/10/2026 — agência por vigência da conta no dia em que o lead chegou.
with janela as (select (current_date - dias)::date as de),
prim as (
  select distinct on (jc.tel8)
         jc.tel8, jc.anuncio_id, jc.dia, jc.card_id,
         agencia_no_dia(right(jc.anuncio_id, 4), jc.dia) as agencia
  from jornada_cache jc
  where jc.anuncio_id is not null and coalesce(jc.tel8,'') <> ''
  order by jc.tel8, jc.visto_em, jc.anuncio_id
),
lead as (
  select p.dia, p.anuncio_id, p.agencia, count(*)::int r,
         count(*) filter (where p.card_id is not null)::int k
  from prim p, janela w where p.dia >= w.de group by 1,2,3
),
pac as (
  select m.conta_id, m.dia, m.anuncio_id, m.agencia,
         case when m.reat_agencia is not null and m.reat_agencia <> 'Não identificada'
                   and m.reat_agencia is distinct from m.agencia
              then m.reat_dia end as corte
  from mv_atribuicao_unica m, janela w
  where m.canal = 'Meta Ads' and m.anuncio_id is not null and m.dia >= w.de
),
prop as (
  select pc.conta_id, count(*)::int o,
         count(*) filter (where pr.status_categoria = 'executada')::int e,
         count(*) filter (where pr.status_categoria = 'aguardando')::int ne,
         round(coalesce(sum(pr.value) filter (where pr.status_categoria = 'aguardando'),0),2) vne
  from pac pc join feegow_proposals pr on pr.feegow_patient_id = pc.conta_id and pr.proposal_date >= pc.dia
       and (pc.corte is null or pr.proposal_date < pc.corte)
  group by 1
),
fat as (
  select pc.conta_id, round(sum(i.valor_brl),2) v, round(sum(least(i.valor_pago_brl, i.valor_brl)),2) pg
  from pac pc join feegow_invoices i on i.conta_id = pc.conta_id and i.data_invoice >= pc.dia
       and (pc.corte is null or i.data_invoice < pc.corte)
  group by 1
),
din as (
  select pc.dia, pc.anuncio_id, pc.agencia, count(*)::int p,
         coalesce(sum(pp.o),0)::int o, coalesce(sum(pp.e),0)::int e,
         coalesce(sum(pp.ne),0)::int ne, round(coalesce(sum(pp.vne),0),2)::float8 vne,
         round(coalesce(sum(ff.v),0),2)::float8 v, round(coalesce(sum(ff.pg),0),2)::float8 pg
  from pac pc left join prop pp on pp.conta_id = pc.conta_id left join fat ff on ff.conta_id = pc.conta_id
  group by 1,2,3
),
reat as (
  select m.conta_id, m.reat_dia as dia, m.reat_anuncio as anuncio_id, m.reat_agencia as agencia
  from mv_atribuicao_unica m, janela w
  where m.reat_agencia is not null and m.reat_dia >= w.de and m.reat_anuncio is not null
    and m.reat_agencia <> 'Não identificada'
    and m.reat_agencia is distinct from m.agencia
    and m.canal is distinct from 'Meta sem id do anúncio'
),
rfat as (
  select r.conta_id, round(sum(i.valor_brl),2) v, round(sum(least(coalesce(i.valor_pago_brl,0), i.valor_brl)),2) pg
  from reat r join feegow_invoices i on i.conta_id = r.conta_id and i.data_invoice >= r.dia
  group by 1
),
rdin as (
  select r.dia, r.anuncio_id, r.agencia, count(*)::int xp,
         count(*) filter (where f.v > 0)::int xc,
         round(coalesce(sum(f.v),0),2)::float8 xv, round(coalesce(sum(f.pg),0),2)::float8 xpg
  from reat r left join rfat f on f.conta_id = r.conta_id
  group by 1,2,3
)
select
  (select coalesce(jsonb_agg(jsonb_build_object(
     'd', to_char(coalesce(l.dia, d.dia),'YYYY-MM-DD'), 'a', coalesce(l.anuncio_id, d.anuncio_id),
     'ag', coalesce(l.agencia, d.agencia),
     'r', coalesce(l.r,0), 'k', coalesce(l.k,0), 'p', coalesce(d.p,0), 'o', coalesce(d.o,0), 'e', coalesce(d.e,0),
     'v', coalesce(d.v,0), 'pg', coalesce(d.pg,0),
     'ab', round((coalesce(d.v,0) - coalesce(d.pg,0))::numeric,2)::float8,
     'ne', coalesce(d.ne,0), 'vne', coalesce(d.vne,0)
   ) order by coalesce(l.dia, d.dia), coalesce(l.anuncio_id, d.anuncio_id)), '[]'::jsonb)
   from lead l
   full join din d on d.dia = l.dia and d.anuncio_id = l.anuncio_id and d.agencia = l.agencia)
  ||
  (select coalesce(jsonb_agg(jsonb_build_object(
     'd', to_char(x.dia,'YYYY-MM-DD'), 'a', x.anuncio_id, 'ag', x.agencia, 'reat', true,
     'r', 0, 'p', 0, 'v', 0, 'pg', 0, 'ab', 0,
     'xp', x.xp, 'xc', x.xc, 'xv', x.xv, 'xpg', x.xpg
   ) order by x.dia, x.anuncio_id), '[]'::jsonb)
   from rdin x);
$function$;
