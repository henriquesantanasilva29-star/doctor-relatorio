-- crm_procedimentos(dias) — Acesso. Bloco `crmproc` do dados.json. Igual à da Doctor desde 15/10/2026.
CREATE OR REPLACE FUNCTION public.crm_procedimentos(dias integer DEFAULT 400)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
-- v5, 15/10/2026 — par (paciente, anúncio) pela v_atribuicao_segmento (a regra de origem do dash em
-- um lugar só): quem já era da base e voltou pelo anúncio entra no anúncio do clique, com o que
-- fechou dali em diante; antes do clique fica no anúncio por onde chegou.
-- Na Acesso a v3 ainda lia a régua antiga (mv_paciente_anuncio, pelo patient_id do CRM) e a
-- proposta "parada" incluía a rejeitada; agora é a mesma função da Doctor.
-- v3 — mesmo rateio dos dois lados: executado e pago pelo item da fatura,
-- parado pelo item da proposta, ambos rateados contra o cabeçalho.
with pac as (
  select conta_id, anuncio_id, dia, ate from v_atribuicao_segmento
  where canal = 'Meta Ads' and anuncio_id is not null and dia >= (current_date - dias)
),
itens as (
  select distinct pc.dia, pc.anuncio_id, f.invoice_id, f.valor_brl fat_v,
         least(f.valor_pago_brl, f.valor_brl) fat_pg,
         it.item_id, it.procedimento_id, coalesce(it.quantidade,1)::numeric qtd,
         coalesce(it.is_cancelado,false) cancelado,
         (coalesce(it.valor_brl,0)*coalesce(it.quantidade,1)
          - coalesce(it.desconto_brl,0) + coalesce(it.acrescimo_brl,0)) liq
  from pac pc
  join feegow_invoices f on f.conta_id = pc.conta_id and f.data_invoice >= pc.dia
       and (pc.ate is null or f.data_invoice < pc.ate)
  join feegow_invoice_items it on it.invoice_id = f.invoice_id
),
tot as (
  select invoice_id, sum(liq) filter (where not cancelado) ativo, sum(liq) todos
  from itens group by 1
),
rate as (
  select i.dia, i.anuncio_id,
    coalesce(classifica_procedimento(o.nome), 'Outros procedimentos') cat,
    i.qtd, i.cancelado, i.fat_v, i.fat_pg,
    case when coalesce(t.ativo,0) > 0 then (case when i.cancelado then 0 else i.liq/t.ativo end)
         when coalesce(t.todos,0) <> 0 then i.liq/t.todos
         else 0 end peso
  from itens i join tot t on t.invoice_id = i.invoice_id
  left join feegow_procedures_official o on o.procedimento_id = i.procedimento_id
),
executado as (
  select dia, anuncio_id, cat,
    coalesce(sum(qtd) filter (where not cancelado),0)::int qe,
    round(sum(peso*fat_v),2)::float8 ve,
    round(sum(peso*fat_pg),2)::float8 vp
  from rate group by 1,2,3
),
prop as (
  select pc.dia, pc.anuncio_id, p.proposal_id, p.value::numeric prop_v
  from pac pc join feegow_proposals p on p.feegow_patient_id = pc.conta_id
  where p.proposal_date >= pc.dia and (pc.ate is null or p.proposal_date < pc.ate)
    and p.status_categoria = 'aguardando'
),
prop_item as (
  select pr.dia, pr.anuncio_id, pr.proposal_id, pr.prop_v,
         classifica_procedimento(btrim(e->>'nome')) cat,
         coalesce((e->>'quantidade')::numeric,1) qtd,
         coalesce((e->>'valor')::numeric,0)*coalesce((e->>'quantidade')::numeric,1)
           - coalesce((e->>'desconto')::numeric,0) + coalesce((e->>'acrescimo')::numeric,0) liq
  from prop pr join feegow_proposals p on p.proposal_id = pr.proposal_id
  cross join lateral jsonb_array_elements(coalesce(p.procedimentos->'data','[]'::jsonb)) e
  where nullif(btrim(e->>'nome'),'') is not null
),
prop_tot as (select proposal_id, sum(liq) tot from prop_item group by 1),
parado as (
  select pi.dia, pi.anuncio_id, pi.cat, sum(pi.qtd)::int qn,
         round(sum(case when coalesce(pt.tot,0) <> 0 then pi.liq/pt.tot*pi.prop_v else 0 end),2)::float8 vn
  from prop_item pi join prop_tot pt on pt.proposal_id = pi.proposal_id
  group by 1,2,3
  union all
  select pr.dia, pr.anuncio_id, 'Outros procedimentos', 0, round(sum(pr.prop_v),2)::float8
  from prop pr where not exists (select 1 from prop_item pi where pi.proposal_id = pr.proposal_id)
  group by 1,2,3
)
select coalesce(jsonb_agg(jsonb_build_object(
  'd', to_char(k.dia,'YYYY-MM-DD'), 'a', k.anuncio_id, 'c', k.cat,
  'qe', coalesce(k.qe,0), 've', coalesce(k.ve,0), 'vp', coalesce(k.vp,0),
  'qn', coalesce(k.qn,0), 'vn', coalesce(k.vn,0)) order by k.dia), '[]'::jsonb)
from (
  select coalesce(e.dia,n.dia) dia, coalesce(e.anuncio_id,n.anuncio_id) anuncio_id,
         coalesce(e.cat,n.cat) cat, e.qe, e.ve, e.vp,
         sum(n.qn) qn, sum(n.vn) vn
  from executado e
  full join (select dia, anuncio_id, cat, sum(qn) qn, sum(vn) vn from parado group by 1,2,3) n
    on n.dia=e.dia and n.anuncio_id=e.anuncio_id and n.cat=e.cat
  group by 1,2,3,4,5,6
) k
$function$;
