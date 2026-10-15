-- agencia_anuncios(dias) — só na Doctor. Bloco `agencia_ads` do dados.json (tabela de anúncios da aba Canais).
CREATE OR REPLACE FUNCTION public.agencia_anuncios(dias integer DEFAULT 400)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
-- v5, 15/10/2026 — paciente e dinheiro pela v_atribuicao_segmento (a regra de origem do dash em um
-- lugar só). Cada anúncio já soma quem chegou por ele + quem já era da base e voltou por ele (do
-- clique em diante); xp/xc/xv/xpg dizem quanto disso é desses que voltaram. Sem linhas à parte.
-- v4, 14/10/2026 — reativação em linhas `reat` separadas.
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
  select s.conta_id, s.dia, s.anuncio_id, s.agencia, s.ate, s.reat, s.paciente
  from v_atribuicao_segmento s, janela w
  where s.canal = 'Meta Ads' and s.anuncio_id is not null and s.dia >= w.de
),
prop as (
  select pc.conta_id, pc.reat, count(*)::int o,
         count(*) filter (where pr.status_categoria = 'executada')::int e,
         count(*) filter (where pr.status_categoria = 'aguardando')::int ne,
         round(coalesce(sum(pr.value) filter (where pr.status_categoria = 'aguardando'),0),2) vne
  from pac pc join feegow_proposals pr on pr.feegow_patient_id = pc.conta_id and pr.proposal_date >= pc.dia
       and (pc.ate is null or pr.proposal_date < pc.ate)
  group by 1,2
),
fat as (
  select pc.conta_id, pc.reat, round(sum(i.valor_brl),2) v,
         round(sum(least(coalesce(i.valor_pago_brl,0), i.valor_brl)),2) pg
  from pac pc join feegow_invoices i on i.conta_id = pc.conta_id and i.data_invoice >= pc.dia
       and (pc.ate is null or i.data_invoice < pc.ate)
  group by 1,2
),
din as (
  select pc.dia, pc.anuncio_id, pc.agencia,
         count(*) filter (where pc.paciente)::int p,
         count(*) filter (where pc.reat)::int xp,
         count(*) filter (where pc.reat and pc.paciente)::int xc,
         coalesce(sum(pp.o),0)::int o, coalesce(sum(pp.e),0)::int e,
         coalesce(sum(pp.ne),0)::int ne, round(coalesce(sum(pp.vne),0),2)::float8 vne,
         round(coalesce(sum(ff.v),0),2)::float8 v, round(coalesce(sum(ff.pg),0),2)::float8 pg,
         round(coalesce(sum(ff.v) filter (where pc.reat),0),2)::float8 xv,
         round(coalesce(sum(ff.pg) filter (where pc.reat),0),2)::float8 xpg
  from pac pc left join prop pp on pp.conta_id = pc.conta_id and pp.reat = pc.reat
       left join fat ff on ff.conta_id = pc.conta_id and ff.reat = pc.reat
  group by 1,2,3
)
select coalesce(jsonb_agg(jsonb_build_object(
  'd', to_char(coalesce(l.dia, d.dia),'YYYY-MM-DD'), 'a', coalesce(l.anuncio_id, d.anuncio_id),
  'ag', coalesce(l.agencia, d.agencia),
  'r', coalesce(l.r,0) + coalesce(d.xp,0), 'k', coalesce(l.k,0), 'p', coalesce(d.p,0),
  'o', coalesce(d.o,0), 'e', coalesce(d.e,0),
  'v', coalesce(d.v,0), 'pg', coalesce(d.pg,0),
  'ab', round((coalesce(d.v,0) - coalesce(d.pg,0))::numeric,2)::float8,
  'ne', coalesce(d.ne,0), 'vne', coalesce(d.vne,0),
  'xp', coalesce(d.xp,0), 'xc', coalesce(d.xc,0), 'xv', coalesce(d.xv,0), 'xpg', coalesce(d.xpg,0)
) order by coalesce(l.dia, d.dia), coalesce(l.anuncio_id, d.anuncio_id)), '[]'::jsonb)
from lead l
full join din d on d.dia = l.dia and d.anuncio_id = l.anuncio_id and d.agencia = l.agencia;
$function$;
