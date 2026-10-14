-- agencia_serie(dias) — só na Doctor. Lida pela publica-relatorio (bloco `agencias` do dados.json).
CREATE OR REPLACE FUNCTION public.agencia_serie(dias integer DEFAULT 400)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
-- v6.2, 14/10/2026 — regra do Henrique: quem chegou pelo anúncio da agência e fechou é paciente
--   daquela agência. Paciente reativado por anúncio de OUTRA agência leva o que fechou a partir
--   do dia do clique para a agência do clique (xp/xc/xv/xpg, como já era) e esse valor sai da
--   agência de chegada (v/pg/nf e propostas só até a véspera do clique) — antes o mesmo fechamento
--   contava nas duas (ex.: chegou pela VX em setembro, clicou na FSX em 05/10 e fechou a
--   hiperbárica no mesmo dia). Clique em post da página ("Não identificada") não reativa.
--   `sv`/`spg` = o fechado/pago que saiu da agência de chegada para a do clique (a aba usa para
--   fechar a sobra dos canais pagos, que continuam contando pela chegada).
-- v6.1, 08/10/2026 — reativação não conta quem chegou por "Meta sem id do anúncio" (anúncio pago
--   de agência desconhecida: não dá para dizer que veio por outro caminho; 32 contas na base) e o
--   pago nulo no Feegow passa a valer zero (antes contava como pago integral; hoje não há nenhum).
-- v6, 07/10/2026 — grão (dia, agência, CONTA) e REATIVAÇÃO.
--   `suf` (sufixo do anúncio = conta) deixa a agência com mais de uma conta ser lida
--   conta a conta: a FSX opera a hiperbárica (0397, coletada) e a odonto da Doctor
--   (0085, não coletada). Somar por agência dá exatamente o mesmo da v5.
--   `xp/xc/xv/xpg` = reativação: paciente que chegou por OUTRO caminho (orgânico,
--   equipe ou anúncio de outra agência) e depois clicou num anúncio desta agência —
--   quantos, quantos compraram, o fechado e o pago desde o dia do clique. Fica fora
--   de r/p/v/pg (régua de chegada). Clique de novo em anúncio da MESMA agência não é
--   reativação dela.
-- v5, 07/10/2026 — paciente e dinheiro pela mv_atribuicao_unica (régua única).
-- v4, 06/10/2026 — agência por VIGÊNCIA (agencia_no_dia / meta_agencia_periodo).
with janela as (select (current_date - dias)::date as de),
prim as (
  select distinct on (jc.tel8)
         jc.tel8, jc.anuncio_id, jc.dia, jc.card_id, jc.origem_do_id as via,
         agencia_no_dia(right(jc.anuncio_id, 4), jc.dia) as agencia
  from jornada_cache jc
  where jc.anuncio_id is not null and coalesce(jc.tel8,'') <> ''
  order by jc.tel8, jc.visto_em, jc.anuncio_id
),
lead as (
  select p.dia, p.agencia, right(p.anuncio_id, 4) as suf, count(*)::int r,
         count(*) filter (where p.via = 'evolution')::int rev,
         count(*) filter (where p.card_id is not null)::int k
  from prim p, janela w where p.dia >= w.de group by 1,2,3
),
pac as (
  select m.conta_id, m.dia, m.agencia, right(m.anuncio_id, 4) as suf,
         case when m.reat_agencia is not null and m.reat_agencia <> 'Não identificada'
                   and m.reat_agencia is distinct from m.agencia
              then m.reat_dia end as corte
  from mv_atribuicao_unica m, janela w
  where m.canal = 'Meta Ads' and m.agencia is not null and m.dia >= w.de
),
prop as (
  select pc.conta_id, count(*)::int o,
         count(*) filter (where pr.status_categoria = 'executada')::int e,
         round(coalesce(sum(pr.value) filter (where pr.status_categoria = 'executada'),0),2) vexec,
         count(*) filter (where pr.status_categoria = 'aguardando')::int ne,
         round(coalesce(sum(pr.value) filter (where pr.status_categoria = 'aguardando'),0),2) vne
  from pac pc join feegow_proposals pr on pr.feegow_patient_id = pc.conta_id and pr.proposal_date >= pc.dia
       and (pc.corte is null or pr.proposal_date < pc.corte)
  group by 1
),
fat as (
  select pc.conta_id,
         (count(distinct i.invoice_id) filter (where pc.corte is null or i.data_invoice < pc.corte))::int nf,
         round(coalesce(sum(i.valor_brl) filter (where pc.corte is null or i.data_invoice < pc.corte),0),2) v,
         round(coalesce(sum(least(coalesce(i.valor_pago_brl,0), i.valor_brl))
                        filter (where pc.corte is null or i.data_invoice < pc.corte),0),2) pg,
         round(coalesce(sum(i.valor_brl) filter (where i.data_invoice >= pc.corte),0),2) sv,
         round(coalesce(sum(least(coalesce(i.valor_pago_brl,0), i.valor_brl))
                        filter (where i.data_invoice >= pc.corte),0),2) spg
  from pac pc join feegow_invoices i on i.conta_id = pc.conta_id and i.data_invoice >= pc.dia
  group by 1
),
din as (
  select pc.dia, pc.agencia, pc.suf, count(*)::int p,
         coalesce(sum(pp.o),0)::int o, coalesce(sum(pp.e),0)::int e,
         round(coalesce(sum(pp.vexec),0),2)::float8 vexec,
         coalesce(sum(pp.ne),0)::int ne, round(coalesce(sum(pp.vne),0),2)::float8 vne,
         coalesce(sum(ff.nf),0)::int nf,
         round(coalesce(sum(ff.v),0),2)::float8 v, round(coalesce(sum(ff.pg),0),2)::float8 pg,
         round(coalesce(sum(ff.sv),0),2)::float8 sv, round(coalesce(sum(ff.spg),0),2)::float8 spg
  from pac pc left join prop pp on pp.conta_id = pc.conta_id left join fat ff on ff.conta_id = pc.conta_id
  group by 1,2,3
),
reat as (
  select m.conta_id, m.reat_dia as dia, m.reat_agencia as agencia, right(m.reat_anuncio, 4) as suf
  from mv_atribuicao_unica m, janela w
  where m.reat_agencia is not null and m.reat_dia >= w.de
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
  select r.dia, r.agencia, r.suf, count(*)::int xp,
         count(*) filter (where f.v > 0)::int xc,
         round(coalesce(sum(f.v),0),2)::float8 xv, round(coalesce(sum(f.pg),0),2)::float8 xpg
  from reat r left join rfat f on f.conta_id = r.conta_id
  group by 1,2,3
),
mid as (
  select i.data as dia, agencia_no_dia(right(i.anuncio_id,4), i.data) as agencia,
         right(i.anuncio_id,4) as suf,
         round(sum(i.investido)::numeric,2)::float8 inv,
         sum(i.impressoes)::int imp, sum(i.cliques)::int cli, sum(i.conversas)::int conv
  from meta_insights_dia i cross join janela w
  where i.nivel = 'ad' and i.anuncio_id is not null and i.data >= w.de
  group by 1,2,3
),
chave as (
  select dia, agencia, suf from lead
  union select dia, agencia, suf from din
  union select dia, agencia, suf from rdin
  union select dia, agencia, suf from mid
),
visto as (
  select right(i.anuncio_id,4) as sufixo, min(i.conta_id) as conta_vista, min(i.data) as primeiro_dia
  from meta_insights_dia i, janela w
  where i.nivel = 'ad' and i.anuncio_id is not null and i.data >= w.de
  group by 1
),
serie as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'd', to_char(k.dia,'YYYY-MM-DD'), 'ag', k.agencia, 'suf', k.suf,
    'r', coalesce(l.r,0), 'rev', coalesce(l.rev,0), 'k', coalesce(l.k,0), 'p', coalesce(d.p,0),
    'o', coalesce(d.o,0), 'e', coalesce(d.e,0), 'vexec', coalesce(d.vexec,0),
    'ne', coalesce(d.ne,0), 'vne', coalesce(d.vne,0), 'nf', coalesce(d.nf,0),
    'v', coalesce(d.v,0), 'pg', coalesce(d.pg,0),
    'ab', round((coalesce(d.v,0) - coalesce(d.pg,0))::numeric,2)::float8,
    'xp', coalesce(x.xp,0), 'xc', coalesce(x.xc,0), 'xv', coalesce(x.xv,0), 'xpg', coalesce(x.xpg,0),
    'sv', coalesce(d.sv,0), 'spg', coalesce(d.spg,0),
    'inv', coalesce(m.inv,0), 'imp', coalesce(m.imp,0),
    'cli', coalesce(m.cli,0), 'conv', coalesce(m.conv,0)
  ) order by k.dia, k.agencia, k.suf), '[]'::jsonb) as j
  from chave k
  left join lead l on l.dia = k.dia and l.agencia = k.agencia and l.suf is not distinct from k.suf
  left join din  d on d.dia = k.dia and d.agencia = k.agencia and d.suf is not distinct from k.suf
  left join rdin x on x.dia = k.dia and x.agencia = k.agencia and x.suf is not distinct from k.suf
  left join mid  m on m.dia = k.dia and m.agencia = k.agencia and m.suf is not distinct from k.suf
),
periodos as (
  select a.sufixo, coalesce(p.agencia, a.agencia) as agencia, a.conta_id, a.gerenciador,
         a.confirmado_em, coalesce(p.nota || ' ', '') || coalesce(a.nota, '') as nota,
         p.vigente_de, p.vigente_ate
  from meta_agencia a
  left join meta_agencia_periodo p on p.sufixo = a.sufixo
),
ref as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'ag', r.agencia, 'suf', r.sufixo, 'conta', coalesce(r.conta_id, v.conta_vista),
    'ger', r.gerenciador, 'coletada', (v.sufixo is not null),
    'desde', to_char(r.confirmado_em,'YYYY-MM-DD'),
    'vig_de', case when r.vigente_de > '2000-01-01' then to_char(r.vigente_de,'YYYY-MM-DD') end,
    'vig_ate', to_char(r.vigente_ate,'YYYY-MM-DD'),
    'coleta_desde', to_char(v.primeiro_dia,'YYYY-MM-DD'), 'nota', r.nota
  ) order by r.agencia, r.vigente_de, r.sufixo), '[]'::jsonb) as j
  from periodos r left join visto v on v.sufixo = r.sufixo
)
select jsonb_build_object('serie', (select j from serie), 'ref', (select j from ref));
$function$;
