import 'dart:math';

import 'package:flutter/material.dart';
import 'admin.dart';
import 'main.dart';

// ───── cliente/regras.dart ─────
// Horários de atendimento. Ajuste conforme a rotina da clínica.
// Os procedimentos e valores vêm de procedimentosDe(area), em admin.dart.
const _horaInicio = {Area.estetica: 9, Area.psicologia: 8};
const _horaFim = {Area.estetica: 18, Area.psicologia: 17}; // o último horário começa 1h antes
const _horaAlmoco = 12; // sem atendimento nesse horário
const _diasAtendimento = {
  Area.estetica: {1, 2, 3, 4, 5, 6}, // segunda a sábado (1 = segunda)
  Area.psicologia: {1, 2, 3, 4, 5}, // segunda a sexta
};
const _duracaoMin = 60; // cada atendimento ocupa 1 hora
const _antecedenciaHoras = 1; // só dá para agendar com pelo menos 1h de antecedência
const _horizonteDias = 60; // agenda aberta pelos próximos 60 dias

List<DateTime> _horariosDoDia(Area a, DateTime dia) {
  if (!_diasAtendimento[a]!.contains(dia.weekday)) return [];
  return [
    for (var h = _horaInicio[a]!; h < _horaFim[a]!; h++)
      if (h != _horaAlmoco) DateTime(dia.year, dia.month, dia.day, h),
  ];
}

bool _ocupaHorario(Atend x) => x.aberto || x.status == StatusAtend.emAtendimento;

/// Profissionais livres no horário (lista vazia = horário indisponível).
List<Usuario> _livres(Area a, DateTime horario, Usuario cliente,
    {Usuario? prof, Atend? ignorar}) {
  final minimo = DateTime.now().add(const Duration(hours: _antecedenciaHoras));
  if (!horario.isAfter(minimo)) return [];
  bool choca(Atend x) =>
      x != ignorar &&
      _ocupaHorario(x) &&
      x.quando.difference(horario).abs().inMinutes < _duracaoMin;
  // O cliente não pode ter dois atendimentos no mesmo horário.
  if (dados.atendimentos.any((x) => x.cliente == cliente && choca(x))) return [];
  final candidatos = prof != null ? [prof] : dados.profissionais(a);
  return [
    for (final p in candidatos)
      if (!dados.atendimentos.any((x) => x.prof == p && choca(x))) p,
  ];
}

bool _diaTemHorario(Area a, DateTime dia, Usuario cliente, {Usuario? prof, Atend? ignorar}) =>
    _horariosDoDia(a, dia).any(
        (h) => _livres(a, h, cliente, prof: prof, ignorar: ignorar).isNotEmpty);

DateTime? _primeiroDiaLivre(Area a, Usuario cliente, {Usuario? prof, Atend? ignorar}) {
  final hoje = DateUtils.dateOnly(DateTime.now());
  for (var i = 0; i <= _horizonteDias; i++) {
    final d = hoje.add(Duration(days: i));
    if (_diaTemHorario(a, d, cliente, prof: prof, ignorar: ignorar)) return d;
  }
  return null;
}

// ───── cliente/seletor_horario.dart ─────
/// Calendário (só dias com vaga) + horários disponíveis do dia escolhido.
class SeletorHorario extends StatefulWidget {
  const SeletorHorario({
    super.key,
    required this.area,
    required this.cliente,
    required this.onChanged,
    this.prof,
    this.ignorar,
  });

  final Area area;
  final Usuario cliente;
  final Usuario? prof;

  /// Agendamento que está sendo remarcado (não conta como ocupado).
  final Atend? ignorar;

  /// Informa o horário escolhido e o profissional que atenderá (null = nada escolhido).
  final void Function(DateTime? horario, Usuario? profissional) onChanged;

  @override
  State<SeletorHorario> createState() => _SeletorHorarioState();
}

class _SeletorHorarioState extends State<SeletorHorario> {
  DateTime? _dia, _horario;

  @override
  void initState() {
    super.initState();
    _dia = _primeiroDiaLivre(widget.area, widget.cliente,
        prof: widget.prof, ignorar: widget.ignorar);
  }

  Widget _chip(DateTime h) {
    final livres = _livres(widget.area, h, widget.cliente,
        prof: widget.prof, ignorar: widget.ignorar);
    return ChoiceChip(
      label: Text(formatarHora(h)),
      selected: _horario == h,
      onSelected: livres.isEmpty
          ? null
          : (v) {
              setState(() => _horario = v ? h : null);
              widget.onChanged(v ? h : null, v ? livres.first : null);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dia = _dia;
    if (dia == null) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Não há horários disponíveis nos próximos 60 dias para esta opção. '
            'Tente outro profissional ou entre em contato com a clínica.'),
      );
    }
    final hoje = DateUtils.dateOnly(DateTime.now());

    final calendario = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: CalendarDatePicker(
        initialDate: dia,
        firstDate: hoje,
        lastDate: hoje.add(const Duration(days: _horizonteDias)),
        selectableDayPredicate: (d) => _diaTemHorario(widget.area, d, widget.cliente,
            prof: widget.prof, ignorar: widget.ignorar),
        onDateChanged: (d) {
          setState(() {
            _dia = d;
            _horario = null;
          });
          widget.onChanged(null, null);
        },
      ),
    );

    final horarios = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Horários em ${formatarData(dia)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('Horários em cinza já estão ocupados.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final h in _horariosDoDia(widget.area, dia)) _chip(h)],
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 720
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [calendario, const SizedBox(width: 24), Expanded(child: horarios)],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [calendario, const SizedBox(height: 12), horarios],
            ),
    );
  }
}

// ───── cliente/cliente_home.dart ─────
/// Página do cliente: só o agendamento dele.
class ClienteHome extends StatefulWidget {
  const ClienteHome({super.key, required this.cliente, required this.area});

  final Usuario cliente;
  final Area area;

  @override
  State<ClienteHome> createState() => _ClienteHomeState();
}

class _ClienteHomeState extends State<ClienteHome> {
  late Area _area = widget.area;
  int _aba = 0;

  void _sair() {
    dados.log('Cliente saiu do sistema', _area, widget.cliente.nome);
    Navigator.pop(context);
  }

  Widget _cartaoArea(Area a, bool cel) {
    final sel = a == _area;
    return Expanded(
      child: Semantics(
        button: true,
        selected: sel,
        label: a.nome,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _area = a),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(vertical: cel ? 14 : 20, horizontal: 12),
            decoration: BoxDecoration(
              color: sel ? a.cor : a.corClara,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: a.cor, width: sel ? 2 : 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(a.icone, size: cel ? 26 : 32, color: sel ? Colors.white : a.cor),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(a.nome,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: cel ? 16 : 20,
                          fontWeight: FontWeight.bold,
                          color: sel ? Colors.white : a.cor)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cel = ehCelular(context);
    final u = widget.cliente;

    return Theme(
      data: criarTema(_area.cor),
      child: FundoSuave(
        cores: [_area.corClara, Colors.white],
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: barra(acoes: [
            if (!cel)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                    child: Text(u.nome, style: const TextStyle(fontWeight: FontWeight.w600))),
              ),
            cel
                ? IconButton(tooltip: 'Sair', icon: const Icon(Icons.logout), onPressed: _sair)
                : TextButton.icon(
                    onPressed: _sair, icon: const Icon(Icons.logout), label: const Text('Sair')),
          ]),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: ListView(
                padding: EdgeInsets.all(cel ? 12 : 24),
                children: [
                  Text('Olá, ${u.primeiroNome}!',
                      style: (cel
                              ? Theme.of(context).textTheme.titleLarge
                              : Theme.of(context).textTheme.headlineSmall)
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('Escolha a área e agende o seu atendimento.'),
                  const SizedBox(height: 16),
                  Row(children: [
                    _cartaoArea(Area.estetica, cel),
                    const SizedBox(width: 12),
                    _cartaoArea(Area.psicologia, cel),
                  ]),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                            value: 0,
                            icon: cel ? null : const Icon(Icons.add_circle_outline),
                            label: const Text('Novo agendamento')),
                        ButtonSegment(
                            value: 1,
                            icon: cel ? null : const Icon(Icons.event_note),
                            label: const Text('Meus agendamentos')),
                      ],
                      selected: {_aba},
                      onSelectionChanged: (s) => setState(() => _aba = s.first),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_aba == 0)
                    NovoAgendamento(
                      key: ValueKey(_area),
                      cliente: u,
                      area: _area,
                      onAgendado: () => setState(() => _aba = 1),
                    )
                  else
                    MeusAgendamentos(cliente: u),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───── cliente/novo_agendamento.dart ─────
class _Passo extends StatelessWidget {
  const _Passo(this.n, this.titulo, this.cor, this.child);

  final int n;
  final String titulo;
  final Color cor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(ehCelular(context) ? 14 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                  radius: 14,
                  backgroundColor: cor,
                  child: Text('$n',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(titulo,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class NovoAgendamento extends StatefulWidget {
  const NovoAgendamento({
    super.key,
    required this.cliente,
    required this.area,
    required this.onAgendado,
  });

  final Usuario cliente;
  final Area area;
  final VoidCallback onAgendado;

  @override
  State<NovoAgendamento> createState() => _NovoAgendamentoState();
}

class _NovoAgendamentoState extends State<NovoAgendamento> {
  String? _servico;
  DateTime? _horario;
  bool _salvando = false;
  int _versao = 0; // força o seletor a recarregar os horários

  Future<void> _confirmar() async {
    final s = _servico, h = _horario;
    if (s == null || h == null) return;
    final c = widget.cliente;

    // Revalida: outra pessoa pode ter ocupado o horário nesse meio-tempo.
    final livres = _livres(widget.area, h, c);
    if (livres.isEmpty) {
      setState(() {
        _horario = null;
        _versao++;
      });
      alerta(context, 'Horário indisponível',
          'Esse horário acabou de ser ocupado. Escolha outro, por favor.');
      return;
    }

    setState(() => _salvando = true);
    // TODO: gravar no backend e programar o lembrete por WhatsApp (UC10).
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    // O cliente não escolhe: o profissional é sorteado entre os que estão livres.
    final prof = livres[Random().nextInt(livres.length)];
    final valor = valorDoProcedimento(widget.area, s);
    dados.atendimentos.add(
        Atend(dados.proximoId(), widget.area, c, prof, s, h, StatusAtend.agendado));
    dados.log(
        'Agendamento criado pelo cliente: $s com ${prof.nome} em ${formatarDataHora(h)}',
        widget.area,
        c.nome);
    setState(() => _salvando = false);

    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        icon: Icon(Icons.check_circle, color: widget.area.cor, size: 40),
        title: const Text('Agendamento realizado!'),
        content: Text(
          '${widget.area.nome} • $s\n'
          '${formatarData(h)} às ${formatarHora(h)}\n'
          'Profissional: ${prof.nome}\n'
          '${valor != null ? 'Valor: ${formatarReais(valor)} (pago no dia do atendimento)\n' : ''}\n'
          '${c.aceitaLembretes ? 'Você receberá um lembrete por WhatsApp no número ${c.contato}.\n' : ''}'
          'Para remarcar ou cancelar (com até 24h de antecedência), use "Meus agendamentos".',
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Ok'))],
      ),
    );
    if (!mounted) return;
    widget.onAgendado();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.area;
    final c = widget.cliente;

    // UC07 1a: cliente com 3 faltas só agenda com aprovação do administrador.
    if (dados.faltas(c) >= 3 && !dados.liberados.contains(c.id)) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber, color: Colors.orange),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Você atingiu 3 faltas registradas, por isso novos agendamentos precisam '
                'da aprovação da clínica. Entre em contato com a recepção para regularizar.',
              ),
            ),
          ]),
        ),
      );
    }

    final procedimentos = procedimentosDe(a);
    final valor = _servico == null ? null : valorDoProcedimento(a, _servico!);
    final pronto = _servico != null && _horario != null;
    final h = _horario;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Passo(
          1,
          'Escolha o procedimento',
          a.cor,
          procedimentos.isEmpty
              ? const Text('Nenhum procedimento disponível no momento.')
              : Column(children: [
                  for (final p in procedimentos)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        selected: _servico == p.nome,
                        selectedTileColor: a.corClara,
                        selectedColor: a.cor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: _servico == p.nome ? a.cor : Colors.black12),
                        ),
                        leading: Icon(_servico == p.nome
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off),
                        title: Text(p.nome),
                        trailing: p.valorCentavos == null
                            ? null
                            : Text(formatarReais(p.valorCentavos!),
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                        onTap: () =>
                            setState(() => _servico = _servico == p.nome ? null : p.nome),
                      ),
                    ),
                ]),
        ),
        const SizedBox(height: 12),
        _Passo(
          2,
          'Escolha o dia e o horário',
          a.cor,
          SeletorHorario(
            key: ValueKey('${a.name}-$_versao'),
            area: a,
            cliente: c,
            onChanged: (hor, _) => setState(() => _horario = hor),
          ),
        ),
        const SizedBox(height: 12),
        if (pronto && h != null)
          Card(
            color: a.corClara,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Resumo', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('${a.nome} • $_servico'),
                Text('${formatarData(h)} às ${formatarHora(h)}'),
                const Text('O profissional é definido pela clínica ao confirmar.',
                    style: TextStyle(fontSize: 12)),
                if (valor != null)
                  Text('Valor: ${formatarReais(valor)} (pago no dia do atendimento)'),
              ]),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: pronto && !_salvando ? _confirmar : null,
          icon: _salvando
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.event_available),
          label: const Text('Confirmar agendamento', style: TextStyle(fontSize: 16)),
          style: FilledButton.styleFrom(
            backgroundColor: a.cor,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ───── cliente/meus_agendamentos.dart ─────
bool _dentroDoPrazo(Atend x) => x.quando.difference(DateTime.now()).inHours >= 24;

void _avisoPrazo(BuildContext c, String acao) => alerta(
      c,
      'Ação bloqueada',
      'Só é possível $acao com pelo menos 24h de antecedência. '
          'Entre em contato com a clínica para falar sobre este agendamento.',
    );

Future<void> _cancelar(BuildContext c, Atend x) async {
  if (!_dentroDoPrazo(x)) return _avisoPrazo(c, 'cancelar');
  final ok = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      title: const Text('Cancelar agendamento?'),
      content: Text('${x.servico} em ${formatarDataHora(x.quando)} com ${x.prof.nome}.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Voltar')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Cancelar agendamento')),
      ],
    ),
  );
  if (ok != true) return;
  x.status = StatusAtend.cancelado;
  dados.log('Agendamento #${x.id} cancelado pelo cliente (${formatarDataHora(x.quando)})', x.area,
      x.cliente.nome);
}

Future<void> _remarcar(BuildContext c, Atend x) async {
  if (!_dentroDoPrazo(x)) return _avisoPrazo(c, 'remarcar');
  DateTime? novo;
  final ok = await showDialog<bool>(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text('Remarcar • ${x.servico}'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: SeletorHorario(
              area: x.area,
              cliente: x.cliente,
              prof: x.prof,
              ignorar: x,
              onChanged: (h, _) => set(() => novo = h),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Voltar')),
          FilledButton(
            onPressed: novo == null ? null : () => Navigator.pop(d, true),
            child: const Text('Confirmar novo horário'),
          ),
        ],
      ),
    ),
  );
  final n = novo;
  if (ok != true || n == null) return;
  final antigo = x.quando;
  x.quando = n;
  x.status = StatusAtend.agendado;
  x.lembrete = StatusLembrete.naoEnviado;
  dados.log(
      'Agendamento #${x.id} remarcado pelo cliente de ${formatarDataHora(antigo)} para ${formatarDataHora(n)}',
      x.area,
      x.cliente.nome);
}

String _textoValor(Atend x) {
  final v = valorDoProcedimento(x.area, x.servico);
  return v == null ? '' : ' • ${formatarReais(v)}';
}

void _confirmarPresenca(Atend x) {
  x.lembrete = StatusLembrete.confirmado;
  x.status = StatusAtend.confirmado;
  dados.log('Presença confirmada pelo cliente (#${x.id})', x.area, x.cliente.nome);
}

class MeusAgendamentos extends StatelessWidget {
  const MeusAgendamentos({super.key, required this.cliente});

  final Usuario cliente;

  @override
  Widget build(BuildContext context) => Obs((c) {
        final l = dados.atendimentos.where((x) => x.cliente == cliente).toList()
          ..sort((x, y) => y.quando.compareTo(x.quando));
        if (l.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Você ainda não tem agendamentos.')),
            ),
          );
        }
        return Column(
          children: [
            for (final x in l)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        CircleAvatar(
                            backgroundColor: x.area.corClara,
                            child: Icon(x.area.icone, color: x.area.cor)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(x.servico,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            Text('${formatarData(x.quando)} às ${formatarHora(x.quando)}'),
                            Text('${x.area.nome} • ${x.prof.nome}${_textoValor(x)}',
                                style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        chipStatus(x.status),
                        if (x.aberto)
                          chipRotulo('Lembrete: ${x.lembrete.rotulo}', x.lembrete.cor),
                      ]),
                      if (x.aberto) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 4, children: [
                          if (x.lembrete == StatusLembrete.enviado ||
                              x.lembrete == StatusLembrete.semResposta)
                            FilledButton.tonalIcon(
                              onPressed: () => _confirmarPresenca(x),
                              icon: const Icon(Icons.check),
                              label: const Text('Confirmar presença'),
                            ),
                          TextButton.icon(
                            onPressed: () => _remarcar(c, x),
                            icon: const Icon(Icons.edit_calendar),
                            label: const Text('Remarcar'),
                          ),
                          TextButton.icon(
                            onPressed: () => _cancelar(c, x),
                            icon: const Icon(Icons.event_busy),
                            label: const Text('Cancelar'),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      });
}