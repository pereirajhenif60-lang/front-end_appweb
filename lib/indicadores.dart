import 'package:flutter/material.dart';

import 'admin.dart';
import 'caixa.dart';
import 'main.dart';
import 'recepcao.dart';

// ───── indicadores/limites.dart ─────
// Limites que disparam os alertas de "revisar fluxo de clientes". Ajuste conforme a rotina.
const limiteEsperaMin = 30; // espera (atual ou média) acima disso gera alerta
const limiteFilaPessoas = 5; // pessoas aguardando na fila
const limiteAtendimentoMin = 90; // atendimento em andamento há mais que isso
const limiteTaxaFaltas = 0.15; // 15% de faltas
const limiteTaxaCancelamento = 0.20; // 20% de cancelamentos
const minimoConfirmacao = 0.60; // abaixo de 60% de confirmados nas próximas 48h
const limiteDemandaEspontanea = 0.30; // 30% de clientes chegando sem agendamento
const lotacaoAmanha = 0.90; // agenda de amanhã quase cheia
const janelaAlertaDias = 30; // período usado nas médias dos alertas

// ───── indicadores/alertas.dart ─────
enum NivelAlerta {
  critico('Crítico', Colors.red, Icons.error_outline),
  atencao('Atenção', Colors.orange, Icons.warning_amber),
  info('Informação', Colors.blue, Icons.info_outline);

  const NivelAlerta(this.rotulo, this.cor, this.icone);
  final String rotulo;
  final Color cor;
  final IconData icone;
}

enum CategoriaAlerta {
  fila('Fila'),
  atendimento('Atendimento'),
  presenca('Presença'),
  agenda('Agenda');

  const CategoriaAlerta(this.rotulo);
  final String rotulo;
}

class AlertaFluxo {
  const AlertaFluxo(this.nivel, this.categoria, this.titulo, this.detalhe);

  final NivelAlerta nivel;
  final CategoriaAlerta categoria;
  final String titulo, detalhe;
}

String _pct(double v) => '${(v * 100).round()}%';

/// Alertas automáticos para revisar o fluxo de clientes da área (fila, atendimento,
/// presença e agenda). Calculados na hora a partir dos dados do sistema.
List<AlertaFluxo> alertasDeFluxo(Area a) {
  final agora = DateTime.now();
  final fim = DateTime(agora.year, agora.month, agora.day + 1);
  final m30 = MetricasFluxo(a, DateTime(agora.year, agora.month, agora.day - (janelaAlertaDias - 1)), fim);
  final l = <AlertaFluxo>[];

  // Fila agora
  final aguardando = filaAtendimento.aguardando(a);
  SenhaFila? maior;
  var maiorMin = 0;
  for (final s in aguardando) {
    final mnt = agora.difference(s.chegada).inMinutes;
    if (mnt > maiorMin) {
      maiorMin = mnt;
      maior = s;
    }
  }
  if (maior != null && maiorMin > limiteEsperaMin) {
    l.add(AlertaFluxo(
        NivelAlerta.critico,
        CategoriaAlerta.fila,
        'Revisar fluxo: espera acima de $limiteEsperaMin min',
        '${maior.cliente.nome} (senha ${maior.codigo}) aguarda há $maiorMin min. Chame o próximo ou acione outro profissional.'));
  }
  if (aguardando.length >= limiteFilaPessoas) {
    l.add(AlertaFluxo(
        NivelAlerta.atencao,
        CategoriaAlerta.fila,
        'Fila com ${aguardando.length} pessoas',
        'Há $limiteFilaPessoas ou mais clientes aguardando. Veja se dá para redistribuir os atendimentos.'));
  }

  // Atendimentos longos
  final longos = dados
      .doArea(a)
      .where((x) =>
          x.status == StatusAtend.emAtendimento &&
          x.iniciadoEm != null &&
          agora.difference(x.iniciadoEm!).inMinutes > limiteAtendimentoMin)
      .toList();
  if (longos.isNotEmpty) {
    l.add(AlertaFluxo(
        NivelAlerta.atencao,
        CategoriaAlerta.atendimento,
        'Atendimento acima do tempo previsto',
        '${longos.map((x) => '${x.cliente.nome} (${agora.difference(x.iniciadoEm!).inMinutes} min)').join(', ')}. Confira se já pode ser concluído.'));
  }

  // Médias dos últimos 30 dias
  if (m30.esperas.length >= 5 && m30.esperaMedia > limiteEsperaMin) {
    l.add(AlertaFluxo(
        NivelAlerta.atencao,
        CategoriaAlerta.fila,
        'Revisar fluxo: espera média de ${m30.esperaMedia.round()} min',
        'Nos últimos $janelaAlertaDias dias a espera média passou de $limiteEsperaMin min. Revise a chegada e a chamada dos clientes.'));
  }
  if ((m30.concluidos.length + m30.faltas) >= 5 && m30.taxaFaltas > limiteTaxaFaltas) {
    l.add(AlertaFluxo(
        m30.taxaFaltas > 0.25 ? NivelAlerta.critico : NivelAlerta.atencao,
        CategoriaAlerta.presenca,
        'Revisar fluxo: taxa de faltas de ${_pct(m30.taxaFaltas)}',
        'Nos últimos $janelaAlertaDias dias foram ${m30.faltas} faltas. Reforce lembretes e confirmações.'));
  }
  if (m30.todos.length >= 8 && m30.taxaCancelamento > limiteTaxaCancelamento) {
    l.add(AlertaFluxo(
        NivelAlerta.atencao,
        CategoriaAlerta.agenda,
        'Muitos cancelamentos (${_pct(m30.taxaCancelamento)})',
        'Nos últimos $janelaAlertaDias dias ${m30.cancelados} agendamentos foram cancelados. Vale entender os motivos.'));
  }
  if (m30.senhas.length >= 5 && m30.demandaEspontanea > limiteDemandaEspontanea) {
    l.add(AlertaFluxo(
        NivelAlerta.info,
        CategoriaAlerta.agenda,
        'Muitos clientes chegam sem agendamento (${_pct(m30.demandaEspontanea)})',
        'Considere divulgar mais o agendamento online ou abrir horários para encaixe.'));
  }

  // Próximas 48 horas
  final prox = dados
      .doArea(a)
      .where((x) =>
          x.aberto &&
          x.quando.isAfter(agora) &&
          x.quando.isBefore(agora.add(const Duration(hours: 48))))
      .toList();
  if (prox.length >= 3) {
    final conf = prox.where(agendamentoConfirmado).length;
    if (conf / prox.length < minimoConfirmacao) {
      l.add(AlertaFluxo(
          NivelAlerta.atencao,
          CategoriaAlerta.presenca,
          'Poucas confirmações para as próximas 48h',
          '$conf de ${prox.length} agendamentos confirmados. Envie ou reforce os lembretes por WhatsApp.'));
    }
  }
  final semResposta = prox.where((x) => x.lembrete == StatusLembrete.semResposta).length;
  if (semResposta > 0) {
    l.add(AlertaFluxo(
        NivelAlerta.atencao,
        CategoriaAlerta.presenca,
        '$semResposta cliente(s) sem resposta ao lembrete',
        'O prazo de confirmação passou. Entre em contato antes do horário.'));
  }

  // Presença
  final vencidos = dados
      .doArea(a)
      .where((x) => x.aberto && x.quando.isBefore(agora.subtract(const Duration(hours: 1))) && !x.chegou)
      .length;
  if (vencidos > 0) {
    l.add(AlertaFluxo(
        NivelAlerta.atencao,
        CategoriaAlerta.presenca,
        '$vencidos agendamento(s) vencido(s) sem check-in',
        'Processe as ausências na aba Faltas para manter a agenda e as faltas em dia.'));
  }
  final bloqueados = dados
      .clientes(a)
      .where((u) => dados.faltas(u) >= 3 && !dados.liberados.contains(u.id))
      .length;
  if (bloqueados > 0) {
    l.add(AlertaFluxo(
        NivelAlerta.info,
        CategoriaAlerta.presenca,
        '$bloqueados cliente(s) com 3 faltas',
        'Novos agendamentos estão bloqueados. Revise cada caso na aba Faltas.'));
  }

  // Agenda de amanhã
  final amanha = DateTime(agora.year, agora.month, agora.day + 1);
  final capacidade = horariosDoDia(a, amanha).length * dados.profissionais(a).length;
  if (capacidade > 0) {
    final ag = dados.doArea(a).where((x) => mesmoDia(x.quando, amanha) && x.aberto).length;
    if (ag == 0) {
      l.add(AlertaFluxo(NivelAlerta.info, CategoriaAlerta.agenda, 'Agenda de amanhã sem agendamentos',
          'Nenhum cliente agendado. Vale divulgar horários ou chamar clientes da lista de espera.'));
    } else if (ag / capacidade >= lotacaoAmanha) {
      l.add(AlertaFluxo(NivelAlerta.atencao, CategoriaAlerta.agenda, 'Agenda de amanhã quase lotada',
          '$ag de $capacidade horários ocupados. Avalie reforço de equipe.'));
    }
  }

  l.sort((x, y) => x.nivel.index.compareTo(y.nivel.index));
  return l;
}

/// Seção "Revisar fluxo de clientes". Use [so] para mostrar só algumas categorias
/// (ex.: fila e atendimento na recepção) e [mostrarVazio] = false para não mostrar nada quando está tudo bem.
List<Widget> secaoAlertasFluxo(BuildContext c, Area a,
    {Set<CategoriaAlerta>? so, bool titulo = true, bool mostrarVazio = true}) {
  final todos = alertasDeFluxo(a).where((x) => so == null || so.contains(x.categoria)).toList();
  if (todos.isEmpty && !mostrarVazio) return [];
  return [
    if (titulo) ...[
      Text('Revisar fluxo de clientes', style: Theme.of(c).textTheme.titleMedium),
      const SizedBox(height: 4),
      const Text('Alertas automáticos sobre fila, atendimento, presença e agenda.',
          style: TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
    ],
    if (todos.isEmpty)
      const Card(
        child: ListTile(
          leading: Icon(Icons.check_circle, color: Colors.green),
          title: Text('Fluxo de clientes dentro do esperado.'),
        ),
      )
    else
      for (final x in todos)
        Card(
          color: x.nivel.cor.withAlpha(25),
          child: ListTile(
            leading: Icon(x.nivel.icone, color: x.nivel.cor),
            title: Text(x.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(x.detalhe),
            trailing: chipRotulo(x.categoria.rotulo, x.nivel.cor),
          ),
        ),
    const SizedBox(height: 8),
  ];
}

// ───── indicadores/metricas.dart ─────
enum PeriodoPainel {
  hoje('Hoje', 0),
  dias7('7 dias', 6),
  dias30('30 dias', 29);

  const PeriodoPainel(this.rotulo, this.dias);
  final String rotulo;
  final int dias;

  DateTime get inicio {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day - dias);
  }
}

/// Indicadores do fluxo de clientes de uma área num período [inicio, fim).
class MetricasFluxo {
  MetricasFluxo(this.area, this.inicio, this.fim);

  final Area area;
  final DateTime inicio, fim;

  late final List<Atend> todos = dados
      .doArea(area)
      .where((x) => !x.quando.isBefore(inicio) && x.quando.isBefore(fim))
      .toList();
  late final List<Atend> concluidos =
      todos.where((x) => x.status == StatusAtend.concluido).toList();
  late final int faltas = todos.where((x) => x.status == StatusAtend.ausente).length;
  late final int cancelados = todos.where((x) => x.status == StatusAtend.cancelado).length;
  late final int emAberto =
      todos.where((x) => x.aberto || x.status == StatusAtend.emAtendimento).length;

  late final double taxaFaltas = (concluidos.length + faltas) == 0
      ? 0
      : faltas / (concluidos.length + faltas);
  late final double taxaCancelamento = todos.isEmpty ? 0 : cancelados / todos.length;

  late final List<Atend> _validos = todos.where((x) => x.status != StatusAtend.cancelado).toList();
  late final double taxaConfirmacao =
      _validos.isEmpty ? 0 : _validos.where(agendamentoConfirmado).length / _validos.length;

  late final List<SenhaFila> senhas = filaAtendimento
      .historico(area)
      .where((s) => !s.chegada.isBefore(inicio) && s.chegada.isBefore(fim))
      .toList();
  late final List<int> esperas = [
    for (final s in senhas)
      if (s.chamadaEm != null) s.chamadaEm!.difference(s.chegada).inMinutes,
  ];
  late final double esperaMedia =
      esperas.isEmpty ? 0 : esperas.fold(0, (s, v) => s + v) / esperas.length;
  late final double demandaEspontanea =
      senhas.isEmpty ? 0 : senhas.where((s) => s.semAgendamento).length / senhas.length;

  late final List<int> duracoes = [
    for (final x in concluidos)
      if (x.iniciadoEm != null && x.concluidoEm != null)
        x.concluidoEm!.difference(x.iniciadoEm!).inMinutes,
  ];
  late final double duracaoMedia =
      duracoes.isEmpty ? 0 : duracoes.fold(0, (s, v) => s + v) / duracoes.length;

  late final List<Lancamento> lancs = dados.lancamentos
      .where((l) =>
          l.area == area && l.ativo && !l.data.isBefore(inicio) && l.data.isBefore(fim))
      .toList();
  late final int receita = lancs.fold(0, (s, l) => s + l.valorCentavos);
  int get ticket {
    final pagos = concluidos.where((x) => x.lancado).length;
    return pagos == 0 ? 0 : (receita / pagos).round();
  }

  late final int clientesUnicos = {for (final x in concluidos) x.cliente}.length;

  late final List<DateTime> dias = () {
    final r = <DateTime>[];
    var d = DateUtils.dateOnly(inicio);
    while (d.isBefore(fim)) {
      r.add(d);
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return r;
  }();

  List<int> get concluidosPorDia =>
      [for (final d in dias) concluidos.where((x) => mesmoDia(x.quando, d)).length];

  late final Map<int, int> porHora = () {
    final m = <int, int>{};
    for (final x in _validos) {
      m[x.quando.hour] = (m[x.quando.hour] ?? 0) + 1;
    }
    return m;
  }();
}

// ───── indicadores/graficos.dart ─────
/// Gráfico de colunas simples (sem pacotes).
class GraficoColunas extends StatelessWidget {
  const GraficoColunas({
    super.key,
    required this.valores,
    required this.rotulos,
    required this.cor,
    this.altura = 140,
  });

  final List<int> valores;
  final List<String> rotulos;
  final Color cor;
  final double altura;

  @override
  Widget build(BuildContext context) {
    final max = valores.fold(0, (m, v) => v > m ? v : m);
    if (valores.isEmpty || max == 0) return const Text('Sem dados no período.');
    final passo = valores.length > 14 ? (valores.length / 7).ceil() : 1;
    return SizedBox(
      height: altura + 48,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < valores.length; i++)
            Expanded(
              child: Tooltip(
                message: '${rotulos[i]}: ${valores[i]}',
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: valores.length > 20 ? 1 : 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(valores.length <= 14 && valores[i] > 0 ? '${valores[i]}' : '',
                          maxLines: 1, style: const TextStyle(fontSize: 11)),
                      Container(
                        height: (altura * valores[i] / max).clamp(2, altura).toDouble(),
                        decoration: BoxDecoration(
                          color: cor,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(i % passo == 0 ? rotulos[i] : '',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ItemBarra {
  const ItemBarra(this.rotulo, this.valor, this.cor, [this.texto]);

  final String rotulo;
  final num valor;
  final Color cor;
  final String? texto;
}

/// Barras horizontais simples (sem pacotes).
class BarrasHorizontais extends StatelessWidget {
  const BarrasHorizontais(this.itens, {super.key});

  final List<ItemBarra> itens;

  @override
  Widget build(BuildContext context) {
    final max = itens.fold<num>(0, (m, i) => i.valor > m ? i.valor : m);
    if (itens.isEmpty || max == 0) return const Text('Sem dados no período.');
    return Column(
      children: [
        for (final i in itens)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 120, child: Text(i.rotulo, overflow: TextOverflow.ellipsis)),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (i.valor / max).toDouble(),
                    minHeight: 14,
                    color: i.cor,
                    backgroundColor: i.cor.withAlpha(30),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: Text(i.texto ?? '${i.valor}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
      ],
    );
  }
}

// ───── indicadores/painel_indicadores.dart ─────
class PainelIndicadores extends StatefulWidget {
  const PainelIndicadores(this.a, {super.key});

  final Area a;

  @override
  State<PainelIndicadores> createState() => _PainelIndicadoresState();
}

class _PainelIndicadoresState extends State<PainelIndicadores> {
  PeriodoPainel _p = PeriodoPainel.dias7;

  Widget _cartao(BuildContext c, String titulo, Widget filho) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: Theme.of(c).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            filho,
          ]),
        ),
      );

  Widget _duplo(Widget x, Widget y) => LayoutBuilder(
        builder: (context, box) => box.maxWidth >= 820
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: x),
                const SizedBox(width: 16),
                Expanded(child: y),
              ])
            : Column(children: [x, const SizedBox(height: 16), y]),
      );

  List<Widget> _linhaProf(MetricasFluxo m, Usuario p) {
    final c = m.concluidos.where((x) => x.prof == p).toList();
    final f = m.todos.where((x) => x.prof == p && x.status == StatusAtend.ausente).length;
    final d = [
      for (final x in c)
        if (x.iniciadoEm != null && x.concluidoEm != null)
          x.concluidoEm!.difference(x.iniciadoEm!).inMinutes,
    ];
    final r = c.fold(0, (s, x) => s + x.valorPago);
    return [
      Text(p.nome),
      Text('${c.length}'),
      Text('$f'),
      Text(d.isEmpty ? '—' : '${(d.fold(0, (s, v) => s + v) / d.length).round()} min'),
      Text(formatarReais(r)),
    ];
  }

  @override
  Widget build(BuildContext context) => Obs((c) {
        final a = widget.a;
        final hoje = DateTime.now();
        final fim = DateTime(hoje.year, hoje.month, hoje.day + 1);
        final m = MetricasFluxo(a, _p.inicio, fim);

        final horas = [
          for (var h = horaInicioPorArea[a]!; h < horaFimPorArea[a]!; h++) h,
        ];
        final porProc = <String, List<Atend>>{};
        for (final x in m.concluidos) {
          porProc.putIfAbsent(x.servico, () => []).add(x);
        }
        final procs = porProc.entries.toList()
          ..sort((x, y) => y.value.length.compareTo(x.value.length));
        final profs = <Usuario>{for (final x in m.todos) x.prof}.toList()
          ..sort((x, y) => x.nome.compareTo(y.nome));

        return Pagina(
          titulo: 'Painel de indicadores – ${a.nome}',
          sub: 'Visão do fluxo de clientes: fila, atendimentos, presença, agenda e receita. Os alertas abaixo usam limites que você pode ajustar no início do arquivo indicadores.dart.',
          acoes: [
            SegmentedButton<PeriodoPainel>(
              showSelectedIcon: false,
              segments: [
                for (final p in PeriodoPainel.values)
                  ButtonSegment(value: p, label: Text(p.rotulo)),
              ],
              selected: {_p},
              onSelectionChanged: (s) => setState(() => _p = s.first),
            ),
          ],
          filhos: [
            ...secaoAlertasFluxo(c, a),
            const SizedBox(height: 16),
            Wrap(spacing: 16, runSpacing: 16, children: [
              kpi(Icons.task_alt, 'Atendimentos concluídos', '${m.concluidos.length}', Colors.green),
              kpi(Icons.people_alt_outlined, 'Clientes atendidos', '${m.clientesUnicos}', Colors.indigo),
              kpi(Icons.event_busy, 'Taxa de faltas', _pct(m.taxaFaltas),
                  m.taxaFaltas > limiteTaxaFaltas ? Colors.red : Colors.teal),
              kpi(Icons.mark_email_read_outlined, 'Taxa de confirmação', _pct(m.taxaConfirmacao),
                  m.taxaConfirmacao < minimoConfirmacao ? Colors.orange : Colors.teal),
              kpi(Icons.hourglass_bottom, 'Espera média',
                  m.esperas.isEmpty ? '—' : '${m.esperaMedia.round()} min',
                  m.esperaMedia > limiteEsperaMin ? Colors.red : Colors.blue),
              kpi(Icons.timer_outlined, 'Duração média',
                  m.duracoes.isEmpty ? '—' : '${m.duracaoMedia.round()} min', Colors.deepPurple),
              kpi(Icons.payments, 'Receita', formatarReais(m.receita), Colors.green),
              kpi(Icons.receipt_long, 'Ticket médio', formatarReais(m.ticket), Colors.teal),
              kpi(Icons.event_note, 'Cancelamentos', _pct(m.taxaCancelamento), Colors.blueGrey),
              kpi(Icons.directions_walk, 'Sem agendamento', _pct(m.demandaEspontanea), Colors.amber),
            ]),
            const SizedBox(height: 24),
            if (_p != PeriodoPainel.hoje) ...[
              _cartao(
                c,
                'Atendimentos concluídos por dia',
                GraficoColunas(
                  valores: m.concluidosPorDia,
                  rotulos: [for (final d in m.dias) '${doisDigitos(d.day)}/${doisDigitos(d.month)}'],
                  cor: a.cor,
                ),
              ),
              const SizedBox(height: 16),
            ],
            _duplo(
              _cartao(
                c,
                'Movimento por horário',
                GraficoColunas(
                  valores: [for (final h in horas) m.porHora[h] ?? 0],
                  rotulos: [for (final h in horas) '${h}h'],
                  cor: Colors.indigo,
                ),
              ),
              _cartao(
                c,
                'Resultado dos agendamentos',
                BarrasHorizontais([
                  ItemBarra('Concluídos', m.concluidos.length, Colors.green),
                  ItemBarra('Faltas', m.faltas, Colors.red),
                  ItemBarra('Cancelados', m.cancelados, Colors.grey),
                  ItemBarra('Em aberto', m.emAberto, Colors.blue),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            _duplo(
              _cartao(
                c,
                'Receita por forma de pagamento',
                BarrasHorizontais([
                  for (final f in FormaPagamento.values)
                    ItemBarra(
                      f.rotulo,
                      m.lancs.where((l) => l.forma == f).fold(0, (s, l) => s + l.valorCentavos),
                      Colors.green,
                      formatarReais(
                          m.lancs.where((l) => l.forma == f).fold(0, (s, l) => s + l.valorCentavos)),
                    ),
                ]),
              ),
              _cartao(
                c,
                'Atendimentos por procedimento',
                BarrasHorizontais([
                  for (final e in procs.take(6))
                    ItemBarra(e.key, e.value.length, a.cor,
                        '${e.value.length} • ${formatarReais(e.value.fold(0, (s, x) => s + x.valorPago))}'),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            Text('Por profissional', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            tabela(
              ['Profissional', 'Concluídos', 'Faltas', 'Duração média', 'Receita'],
              [for (final p in profs) _linhaProf(m, p)],
            ),
          ],
        );
      });
}