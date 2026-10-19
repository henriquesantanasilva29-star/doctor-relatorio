-- canal_serie(dias) — Doctor. Bloco `canais` do dados.json.
CREATE OR REPLACE FUNCTION public.canal_serie(dias integer DEFAULT 400)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
-- 19/10/2026: caixa (pgd/nqd) pela régua do Resumo faturamento — ver o CTE `caixa`.
-- 16/10/2026: número de WhatsApp de agência (meta_numero_agencia; hoje o 5700 → conta 0397, FSX, desde
-- 01/10). Contato NOVO cuja 1ª conversa foi nesse número e que não tem anúncio identificado conta em
-- "Meta Ads" (a mesma regra que a v_atribuicao_segmento aplica ao paciente). Base importada fica fora.
-- 15/10/2026 (tarde): o pagamento segue a FATURA — fatura aberta antes do clique de reativação é da
-- chegada, mesmo paga depois (antes contava pela data do pagamento e dava à agência do clique um
-- dinheiro de venda feita antes dele).
-- v3, 15/10/2026 — paciente, proposta, faturado, agenda e caixa pela v_atribuicao_segmento (a regra
-- de origem do dash em um lugar só): quem já era da base e voltou pelo anúncio conta em "Meta Ads"
-- a partir do clique; antes do clique, no canal por onde tinha chegado.
-- v2, 07/10/2026 — paciente, proposta, faturado, agenda e caixa pela
-- mv_atribuicao_unica (régua única da aba Canais, a mesma das agências e da tabela de
-- campanhas). Contato e chegada (ct, ctp, ch, pes, k) continuam por contato do CRM.
-- Parado na mesa (ne/vne) só com proposta aguardando aprovação.
with pac as (
  select conta_id, canal, dia, ate, reat, paciente from v_atribuicao_segmento
  where dia >= (current_date - dias)
),
ad1 as (
  -- o utm guarda o ÚLTIMO anúncio clicado: só vale para o dia da criação do
  -- contato se o anúncio já existia (07/10/2026)
  select i.anuncio_id, (min(i.data)::timestamp at time zone 'America/Manaus') inicio
  from meta_insights_dia i where i.nivel = 'ad' and i.anuncio_id is not null group by 1
),
prim_num as (
  -- 1ª conversa de cada contato, quando foi num número de agência dentro da vigência
  select f.contact_id, f.d
  from (select distinct on (s.contact_id) s.contact_id, s.channel_id,
               (s.created_at_wts at time zone 'America/Manaus')::date d
        from helena_sessions s where s.created_at_wts is not null
        order by s.contact_id, s.created_at_wts) f
  join helena_channels hc on hc.id::text = f.channel_id
  join meta_numero_agencia n on n.numero = right(hc.phone_digits, 4)
       and f.d >= n.vigente_de and f.d <= coalesce(n.vigente_ate, 'infinity'::date)
),
cls0 as (
  select c.id contato_id,
         (c.created_at_wts at time zone 'America/Manaus')::date dia,
         case
           when classifica_canal(case when a1.inicio is not null and c.created_at_wts < a1.inicio - interval '1 day' then '{}'::jsonb else c.utm end, c.origin) not in ('Meta Ads','Meta sem id do anúncio','Google Ads')
            and exists (
              select 1 from origem_anuncio o
              where o.telefone8 = right(c.phone_digits, 8)
                and (o.ocorrido_em at time zone 'America/Manaus')::date
                    between ((c.created_at_wts at time zone 'America/Manaus'))::date - 1
                        and ((c.created_at_wts at time zone 'America/Manaus'))::date + 1)
           then 'Meta Ads'
           else classifica_canal(case when a1.inicio is not null and c.created_at_wts < a1.inicio - interval '1 day' then '{}'::jsonb else c.utm end, c.origin)
         end canal
  from helena_contacts c
  left join ad1 a1 on a1.anuncio_id = c.utm->>'sourceId'
  where c.created_at_wts is not null
),
cls as (
  select c0.contato_id, c0.dia,
         case when pn.contact_id is not null and c0.canal not in ('Meta Ads','Google Ads','Base importada')
                   and pn.d between c0.dia - 1 and c0.dia + 1
              then 'Meta Ads' else c0.canal end canal
  from cls0 c0 left join prim_num pn on pn.contact_id = c0.contato_id
),
contato as (
  select cl.dia, cl.canal, cl.contato_id,
         (x.patient_id is not null) virou
  from cls cl
  left join mv_contato_paciente x on x.helena_contact_id = cl.contato_id
  where cl.dia >= (current_date - dias)
),
ct as (
  select dia, canal, count(*)::int ct, count(*) filter (where virou)::int ctp
  from contato group by 1,2
),
cheg as (
  select (s.created_at_wts at time zone 'America/Manaus')::date dia,
         cl.canal,
         count(*)::int ch,
         count(distinct s.contact_id)::int pes
  from helena_sessions s
  join cls cl on cl.contato_id = s.contact_id
  where s.created_at_wts is not null
    and (s.created_at_wts at time zone 'America/Manaus')::date >= (current_date - dias)
  group by 1,2
),
caixa as (
  -- 19/10/2026: RECEBIDO = régua do Resumo faturamento (o "SEM DOC" da meta): crédito do caixa
  -- (feegow_movimento, cd 'C', forma sem DOC) pela data do movimento. O dono é o paciente da fatura
  -- que o movimento quita: no trecho de reativação se a fatura é do clique em diante; antes, no de
  -- chegada. Movimento sem fatura no espelho cai em 'Sem rastreio' — a soma é sempre a do caixa.
  select m.data as dia,
         coalesce(s.canal, 'Sem rastreio (pré-CRM)') as canal,
         count(*)::int nqd,
         round(sum(m.valor),2)::float8 pgd
  from feegow_movimento m
  left join feegow_invoices f on f.invoice_id = (case when m.numero_invoice ~ '^[0-9]+$' then m.numero_invoice::bigint end)
  left join v_atribuicao_segmento s on s.conta_id = f.conta_id
       and ((not s.reat and (s.ate is null or f.data_invoice < s.ate))
            or (s.reat and f.data_invoice >= s.dia))
  where m.cd = 'C' and coalesce(m.forma, '') !~* 'doc' and m.data >= (current_date - dias)
  group by 1,2
),
pacd as (select dia, canal, count(*) filter (where paciente)::int p from pac group by 1,2),
base as (
  select dia, canal from ct
  union select dia, canal from cheg
  union select dia, canal from caixa
  union select dia, canal from pacd
),
cards as (
  select ct.dia, ct.canal, count(*)::int n
  from contato ct join helena_cards k on k.contact_ids @> array[ct.contato_id]
  group by 1,2
),
prop as (
  select pc.dia, pc.canal, count(*)::int o,
    count(*) filter (where p.status_categoria = 'executada')::int e,
    count(*) filter (where p.status_categoria = 'aguardando')::int ne,
    round(coalesce(sum(p.value) filter (where p.status_categoria = 'aguardando'),0),2)::float8 vne,
    round(coalesce(sum(p.value) filter (where p.status_categoria = 'executada'),0),2)::float8 vprop
  from pac pc join feegow_proposals p on p.feegow_patient_id = pc.conta_id
  where p.proposal_date >= pc.dia and (pc.ate is null or p.proposal_date < pc.ate) group by 1,2
),
fat as (
  select pc.dia, pc.canal, count(*)::int nf,
    round(sum(f.valor_brl),2)::float8 v, round(sum(least(f.valor_pago_brl, f.valor_brl)),2)::float8 pg,
    round(sum(f.valor_brl - least(f.valor_pago_brl, f.valor_brl)),2)::float8 ab,
    count(distinct pc.conta_id)::int pf
  from pac pc join feegow_invoices f on f.conta_id = pc.conta_id and f.data_invoice >= pc.dia
       and (pc.ate is null or f.data_invoice < pc.ate)
  group by 1,2
),
ag as (
  select pc.dia, pc.canal, count(*)::int qa,
         count(*) filter (where a.status_label in ('atendido','em_atendimento'))::int qat
  from pac pc
  join mv_conta_paciente cp on cp.conta_id = pc.conta_id
  join v_feegow_agendamento_atual a on a.patient_id::text = cp.patient_id
  where a.data_agendamento >= pc.dia and (pc.ate is null or a.data_agendamento < pc.ate) group by 1,2
)
select coalesce(jsonb_agg(jsonb_build_object(
  'd', to_char(b.dia,'YYYY-MM-DD'), 'c', b.canal,
  'ch', coalesce(cg.ch,0), 'pes', coalesce(cg.pes,0),
  'ct', coalesce(ct.ct,0), 'ctp', coalesce(ct.ctp,0),
  'k', coalesce(kd.n,0), 'p', coalesce(pd.p,0),
  'o', coalesce(pr.o,0), 'e', coalesce(pr.e,0),
  'ne', coalesce(pr.ne,0), 'vne', coalesce(pr.vne,0), 'vprop', coalesce(pr.vprop,0),
  'v', coalesce(f.v,0), 'pg', coalesce(f.pg,0), 'ab', coalesce(f.ab,0),
  'nf', coalesce(f.nf,0), 'pf', coalesce(f.pf,0),
  'qa', coalesce(ag.qa,0), 'qat', coalesce(ag.qat,0),
  'pgd', coalesce(cx.pgd,0), 'nqd', coalesce(cx.nqd,0)) order by b.dia), '[]'::jsonb)
from base b
left join ct       on ct.dia=b.dia and ct.canal=b.canal
left join cheg cg  on cg.dia=b.dia and cg.canal=b.canal
left join cards kd on kd.dia=b.dia and kd.canal=b.canal
left join pacd  pd on pd.dia=b.dia and pd.canal=b.canal
left join prop  pr on pr.dia=b.dia and pr.canal=b.canal
left join fat   f  on f.dia=b.dia  and f.canal=b.canal
left join ag       on ag.dia=b.dia and ag.canal=b.canal
left join caixa cx on cx.dia=b.dia and cx.canal=b.canal
$function$;
