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

## O que não sai daqui

Fora do NPS, nenhum dado é pessoal: só agregados por dia, campanha, anúncio e
unidade. O nome e o texto do paciente aparecem **apenas** na aba de NPS, e
apenas para quem abriu com chave.
