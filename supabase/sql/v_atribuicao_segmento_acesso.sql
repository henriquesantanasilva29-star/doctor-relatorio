-- v_atribuicao_segmento — ACESSO (dfvmuqxjdcvwskrrdbfm). A da Doctor está em v_atribuicao_segmento_doctor.sql:
-- mesma regra + o número de WhatsApp de agência (16/10/2026). Até 15/10 as duas eram iguais.
-- A REGRA DE ORIGEM EM UM LUGAR SÓ. Toda função do dash que diz "de onde veio o paciente e o
-- dinheiro dele" (canal_serie, agencia_serie, agencia_anuncios, agencia_caixa, jornada_anuncio,
-- crm_procedimentos, rastro_periodo, aberto_periodo) lê daqui. Mudou a regra, muda aqui.
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
-- Pagamento entra pela data do pagamento: no reat a partir do clique; antes disso, na chegada.
-- Limite: a mv guarda só a PRIMEIRA reativação de cada paciente.
create or replace view public.v_atribuicao_segmento as
-- sem CTE de propósito: o filtro por conta_id de quem lê desce até a mv
select u.conta_id, u.canal, u.anuncio_id, u.agencia, u.dia,
       case when (u.reat_agencia is not null and u.reat_dia is not null
        and u.reat_agencia <> 'Não identificada'
        and u.reat_agencia is distinct from u.agencia
        and u.canal is distinct from 'Meta sem id do anúncio') then u.reat_dia end as ate,
       false as reat, true as paciente, u.via, u.era_da_base
from public.mv_atribuicao_unica u
union all
select u.conta_id, 'Meta Ads'::text, u.reat_anuncio, u.reat_agencia, u.reat_dia,
       null::date, true,
       exists (select 1 from public.feegow_invoices f
               where f.conta_id = u.conta_id and f.data_invoice >= u.reat_dia),
       'reativacao'::text, false
from public.mv_atribuicao_unica u
where (u.reat_agencia is not null and u.reat_dia is not null
        and u.reat_agencia <> 'Não identificada'
        and u.reat_agencia is distinct from u.agencia
        and u.canal is distinct from 'Meta sem id do anúncio');

comment on view public.v_atribuicao_segmento is
  'Regra de origem do dash (15/10/2026): chegada até a véspera do clique de reativação; depois, a agência do clique. Ver supabase/sql/v_atribuicao_segmento_acesso.sql no repositório doctor-relatorio.';
