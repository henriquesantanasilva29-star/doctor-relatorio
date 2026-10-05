// painel-canais v1 — 05/10/2026
//
// A aba "Canais · pago × orgânico" dentro do portal de relatórios
// (relatorio.arasys.software). Até aqui ela morava no GitHub Pages e lia o
// dado pela função `relatorio`, com chave no link (#kd / #ka), e o quadro de
// vendas por equipe vinha do bi-painel do projeto Controle de metas. Pedido do
// Sant'Ana em 05/10: funcionar com o login do portal e com o dado das bases,
// sem chave no link e sem Controle de metas.
//
// O DADO é o MESMO dados.json que a publica-relatorio grava todo dia às 05:30
// em relatorio_arquivo, mas SÓ os blocos de marketing. O dados.json inteiro
// carrega as vozes do NPS (nome e texto de paciente), a agenda e o financeiro
// por unidade; nada disso sai por aqui.
//
// O quadro de vendas por equipe NÃO passa por esta função: a página pede o
// `caixa_equipes` da feegow-relatorios, o mesmo do Resumo faturamento.
//
// AUTENTICAÇÃO: a do portal (panel_session + panel_users), igual à
// painel-equipes e à feegow-relatorios. SÓ ADMIN: é número da operação
// inteira (caixa por canal e por agência), e não existe recorte dele por
// equipe ou por unidade que permita abrir para quem não é admin.
//
// SÓ LEITURA. verify_jwt PRECISA ficar false: a página só manda content-type,
// a autenticação é feita aqui dentro.
//
// USO (POST, JSON)
//   { token, action: "dados" }      -> blocos de marketing do dados.json
//   { token, action: "criativos" }  -> miniaturas dos anúncios (criativos.json)
//
// Roda IGUAL na Doctor (myiqdeonxuznvhtsvfxg) e na Acesso (dfvmuqxjdcvwskrrdbfm).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const VERSAO = 1;
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } });

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
  "Cache-Control": "private, no-store, max-age=0",
};
const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { "content-type": "application/json; charset=utf-8", ...CORS } });

const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
const sha256hex = async (s: string) => hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));

/* Os blocos que a aba Canais lê, e só eles. Qualquer bloco novo que a
   relatorio_payload passar a gravar fica de fora até alguém pôr aqui — é de
   propósito: o que sai por esta porta é decidido nesta lista, não lá. */
const BLOCOS = [
  "canais", "midia", "jornada", "agencias", "agencia_caixa", "agencia_ads",
  "agencia_proc", "crmproc", "cria", "conta",
  "de", "ate", "gerado_em", "jornada_em", "espelho", "dias_janela",
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method === "GET") return J({ ok: true, funcao: "painel-canais", versao: VERSAO, somente_leitura: true });
  if (req.method !== "POST") return J({ error: "POST only" }, 405);

  let body: any = {}; try { body = await req.json(); } catch { /* noop */ }

  // ---------------------------------------------------------- autenticação
  if (!body.token) return J({ error: "Entre pelo portal de relatórios.", relogar: true }, 401);
  const th = await sha256hex(String(body.token));
  const { data: s } = await sb.from("panel_session")
    .select("email,nome,expira_em").eq("token_hash", th).maybeSingle();
  if (!s) return J({ error: "Sessão inválida. Entre de novo.", relogar: true }, 401);
  if (new Date(s.expira_em).getTime() <= Date.now()) {
    await sb.from("panel_session").delete().eq("token_hash", th);
    return J({ error: "Sua sessão expirou. Entre de novo.", relogar: true }, 401);
  }
  const { data: u } = await sb.from("panel_users").select("nome,ativo,admin").eq("email", s.email).maybeSingle();
  if (!u || !u.ativo) return J({ error: "Seu acesso foi desativado.", relogar: true }, 401);
  if (!u.admin) {
    return J({ error: "A aba Canais é número da operação inteira; só administrador vê.", sem_acesso: true }, 403);
  }
  const quem = { nome: u.nome || s.nome || String(s.email), email: String(s.email), admin: true };

  // ----------------------------------------------------------------- leitura
  const acao = String(body.action ?? "dados");
  const arquivo = acao === "dados" ? "dados.json" : acao === "criativos" ? "criativos.json" : null;
  if (!arquivo) return J({ error: "ação inválida (dados, criativos)" }, 400);

  const { data, error } = await sb.from("relatorio_arquivo")
    .select("conteudo, atualizado_em").eq("caminho", arquivo).maybeSingle();
  if (error) return J({ error: `não consegui ler ${arquivo}: ${error.message}` }, 500);
  if (!data || !data.conteudo) {
    return J({ error: `${arquivo} ainda não foi gravado no banco. Ele sai na publicação das 05:30.` }, 503);
  }

  if (arquivo === "criativos.json") {
    // Só miniatura de anúncio, sem nada de paciente: vai inteiro, sem
    // desmontar o texto (são megabytes de base64 que não precisam ser lidos).
    const corpo = `{"ok":true,"versao":${VERSAO},"atualizado_em":${JSON.stringify(data.atualizado_em)},` +
      `"criativos":${data.conteudo}}`;
    return new Response(corpo, { status: 200, headers: { "content-type": "application/json; charset=utf-8", ...CORS } });
  }

  let tudo: any;
  try { tudo = JSON.parse(String(data.conteudo)); }
  catch (e) { return J({ error: `dados.json ilegível: ${String(e).slice(0, 200)}` }, 500); }
  const saida: Record<string, unknown> = {};
  for (const k of BLOCOS) if (tudo[k] !== undefined) saida[k] = tudo[k];

  return J({ ok: true, versao: VERSAO, quem, atualizado_em: data.atualizado_em, ...saida });
});
