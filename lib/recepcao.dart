import 'dart:async';

import 'package:flutter/material.dart';

import 'admin.dart';
import 'caixa.dart';
import 'indicadores.dart';
import 'main.dart';

// ───────────────────────── Modelo da fila ─────────────────────────

enum StatusSenha { aguardando, chamado, emAtendimento, desistiu }

extension StatusSenhaInfo on StatusSenha {
  String get rotulo => switch (this) {
        StatusSenha.aguardando => 'aguardando',
        StatusSenha.chamado => 'chamado',
        StatusSenha.emAtendimento => 'em atendimento',
        StatusSenha.desistiu => 'não compareceu',
      };

  Color get cor => switch (this) {
        StatusSenha.aguardando => Colors.blue,
        StatusSenha.chamado => Colors.orange,
        StatusSenha.emAtendimento => Colors.green,
        StatusSenha.desistiu => Colors.grey,
      };

  IconData get icone => switch (this) {
        StatusSenha.aguardando => Icons.hourglass_bottom,
        StatusSenha.chamado => Icons.campaign_outlined,
        StatusSenha.emAtendimento => Icons.play_circle_outline,
        StatusSenha.desistiu => Icons.person_off_outlined,
      };
}

/// Senha da fila: nasce no check-in e está sempre ligada a um agendamento/atendimento.
class SenhaFila {
  SenhaFila({
    required this.id,
    required this.codigo,
    required this.atend,
    required this.preferencial,
    required this.semAgendamento,
    required this.chegada,
  });

  final int id;
  final String codigo;
  final Atend atend;
  final bool preferencial;

  /// Cliente chegou sem agendamento (o atendimento foi criado no check-in).
  final bool semAgendamento;
  final DateTime chegada;

  StatusSenha status = StatusSenha.aguardando;
  DateTime? chamadaEm;
  int chamadas = 0;

  Area get area => atend.area;
  Usuario get cliente => atend.cliente;
  Usuario get prof => atend.prof;

  /// A senha ainda vale (não saiu da fila e o atendimento está em aberto ou em andamento)?
  bool get ativa =>
      status != StatusSenha.desistiu &&
      (atend.aberto || atend.status == StatusAtend.emAtendimento);

  /// Situação real: se o atendimento foi iniciado por outra tela (ex.: "Receber cliente"),
  /// a senha já aparece como "em atendimento".
  StatusSenha get situacao {
    if (status == StatusSenha.desistiu) return StatusSenha.desistiu;
    if (atend.status == StatusAtend.emAtendimento) return StatusSenha.emAtendimento;
    return status;
  }
}

/// Fila de atendimento em memória. Troque pelo seu backend.
class FilaAtendimento extends ChangeNotifier {
  FilaAtendimento() {
    _semear();
  }

  final _senhas = <SenhaFila>[];
  int _seq = 0;

  /// Todas as senhas da área (inclui dias anteriores), para os indicadores.
  List<SenhaFila> historico(Area a) => _senhas.where((s) => s.area == a).toList();

  /// Senhas de dias anteriores (dados de exemplo para o painel de indicadores).
  void _semear() {
    for (final x in dados.atendimentos) {
      final ini = x.iniciadoEm;
      if (x.status != StatusAtend.concluido || ini == null) continue;
      if (mesmoDia(x.quando, DateTime.now())) continue;
      _senhas.add(SenhaFila(
        id: ++_seq,
        codigo: '${x.area == Area.estetica ? 'E' : 'P'}${(x.id % 100).toString().padLeft(3, '0')}',
        atend: x,
        preferencial: false,
        semAgendamento: x.id % 7 == 0,
        chegada: ini.subtract(Duration(minutes: 6 + (x.id * 7) % 34)),
      )
        ..status = StatusSenha.emAtendimento
        ..chamadaEm = ini.subtract(const Duration(minutes: 2))
        ..chamadas = 1);
    }
  }

  void mudou() => notifyListeners();

  List<SenhaFila> doDia(Area a) => _senhas
      .where((s) => s.area == a && mesmoDia(s.chegada, DateTime.now()))
      .toList();

  static int _ordem(SenhaFila x, SenhaFila y) {
    if (x.preferencial != y.preferencial) return x.preferencial ? -1 : 1;
    return x.chegada.compareTo(y.chegada);
  }

  /// Aguardando, na ordem de chamada: prioritários primeiro, depois por chegada.
  List<SenhaFila> aguardando(Area a) => doDia(a)
      .where((s) => s.ativa && s.situacao == StatusSenha.aguardando)
      .toList()
    ..sort(_ordem);

  /// Já chamados e ainda não atendidos (o mais recente primeiro).
  List<SenhaFila> chamados(Area a) => doDia(a)
      .where((s) => s.ativa && s.situacao == StatusSenha.chamado)
      .toList()
    ..sort((x, y) => y.chamadaEm!.compareTo(x.chamadaEm!));

  List<SenhaFila> emAtendimento(Area a) => doDia(a)
      .where((s) => s.ativa && s.situacao == StatusSenha.emAtendimento)
      .toList()
    ..sort((x, y) => x.chegada.compareTo(y.chegada));

  /// Chamadas de hoje (a mais recente primeiro), para o painel da fila.
  List<SenhaFila> chamadasRecentes(Area a) => doDia(a)
      .where((s) => s.ativa && s.chamadaEm != null)
      .toList()
    ..sort((x, y) => y.chamadaEm!.compareTo(x.chamadaEm!));

  /// Senha ativa de um agendamento (se o cliente já fez check-in).
  SenhaFila? ativaDe(Atend x) {
    for (final s in _senhas) {
      if (s.atend == x && s.ativa) return s;
    }
    return null;
  }

  SenhaFila? ativaDoCliente(Usuario c, Area a) {
    for (final s in doDia(a)) {
      if (s.cliente == c && s.ativa) return s;
    }
    return null;
  }

  /// Última senha emitida para o agendamento (mesmo que já encerrada).
  SenhaFila? ultimaDe(Atend x) {
    SenhaFila? r;
    for (final s in _senhas) {
      if (s.atend == x) r = s;
    }
    return r;
  }

  SenhaFila emitir(Atend x, {required bool preferencial, required bool semAgendamento}) {
    final a = x.area;
    final hoje = DateTime.now();
    final n = _senhas
            .where((s) => s.area == a && s.preferencial == preferencial && mesmoDia(s.chegada, hoje))
            .length +
        1;
    final letra = a == Area.estetica ? 'E' : 'P';
    final prio = preferencial ? 'P' : '';
    final s = SenhaFila(
      id: ++_seq,
      codigo: '$letra$prio${n.toString().padLeft(3, '0')}',
      atend: x,
      preferencial: preferencial,
      semAgendamento: semAgendamento,
      chegada: hoje,
    );
    _senhas.add(s);
    notifyListeners();
    return s;
  }
}

final filaAtendimento = FilaAtendimento();

extension AtendChegada on Atend {
  /// O cliente já fez check-in (está na fila)? Quem fez check-in não vira "ausência".
  bool get chegou => filaAtendimento.ativaDe(this) != null;
}

// ───────────────────────── Utilitários de tela ─────────────────────────

/// Reconstrói quando [dados] ou a fila mudam, e a cada 30 s (para atualizar o tempo de espera).
class _Observa extends StatefulWidget {
  const _Observa(this.builder);

  final Widget Function(BuildContext) builder;

  @override
  State<_Observa> createState() => _ObservaState();
}

class _ObservaState extends State<_Observa> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([dados, filaAtendimento]),
        builder: (c, _) => widget.builder(c),
      );
}

class _Relogio extends StatefulWidget {
  const _Relogio();

  @override
  State<_Relogio> createState() => _RelogioState();
}

class _RelogioState extends State<_Relogio> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(formatarHora(DateTime.now()),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      );
}

Widget _chipSenha(SenhaFila s) => chipRotulo(
      s.codigo,
      s.preferencial ? Colors.purple : s.area.cor,
      icone: s.preferencial ? Icons.accessible : Icons.confirmation_number_outlined,
    );

/// Célula da senha de um atendimento (traço se o cliente não passou pela fila).
Widget celulaSenha(Atend x) {
  final s = filaAtendimento.ultimaDe(x);
  return s == null ? const Text('—') : _chipSenha(s);
}

/// Situação do cliente: cadastro, faltas e bloqueio/liberação.
Widget chipSituacaoCliente(Usuario c) {
  if (!c.ativo) return chipRotulo('cadastro desativado', Colors.grey, icone: Icons.block);
  final f = dados.faltas(c);
  if (f >= 3) {
    return dados.liberados.contains(c.id)
        ? chipRotulo('liberado (3 faltas)', Colors.orange, icone: Icons.lock_open)
        : chipRotulo('bloqueado (3 faltas)', Colors.red, icone: Icons.block);
  }
  if (f > 0) {
    final pl = f > 1 ? 's' : '';
    return chipRotulo('$f falta$pl', Colors.amber, icone: Icons.warning_amber);
  }
  return chipRotulo('regular', Colors.green, icone: Icons.check_circle_outline);
}

/// Confirmação do agendamento (lembrete respondido ou confirmado pela recepção).
bool agendamentoConfirmado(Atend x) =>
    x.status == StatusAtend.confirmado || x.lembrete == StatusLembrete.confirmado;

Widget chipConfirmacao(Atend x, {bool semAgendamento = false}) {
  if (semAgendamento) {
    return chipRotulo('sem agendamento', Colors.blueGrey, icone: Icons.directions_walk);
  }
  if (agendamentoConfirmado(x)) {
    return chipRotulo('confirmado', Colors.green, icone: Icons.check_circle_outline);
  }
  return switch (x.lembrete) {
    StatusLembrete.semResposta =>
      chipRotulo('sem resposta', Colors.red, icone: Icons.sms_failed_outlined),
    StatusLembrete.enviado =>
      chipRotulo('lembrete enviado', Colors.orange, icone: Icons.mark_email_unread_outlined),
    _ => chipRotulo('não confirmado', Colors.blueGrey, icone: Icons.help_outline),
  };
}

/// Início do atendimento, usado na recepção, no painel do auxiliar e no do administrador.
/// Só atende cliente cadastrado e ativo. Se o cliente está na fila, a senha dele passa a
/// "em atendimento" e o horário de início fica registrado.
void receberAtendimento(BuildContext c, Atend x, {String? autor}) {
  if (!dados.usuarios.contains(x.cliente) || !x.cliente.ativo) {
    alerta(c, 'Atendimento impedido',
        'Cliente não cadastrado ou desativado. O sistema impede o atendimento: solicite o cadastro prévio ao Administrador.');
    dados.log('Recebimento impedido: cliente ${x.cliente.nome} não cadastrado/ativo', x.area, autor);
    return;
  }
  final senha = filaAtendimento.ativaDe(x);
  if (senha != null) senha.status = StatusSenha.emAtendimento;
  x.status = StatusAtend.emAtendimento;
  x.iniciadoEm = DateTime.now();
  filaAtendimento.mudou();
  dados.log(
      'Cliente recebido para atendimento: ${x.cliente.nome} (#${x.id})${senha == null ? '' : ' • senha ${senha.codigo}'}',
      x.area,
      autor);
  msg(c, 'Atendimento de ${x.cliente.nome} iniciado.');
}

/// Tempo de atendimento: "há X min" enquanto em andamento; a duração depois de concluído.
Widget celulaTempo(Atend x) {
  final ini = x.iniciadoEm;
  if (ini == null) return const Text('—');
  final fim = x.concluidoEm;
  final min = (fim ?? DateTime.now()).difference(ini).inMinutes;
  return Text(fim == null ? 'há $min min' : '$min min');
}

/// Senha do cliente na fila, para a página do cliente (null se não fez check-in ou já saiu).
Widget? chipSenhaDoCliente(Atend x) {
  final s = filaAtendimento.ultimaDe(x);
  if (s == null || !s.ativa) return null;
  return chipRotulo('Senha ${s.codigo} • ${s.situacao.rotulo}', s.situacao.cor, icone: s.situacao.icone);
}

// ───────────────────────── Check-in ─────────────────────────

/// Abre o check-in e, se concluído, mostra a senha do cliente.
Future<void> abrirCheckin(BuildContext c, Area area, {String? autor, Atend? agendamento}) async {
  final s = await showDialog<SenhaFila>(
    context: c,
    builder: (_) => CheckinDialog(area: area, autor: autor, agendamento: agendamento),
  );
  if (s == null || !c.mounted) return;
  await showDialog<void>(
    context: c,
    builder: (d) => AlertDialog(
      title: const Text('Check-in realizado'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Senha de ${s.cliente.primeiroNome}'),
        Text(s.codigo,
            style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: area.cor)),
        if (s.preferencial) chipRotulo('Atendimento prioritário', Colors.purple, icone: Icons.accessible),
        const SizedBox(height: 12),
        const Text('Aguarde ser chamado(a) no painel da fila.', textAlign: TextAlign.center),
      ]),
      actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
    ),
  );
}

class CheckinDialog extends StatefulWidget {
  const CheckinDialog({super.key, required this.area, this.autor, this.agendamento});

  final Area area;
  final String? autor;

  /// Agendamento já escolhido (atalho da lista "aguardando chegada").
  final Atend? agendamento;

  @override
  State<CheckinDialog> createState() => _CheckinDialogState();
}

class _CheckinDialogState extends State<CheckinDialog> {
  Usuario? _cli;
  Atend? _agendamento;
  bool _sem = false; // chegou sem agendamento
  bool _preferencial = false;
  late String _serv = servicosDe(widget.area).first;
  Usuario? _prof;
  String? _erro;

  Area get _area => widget.area;

  @override
  void initState() {
    super.initState();
    final ps = dados.profissionais(_area);
    _prof = ps.isEmpty ? null : ps.first;
    final x = widget.agendamento;
    if (x != null) {
      _cli = x.cliente;
      _agendamento = x;
    }
  }

  List<Atend> _agendamentosDoDia() {
    final c = _cli;
    if (c == null) return const [];
    final l = dados
        .doArea(_area)
        .where((x) => x.cliente == c && x.aberto && mesmoDia(x.quando, DateTime.now()) && !x.chegou)
        .toList();
    l.sort((x, y) => x.quando.compareTo(y.quando));
    return l;
  }

  void _escolherCliente(Usuario? c) {
    setState(() {
      _cli = c;
      _erro = null;
      final l = _agendamentosDoDia();
      _agendamento = l.isEmpty ? null : l.first;
      _sem = l.isEmpty;
    });
  }

  void _fazerCheckin() {
    final cli = _cli;
    final autor = widget.autor;
    if (cli == null) {
      setState(() => _erro = 'Escolha o cliente.');
      return;
    }
    if (!cli.ativo || !dados.usuarios.contains(cli)) {
      setState(() => _erro =
          'Cliente não cadastrado ou desativado. O sistema impede o atendimento: solicite o cadastro prévio ao Administrador.');
      dados.log('Check-in impedido: cliente ${cli.nome} não cadastrado/ativo', _area, autor);
      return;
    }
    final jaNaFila = filaAtendimento.ativaDoCliente(cli, _area);
    if (jaNaFila != null) {
      setState(() => _erro = '${cli.nome} já está na fila com a senha ${jaNaFila.codigo}.');
      return;
    }

    Atend atend;
    if (_sem) {
      final prof = _prof;
      if (prof == null) {
        setState(() => _erro = 'Escolha o profissional responsável.');
        return;
      }
      if (dados.faltas(cli) >= 3 && !dados.liberados.contains(cli.id)) {
        setState(() => _erro =
            '${cli.nome} atingiu 3 faltas. Atendimento sem agendamento bloqueado: depende da aprovação do Administrador.');
        dados.log('Check-in sem agendamento bloqueado (cliente com 3 faltas): ${cli.nome}', _area, autor);
        return;
      }
      atend = Atend(dados.proximoId(), _area, cli, prof, _serv, DateTime.now(), StatusAtend.agendado);
      dados.atendimentos.add(atend);
      dados.log('Cliente chegou sem agendamento: ${cli.nome} • $_serv com ${prof.nome}', _area, autor);
    } else {
      final x = _agendamento;
      if (x == null) {
        setState(() => _erro = 'Escolha o agendamento ou marque "Sem agendamento".');
        return;
      }
      atend = x;
    }

    final s = filaAtendimento.emitir(atend, preferencial: _preferencial, semAgendamento: _sem);
    final prio = _preferencial ? ' (prioritária)' : '';
    dados.log('Check-in: ${cli.nome} • senha ${s.codigo}$prio • #${atend.id}', _area, autor);
    Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) {
    final clientes = dados.clientes(_area);
    final agendamentos = _agendamentosDoDia();
    return AlertDialog(
      title: const Text('Check-in do cliente'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            seletor<Usuario>('Cliente (cadastrado)', clientes.contains(_cli) ? _cli : null,
                clientes, _escolherCliente, (u) => u.nome),
            if (_cli != null) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Situação do cliente:'),
                chipSituacaoCliente(_cli!),
              ]),
              const SizedBox(height: 16),
              const Text('Agendamento de hoje', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final x in agendamentos)
                  ChoiceChip(
                    label: Text(
                        '${formatarHora(x.quando)} • ${x.servico} • ${agendamentoConfirmado(x) ? 'confirmado' : 'não confirmado'}'),
                    selected: !_sem && _agendamento == x,
                    onSelected: (_) => setState(() {
                      _agendamento = x;
                      _sem = false;
                    }),
                  ),
                ChoiceChip(
                  label: const Text('Sem agendamento'),
                  selected: _sem,
                  onSelected: (_) => setState(() => _sem = true),
                ),
              ]),
              if (_sem) ...[
                const SizedBox(height: 12),
                seletor<String>('Tipo de serviço', _serv, servicosDe(_area),
                    (v) => setState(() => _serv = v!)),
                const SizedBox(height: 12),
                seletor<Usuario>('Profissional responsável', _prof, dados.profissionais(_area),
                    (v) => setState(() => _prof = v), (u) => u.nome),
              ],
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _preferencial,
                onChanged: (v) => setState(() => _preferencial = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('Atendimento prioritário'),
                subtitle: const Text(
                    'Idoso, gestante, lactante, pessoa com deficiência ou com criança de colo.'),
              ),
            ],
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _fazerCheckin, child: const Text('Fazer check-in')),
      ],
    );
  }
}

// ───────────────────────── Recepção e fila ─────────────────────────

class PaginaRecepcao extends StatelessWidget {
  const PaginaRecepcao(this.area, {super.key, this.autor});

  final Area area;

  /// Quem está operando (nome do auxiliar). Null = administrador.
  final String? autor;

  void _chamar(SenhaFila s) {
    s.status = StatusSenha.chamado;
    s.chamadaEm = DateTime.now();
    s.chamadas++;
    filaAtendimento.mudou();
    dados.log('Senha ${s.codigo} chamada: ${s.cliente.nome} (chamada ${s.chamadas})', area, autor);
  }

  void _chamarProxima(BuildContext c) {
    final l = filaAtendimento.aguardando(area);
    if (l.isEmpty) {
      msg(c, 'Não há ninguém aguardando.');
      return;
    }
    final s = l.first;
    _chamar(s);
    msg(c, 'Chamando a senha ${s.codigo}.');
  }

  void _iniciar(BuildContext c, SenhaFila s) {
    if (!s.cliente.ativo) {
      alerta(c, 'Atendimento impedido', 'Cliente desativado. Procure o Administrador.');
      dados.log('Início impedido: cliente ${s.cliente.nome} desativado', area, autor);
      return;
    }
    s.status = StatusSenha.emAtendimento;
    s.atend.status = StatusAtend.emAtendimento;
    s.atend.iniciadoEm = DateTime.now();
    filaAtendimento.mudou();
    dados.log('Atendimento iniciado pela fila: ${s.cliente.nome} • senha ${s.codigo} (#${s.atend.id})',
        area, autor);
  }

  Future<void> _naoCompareceu(BuildContext c, SenhaFila s) async {
    final ok = await confirmar(
        c,
        'Cliente não compareceu à chamada?',
        s.semAgendamento
            ? '${s.cliente.nome} (senha ${s.codigo}) sai da fila e o atendimento sem agendamento é cancelado.'
            : '${s.cliente.nome} (senha ${s.codigo}) sai da fila. O agendamento continua em aberto.',
        rotulo: 'Retirar da fila');
    if (!ok) return;
    s.status = StatusSenha.desistiu;
    if (s.semAgendamento) s.atend.status = StatusAtend.cancelado;
    filaAtendimento.mudou();
    dados.log('Cliente não compareceu à chamada: ${s.cliente.nome} • senha ${s.codigo}', area, autor);
  }

  /// Registra a confirmação do agendamento feita pela recepção (ex.: por telefone).
  void _confirmarPresenca(BuildContext c, Atend x) {
    x.lembrete = StatusLembrete.confirmado;
    x.status = StatusAtend.confirmado;
    dados.log('Confirmação registrada na recepção: ${x.cliente.nome} (#${x.id})', area, autor);
    msg(c, 'Agendamento de ${x.cliente.nome} confirmado.');
  }

  Widget _acoes(BuildContext c, SenhaFila s) {
    final chamado = s.situacao == StatusSenha.chamado;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (chamado) ...[
        TextButton(onPressed: () => _chamar(s), child: const Text('Chamar de novo')),
        FilledButton(onPressed: () => _iniciar(c, s), child: const Text('Iniciar atendimento')),
      ] else
        FilledButton.tonal(onPressed: () => _chamar(s), child: const Text('Chamar')),
      IconButton(
          tooltip: 'Não compareceu',
          icon: const Icon(Icons.person_off_outlined),
          onPressed: () => _naoCompareceu(c, s)),
    ]);
  }

  @override
  Widget build(BuildContext context) => _Observa((c) {
        final agora = DateTime.now();
        final aguardando = filaAtendimento.aguardando(area);
        final chamados = filaAtendimento.chamados(area);
        final espera = [...chamados, ...aguardando];
        // Em atendimento = qualquer atendimento em andamento (iniciado pela fila ou por outra tela).
        final emAtend = dados
            .doArea(area)
            .where((x) => x.status == StatusAtend.emAtendimento)
            .toList()
          ..sort((x, y) => x.quando.compareTo(y.quando));
        final concluidos = dados
            .doArea(area)
            .where((x) => x.status == StatusAtend.concluido && mesmoDia(x.quando, agora))
            .toList()
          ..sort((x, y) => y.quando.compareTo(x.quando));
        final chegadas = dados
            .doArea(area)
            .where((x) => x.aberto && mesmoDia(x.quando, agora) && !x.chegou)
            .toList()
          ..sort((x, y) => x.quando.compareTo(y.quando));
        var maior = 0;
        for (final s in aguardando) {
          final m = agora.difference(s.chegada).inMinutes;
          if (m > maior) maior = m;
        }
        return Pagina(
          titulo: 'Recepção e fila – ${area.nome}',
          sub: 'Registre a chegada do cliente (check-in), acompanhe a confirmação e a situação dele, chame, inicie e conclua o atendimento num só lugar. Quem fez check-in não é marcado como ausente. Prioritários (idosos, gestantes, pessoas com deficiência) são chamados primeiro.',
          acoes: [
            FilledButton.icon(
                onPressed: () => abrirCheckin(c, area, autor: autor),
                icon: const Icon(Icons.how_to_reg),
                label: const Text('Fazer check-in')),
            FilledButton.tonalIcon(
                onPressed: () => _chamarProxima(c),
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Chamar próximo')),
            OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    c, MaterialPageRoute(builder: (_) => PainelFilaPage(area: area))),
                icon: const Icon(Icons.tv),
                label: const Text('Abrir painel da fila')),
          ],
          filhos: [
            ...secaoAlertasFluxo(c, area,
                so: {CategoriaAlerta.fila, CategoriaAlerta.atendimento},
                titulo: false,
                mostrarVazio: false),
            Wrap(spacing: 16, runSpacing: 16, children: [
              kpi(Icons.hourglass_bottom, 'Aguardando', '${aguardando.length}', Colors.blue),
              kpi(Icons.campaign_outlined, 'Chamados', '${chamados.length}', Colors.orange),
              kpi(Icons.play_circle_outline, 'Em atendimento', '${emAtend.length}', Colors.green),
              kpi(Icons.task_alt, 'Concluídos hoje', '${concluidos.length}', Colors.teal),
              kpi(Icons.timer_outlined, 'Maior espera', '$maior min', Colors.indigo),
            ]),
            const SizedBox(height: 24),
            Text('Fila de espera', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            tabela(
              ['Senha', 'Cliente', 'Situação do cliente', 'Confirmação', 'Serviço', 'Profissional',
                'Chegada', 'Espera', 'Situação', 'Ações'],
              [
                for (final s in espera)
                  [
                    _chipSenha(s),
                    Text(s.cliente.nome),
                    chipSituacaoCliente(s.cliente),
                    chipConfirmacao(s.atend, semAgendamento: s.semAgendamento),
                    Text(s.atend.servico),
                    Text(s.prof.nome),
                    Text(formatarHora(s.chegada)),
                    Text('${agora.difference(s.chegada).inMinutes} min'),
                    chipRotulo(s.situacao.rotulo, s.situacao.cor, icone: s.situacao.icone),
                    _acoes(c, s),
                  ]
              ],
            ),
            const SizedBox(height: 24),
            Text('Em atendimento agora', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            tabela(
              ['Senha', 'Cliente', 'Situação do cliente', 'Serviço', 'Profissional', 'Início', 'Em atendimento', 'Ação'],
              [
                for (final x in emAtend)
                  [
                    celulaSenha(x),
                    Text(x.cliente.nome),
                    chipSituacaoCliente(x.cliente),
                    Text(x.servico),
                    Text(x.prof.nome),
                    Text(formatarHora(x.iniciadoEm ?? x.quando)),
                    celulaTempo(x),
                    FilledButton.icon(
                        onPressed: () => concluirAtendimento(c, x, autor: autor),
                        icon: const Icon(Icons.check),
                        label: const Text('Concluir')),
                  ]
              ],
            ),
            const SizedBox(height: 24),
            Text('Concluídos hoje', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            tabela(
              ['Senha', 'Cliente', 'Serviço', 'Profissional', 'Duração', 'Caixa'],
              [
                for (final x in concluidos)
                  [
                    celulaSenha(x),
                    Text(x.cliente.nome),
                    Text(x.servico),
                    Text(x.prof.nome),
                    celulaTempo(x),
                    celulaPagamento(c, x, autor: autor),
                  ]
              ],
            ),
            const SizedBox(height: 24),
            Text('Agendamentos de hoje aguardando a chegada',
                style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            tabela(
              ['Hora', 'Cliente', 'Situação do cliente', 'Confirmação', 'Serviço', 'Profissional', 'Ações'],
              [
                for (final x in chegadas)
                  [
                    Text(formatarHora(x.quando)),
                    Text(x.cliente.nome),
                    chipSituacaoCliente(x.cliente),
                    chipConfirmacao(x),
                    Text(x.servico),
                    Text(x.prof.nome),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!agendamentoConfirmado(x))
                        TextButton(
                            onPressed: () => _confirmarPresenca(c, x),
                            child: const Text('Confirmar')),
                      TextButton.icon(
                          onPressed: () => abrirCheckin(c, area, autor: autor, agendamento: x),
                          icon: const Icon(Icons.how_to_reg),
                          label: const Text('Check-in')),
                    ]),
                  ]
              ],
            ),
          ],
        );
      });
}

// ───────────────────────── Concluir atendimento (compartilhado) ─────────────────────────

/// Conclusão do atendimento, usada na recepção, no painel do auxiliar e no do administrador.
/// Exige a confirmação de que o serviço foi realizado; depois, o atendimento fica disponível no caixa.
Future<void> concluirAtendimento(BuildContext c, Atend x, {String? autor}) async {
  final ok = await showDialog<bool>(
      context: c, builder: (_) => ConcluirAtendimentoDialog(x: x, autor: autor));
  if (ok == true && c.mounted) {
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(
      content: const Text('Atendimento concluído. Disponível para lançamento no caixa.'),
      action: SnackBarAction(
        label: 'Receber pagamento',
        onPressed: () {
          if (c.mounted) receberPagamento(c, x, autor: autor);
        },
      ),
    ));
  }
}

class ConcluirAtendimentoDialog extends StatefulWidget {
  const ConcluirAtendimentoDialog({super.key, required this.x, this.autor});

  final Atend x;
  final String? autor;

  @override
  State<ConcluirAtendimentoDialog> createState() => _ConcluirAtendimentoDialogState();
}

class _ConcluirAtendimentoDialogState extends State<ConcluirAtendimentoDialog> {
  bool _confirmou = false;
  String? _erro;

  void _concluir() {
    final x = widget.x;
    if (!_confirmou) {
      setState(() =>
          _erro = 'Ação bloqueada: confirme no sistema que o atendimento foi realizado.');
      dados.log('Conclusão bloqueada sem confirmação: ${x.cliente.nome} (#${x.id})', x.area,
          widget.autor);
      return;
    }
    x.status = StatusAtend.concluido;
    x.concluidoEm = DateTime.now();
    filaAtendimento.mudou();
    dados.log(
        'Atendimento concluído: ${x.cliente.nome} (#${x.id})${x.iniciadoEm == null ? '' : ', duração ${x.concluidoEm!.difference(x.iniciadoEm!).inMinutes} min'}, disponível para lançamento no caixa',
        x.area,
        widget.autor);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.x;
    final senha = filaAtendimento.ultimaDe(x);
    return AlertDialog(
      title: const Text('Concluir atendimento'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${x.cliente.nome} • ${x.servico}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (senha != null) Text('Senha ${senha.codigo}'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            chipSituacaoCliente(x.cliente),
            chipConfirmacao(x),
          ]),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _confirmou,
            onChanged: (v) => setState(() => _confirmou = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('Confirmo que o atendimento foi realizado.'),
          ),
          if (_erro != null)
            Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _concluir, child: const Text('Concluir')),
      ],
    );
  }
}

// ───────────────────────── Painel da fila ─────────────────────────

/// Página do painel dentro do menu (prévia + botão de tela cheia).
class PaginaPainelFila extends StatelessWidget {
  const PaginaPainelFila(this.area, {super.key});

  final Area area;

  @override
  Widget build(BuildContext context) => Pagina(
        titulo: 'Painel da fila – ${area.nome}',
        sub: 'Tela para a TV da sala de espera: mostra a senha chamada agora e as próximas, sem nomes de clientes (privacidade). Abra em tela cheia no computador ligado à TV.',
        acoes: [
          FilledButton.icon(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => PainelFilaPage(area: area))),
              icon: const Icon(Icons.fullscreen),
              label: const Text('Abrir em tela cheia')),
        ],
        filhos: [QuadroFila(area: area, compacto: true)],
      );
}

/// Painel em tela cheia, sem login (para a TV). Sem [area], mostra as duas áreas.
class PainelFilaPage extends StatelessWidget {
  const PainelFilaPage({super.key, this.area});

  final Area? area;

  @override
  Widget build(BuildContext context) {
    final areas = area == null ? Area.values : [area!];
    return FundoSuave(
      cores: [Area.estetica.corClara, Area.psicologia.corClara],
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: barra(acoes: [
          const _Relogio(),
          IconButton(
              tooltip: 'Fechar painel',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context)),
        ]),
        body: LayoutBuilder(builder: (c, cons) {
          final lado = cons.maxWidth >= 900 && areas.length > 1;
          return lado
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final a in areas) ...[
                      Expanded(child: SingleChildScrollView(child: QuadroFila(area: a))),
                      if (a != areas.last) const SizedBox(width: 16),
                    ],
                  ]),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                  for (final a in areas) ...[
                    QuadroFila(area: a),
                    const SizedBox(height: 16),
                  ],
                ]);
        }),
      ),
    );
  }
}

/// Quadro de uma área: chamada atual, próximas senhas e últimas chamadas.
class QuadroFila extends StatelessWidget {
  const QuadroFila({super.key, required this.area, this.compacto = false});

  final Area area;
  final bool compacto;

  @override
  Widget build(BuildContext context) => _Observa((c) {
        final recentes = filaAtendimento.chamadasRecentes(area);
        final atual = recentes.isEmpty ? null : recentes.first;
        final anteriores = recentes.skip(1).take(4).toList();
        final proximos = filaAtendimento.aguardando(area);
        return LayoutBuilder(builder: (ctx, cons) {
          final tamCodigo = compacto ? 56.0 : (cons.maxWidth * 0.22).clamp(56.0, 130.0);
          final tamTexto = compacto ? 14.0 : (cons.maxWidth * 0.035).clamp(16.0, 26.0);
          return Card(
            color: Colors.white,
            elevation: 3,
            child: Padding(
              padding: EdgeInsets.all(compacto ? 16 : 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  CircleAvatar(
                      backgroundColor: area.cor,
                      child: Icon(area.icone, color: Colors.white)),
                  const SizedBox(width: 12),
                  Text(area.nome,
                      style: TextStyle(
                          fontSize: tamTexto + 6, fontWeight: FontWeight.bold, color: area.cor)),
                ]),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: area.corClara, borderRadius: BorderRadius.circular(16)),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: atual == null
                        ? Padding(
                            key: const ValueKey('vazio'),
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text('Aguardando as próximas chamadas',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: tamTexto + 2)),
                          )
                        : Column(
                            key: ValueKey('${atual.id}-${atual.chamadas}-${atual.situacao.name}'),
                            children: [
                              Text(
                                  atual.situacao == StatusSenha.chamado
                                      ? 'CHAMANDO AGORA'
                                      : 'EM ATENDIMENTO',
                                  style: TextStyle(
                                      fontSize: tamTexto,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.5)),
                              Text(atual.codigo,
                                  style: TextStyle(
                                      fontSize: tamCodigo,
                                      fontWeight: FontWeight.bold,
                                      color: atual.preferencial ? Colors.purple : area.cor)),
                              Text('Dirija-se a ${atual.prof.nome}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: tamTexto)),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Próximas senhas',
                    style: TextStyle(fontSize: tamTexto, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (proximos.isEmpty)
                  Text('Ninguém aguardando.', style: TextStyle(fontSize: tamTexto - 2))
                else
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in proximos.take(8))
                      Chip(
                        avatar: s.preferencial
                            ? const Icon(Icons.accessible, size: 18, color: Colors.purple)
                            : null,
                        label: Text(s.codigo,
                            style: TextStyle(
                                fontSize: tamTexto, fontWeight: FontWeight.bold)),
                      ),
                    if (proximos.length > 8)
                      Chip(
                          label: Text('+${proximos.length - 8}',
                              style: TextStyle(fontSize: tamTexto))),
                  ]),
                if (anteriores.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Últimas chamadas',
                      style: TextStyle(fontSize: tamTexto, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  for (final s in anteriores)
                    Text('${s.codigo} • ${formatarHora(s.chamadaEm!)} • ${s.prof.nome}',
                        style: TextStyle(fontSize: tamTexto - 2)),
                ],
              ]),
            ),
          );
        });
      });
}