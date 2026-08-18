/* comum.js — módulo único das cascas do Grupo JOB.
   Regra de ouro: nenhum número é publicado sem régua declarada, e fonte parada
   não produz número — produz "não sei". Ver regua.html.

   Quem edita este arquivo precisa subir o ?v=N em TODAS as cascas que o carregam,
   senão metade dos leitores fica com uma versão e metade com outra — e a divergência
   que isso cria é mais difícil de diagnosticar do que a que viemos matar. */
(function (raiz) {
'use strict';

var API = 'https://oqzbmdajkqexbpivkacv.supabase.co/functions/v1/bi-painel';

/* ---------- formato ---------- */
var brl = function (v, casas) {
  return v == null ? '—' : Number(v).toLocaleString('pt-BR',
    { style: 'currency', currency: 'BRL', maximumFractionDigits: casas == null ? 0 : casas });
};
var num = function (v) { return Number(v || 0).toLocaleString('pt-BR'); };
var pct = function (v, casas) {
  return v == null ? '—' : (Math.round(v * Math.pow(10, casas == null ? 1 : casas)) /
    Math.pow(10, casas == null ? 1 : casas)).toLocaleString('pt-BR') + '%';
};
var esc = function (s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
  });
};
function iso(d) {
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' +
         String(d.getDate()).padStart(2, '0');
}
function br(s) { var p = String(s).slice(0, 10).split('-'); return p[2] + '/' + p[1] + '/' + p[0]; }
function diasEntre(a, b) {
  return Math.round((new Date(b + 'T00:00:00Z') - new Date(a + 'T00:00:00Z')) / 86400000);
}
/* dia fechado em Manaus (UTC-4), sem depender do fuso de quem abre */
function hojeManaus() {
  var d = new Date(Date.now() - 4 * 3600 * 1000);
  return new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
}

/* ---------- período: UMA implementação para todas as cascas ----------
   Presets relativos apenas. Mês cravado em 2026 aponta para fora da janela em 2027. */
var PRESETS = [
  { id: 'hoje',   rot: 'Hoje' },
  { id: '7d',     rot: '7 dias' },
  { id: 'mes',    rot: 'Mês' },
  { id: 'mes-1',  rot: 'Mês anterior' },
  { id: '30d',    rot: '30 dias' }
];
function periodoDe(p) {
  var h = hojeManaus(), a, b;
  if (p === 'hoje')       { a = h; b = h; }
  else if (p === '7d')    { a = new Date(h); a.setDate(a.getDate() - 6); b = h; }
  else if (p === '30d')   { a = new Date(h); a.setDate(a.getDate() - 29); b = h; }
  else if (p === 'mes-1') { a = new Date(h.getFullYear(), h.getMonth() - 1, 1);
                            b = new Date(h.getFullYear(), h.getMonth(), 0); }
  else                    { a = new Date(h.getFullYear(), h.getMonth(), 1); b = h; }
  return [iso(a), iso(b)];
}

/* ---------- estado no fragmento, sempre inteiro ---------- */
// 't' = lado do switch de tráfego (pago | organico). Viaja junto com o resto do estado,
// senão mandar o link para alguém abre no lado errado.
var CAMPOS = ['k', 'kd', 'ka', 'ini', 'fim', 'doc', 'e', 'a', 'p', 't'];
var estado = {};
function leEstado() {
  var h = new URLSearchParams(location.hash.replace(/^#/, ''));
  CAMPOS.forEach(function (c) { estado[c] = h.get(c) || ''; });
  if (!estado.doc) estado.doc = 'sem_doc';
  if (!estado.p && !(estado.ini && estado.fim)) estado.p = 'mes';
  if (!estado.ini || !estado.fim) {
    var pp = periodoDe(estado.p || 'mes');
    estado.ini = pp[0]; estado.fim = pp[1];
  }
  return estado;
}
function gravaEstado(patch) {
  Object.keys(patch || {}).forEach(function (c) { estado[c] = patch[c]; });
  var q = new URLSearchParams();
  CAMPOS.forEach(function (c) { if (estado[c]) q.set(c, estado[c]); });
  history.replaceState(null, '', '#' + q.toString());
}
/* todo link interno sai daqui: copia o estado e aplica o patch.
   É isso que impede um clique de trocar o período do leitor em silêncio. */
function link(destino, patch) {
  var q = new URLSearchParams();
  CAMPOS.forEach(function (c) { if (estado[c]) q.set(c, estado[c]); });
  Object.keys(patch || {}).forEach(function (c) {
    if (patch[c] === null || patch[c] === '') q.delete(c); else q.set(c, patch[c]);
  });
  return destino + '#' + q.toString();
}
/* reescreve o href no instante do clique, para nenhum endereço envelhecer na página */
function ligaNavegacao() {
  document.addEventListener('click', function (ev) {
    var a = ev.target.closest && ev.target.closest('a[data-para]');
    if (!a) return;
    var patch = {};
    if (a.dataset.patch) { try { patch = JSON.parse(a.dataset.patch); } catch (e) { patch = {}; } }
    a.setAttribute('href', link(a.dataset.para, patch));
  }, true);
}

/* ---------- réguas: índice mínimo, verbete completo em regua.html ---------- */
var REGUAS = {
  'caixa.hub.semdoc': { rot: 'caixa · sem convênio',
    txt: 'Dinheiro que entrou, deduplicado por conta+item, status Quitado ou Parcialmente pago. NÃO inclui Hapvida.',
    naoBate: ['proposta.face', 'funil.coorte'] },
  'caixa.hub.total': { rot: 'caixa · com convênio',
    txt: 'Particular + Hapvida, mesma dedup. Só existe a partir de 01/05/2026.',
    naoBate: ['proposta.face', 'funil.coorte'] },
  'caixa.hub.sodoc': { rot: 'caixa · só convênio',
    txt: 'Só Hapvida. Só existe a partir de 01/05/2026.', naoBate: ['meta.particular'] },
  'meta.particular': { rot: 'meta cadastrada',
    txt: 'Alvo mensal por unidade. O cadastro devolve "particular" nos dois ramos do CASE, então mesmo a meta marcada como convênio é meta de particular.',
    naoBate: ['caixa.hub.sodoc'] },
  'agenda.comparecimento': { rot: 'comparecimento',
    txt: 'Atendidos ÷ (atendidos + faltas), pelos lotes do período. Quem está na fila conta em "em curso", não em atendido.' },
  'midia.custo_conversa': { rot: 'custo por conversa',
    txt: 'Investimento ÷ conversas iniciadas, na coleta do hub. Não é CPL: a conta não tem lead.' },
  'funil.coorte': { rot: 'coorte de criação',
    txt: 'Cartões CRIADOS no dia, contados na etapa em que estão HOJE. Não é movimento e não é saldo do quadro: é uma coorte redatada. Cartão criado ontem ainda não teve tempo de ser desqualificado, então os dias recentes sempre parecem vazios nas etapas finais.',
    naoBate: ['caixa.hub.semdoc'] },
  'nps.indice': { rot: 'NPS',
    txt: '(promotores − detratores) ÷ respostas × 100. A unidade é remontada por telefone, então a soma das unidades é menor que o total.' },
  'proposta.face': { rot: 'valor de face',
    txt: 'Valor do orçamento criado no período, classificado pelo status de hoje. Não é caixa e não deve bater com ele.',
    naoBate: ['caixa.hub.semdoc'] },
  'disparo.indefinida': { rot: 'régua não resolvida',
    txt: 'O gerador define disparo como origin=API (16.718) ou como qualquer saída com template (30.300). A escolha dobra o denominador.' }
};
/* todo número publicado passa por aqui. Id inexistente vira selo vermelho — e é
   proposital que fique feio: régua declarada e falsa é pior que régua ausente. */
function renderNum(texto, idRegua) {
  if (!idRegua) return '<span class="num">' + esc(texto) + '</span>' +
    '<span class="regua faltando" title="este número foi publicado sem régua declarada">régua ausente</span>';
  var r = REGUAS[idRegua];
  if (!r) return '<span class="num">' + esc(texto) + '</span>' +
    '<a class="regua faltando" href="regua.html#m=' + esc(idRegua) + '">régua ' + esc(idRegua) + ' não existe</a>';
  var ambar = r.naoBate && r.naoBate.length ? ' ambar' : '';
  var t = r.txt + (r.naoBate && r.naoBate.length
    ? '\n\nNÃO SOMA COM: ' + r.naoBate.map(function (x) {
        return (REGUAS[x] && REGUAS[x].rot) || x; }).join(', ') : '');
  return '<span class="num">' + esc(texto) + '</span>' +
    '<a class="regua' + ambar + '" href="regua.html#m=' + esc(idRegua) + '" title="' + esc(t) + '">' +
    esc(r.rot) + '</a>';
}
function nsei(motivo) {
  return '<span class="nsei-sel">não sei' + (motivo ? ' · ' + esc(motivo) : '') + '</span>';
}

/* Descreve a chave recebida sem revelá-la. "Confira a chave" sozinho não ajuda:
   quem colou um endereço truncado precisa ver que chegaram três caracteres. */
function descreveChave(k) {
  if (!k) return 'nenhuma chave veio no endereço';
  var n = k.length;
  if (n < 12) return 'chegou uma chave de ' + n + ' caractere' + (n === 1 ? '' : 's') +
    ' (“' + esc(k) + '”) — as chaves desta casa têm 24 ou 64. ' +
    'Isso costuma ser endereço copiado já encurtado, com reticências no lugar da chave';
  return 'chegou uma chave de ' + n + ' caracteres, começando em “' + esc(k.slice(0, 4)) +
    '” e terminando em “' + esc(k.slice(-4)) + '”';
}
/* mensagem única de falha, para as cascas não divergirem nem nisso */
function explicaFalha(e, chave) {
  var s = String(e);
  if (s.indexOf('401') >= 0 || s.indexOf('404') >= 0) {
    return 'Acesso negado — ' + descreveChave(chave) + '. ' +
      'Chave revogada e chave inexistente devolvem a mesma resposta, de propósito.';
  }
  if (s.indexOf('AbortError') >= 0) return 'O hub não respondeu em 20 segundos. Tentando de novo em 1 minuto…';
  return 'Não consegui buscar agora (' + esc(s) + '). Tentando de novo em 1 minuto…';
}

/* ---------- delta: não atravessa troca de régua (invariante 3) ---------- */
function delta(atual, anterior, trocas) {
  if (trocas && trocas.length) {
    return { tipo: 'nsei', motivo: 'a régua mudou em ' + br(trocas[0].muda_em) };
  }
  if (atual == null || anterior == null) return { tipo: 'nsei', motivo: 'sem base de comparação' };
  if (!anterior) return { tipo: 'nsei', motivo: 'período anterior sem dado' };
  var v = (atual - anterior) / Math.abs(anterior) * 100;
  if (Math.abs(v) < 1) return { tipo: 'estavel', v: v };
  return { tipo: v > 0 ? 'sobe' : 'cai', v: v };
}

/* ---------- busca com timeout, sem acumular ciclo ---------- */
var _timer = null, _ciclo = null;
function busca(params, aoChegar, aoFalhar) {
  var ctl = new AbortController();
  var corta = setTimeout(function () { ctl.abort(); }, 20000);
  var q = new URLSearchParams(params).toString();
  return fetch(API + '?' + q, { signal: ctl.signal })
    .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(function (d) { clearTimeout(corta); aoChegar(d); })
    .catch(function (e) {
      clearTimeout(corta);
      clearTimeout(_timer);
      if (_ciclo) { clearInterval(_ciclo); _ciclo = null; }
      aoFalhar(e);
    });
}
function repete(fn, ms) { if (_ciclo) clearInterval(_ciclo); _ciclo = setInterval(fn, ms); }
function tentaDeNovo(fn, ms) { clearTimeout(_timer); _timer = setTimeout(fn, ms); }

/* ---------- tabela responsiva: rótulo viaja na célula ---------- */
function tabela(colunas, linhas, legenda) {
  var th = colunas.map(function (c) {
    return '<th' + (c.r ? ' class="r"' : '') + '>' + esc(c.rot) + '</th>'; }).join('');
  var tb = linhas.map(function (l) {
    return '<tr>' + colunas.map(function (c, i) {
      return '<td data-rot="' + esc(c.rot) + '"' + (c.r ? ' class="r"' : '') + '>' +
        (l[i] == null ? '—' : l[i]) + '</td>'; }).join('') + '</tr>';
  }).join('');
  return '<div class="tabela-wrap"><table>' +
    (legenda ? '<caption>' + esc(legenda) + '</caption>' : '') +
    '<thead><tr>' + th + '</tr></thead><tbody>' +
    (tb || '<tr><td colspan="' + colunas.length + '">sem dados no período</td></tr>') +
    '</tbody></table></div>';
}

/* ---------- filtros padrão ---------- */
function pintaFiltros(alvo, aoTrocar) {
  var h = PRESETS.map(function (p) {
    return '<button class="pill' + (estado.p === p.id ? ' on' : '') + '" data-p="' + p.id + '">' +
      esc(p.rot) + '</button>'; }).join('');
  h += '<span class="datas"><input type="date" id="f-ini" value="' + esc(estado.ini) + '">' +
       ' até <input type="date" id="f-fim" value="' + esc(estado.fim) + '">' +
       '<button class="pill" id="f-aplicar">Aplicar</button></span>';
  h += '<span class="divisor"></span>';
  [['sem_doc', 'Particular'], ['com_doc', 'Particular + convênio'], ['so_doc', 'Só convênio']]
    .forEach(function (d) {
      h += '<button class="pill' + (estado.doc === d[0] ? ' on' : '') + '" data-doc="' + d[0] + '">' +
        esc(d[1]) + '</button>';
    });
  alvo.innerHTML = h;
  alvo.querySelectorAll('[data-p]').forEach(function (b) {
    b.addEventListener('click', function () {
      var pp = periodoDe(b.dataset.p);
      gravaEstado({ p: b.dataset.p, ini: pp[0], fim: pp[1] });
      pintaFiltros(alvo, aoTrocar); aoTrocar();
    });
  });
  alvo.querySelectorAll('[data-doc]').forEach(function (b) {
    b.addEventListener('click', function () {
      gravaEstado({ doc: b.dataset.doc }); pintaFiltros(alvo, aoTrocar); aoTrocar();
    });
  });
  alvo.querySelector('#f-aplicar').addEventListener('click', function () {
    var a = alvo.querySelector('#f-ini').value, b = alvo.querySelector('#f-fim').value;
    if (!a || !b) return;
    if (a > b) { var t = a; a = b; b = t; }
    gravaEstado({ ini: a, fim: b, p: '' }); pintaFiltros(alvo, aoTrocar); aoTrocar();
  });
}

raiz.JOB = {
  API: API, brl: brl, num: num, pct: pct, esc: esc, iso: iso, br: br,
  diasEntre: diasEntre, hojeManaus: hojeManaus,
  PRESETS: PRESETS, periodoDe: periodoDe,
  estado: estado, leEstado: leEstado, gravaEstado: gravaEstado, link: link,
  ligaNavegacao: ligaNavegacao,
  REGUAS: REGUAS, renderNum: renderNum, nsei: nsei, delta: delta,
  descreveChave: descreveChave, explicaFalha: explicaFalha,
  busca: busca, repete: repete, tentaDeNovo: tentaDeNovo,
  tabela: tabela, pintaFiltros: pintaFiltros
};
})(window);
