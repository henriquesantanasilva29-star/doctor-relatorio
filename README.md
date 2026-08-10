# Doctor Mais Saúde — relatório de performance

Dois documentos estáticos, sem servidor e sem banco: todo o dado vai embutido e o
cálculo acontece no navegador. Abrem offline depois de baixados.

| Arquivo | O que é |
|---|---|
| `index.html` | Relatório de performance — mídia paga, Meta × CRM, comercial e financeiro, conferência. Período editável no cabeçalho. |
| `painel.html` | Painel de mídia, mais enxuto, com a mesma conciliação Meta × CRM. |

## O que o relatório responde

- **Mídia paga** — investimento, impressões, cliques, CTR, CPC, CPM e conversas
  iniciadas por campanha, na conta `act_1400309970874524`.
- **Meta × CRM** — o que cada sistema conta e por que os números diferem. A Meta
  conta conversa (evento, creditada ao dia do anúncio); o Life CRM conta contato
  (pessoa, no dia da mensagem). Em julho/2026 a lacuna foi de 545 conversas, e
  522 delas eram gente que já estava no CRM e voltou a conversar.
- **Comercial e financeiro** — propostas, execução, faturamento e caixa das
  unidades 0, 2 e 4.
- **Conferência** — nossa coleta contra o relatório de julho da agência,
  linha a linha.

Clicar numa especialidade abre os anúncios dela: miniatura, texto, chamada e o
funil de cada um, do investimento à receita executada.

## Três coisas que o documento não faz, de propósito

1. **Não publica alcance nem frequência.** São métricas desduplicadas; somar dia
   a dia infla o número em cerca de duas vezes (707.535 somado contra 313.926
   reais, em julho).
2. **Não mede cobertura antes de 03/06/2026.** O espelho de contatos do CRM
   começa nessa data. Cobertura baixa antes disso é ausência de fonte, não
   rastreio quebrado — e o relatório avisa em vez de deixar a conclusão errada
   acontecer.
3. **Não trata receita rastreada como receita total.** A ponte que liga telefone
   do CRM a paciente do Feegow resolve cerca de 17% dos contatos. O que aparece
   é piso, e está dito em cada painel.

## Dado que não está aqui

Nenhum dado pessoal. Não há nome, telefone, CPF, e-mail nem identificador de
paciente — só agregados por dia, campanha, anúncio e unidade.
