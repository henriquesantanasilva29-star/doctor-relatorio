-- publica_apos_carga() — igual nas duas bases (só muda a URL da publica-relatorio; a Acesso usa ?dias=400).
-- 19/10/2026 (Henrique: Canais e Resumo faturamento "têm que rodar no mesmo horário"): o dados.json
-- do Canais é republicado assim que termina uma carga do Feegow (a diária das 07:05 ou um "Atualizar
-- do Feegow" no meio do dia) — a mesma carga que o Resumo faturamento mostra em "Carga de".
-- Cron `publica-relatorio-apos-carga` a cada 5 min (Doctor 2-59/5, Acesso 3-59/5). Substituiu o
-- `publica-relatorio-pos-carga` fixo das 07:30/07:35, que durou poucas horas.
create table if not exists public.relatorio_publica_carga (
  lote text primary key,
  terminou_em timestamptz not null,
  pedido_em timestamptz not null default now(),
  req bigint
);
alter table public.relatorio_publica_carga enable row level security;

create or replace function public.publica_apos_carga()
returns text language plpgsql security definer set search_path to 'public' as $$
declare v_lote text; v_fim timestamptz; v_pend int; v_req bigint;
begin
  select lote into v_lote from feegow_carga_fila where lote not like 'historico%' order by id desc limit 1;
  if v_lote is null then return 'sem carga'; end if;
  select max(fim_em), count(*) filter (where status in ('pendente','rodando'))
    into v_fim, v_pend from feegow_carga_fila where lote = v_lote;
  if v_pend > 0 or v_fim is null then return 'carga em andamento'; end if;
  if exists (select 1 from relatorio_publica_carga where lote = v_lote and terminou_em >= v_fim) then
    return 'já publicado';
  end if;
  select net.http_get(url := 'https://myiqdeonxuznvhtsvfxg.supabase.co/functions/v1/publica-relatorio',
  -- Acesso: 'https://dfvmuqxjdcvwskrrdbfm.supabase.co/functions/v1/publica-relatorio?dias=400'
                      timeout_milliseconds := 180000) into v_req;
  insert into relatorio_publica_carga (lote, terminou_em, req) values (v_lote, v_fim, v_req)
  on conflict (lote) do update set terminou_em = excluded.terminou_em, pedido_em = now(), req = excluded.req;
  return 'publicado (' || v_lote || ')';
end $$;
