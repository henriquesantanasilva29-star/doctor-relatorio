-- v_atribuicao_segmento — DOCTOR (myiqdeonxuznvhtsvfxg). A da Acesso está em v_atribuicao_segmento_acesso.sql.
-- A REGRA DE ORIGEM EM UM LUGAR SÓ. Toda função do dash que diz "de onde veio o paciente e o
-- dinheiro dele" (canal_serie, agencia_serie, agencia_anuncios, agencia_caixa, jornada_anuncio,
-- crm_procedimentos, rastro_periodo, aberto_periodo) lê daqui. Mudou a regra, muda aqui.
--
-- v2, 16/10/2026 — NÚMERO DE WHATSAPP DE AGÊNCIA (Henrique: "inclua o que está sendo trabalhado no
-- 5700 na FSX também" → "tudo que chega novo no 5700"). Quem chega NOVO por um número da tabela
-- meta_numero_agencia (1ª conversa do contato foi nele, no dia da chegada ±1) e não tem anúncio
-- identificado (canal Direto, Criado pela equipe, Meta sem id do anúncio…) conta como 'Meta Ads' da
-- agência da conta `sufixo` naquele dia, com anuncio_id nulo e via 'numero_' || número. Anúncio
-- identificado continua com a agência do anúncio (Vanguarda que cai no 5700 segue Vanguarda).
-- Não entra: quem já era da base (era_da_base) e Base importada. Hoje: 5700 → 0397 (FSX) desde 01/10.
-- Em 01-16/10: +6 pacientes para a FSX (5 Direto, 1 Criado pela equipe), R$ 585,30 recebidos.
-- A mesma regra para contato (canal_serie) e lead (agencia_serie, suf 'wa5700').
--
-- v1, 15/10/2026 — regra do Henrique (14/10): quem chegou pelo anúncio da agência dentro do
-- período e fechou é paciente daquela agência, mesmo que já estivesse na base.
-- Cada paciente do Feegow (mv_atribuicao_unica) vira 1 ou 2 trechos:
--   chegada  — canal/anúncio/agência por onde chegou, de `dia` até a véspera de `ate`
--              (`ate` = dia do clique que o reativou; nulo se não foi reativado);
--   reat     — canal 'Meta Ads', anúncio/agência do clique, de `dia` (o clique) em diante.
-- Reativa: anúncio de OUTRA agência clicado depois da chegada (mv_atribuicao_unica.reat_*).
-- Não reativa: clique em post da página (agência "Não identificada") e quem chegou por
-- "Meta sem id do anúncio" (anúncio pago de agência desconhecida).
-- `paciente` = conta como paciente do trecho: a chegada sempre; o reat só se fechou (tem conta
-- no Feegow a partir do clique).
-- Fatura, proposta e agenda entram no trecho pela data: dia <= data < ate.
-- Pagamento segue a fatura: fatura do trecho de reativação (data >= clique) é do reat; antes, da chegada.
-- Limite: a mv guarda só a PRIMEIRA reativação de cada paciente.

create table if not exists public.meta_numero_agencia (
  numero     text not null,           -- últimos 4 dígitos do número de WhatsApp (helena_channels.phone_digits)
  sufixo     text not null,           -- conta de anúncio cuja agência fica com quem chega pelo número
  vigente_de date not null,
  vigente_ate date,
  nota       text,
  primary key (numero, vigente_de)
);
alter table public.meta_numero_agencia enable row level security;
comment on table public.meta_numero_agencia is
  'Número de WhatsApp operado por uma agência: quem chega NOVO por ele, sem anúncio identificado, conta para a agência da conta `sufixo` no dia. Lido pela chegada_por_numero (v_atribuicao_segmento), canal_serie e agencia_serie.';
insert into public.meta_numero_agencia (numero, sufixo, vigente_de, nota)
values ('5700', '0397', '2026-10-01',
        'Henrique, 16/10/2026: tudo que chega novo no WhatsApp 5700 é da agência da conta 0397 (FSX desde 01/10), mesmo sem anúncio identificado. Anúncio identificado (ex.: Vanguarda que cai no 5700) continua com a agência do anúncio.')
on conflict do nothing;

-- Sem SET search_path de propósito (nomes qualificados): assim o Postgres expande a função dentro
-- da view e o filtro por conta_id de quem lê continua descendo até a mv (view inteira: ~0,1 s).
create or replace function public.chegada_por_numero(p_contato uuid, p_dia date, p_canal text, p_base boolean)
returns table(agencia text, numero text)
language sql stable
as $$
  select public.agencia_no_dia(n.sufixo, p_dia), n.numero
  from public.meta_numero_agencia n
  where p_contato is not null
    and coalesce(p_canal, '') not in ('Meta Ads', 'Google Ads', 'Base importada')
    and not coalesce(p_base, false)
    and p_dia >= n.vigente_de and p_dia <= coalesce(n.vigente_ate, 'infinity'::date)
    and exists (
      select 1 from (
        select right(c.phone_digits, 4) as num, (s.created_at_wts at time zone 'America/Manaus')::date as d
        from public.helena_sessions s
        join public.helena_channels c on c.id::text = s.channel_id
        where s.contact_id = p_contato and s.created_at_wts is not null
        order by s.created_at_wts limit 1) f
      where f.num = n.numero and f.d between p_dia - 1 and p_dia + 1)
  order by n.vigente_de desc
  limit 1
$$;
comment on function public.chegada_por_numero(uuid, date, text, boolean) is
  'Agência do número de WhatsApp por onde o contato chegou NOVO (1ª conversa no número, no dia da chegada ±1), para quem não tem anúncio identificado. Vazio = regra não se aplica. Ver meta_numero_agencia.';

create or replace view public.v_atribuicao_segmento as
-- sem CTE de propósito: o filtro por conta_id de quem lê desce até a mv
select u.conta_id,
       case when w.numero is not null then 'Meta Ads'::text else u.canal end as canal,
       u.anuncio_id,
       case when w.numero is not null then w.agencia else u.agencia end as agencia,
       u.dia,
       case when (u.reat_agencia is not null and u.reat_dia is not null
        and u.reat_agencia <> 'Não identificada'
        and u.reat_agencia is distinct from (case when w.numero is not null then w.agencia else u.agencia end)
        and (w.numero is not null or u.canal is distinct from 'Meta sem id do anúncio')) then u.reat_dia end as ate,
       false as reat, true as paciente,
       case when w.numero is not null then 'numero_' || w.numero else u.via end as via,
       u.era_da_base
from public.mv_atribuicao_unica u
left join lateral public.chegada_por_numero(u.contato_id, u.dia, u.canal, u.era_da_base) w on true
union all
select u.conta_id, 'Meta Ads'::text, u.reat_anuncio, u.reat_agencia, u.reat_dia,
       null::date, true,
       exists (select 1 from public.feegow_invoices f
               where f.conta_id = u.conta_id and f.data_invoice >= u.reat_dia),
       'reativacao'::text, false
from public.mv_atribuicao_unica u
left join lateral public.chegada_por_numero(u.contato_id, u.dia, u.canal, u.era_da_base) w on true
where (u.reat_agencia is not null and u.reat_dia is not null
        and u.reat_agencia <> 'Não identificada'
        and u.reat_agencia is distinct from (case when w.numero is not null then w.agencia else u.agencia end)
        and (w.numero is not null or u.canal is distinct from 'Meta sem id do anúncio'));

comment on view public.v_atribuicao_segmento is
  'Regra de origem do dash (15/10/2026; número de WhatsApp da agência em 16/10/2026): chegada até a véspera do clique de reativação; depois, a agência do clique. Quem chega novo pelo número de uma agência (meta_numero_agencia) sem anúncio identificado conta para ela. Ver supabase/sql/v_atribuicao_segmento_doctor.sql no repositório doctor-relatorio.';
