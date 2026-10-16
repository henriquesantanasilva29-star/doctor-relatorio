# Doctor Mais Saúde — relatório de performance

**https://henriquesantanasilva29-star.github.io/doctor-relatorio/**

Abre em qualquer dia e mostra o dado até aquele dia. Ninguém precisa gerar nada.

## O endereço é aberto, o dado não

Este repositório guarda apenas a **casca**: o HTML, sem um único número dentro.
Abrir o endereço acima sem chave mostra uma página vazia dizendo isso.

O dado vive no banco e sai por um endpoint que exige chave. O link completo tem
a chave no fim, depois do `#`:

```
https://henriquesantanasilva29-star.github.io/doctor-relatorio/#k=SUA_CHAVE
```

**O `#` não é enfeite.** O que vem depois dele o navegador não manda para
servidor nenhum — nem para o GitHub, que hospeda esta página. A chave só sai da
máquina de quem abriu quando o navegador vai buscar o dado, e vai direto para o
Supabase.

Foi assim que ficou porque a aba de NPS mostra **o que cada paciente escreveu,
com nome**. Isso é informação de saúde de gente identificável, e não pode ficar
num endereço que qualquer um abre.

### Chaves

Uma por pessoa ou por equipe, para dar para desligar uma sem derrubar as outras:

```sql
select abre_chave_relatorio('Fulano — marketing');   -- emite
select revoga_chave_relatorio('Fulano — marketing'); -- desliga
select * from v_relatorio_acesso;                    -- quem abriu, quantas vezes, quando
```

Chave revogada devolve 404, igual a chave inexistente — quem estiver batendo na
porta às cegas não descobre qual das duas é.

## Como se atualiza

```
Meta Ads ─┐
Feegow   ─┼─► coleta automática ─► Supabase ─► publica-relatorio ─┬─► banco (o dado)
Life CRM ─┘   (de 2 em 2 min a       (banco)     (cron 05:30)     │
               1x por dia)                                        └─► este repositório (a casca)
```

| Arquivo | Onde vive | Quem escreve |
|---|---|---|
| `index.html` | aqui, aberto | `publica-relatorio`, a partir de `relatorio_arquivo` |
| `dados.json` | só no banco | `publica-relatorio`, todo dia às 05:30 |
| `criativos.json` | só no banco | `publica-relatorio`, quando entra anúncio novo |

O commit da casca só acontece se o HTML mudou de verdade, então o histórico
daqui continua dizendo alguma coisa.

### Mudar a casca não depende de ninguém clicar

O `index.html` já subiu à mão pela tela de upload do GitHub. Não sobe mais:

```
build_lc.py  ─►  recebe-arquivo  ─►  relatorio_arquivo  ─►  publica-relatorio  ─►  GitHub
                 (vale de uso único, amarrado ao sha256 do arquivo)
```

`abre_upload_relatorio(caminho, sha256, bytes)` devolve um token que só aceita
**aquele** conteúdo exato, uma vez, dentro de 30 minutos. Token sozinho não
escreve nada: corpo que não bate com o sha registrado é recusado sem gravar.

## Se o relatório parar

Ele avisa sozinho: passando de 36 horas sem publicação, aparece uma tarja no
topo da página dizendo há quantos dias está parado. A causa se descobre em uma
consulta:

```sql
select * from v_publicacao_saude;
```

Ela separa as duas falhas possíveis — a coleta parou, ou só a publicação parou —
porque o conserto é diferente em cada caso. O histórico de tentativas fica em
`publicacao_log`.

A causa mais provável de parada é o token do GitHub expirar. Ele é um
fine-grained token com `Contents: read and write` neste repositório, guardado no
Supabase como `GITHUB_TOKEN_RELATORIO`.

## O que o relatório responde

- **Mídia paga** — investimento, impressões, cliques, CTR, CPC, CPM e conversas
  por campanha. Clicar numa especialidade abre os anúncios: imagem, texto,
  chamada e o funil de cada um.
- **Meta × CRM** — o que cada sistema conta e por que os números diferem. A Meta
  conta conversa (evento, no dia do anúncio); o Life CRM conta contato (pessoa,
  no dia da mensagem). Nunca batem, e a diferença tem causa medida.
- **Comercial e financeiro** — propostas, execução, faturamento e caixa das
  unidades 0, 2 e 4.
- **NPS** — índice, taxa de resposta, notas, tempo de espera, motivos e as vozes
  dos pacientes, com filtro por unidade. É o mesmo dado dos quatro PDFs diários,
  conferido contra eles dígito a dígito em 01–10/08/2026.
- **Conferência** — nossa coleta contra o relatório de julho da agência.

### Sobre o NPS

A pesquisa não grava a unidade — ela é remontada pelo telefone, procurando
agendamento na Doctor em até três dias antes do envio. Quando a janela devolve
mais de uma unidade, ou nenhuma, a resposta entra no consolidado e em unidade
nenhuma. Por isso **a soma das três unidades é menor que o total**, e existe o
filtro "Sem vínculo" para ver quem ficou de fora.

O mesmo vale para as vozes: a unidade de um comentário é reconstruída, não
declarada. Se o vínculo estiver errado, a fala aparece na unidade errada — em
caso de dúvida, leia no filtro **Tudo**.

A aba também mostra quantas respostas combinam nota baixa com subnotas altas —
o padrão de quem leu a régua ao contrário. Elas continuam contando no número
oficial; o que a página faz é dizer quanto o índice mudaria sem elas.

## Relatório mensal de unidades (`mensal.html`)

O deck mensal por unidade (o "Unidades – Julho Final 2026" que era montado à mão)
se monta sozinho, com o mês escolhido na tela. Abre pela aba **Relatório mensal** do
`grupo.html`, com as chaves da Doctor (`kd`) e da Acesso (`ka`); a do BI (`kb`) só traz as metas.

Os números vêm **da API do Feegow**, espelhada em cada CRM — nada do Briefing nem do
Controle de Metas:

```
API Feegow ─► CRM Doctor / CRM Acesso ─► relatorio_mensal_api(mes) ─► relatorio_mensal_cache
  agenda 5 min · propostas 15 min            (cron :12/:42 e :14/:44, mês corrente e anterior)
  contas/pagamentos 1 h                                 │
                                   relatorio-mensal?k=…&mes=YYYY-MM ─► mensal.html
```

Ao abrir, a página mostra o último cálculo na hora e chama `&atualizar=1`: o CRM coleta os
últimos 2 dias na API (contas, pagamentos e propostas) e recalcula; a página se redesenha
sozinha quando termina (~1 min). A coleta tem trava de 5 min.

Quem vendeu: a API não traz o vendedor da conta. Item com agendamento → quem agendou; sem
agendamento → quem fez a proposta executada do mesmo paciente nos 45 dias anteriores; o resto
fica em "Sem atribuição". O time de cada pessoa está em `relatorio_equipe_pessoa` (editável,
nos dois CRMs).

## Canais · pago × orgânico (`canais.html`) — mudou para o portal em 05/10/2026

A aba Canais agora mora no **portal de relatórios**
(**https://relatorio.arasys.software/#canais**), com o login dele. Acabou a chave
no link e acabou o Controle de metas:

```
publica-relatorio (05:30) ─► relatorio_arquivo.dados.json ─► painel-canais ─┐
  (Doctor e Acesso, cada uma no seu Life CRM)        só os blocos de       │
                                                     marketing, só admin   ├─► canais.html
espelho do Feegow ─► feegow-relatorios (caixa_equipes) ─────────────────────┘   (no portal)
                     quadro de vendas por equipe = "Quem vendeu" do Resumo faturamento
```

- **Login:** a página roda na mesma origem do portal, dentro da aba Canais, e lê a
  sessão do login único que o portal mantém só em memória (`window.__portalSessao()`,
  desde 07/10). Nada passa pelo endereço. Sessão vencida lá dentro devolve o portal
  para o login.
- **Quem vê:** só administrador. É número da operação inteira (caixa por canal e por
  agência das duas marcas), e a `painel-canais` recusa quem não é admin.
- **Dado:** o mesmo `dados.json` de antes, mas a `painel-canais` só deixa sair os
  blocos de marketing (`canais`, `midia`, `jornada`, `agencias`, `agencia_*`,
  `crmproc`, `cria`, `conta`). As vozes do NPS, a agenda e o financeiro por unidade
  ficam no banco. O código da função está em `supabase/functions/painel-canais/`.
- **Quadro de equipes:** saiu do `bi-painel` (projeto Controle de metas, régua da
  planilha) e passou a ser a leitura "Quem vendeu" do Resumo faturamento: caixa do
  período ligado à proposta pela fatura, na equipe de quem criou a proposta.
- Uma marca que falha não derruba a outra. Antes, a chave revogada da Doctor apagava
  a tela inteira.

O `canais.html` deste repositório é a cópia versionada do que roda no portal. Aberto
pelo GitHub Pages, sem a sessão do portal, ele só aponta para lá; a aba Canais do
`grupo.html` também abre o portal.

**Para publicar uma mudança:** o portal é estático na Hostinger. Sobe `canais.html`
(e o `index.html` do portal, se mudou) pelo Gerenciador de Arquivos do hPanel, na
pasta do subdomínio `relatorio.arasys.software`. **Antes de subir, baixe o que está no
ar e compare**: outras conversas também publicam esse arquivo (login único e modo
escuro entraram assim em 07/10).

### Canais v2 — refeito do zero em 14/10/2026

O Henrique achou a aba "totalmente quebrada" (tema antigo do Life CRM, texto demais,
~300 KB). O `canais.html` foi reescrito do zero (~53 KB) com os tokens e as fontes do
portal (Arasys, claro/escuro por `rel_tema`), **só indicadores**, explicação apenas no
`title` (passar o mouse). Mesmo backend: `painel-canais` `dados` / `aberto` / `rastro`.

- **Filtros:** período (7 dias, 30 dias, os 3 últimos meses, Tudo, de/até), marca (as
  duas, Doctor, Acesso) e agência (Todas, Vanguarda, FSX, VX). Sem comparação de período.
  Quadro de vendas por equipe saiu (decisão do Henrique).
- **Indicadores (Todas):** caixa no período, caixa de anúncio, investimento, leads de
  anúncio, pacientes novos, faturado, retorno, em aberto. **Com uma agência:** caixa da
  agência (e quanto veio de quem chegou antes), investimento, leads, pacientes, faturado,
  retorno, em aberto e reativação.
- **Blocos:** Origem do caixa (barra de 4 grupos + tabela por canal; só com agência =
  Todas), Agências (abre conta a conta; odonto 0085/0279 = "venda fora do Feegow"; linha
  "Sem agência identificada" = canais pagos − agências), Anúncios (ordenável, 15 + ver
  todos), Fechado e não pago e Quem pagou (lidos na hora, até 93 dias).
- **Uma conta só:** `resumoPago()` alimenta os indicadores e a linha Total das agências.
  Leads = telefones das agências + leads do Google e do Meta sem código; custo por paciente
  e retorno sem as contas de odonto; retorno = faturado do Meta ÷ investimento medível.
- **Acesso sem bloco `agencias`:** a série é montada na página pela `jornada` + `midia`,
  com a vigência em `CONTAS_ACESSO` (0418 Vanguarda; 0279 VX até 30/09, FSX desde 01/10).
- **Quem pagou com agência escolhida:** quem a agência trouxe conta pela origem; quem ela
  só reativou fica no chip "Reativação" (antes somava no anúncio).
- **Conferência (dados de 14/10, 01–12/10):** caixa Doctor R$ 162.731,52 e Acesso
  R$ 321.191,80 (= Feegow e = soma do Quem pagou); Total das agências = indicadores nas
  duas marcas (caixa de anúncio R$ 64.240, 193 pacientes, retorno 4,2×). A origem do
  "Quem pagou" na Acesso difere ~R$ 700 da Origem do caixa porque um é lido na hora e o
  outro é a foto das 05:30 (pacientes "sem ligação" que ganharam ligação no dia).

### Anúncios por tipo e por agência, com o que foi recebido — 16/10/2026

Pedido do Henrique: a seção que mostrava os anúncios por tipo, por agência, com as métricas de cada um,
criativo, copy e o que foi vendido tinha sumido na v2. Voltou na seção **Anúncios**, **sem faturado** —
o dinheiro ali é o **recebido** no período.

- **Agrupa** por tipo (padrão) ou por agência; o filtro de marca e de agência do topo vale. Cada grupo
  mostra anúncios, investimento, conversas, leads, pacientes, custo/paciente, recebido, retorno
  (recebido ÷ investimento, sem odonto) e as 3 categorias que mais entraram. Clicou, abre os cartões.
- **Cartão do anúncio:** miniatura (`criativos.json`, pedido só quando abre o grupo), nome, campanha,
  agência, marca, dias no ar, link da publicação e do gerenciador, texto (copy) com "ver texto
  completo", métricas (investido, conversas, custo/conversa, leads, pacientes, custo/paciente,
  recebido, retorno, quantos pagaram) e **"Com o que foi recebido"**: categorias com barra e
  percentual, e "ver procedimentos" (os 12 maiores + o resto somado).
- **Tipo** sai do nome da campanha: descarta agência, formato, público, data, valor e "AD n" e fica
  com o primeiro pedaço útil, com apelidos (ULTRASSONOGRAFIA→Ultrassom, CARDIOLOGISTA→Cardiologia,
  APH→Atendimento pré-hospitalar…). Campanha genérica ("Procedimentos") usa o nome do anúncio — por
  isso o ultrassom da FSX e o da Vanguarda caem no mesmo grupo. Odonto (0085/0279) é um tipo só.
- **Recebido por anúncio** sai do `rastro_periodo` (o mesmo de "Quem pagou"), que ganhou o campo
  `itens` nas linhas de anúncio: cada pagamento do dia rateado pelos itens não cancelados da fatura
  que ele paga (valor × quantidade − desconto + acréscimo). A soma fecha com o pago no centavo
  (01–16/10: Doctor R$ 58.181,31; Acesso R$ 35.769,40). `adrow/peso/itens` são MATERIALIZED — sem
  isso o rastro da Doctor ia de 0,5 s para 10 s. Paciente de "Meta sem id" e Google fica fora (não há
  anúncio para pendurar). Período acima de 93 dias: recebido por anúncio não aparece (aviso na seção).

### Regra de origem em um lugar só: `v_atribuicao_segmento` — 14 e 15/10/2026

Regra do Henrique (14/10): **chegou pelo anúncio da agência dentro do período e fechou = paciente
daquela agência**, mesmo que já estivesse na base. E (15/10): **uma mudança de lógica vale para o
dash inteiro** — não pode haver um bloco com a regra nova e outro com a velha.

Por isso a regra saiu das funções e foi para uma view, igual nas duas bases
(`supabase/sql/v_atribuicao_segmento.sql`). Cada paciente do Feegow (`mv_atribuicao_unica`) vira
um ou dois trechos:

- **chegada** — canal/anúncio/agência por onde chegou, do dia da chegada até a véspera do clique
  de reativação (`ate`);
- **reat** — canal `Meta Ads`, anúncio e agência do clique, do clique em diante. Conta como
  paciente (`paciente`) só se fechou conta no Feegow depois do clique.

Reativa só anúncio de OUTRA agência; não reativa clique em post da página ("Não identificada")
nem quem chegou por "Meta sem id do anúncio". Fatura, proposta e agenda entram no trecho pela
data. **Pagamento segue a fatura** (15/10, tarde): fatura aberta antes do clique é da chegada,
mesmo paga depois; só a fatura aberta a partir do clique é da agência do clique (antes contava
pela data do pagamento e a FSX levou R$ 1.500 de uma venda feita pela VX dias antes do clique).
Limite: a mv guarda só a primeira reativação.

**Quem lê a view** (mudou a regra, muda só a view):

| Função | Base | Bloco / uso |
|---|---|---|
| `canal_serie` v3 | as duas | `canais` (origem do recebido, cartões) |
| `agencia_serie` v7 | Doctor | `agencias.serie` — r/p/v/pg já somam quem voltou; xp/xc/xv/xpg = quanto disso |
| `agencia_anuncios` v5 | Doctor | `agencia_ads` |
| `agencia_caixa` v5 | as duas | `agencia_caixa` (linha `reat` = pago a partir do clique) |
| `jornada_anuncio` v7 (Doctor) / v6 (Acesso) | as duas | `jornada` — na Acesso saiu da régua antiga `mv_paciente_anuncio` |
| `crm_procedimentos` v5 | as duas | `crmproc` e `agencia_proc` — na Acesso também saiu da régua antiga |
| `rastro_periodo` | as duas | "Quem pagou" — dono do dia; quem voltou vem com via `reativacao` |
| `aberto_periodo` v6 | as duas | "Fechado e não pago" — linha `c` até o clique, linha `r` dali em diante |

Conferido em 01-14/10 depois da troca: na Doctor, canais pagos = soma de `agencia_caixa` =
"Quem pagou" de anúncio (R$ 50.672,87); canal Meta Ads = série das agências = tabela de
anúncios (128 pacientes, R$ 47.105,78 de faturado); caixa total = Feegow (R$ 185.906,65, igual
antes). Na Acesso, canal Meta Ads = `jornada` (128 pacientes, R$ 17.090,42) e caixa de anúncio =
`agencia_caixa` (R$ 32.989,17). FSX em outubro: 24 pacientes (20 chegaram, 4 já eram da base), e o
caixa dela passou de R$ 799 para R$ 14.294.

Conferido de novo em 01-15/10, já com o pagamento pela fatura: na Doctor, canais pagos = soma de
`agencia_caixa` = "Quem pagou" de anúncio (R$ 53.154,10) e recebido total = Feegow (R$ 196.085,00);
na Acesso, R$ 33.838,48 e R$ 418.267,81, os três iguais. FSX: recebido R$ 13.144,71, dos quais
R$ 12.245,24 de quem já era da base (contas 29181, 30740, 31121, 31152).

**Nome (15/10):** "caixa" virou **Recebido** na aba (Recebido no período, Recebido de anúncio,
Recebido da agência, coluna Recebido, "Origem do recebido") = pagamentos do Feegow no período.
O "recebido" da coorte (quanto do faturado de quem chegou no período já foi pago) virou **Já pago**,
para não ter dois "Recebido" com contas diferentes.

A aba Canais não soma mais nada por conta própria: lê r/p/v/pg prontos. Em 15/10 uma versão antiga
da aba (layout de cartões por agência, ~254 KB) foi subida por cima da v2 por outra sessão; a v2 foi
reposta e a largura dentro do portal passou a acompanhar o portal, que era o que a outra versão trazia.

**Não entra (sem rastro de anúncio):** em 01-14/10, 8 pacientes compraram hiperbárica (R$ 27.190
pagos) sem nenhum anúncio no telefone — 5 chegaram em outubro direto no WhatsApp 2125 sem utm e 3
foram criados pela equipe. Ficam em "Direto" e "Equipe" até alguém dizer de onde vieram.

### Régua única de origem — 07/10/2026

Até 07/10 a aba tinha três réguas de "paciente de tráfego pago", cada uma com o seu
cruzamento de identidade, e os números não fechavam entre si (em 07/09–06/10: 238,
203 e 279 pacientes; faturado de R$ 53 mil, R$ 46 mil e R$ 66 mil para o mesmo
tráfego). Agora tudo sai de **`mv_atribuicao_unica`** (uma linha por paciente do
Feegow), montada por `atribuicao_pacientes()` em cada base e atualizada a cada 20 min
pelo `refresh_mvs_jornada()`:

- **Telefone liga tudo:** paciente do Feegow ↔ contatos do CRM ↔ anúncios. Telefone de
  família liga todos os pacientes do número; telefone de enchimento (00000000…) ou
  dividido por mais de 6 pacientes não liga ninguém.
- **Chegada** = primeiro contato; anúncio até 1 dia depois dele faz o paciente ser do
  anúncio (agência pela vigência da conta no dia). "Base importada" (migração de
  05/06) não é chegada. Anúncio clicado depois de chegar por outro caminho é
  **reativação** (`reat_*`), não paciente novo da agência.
- **utm regravado:** o CRM grava no contato o utm do ÚLTIMO anúncio clicado. Se o
  anúncio começou depois da criação do contato, a data do toque vira a primeira
  conversa a partir do início do anúncio (`v_jornada_origem`) e o canal do contato
  sai só da origem do cadastro.
- **Parado na mesa** = só proposta aguardando aprovação (rejeitada não entra).
- Leem dela: `canal_serie`, `agencia_serie`, `agencia_anuncios`, `agencia_caixa`,
  `jornada_anuncio`, `crm_procedimentos`/`agencia_procedimentos` e `rastro_periodo`.
  Conferência de 07/09–06/10 na Doctor: cartão Tráfego pago = soma das agências =
  tabela de campanhas = lista de quem pagou (315 pacientes, R$ 68.481,70 fechados,
  R$ 82.891,50 de caixa); caixa total = Feegow (R$ 433.373,85).
- **Agência com mais de uma conta:** a FSX opera a conta da FarMelhor (hiperbárica, final
  0397, coletada) e, desde 04/10, a de odonto da Doctor na BM OrthoDontic Manaus (final
  0085, WhatsApp final 7899), cadastrada em 07/10 em `meta_agencia`/`meta_agencia_periodo`.
  A 0085 não está compartilhada com o portfólio da Doctor: sem investimento dela, o cartão
  junta as contas, marca "investimento parcial" e deixa custo e retorno da agência em
  branco — e abre "conta a conta", com o retorno de cada conta coletada.
- **Reativação** (`agencia_serie` v6, campos `xp/xc/xv/xpg`): quem chegou por outro caminho
  (orgânico, equipe ou anúncio de outra agência) e comprou depois de clicar no anúncio da
  agência. Conta o fechado desde o dia do clique, fica fora do número grande e da soma com
  o cartão Tráfego pago. Na 1ª semana da FSX: 4 reativados, 2 compraram hiperbárica,
  R$ 12.500 fechados. A série agora tem grão (dia, agência, conta) — somar por agência dá
  o mesmo da v5. A MV guarda só a PRIMEIRA reativação de cada paciente.
- **Em aberto, paciente por paciente** (`aberto_periodo(de, ate)`, até 93 dias, desde 08/10):
  o "Falta pagar" dos cartões aberto por paciente — quem chegou no período (ou foi reativado
  por anúncio) e tem conta aberta no Feegow. A situação (v3) junta os itens das contas e a
  AGENDA do Feegow (eventos de agendamento em `events`, por paciente): realizado ou atendido
  sem baixa (cobrar), horário de hoje em diante (confirmar), horário que passou sem atendimento
  (remarcar — com o que a agenda registra: não compareceu, desmarcou ou ficou como marcado) e
  sem nenhum horário (agendar). Item sem agendamento carrega a data da conta, não um horário.
  Lido na hora pela `painel-canais` v5 (`action: "aberto"`), **com o nome do paciente desde
  09/10** (v4 — decisão do Henrique: a aba só abre com login de administrador ou com a aba
  Canais liberada, e cobrar exige saber quem é; o nome não vai para o `dados.json`). Nome do
  Feegow (`feegow_pacientes`, depois `feegow_paciente`) e, na falta, do CRM pela identidade do
  Feegow (`mv_conta_paciente` → `patients`, e `patients.custom.feegow_patient_id`) — 100% da
  lista com nome nas duas bases; busca por nome (sem acento) ou código. A soma por agência
  confere com o cartão (08/10: FSX R$ 1.350,64, Vanguarda R$ 5.860,21). SQL em
  `supabase/sql/aberto_periodo.sql`.
- **Auditoria de 08/10** (agente separado, só leitura): cartões = agências = campanhas = rastro =
  em aberto, e caixa total = Feegow, nas duas marcas e em dois períodos — tudo fecha no centavo.
  Correções que saíram dela: reativação não conta quem chegou por "Meta sem id do anúncio"
  (`agencia_serie` v6.1); pago nulo do Feegow vale zero; na Acesso o telefone do cadastro do
  paciente (`patients`) entrou na régua, porque o `feegow_paciente` de lá só tem quem passou pela
  agenda (+202 pacientes atribuídos, +20 de anúncio); "Sem rastreio (pré-CRM)" aparece na tela
  como "Sem ligação com o CRM" — é paciente sem telefone válido, com telefone dividido por mais
  de 6 cadastros ou sem conversa com a clínica, não paciente anterior ao CRM.
- **Espelho do WhatsApp (Evolution) parado:** o coletor `evolution-anuncios` (projeto Sentinela,
  cron 14) recebe 404 porque as instâncias "Doctor-5700" (desde 05/10) e "DOCTOR corporativo
  Vieralves - 2125" (desde 21/09) não existem mais no Evolution — os números foram para Z-API no
  Life CRM. **Decisão de 08/10 (Henrique): a procedência vem do CRM (Z-API).** O CRM grava no
  contato só o ÚLTIMO anúncio clicado; o gatilho `trg_helena_utm_historico` (Doctor e Acesso)
  guarda cada troca em `crm_utm_historico` com a hora — o utm sobrescrito com a data corrigida
  pela mesma regra da `v_jornada_origem`. Na Doctor ele entra na régua pela `v_jornada_origem`
  (via `crm_utm`); na Acesso, direto na `atribuicao_pacientes`. Nada disso escreve no CRM.
  **Em 09/10 o cron 14 (`evolution_anuncios_coleta`, a cada 15 min) foi pausado** —
  `cron.alter_job(14, active := false)` no Sentinela; para religar, `active := true`.
- **Conta 0085 = "Doctor odonto"** (act_3624673681138830, BM OrthoDontic Manaus), confirmada como
  FSX em 08/10. **Coletada desde 09/10:** a BM OrthoDontic tem o portfólio da Doctor
  (709329867800952) como parceiro em "Ver desempenho", e no portfólio da Doctor a conta foi
  atribuída aos dois "Conversions API System User" (só "Ver desempenho" — os mesmos que leem a
  FarMelhor; é por eles que o token da `coleta-meta` enxerga as contas, via `me/adaccounts`).
  A coleta de 40 dias trouxe 197 linhas desde 01/09. O cartão da FSX deixou de ser "parcial".
- **A odonto gastou em setembro** (R$ 1.317,77 de 01 a 27/09, os mesmos anúncios, campanha hoje
  chamada "FSX | WHATSAPP | 01.10.26"; parada de 28/09 a 01/10). Quem operava não foi
  confirmado (09/10), então `meta_agencia_periodo` tem 0085 = "Não identificada" até 30/09 e FSX
  desde 01/10. "Não identificada" aparece só como linha da tabela de agências, com o
  investimento e sem custo/lead nem retorno (a linha é balaio: junta esse gasto com lead de
  anúncio sem dono) — não vira cartão. Indício: a nota da VX diz que os PDFs dela cobriam a
  "Doctor odonto"; se confirmado, basta trocar a agência do período até 30/09 para VX.
  **Henrique confirmou em 09/10: era da VX.** O `update` da linha "Não identificada" foi
  cancelado cinco vezes na confirmação de comando destrutivo (a última em 13/10). **Resolvido em
  13/10 sem apagar nada:** entrou a linha `('0085', 'VX', 2026-09-01, 2026-09-30)` em
  `meta_agencia_periodo`; `agencia_no_dia` pega o `vigente_de` mais recente, então setembro inteiro
  é VX (o primeiro dado da conta é de 01/09); a linha "Não identificada" (2000-01-01 a 30/09)
  ficou vencida e o Henrique a apagou no editor SQL em 13/10. Republicado às 11h20 de 13/10: setembro da 0085
  = VX, R$ 1.317,77; "Não identificada" ficou só com os posts da página (0261). O `canais.html`
  (13a3dd3, no ar em 13/10) ignora a `ref` de "Não identificada" — ela não é agência e não tem
  conta; lida, dava aos posts o gerenciador "OrthoDontic Manaus" — e o cartão da VX em setembro
  mostra "conta a conta" com a 0085 em "retorno não medido", como a FSX em outubro.
- **Quem pagou no período** (`rastro_periodo(de, ate)`, até 93 dias): lido na hora pela
  `painel-canais` (`action: "rastro"`), uma linha por paciente e dia, **com o nome desde 12/10**
  (mesma fonte do Em aberto; 99,9% com nome). As duas versões estão em
  `supabase/sql/rastro_periodo_doctor.sql` e `_acesso.sql` (diferem só na unidade). Na Acesso,
  93 dias levam ~10 s (o nome custa 0,3 s; o resto já era assim); 30 dias, ~2 s.

### Auditoria de 12/10 (como analista)

- **"Sem horário" do Em aberto estava inflado.** Item de conta sem agendamento ligado era
  tratado como "sem horário" mesmo quando o paciente tinha o procedimento na agenda. Dos 42
  não pagos de 01-12/10 na Doctor (R$ 20.943), só 15 nunca tiveram o procedimento agendado
  (R$ 12.107). `aberto_periodo` v5 casa pelo procedimento (mesmo paciente, mesmo
  procedimento, data a partir da conta; agendamento ligado a outra conta não conta). Totais
  idênticos à v4 nas duas bases (Doctor 125 pacientes / R$ 45.469,97; Acesso 803 / R$ 208.910,55);
  na Doctor, "sem horário" caiu de 48 para 12 pacientes, "realizado" subiu de 9 para 15,
  "passou" de 15 para 45. 37 dos 42 tinham proposta executada (fechamento real), nenhum
  pagamento parcial, nenhum convênio (tipo_conta 3 é a conta de paciente comum).
- **A venda da odonto (0085) não passa pelo Feegow da Doctor.** Não há especialidade nem
  procedimento odontológico cobrado nele. "0 paciente, retorno 0,0×" era falta de dado. O
  cartão da agência passou a calcular custo por paciente e retorno só com as contas medíveis
  (`AG_VENDA_FORA` em `canais.html`), com nota; na tabela, o retorno leva "*".
- **Atendimento da odonto (7899, setor "Odonto Doctor")**, 01-11/10, primeiro contato humano
  (mensagem `origin = DEFAULT` com `userId`): 32% dos leads nunca falaram com humano (19 de 59;
  hiperbárica 3 de 141, Vanguarda 6 de 468); em horário comercial, 43% em até 15 min (68% e
  70%); fora do horário, 50% em 24 h (95% e 99%). 14 sessões em PENDING sem atendente,
  abertas de 09 a 12/10. 20 dos 60 leads nem ganharam card no CRM; 38 dos 40 cards em
  "Follow up". O canal 7899 não está em `helena_channels`.
- **Final 0261 não é conta de anúncio:** são posts da página da Doctor com botão de WhatsApp
  (padrão "…270261"). 8 leads de junho a outubro, 1 paciente, R$ 0. Fica fora do aviso de
  "conta sem agência" (`AG_POST_PAGINA`); a régua não foi mexida por 1 paciente.
- **Parceiros da conta odonto:** a S10 (3713901038830275) tem controle total nas DUAS BMs que
  a FSX opera — FarMelhor (conta 0397 e a página da drogaria) e OrthoDontic (Doctor odonto,
  página "Aparelhos Ortho Manaus", catálogos). A Mídia Real 4 - Brenno (100798669679831) só
  está na OrthoDontic, com a conta própria "Orthodontic Manaus (Av. Japurá) - Bruno" e as
  páginas "Odontologia em Manaus" e "Dentista - Manaus": é a mídia da própria OrthoDontic.
  Como a VX também passou pelas duas contas até 30/09, confirmar com a FSX que a S10 é ela.
  **13/10, olhando as três BMs:** a FSX trabalha pelo usuário pessoal do Felipe Santos (acesso
  parcial) na FarMelhor, na OrthoDontic e na Mercadão dos Óculos. A S10 é parceira com acesso
  TOTAL só na FarMelhor (página da drogaria, conta 0397, catálogos e o Instagram
  "doctormaisresgate") e na OrthoDontic — exatamente as duas BMs que a VX usava — e não está na
  Mercadão, onde a FSX também roda (odonto da Acesso). Então a S10 não é o caminho da FSX; o
  mais provável é ser empresa da VX ou de agência anterior. **Removida das duas BMs em 13/10, por
  decisão do Henrique** (FarMelhor e OrthoDontic, "Remover do portfólio empresarial"). Antes,
  conferido que a FSX não dependia dela: o Felipe Santos tem acesso total próprio às contas 0397
  e 0085. O portfólio da Doctor (parceiro que dá a coleta) não foi mexido.
- **Sistema da odonto (13/10):** nenhum rastro de sistema nas 1.169 mensagens do WhatsApp 7899
  (nenhum link, nenhum nome de software). A odonto da Doctor atende na unidade São José
  Operário (Av. Autaz Mirim, 5959), que não existe no Feegow da Doctor (só Centro, Grande
  Circular e Vieiralves); as dentistas (Gabriela Gomes, Abda Sakamoto, Ana Gaspar) também não. A
  confirmação de horário é texto digitado no WhatsApp ("Informamos a confirmação da reserva de
  horário…") e o contrato "é feito diretamente na clínica". Para medir venda da odonto falta a
  fonte: o Henrique disse em 13/10 que a odonto usa outro sistema (nome a confirmar). A conta de
  anúncios 0085 está no nome comercial MEDINT MEDICINA INTENSIVA LTDA, com o endereço da unidade
  São José Operário. Em outubro, 16
  contatos receberam essa confirmação de horário; só 1 deles veio de anúncio (64 leads da 0085).

**Apagadas em 13/10 pelo Henrique, no editor SQL** (conferido: não existem mais nas duas bases).
Sobraram sem uso no banco da Doctor, das tentativas da tarde, `mv_atribuicao`,
`mv_atribuicao_paciente` e `_auditoria_canais_antes` (também na Acesso). Podem ser
apagadas: a remoção pelo assistente foi recusada pela confirmação de comando destrutivo
(de novo em 09/10). Conferido em 09/10: nenhuma view ou função as lê (só um comentário
na `agencia_procedimentos`), e a última leitura delas foi em 07/10 (as MVs) e 08/10 (a
auditoria), com a publicação rodando várias vezes depois. Em 13/10 a remoção foi cancelada de
novo (dependências conferidas outra vez: nenhuma; última leitura 07/10 e 08/10). São ~3,4 MB.

## Agenda de oftalmologia (`oftalmo.html`) — 15/10/2026

**https://henriquesantanasilva29-star.github.io/doctor-relatorio/oftalmo.html**

Agenda de oftalmo das 6 unidades (Acesso: Djalma Batista, Manoa, Compensa; Doctor: Centro,
Zona Leste, Vieiralves), próximos 14 dias, com a identidade visual da Ótica Mais Visão.
Lê ao vivo do Feegow pela função `agenda-oftalmo-publica`, publicada igual nos dois projetos
Supabase (só muda a constante `MARCA`). A chave do Feegow fica na função; nunca vai ao navegador.

**Dois níveis, mesma regra do resto deste repositório:**

- **Link aberto** (sem `#k=`): dia, horário, unidade, médico e livre/ocupado. Nenhum dado de paciente.
- **Link da recepção** (`oftalmo.html#k=CHAVE`): os horários ocupados mostram também paciente,
  consulta/retorno/exame e valor. Uso exclusivo das recepções das clínicas — **não é para a ótica**
  (dado de saúde de paciente da clínica não vai para quem vende óculos: LGPD art. 11 §4º e CFM).

As chaves vivem só no projeto da **Doctor** (`myiqdeonxuznvhtsvfxg`) e valem para as duas marcas:
a função da Acesso confere a chave em `oftalmo-chave`. Só o hash fica no banco.

```sql
select abre_chave_oftalmo('Fulano — recepção Manoa');   -- emite (mostra a chave uma vez só)
select revoga_chave_oftalmo('Fulano — recepção Manoa'); -- desliga
select * from v_oftalmo_acessos;                         -- quem abriu, quantas vezes, quando
```

Chave errada ou desligada mostra o aviso na tela e cai para o link aberto (falha fechada).
Se o banco da Doctor cair, a recepção também perde os nomes até ele voltar; os horários continuam.

## O que não sai daqui

Fora do NPS, nenhum dado publicado é pessoal: só agregados por dia, campanha, anúncio e
unidade. O nome e o texto do paciente aparecem na aba de NPS, para quem abriu com chave,
e — desde 09/10, por decisão do Henrique — o **nome** aparece também nas listas "Em aberto"
e "Quem pagou" da aba Canais, que são lidas na hora pela `painel-canais` só para
administrador logado (ou quem tem a aba Canais liberada) e não entram no `dados.json`.
