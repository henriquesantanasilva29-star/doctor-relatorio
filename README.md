# Doctor Mais Saúde — relatório de performance

**https://henriquesantanasilva29-star.github.io/doctor-relatorio/**

Abre em qualquer dia e mostra o dado até aquele dia. Ninguém precisa gerar nada.

## Como se atualiza

```
Meta Ads ─┐
Feegow   ─┼─► coleta automática ─► Supabase ─► publica-relatorio ─► este repositório
Life CRM ─┘   (de 2 em 2 min a       (banco)     (cron 05:30)         (GitHub Pages)
               1x por dia)
```

| Arquivo | Quem escreve | Quando |
|---|---|---|
| `index.html` | pessoa | quando o relatório muda de forma |
| `dados.json` | `publica-relatorio` | todo dia às 05:30, se algum número mudou |
| `criativos.json` | `publica-relatorio` | quando entra anúncio novo |

O commit só acontece se algum número mudou de verdade — dia sem veiculação não
gera commit. Assim o histórico do repositório continua dizendo alguma coisa.

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
- **NPS** — índice, taxa de resposta, nota média, subnotas do formulário, tempo
  de espera relatado e motivos, por unidade e por dia. É o mesmo dado dos quatro
  PDFs diários, conferido contra eles dígito a dígito em 01–10/08/2026.
- **Conferência** — nossa coleta contra o relatório de julho da agência.

### Sobre o NPS

A pesquisa não grava a unidade — ela é remontada pelo telefone, procurando
agendamento na Doctor em até três dias antes do envio. Quando a janela devolve
mais de uma unidade, ou nenhuma, a resposta entra no consolidado e em unidade
nenhuma. Por isso **a soma das três unidades é menor que o total**, e a linha
"sem unidade identificada" está na tabela para a conta fechar à vista.

A aba também mostra quantas respostas combinam nota baixa com subnotas altas —
o padrão de quem leu a régua ao contrário. Elas continuam contando no número
oficial; o que a página faz é dizer quanto o índice mudaria sem elas.

## Três coisas que ele não faz, de propósito

1. **Não publica alcance nem frequência.** São desduplicadas; somar dia a dia
   infla o número em cerca de duas vezes.
2. **Não mede cobertura antes de 03/06/2026**, quando o espelho de contatos do
   CRM começa. Número baixo antes disso é ausência de fonte, não rastreio
   quebrado — e a página avisa.
3. **Não trata receita rastreada como receita total.** A ponte telefone →
   paciente resolve cerca de 17%. O que aparece é piso, e está dito em cada painel.

## Não tem dado pessoal

Nenhum nome, telefone, CPF, e-mail ou identificador de paciente. Só agregados
por dia, campanha, anúncio e unidade.

**Comentário de paciente também não entra.** Esta página é pública e indexável;
comentário sobre atendimento, junto de data e unidade, é informação de saúde de
alguém potencialmente identificável. O que sai aqui é contagem, média e tema —
as vozes na íntegra continuam nos PDFs internos, que é onde ajudam a operação.
