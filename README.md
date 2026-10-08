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
  por anúncio) e tem conta aberta no Feegow, com a situação tirada dos itens: realizado e não
  pago (cobrar), horário passou sem atendimento (remarcar), sem horário marcado (agendar),
  marcado (confirmar). Item sem agendamento carrega a data da conta, não um horário, e por isso
  não vira falta. Lido na hora pela `painel-canais` v5 (`action: "aberto"`), sem nome; a soma
  por agência confere com o cartão (08/10: FSX R$ 1.350,64, Vanguarda R$ 5.860,21). O SQL está
  em `supabase/sql/aberto_periodo.sql`.
- **Quem pagou no período** (`rastro_periodo(de, ate)`, até 93 dias): lido na hora pela
  `painel-canais` (`action: "rastro"`), uma linha por paciente e dia, sem nome.

Sobraram sem uso no banco da Doctor, das tentativas da tarde, `mv_atribuicao`,
`mv_atribuicao_paciente` e `_auditoria_canais_antes` (também na Acesso). Podem ser
apagadas: a remoção pelo assistente foi recusada pela confirmação de comando destrutivo.

## O que não sai daqui

Fora do NPS, nenhum dado é pessoal: só agregados por dia, campanha, anúncio e
unidade. O nome e o texto do paciente aparecem **apenas** na aba de NPS, e
apenas para quem abriu com chave.
