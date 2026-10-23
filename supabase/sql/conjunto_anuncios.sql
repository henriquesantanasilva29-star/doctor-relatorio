-- conjunto_anuncios() — 23/10/2026, nas duas bases (Doctor e Acesso), igual.
--
-- O público (conjunto de anúncios) de cada anúncio, para o agrupamento "Por público" da seção Anúncios
-- da aba Canais. Pedido do Henrique em 23/10, depois do relatório de anúncios para a Vanguarda.
--
-- Um anúncio pertence a um conjunto só (conferido: nenhum anúncio com dois conjunto_id nas duas bases).
-- O nome do conjunto pode mudar no Gerenciador (um caso na Acesso): vale o nome mais recente do conjunto_id.
-- A segmentação detalhada (idade, raio, interesses) e o orçamento do conjunto NÃO estão aqui: a coleta da
-- Meta grava o resultado diário por anúncio, não a configuração do conjunto.
--
-- Lida pela painel-canais (v8, action "dados") com a service_role; anon e authenticated não executam.
create or replace function public.conjunto_anuncios()
returns table(a text, cid text, conj text)
language sql
stable
set search_path to 'public'
as $$
  with u as (
    select distinct on (objeto_id) objeto_id as a, conjunto_id as cid
    from meta_insights_dia
    where nivel = 'ad' and objeto_id is not null and conjunto_id is not null
    order by objeto_id, data desc
  ), n as (
    select distinct on (conjunto_id) conjunto_id as cid, conjunto as conj
    from meta_insights_dia
    where nivel = 'ad' and coalesce(conjunto, '') <> ''
    order by conjunto_id, data desc
  )
  select u.a, u.cid, n.conj from u join n using (cid)
$$;

revoke all on function public.conjunto_anuncios() from public, anon, authenticated;
grant execute on function public.conjunto_anuncios() to service_role;

comment on function public.conjunto_anuncios() is
  'Público (conjunto) de cada anúncio, nome mais recente do conjunto. Aba Canais, agrupamento Por público (23/10/2026).';
