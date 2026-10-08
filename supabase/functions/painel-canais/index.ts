// painel-canais v5 — 08/10/2026
//
// A aba "Canais · pago × orgânico" dentro do portal de relatórios
// (relatorio.arasys.software). Até 05/10 ela morava no GitHub Pages e lia o
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
// v4 (07/10/2026): action "rastro" — quem pagou no período, paciente por
// paciente (código do Feegow, sem nome), lido NA HORA do banco pela função
// rastro_periodo(de, ate), com a origem pela régua única (mv_atribuicao_unica).
// Não vai no dados.json: na Acesso são 15 mil linhas em 62 dias.
//
// v5 (08/10/2026): action "aberto" — quem chegou no período (ou foi reativado
// por anúncio) e tem conta aberta no Feegow, paciente por paciente (código do
// Feegow, sem nome), com a situação: realizado e não pago, data passou, marcado.
// Lido na hora pela função aberto_periodo(de, ate). Pedido do Sant'Ana em 08/10.
//
// O quadro de vendas por equipe NÃO passa por esta função: a página pede o
// `caixa_equipes` da feegow-relatorios, o mesmo do Resumo faturamento.
//
// SÓ LEITURA. verify_jwt PRECISA ficar false: a página só manda content-type,
// a autenticação é feita aqui dentro.
//
// USO (POST, JSON)
//   { sessao, device_id, action: "dados" }      -> blocos de marketing do dados.json
//   { sessao, device_id, action: "criativos" }  -> miniaturas dos anúncios (criativos.json)
//   { sessao, device_id, action: "rastro", de, ate } -> pagamentos por paciente (até 93 dias)
//   { sessao, device_id, action: "aberto", de, ate } -> conta aberta por paciente (até 93 dias)
//   (o token antigo do portal, { token }, segue aceito durante a troca de login)
//
// Roda IGUAL na Doctor (myiqdeonxuznvhtsvfxg) e na Acesso (dfvmuqxjdcvwskrrdbfm).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const VERSAO = 5; // v2 (07/10): login único · v3: painel "canais" · v4: rastro · v5: aberto
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

// ------------------------------------------------ LOGIN ÚNICO (07/10/2026)
// O portal entra pelo painel-login (hub na Doctor) e manda {sessao, device_id}.
// Quem é a pessoa, o que ela abre e o que ela vê vêm do validar_sessao, lido
// na hora (guardado 60 s por sessão nesta instância). Nada do navegador além
// da sessão. O token antigo (panel_session) continua aceito durante a troca,
// para a cópia de segurança do portal seguir funcionando.
//   admin (vê a operação inteira, como o antigo panel_users.admin)
//     = master/superADM, ou quem tem o painel "relatorio_admin".
//   equipes = escopos da marca desta base; unidades = escopos do grupo.
const PAINEL_LOGIN_URL = "https://myiqdeonxuznvhtsvfxg.supabase.co/functions/v1/painel-login";
const BASE_AQUI = (Deno.env.get("SUPABASE_URL") ?? "").includes("dfvmuqxjdcvwskrrdbfm") ? "acesso" : "doctor";
const TODAS_UNIDADES = ["20", "21", "55", "0", "2", "4", "cc_doctor", "cc_acesso"];
type SessaoUnica = { nome: string; crm_user_id: string; nivel: string; tudo: boolean; admin: boolean;
                     modulos: string[]; equipes: string[]; unidades: string[] };
const _cacheSessao = new Map<string, { ate: number; j: any }>();
async function lerSessaoUnica(body: any): Promise<SessaoUnica | { status: number; erro: string }> {
  const sessao = String(body?.sessao ?? "").slice(0, 300), device = String(body?.device_id ?? "").slice(0, 128);
  if (!sessao || !device) return { status: 401, erro: "sessao_invalida" };
  const chave = device + "|" + sessao;
  let j: any = null;
  const c = _cacheSessao.get(chave);
  if (c && c.ate > Date.now()) j = c.j;
  else {
    let http = 0;
    try {
      const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 8000);
      const r = await fetch(PAINEL_LOGIN_URL, { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ op: "validar_sessao", sessao, device_id: device }), signal: ctl.signal });
      clearTimeout(t);
      http = r.status; j = await r.json().catch(() => ({}));
    } catch { return { status: 503, erro: "login_fora_do_ar" }; }
    if (http !== 200 || !j?.ok) return { status: http === 403 ? 403 : 401, erro: String(j?.erro ?? "sessao_invalida") };
    if (_cacheSessao.size > 500) _cacheSessao.clear();
    _cacheSessao.set(chave, { ate: Date.now() + 60_000, j });
  }
  if (j.precisa_trocar) return { status: 403, erro: "trocar_senha" };
  const a = j.acessos ?? {};
  const modulos: string[] = Array.isArray(a.modulos) ? a.modulos.map(String) : [];
  const tudo = !!a.tudo;
  const admin = tudo || modulos.includes("relatorio_admin");
  const esc = a.escopos ?? {};
  const lista = (x: any) => Array.isArray(x) ? x.map(String) : [];
  return { nome: String(j.nome ?? ""), crm_user_id: String(j.crm_user_id ?? ""), nivel: String(j.nivel ?? "usuario"),
           tudo, admin, modulos,
           equipes: lista(esc?.[BASE_AQUI]?.equipe),
           unidades: admin ? TODAS_UNIDADES.slice() : lista(esc?.grupo?.unidade) };
}
const ehSessaoUnica = (x: any): x is SessaoUnica => x && typeof x === "object" && "modulos" in x;
// painel do catálogo liberado? Só por liberação explícita (07/10, 15:13): todo
// relatório, atual ou futuro, precisa do seu painel na tela de acessos. Só
// master/superADM (tudo) abrem sem linha. "relatorio_admin" NÃO abre relatório.
const temPainel = (s: SessaoUnica, ...ids: string[]) => s.tudo || ids.some((id) => s.modulos.includes(id));
function negaSessaoUnica(r: { status: number; erro: string }, J: (o: unknown, s?: number) => Response): Response {
  if (r.erro === "trocar_senha") return J({ error: "Troque a senha provisória antes de abrir os relatórios. Entre de novo.", relogar: true, trocar_senha: true }, 403);
  if (r.status === 503) return J({ error: "Não consegui conferir seu login agora. Tente de novo em instantes." }, 503);
  if (r.erro === "bloqueado" || r.erro === "sem_acesso") return J({ error: "Seu acesso está bloqueado. Fale com o administrador.", relogar: true }, 401);
  return J({ error: "Sua sessão acabou. Entre de novo.", relogar: true }, 401);
}
// ---------------------------------------------- fim do LOGIN ÚNICO

const DATA = /^\d{4}-\d{2}-\d{2}$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method === "GET") return J({ ok: true, funcao: "painel-canais", versao: VERSAO, somente_leitura: true });
  if (req.method !== "POST") return J({ error: "POST only" }, 405);

  let body: any = {}; try { body = await req.json(); } catch { /* noop */ }

  // ---------------------------------------------------------- autenticação
  let quem: { nome: string; email: string | null; admin: boolean };
  if (body.sessao) {
    const su = await lerSessaoUnica(body);
    if (!ehSessaoUnica(su)) return negaSessaoUnica(su, J);
    if (!temPainel(su, "canais")) {
      return J({ error: "A aba Canais precisa ser liberada na tela de acessos (painel Canais de marketing).", sem_acesso: true }, 403);
    }
    quem = { nome: su.nome, email: null, admin: true };
  } else {
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
    quem = { nome: u.nome || s.nome || String(s.email), email: String(s.email), admin: true };
  }

  const acao = String(body.action ?? "dados");

  // ------------------------------------------------- rastro (v4, 07/10/2026)
  // Pagamento e fatura por paciente e dia, com a origem pela régua única. Sem
  // nome: o paciente aparece pelo código do Feegow.
  if (acao === "rastro") {
    const de = String(body.de ?? ""), ate = String(body.ate ?? "");
    if (!DATA.test(de) || !DATA.test(ate) || de > ate) return J({ error: "período inválido (de, ate em AAAA-MM-DD)" }, 400);
    const dias = (Date.parse(ate) - Date.parse(de)) / 86_400_000;
    if (dias > 93) return J({ error: "o rastro vai até 93 dias por vez; encurte o período" }, 400);
    const { data, error } = await sb.rpc("rastro_periodo", { p_de: de, p_ate: ate });
    if (error) return J({ error: `não consegui ler o rastro: ${error.message}` }, 500);
    return J({ ok: true, versao: VERSAO, de, ate, rastro: data ?? [] });
  }

  // ------------------------------------------------- aberto (v5, 08/10/2026)
  // Conta aberta no Feegow de quem chegou no período, pela régua única. Sem
  // nome: o paciente aparece pelo código do Feegow.
  if (acao === "aberto") {
    const de = String(body.de ?? ""), ate = String(body.ate ?? "");
    if (!DATA.test(de) || !DATA.test(ate) || de > ate) return J({ error: "período inválido (de, ate em AAAA-MM-DD)" }, 400);
    const dias = (Date.parse(ate) - Date.parse(de)) / 86_400_000;
    if (dias > 93) return J({ error: "a lista de em aberto vai até 93 dias por vez; encurte o período" }, 400);
    const { data, error } = await sb.rpc("aberto_periodo", { p_de: de, p_ate: ate });
    if (error) return J({ error: `não consegui ler as contas em aberto: ${error.message}` }, 500);
    return J({ ok: true, versao: VERSAO, de, ate, lido_em: new Date().toISOString(), aberto: data ?? [] });
  }

  // ----------------------------------------------------------------- leitura
  const arquivo = acao === "dados" ? "dados.json" : acao === "criativos" ? "criativos.json" : null;
  if (!arquivo) return J({ error: "ação inválida (dados, criativos, rastro, aberto)" }, 400);

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
