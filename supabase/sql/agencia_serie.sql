-- agencia_serie(dias) — só na Doctor. Lida pela publica-relatorio (bloco `agencias` do dados.json).
CREATE OR REPLACE FUNCTION public.agencia_serie(dias integer DEFAULT 400)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
-- v8, 16/10/2026 — número de WhatsApp de agência (meta_numero_agencia; hoje o 5700 → conta 0397, FSX,
--   desde 01/10). Quem chega NOVO pelo número sem anúncio identificado conta para a agência dela:
--   o paciente/dinheiro já vem assim da v_atribuicao_segmento (anuncio_id nulo, via 'numero_5700');
--   aqui entra o LEAD (telefone cuja 1ª conversa foi no número e que não tem jornada de anúncio).
--   As duas coisas saem com suf = 'wa' || número ('wa5700'), linha própria dentro da agência.
-- v7, 15/10/2026 — paciente e dinheiro pela v_atribuicao_segmento (a regra de origem do dash em um
--   lugar só). r/p/v/pg/ab/propostas JÁ SOMAM quem chegou pela agência + quem já era da base e
--   voltou pelo anúncio dela (a partir do clique); xp/xc/xv/xpg dizem quanto disso é desses que
--   voltaram (xp = voltaram, xc = fecharam). Quem lê não soma mais nada: soma direto r/p/v/pg.
--   Sai sv/spg da v6.2 (a sobra dos canais agora fecha porque a canal_serie usa a mesma regra).
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
numl as (
  -- 1ª conversa do contato foi num número de agência, dentro da vigência, e o telefone não tem
  -- jornada de anúncio (esse já conta como lead do anúncio). Base importada não é lead novo.
  select distinct on (right(c.phone_digits, 8))
         right(c.phone_digits, 8) as tel8, f.d as dia, agencia_no_dia(n.sufixo, f.d) as agencia,
         'wa' || n.numero as suf,
         exists (select 1 from helena_cards k where k.contact_ids @> array[c.id]) as card
  from (select distinct on (s.contact_id) s.contact_id, s.channel_id,
               (s.created_at_wts at time zone 'America/Manaus')::date d
        from helena_sessions s where s.created_at_wts is not null
        order by s.contact_id, s.created_at_wts) f
  join helena_channels hc on hc.id::text = f.channel_id
  join meta_numero_agencia n on n.numero = right(hc.phone_digits, 4)
       and f.d >= n.vigente_de and f.d <= coalesce(n.vigente_ate, 'infinity'::date)
  join helena_contacts c on c.id = f.contact_id
  cross join janela w
  where f.d >= w.de and coalesce(right(c.phone_digits, 8), '') <> ''
    and (c.created_at_wts at time zone 'America/Manaus')::date between f.d - 1 and f.d + 1
    and classifica_canal(c.utm, c.origin) <> 'Base importada'
    and not exists (select 1 from prim p where p.tel8 = right(c.phone_digits, 8))
  order by right(c.phone_digits, 8), f.d
),
lead as (
  select p.dia, p.agencia, right(p.anuncio_id, 4) as suf, count(*)::int r,
         count(*) filter (where p.via = 'evolution')::int rev,
         count(*) filter (where p.card_id is not null)::int k
  from prim p, janela w where p.dia >= w.de group by 1,2,3
  union all
  select n.dia, n.agencia, n.suf, count(*)::int, 0, count(*) filter (where n.card)::int
  from numl n group by 1,2,3
),
pac as (
  -- trechos da v_atribuicao_segmento que são de anúncio com agência: chegada por anúncio (até a
  -- véspera da reativação, se houve) e reativação (do clique em diante)
  select s.conta_id, s.dia, s.agencia,
         coalesce(right(s.anuncio_id, 4), case when s.via like 'numero\_%' then 'wa' || substr(s.via, 8) end) as suf,
         s.ate, s.reat, s.paciente
  from v_atribuicao_segmento s, janela w
  where s.canal = 'Meta Ads' and s.agencia is not null and s.dia >= w.de
),
prop as (
  select pc.conta_id, pc.reat, count(*)::int o,
         count(*) filter (where pr.status_categoria = 'executada')::int e,
         round(coalesce(sum(pr.value) filter (where pr.status_categoria = 'executada'),0),2) vexec,
         count(*) filter (where pr.status_categoria = 'aguardando')::int ne,
         round(coalesce(sum(pr.value) filter (where pr.status_categoria = 'aguardando'),0),2) vne
  from pac pc join feegow_proposals pr on pr.feegow_patient_id = pc.conta_id and pr.proposal_date >= pc.dia
       and (pc.ate is null or pr.proposal_date < pc.ate)
  group by 1,2
),
fat as (
  select pc.conta_id, pc.reat, count(distinct i.invoice_id)::int nf,
         round(sum(i.valor_brl),2) v, round(sum(least(coalesce(i.valor_pago_brl,0), i.valor_brl)),2) pg
  from pac pc join feegow_invoices i on i.conta_id = pc.conta_id and i.data_invoice >= pc.dia
       and (pc.ate is null or i.data_invoice < pc.ate)
  group by 1,2
),
din as (
  select pc.dia, pc.agencia, pc.suf,
         count(*) filter (where pc.paciente)::int p,
         count(*) filter (where pc.reat)::int xp,
         count(*) filter (where pc.reat and pc.paciente)::int xc,
         coalesce(sum(pp.o),0)::int o, coalesce(sum(pp.e),0)::int e,
         round(coalesce(sum(pp.vexec),0),2)::float8 vexec,
         coalesce(sum(pp.ne),0)::int ne, round(coalesce(sum(pp.vne),0),2)::float8 vne,
         coalesce(sum(ff.nf),0)::int nf,
         round(coalesce(sum(ff.v),0),2)::float8 v, round(coalesce(sum(ff.pg),0),2)::float8 pg,
         round(coalesce(sum(ff.v) filter (where pc.reat),0),2)::float8 xv,
         round(coalesce(sum(ff.pg) filter (where pc.reat),0),2)::float8 xpg
  from pac pc left join prop pp on pp.conta_id = pc.conta_id and pp.reat = pc.reat
       left join fat ff on ff.conta_id = pc.conta_id and ff.reat = pc.reat
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
    'r', coalesce(l.r,0) + coalesce(d.xp,0), 'rev', coalesce(l.rev,0), 'k', coalesce(l.k,0), 'p', coalesce(d.p,0),
    'o', coalesce(d.o,0), 'e', coalesce(d.e,0), 'vexec', coalesce(d.vexec,0),
    'ne', coalesce(d.ne,0), 'vne', coalesce(d.vne,0), 'nf', coalesce(d.nf,0),
    'v', coalesce(d.v,0), 'pg', coalesce(d.pg,0),
    'ab', round((coalesce(d.v,0) - coalesce(d.pg,0))::numeric,2)::float8,
    'xp', coalesce(d.xp,0), 'xc', coalesce(d.xc,0), 'xv', coalesce(d.xv,0), 'xpg', coalesce(d.xpg,0),
    'inv', coalesce(m.inv,0), 'imp', coalesce(m.imp,0),
    'cli', coalesce(m.cli,0), 'conv', coalesce(m.conv,0)
  ) order by k.dia, k.agencia, k.suf), '[]'::jsonb) as j
  from chave k
  left join lead l on l.dia = k.dia and l.agencia = k.agencia and l.suf is not distinct from k.suf
  left join din  d on d.dia = k.dia and d.agencia = k.agencia and d.suf is not distinct from k.suf
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
),
refn as (
  -- número de WhatsApp de agência: linha 'wa' || número dentro da agência (16/10/2026)
  select coalesce(jsonb_agg(jsonb_build_object(
    'ag', agencia_no_dia(n.sufixo, n.vigente_de), 'suf', 'wa' || n.numero, 'conta', null,
    'ger', 'WhatsApp ' || n.numero || ' · sem anúncio identificado', 'coletada', false,
    'vig_de', to_char(n.vigente_de,'YYYY-MM-DD'), 'vig_ate', to_char(n.vigente_ate,'YYYY-MM-DD'),
    'nota', n.nota
  ) order by n.numero, n.vigente_de), '[]'::jsonb) as j
  from meta_numero_agencia n
)
select jsonb_build_object('serie', (select j from serie), 'ref', (select j from ref) || (select j from refn));
$function$;
