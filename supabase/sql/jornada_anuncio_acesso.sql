-- jornada_anuncio(dias) — Acesso. Bloco `jornada` do dados.json (funil por anúncio; a aba Canais monta
-- a série das agências da Acesso a partir dele).
CREATE OR REPLACE FUNCTION public.jornada_anuncio(dias integer DEFAULT 400)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
-- v6, 15/10/2026 — paciente e dinheiro pela v_atribuicao_segmento (a regra de origem do dash em um
-- lugar só, a mesma da canal_serie e da Doctor). Antes vinha de mv_paciente_anuncio, uma régua
-- antiga que não fechava com o canal Meta Ads (em 01-12/10: 69 pacientes aqui, 96 no canal). Agora
-- o anúncio soma quem chegou por ele + quem já era da base e voltou por ele (do clique em diante).
-- Lead `r` = contato do CRM criado com o anúncio no utm naquele dia (a Acesso não tem a
-- jornada_cache da Doctor) + quem voltou pelo anúncio.
-- v5 — a fatura é a fonte do faturado: v = pg + ab por construção.
with pac as (
  select conta_id, anuncio_id, dia, ate, reat, paciente from v_atribuicao_segmento
  where canal = 'Meta Ads' and anuncio_id is not null and dia >= (current_date - dias)
),
contato as (
  select c.id contato_id, (c.created_at_wts at time zone 'America/Manaus')::date dia,
         c.utm->>'sourceId' anuncio_id
  from helena_contacts c
  where c.utm->>'sourceId' ~ '^120[0-9]{14,17}$' and c.created_at_wts is not null
    and (c.created_at_wts at time zone 'America/Manaus')::date >= (current_date - dias)
),
lead as (select dia, anuncio_id, count(*)::int r from contato group by 1,2),
cards as (
  select ct.dia, ct.anuncio_id, count(*)::int n
  from contato ct join helena_cards k on k.contact_ids @> array[ct.contato_id] group by 1,2
),
pacd as (select dia, anuncio_id, count(*) filter (where paciente)::int p,
                count(*) filter (where reat)::int xp from pac group by 1,2),
prop as (
  select pc.dia, pc.anuncio_id, count(*)::int o,
    count(*) filter (where p.status_categoria = 'executada')::int e,
    round(coalesce(sum(p.value) filter (where p.status_categoria = 'executada'),0),2)::float8 v,
    count(*) filter (where p.status_categoria = 'aguardando')::int ne,
    round(coalesce(sum(p.value) filter (where p.status_categoria = 'aguardando'),0),2)::float8 vne,
    count(distinct pc.conta_id) filter (where p.status_categoria = 'executada')::int pexec
  from pac pc join feegow_proposals p on p.feegow_patient_id = pc.conta_id
  where p.proposal_date >= pc.dia and (pc.ate is null or p.proposal_date < pc.ate) group by 1,2
),
cobertura as (
  select pc.conta_id, pc.reat, (d->>'procedimento_id') proc,
         sum(case when (d->>'quantidade') ~ '^[0-9]+$' then (d->>'quantidade')::int else 1 end)::int qtd
  from pac pc join feegow_proposals p on p.feegow_patient_id = pc.conta_id
  cross join lateral jsonb_array_elements(p.procedimentos->'data') d
  where p.proposal_date >= pc.dia and (pc.ate is null or p.proposal_date < pc.ate)
    and p.status_categoria = 'executada'
    and jsonb_typeof(p.procedimentos->'data') = 'array'
  group by 1,2,3
),
agenda_ord as (
  select pc.dia, pc.anuncio_id, pc.conta_id, pc.reat, a.procedimento_id::text proc, a.valor_brl v,
         row_number() over (partition by pc.conta_id, pc.reat, a.procedimento_id
                            order by a.data_agendamento, a.agendamento_id) ordem
  from pac pc
  join mv_conta_paciente cp on cp.conta_id = pc.conta_id
  join v_feegow_agendamento_atual a on a.patient_id::text = cp.patient_id
  where a.data_agendamento >= pc.dia and (pc.ate is null or a.data_agendamento < pc.ate)
    and a.status_label in ('atendido','em_atendimento')
),
consulta as (
  select g.dia, g.anuncio_id, count(*)::int qc, round(coalesce(sum(g.v),0),2)::float8 vc
  from agenda_ord g
  left join cobertura c on c.conta_id = g.conta_id and c.reat = g.reat and c.proc = g.proc
  where g.ordem > coalesce(c.qtd, 0)
  group by 1,2
),
fat as (
  select pc.dia, pc.anuncio_id, count(*)::int nf,
    round(sum(f.valor_brl),2)::float8 v, round(sum(least(f.valor_pago_brl, f.valor_brl)),2)::float8 pg,
    round(sum(f.valor_brl - least(f.valor_pago_brl, f.valor_brl)),2)::float8 ab,
    count(distinct pc.conta_id)::int pconc
  from pac pc join feegow_invoices f on f.conta_id = pc.conta_id and f.data_invoice >= pc.dia
       and (pc.ate is null or f.data_invoice < pc.ate)
  group by 1,2
),
chaves as (select dia, anuncio_id from lead union select dia, anuncio_id from pacd)
select coalesce(jsonb_agg(jsonb_build_object(
  'd', to_char(k.dia,'YYYY-MM-DD'), 'a', k.anuncio_id,
  'r', coalesce(l.r,0) + coalesce(pd.xp,0), 'k', coalesce(c.n,0), 'p', coalesce(pd.p,0),
  'o', coalesce(pr.o,0), 'e', coalesce(pr.e,0),
  'v', coalesce(f.v,0), 'pg', coalesce(f.pg,0), 'ab', coalesce(f.ab,0), 'nf', coalesce(f.nf,0),
  'vprop', coalesce(pr.v,0), 'vcons', coalesce(cs.vc,0), 'qc', coalesce(cs.qc,0),
  'ne', coalesce(pr.ne,0), 'vne', coalesce(pr.vne,0),
  'pexec', coalesce(pr.pexec,0), 'pconc', coalesce(f.pconc,0)) order by k.dia), '[]'::jsonb)
from chaves k
left join lead l      on l.dia=k.dia and l.anuncio_id=k.anuncio_id
left join cards c     on c.dia=k.dia and c.anuncio_id=k.anuncio_id
left join pacd pd     on pd.dia=k.dia and pd.anuncio_id=k.anuncio_id
left join prop pr     on pr.dia=k.dia and pr.anuncio_id=k.anuncio_id
left join consulta cs on cs.dia=k.dia and cs.anuncio_id=k.anuncio_id
left join fat f       on f.dia=k.dia and f.anuncio_id=k.anuncio_id
$function$;
