import 'dart:math';

import 'package:flutter/material.dart';

import 'admin.dart';
import 'caixa.dart';
import 'main.dart';

/// Painel do auxiliar (Psicologia ou Estética): agenda, recepção, conclusão, caixa.
class AuxiliarPanel extends StatelessWidget {
  const AuxiliarPanel({super.key, required this.auxiliar});

  final Usuario auxiliar;

  @override
  Widget build(BuildContext context) {
    final area = auxiliar.area;
    return PainelComMenu(
      area: area,
      titulo: '${auxiliar.nome} • ${area.nome}',
      podeTrocarArea: false,
      sair: (c) => botaoSair(c,
          acao: 'Logout do auxiliar', area: area, autor: auxiliar.nome),
      secoes: [
        SecaoPainel(Icons.event_available, 'Agendar serviço', PaginaAgendarServico(auxiliar)),
        SecaoPainel(Icons.edit_calendar, 'Remarcar/cancelar serviço', PaginaRemarcarCancelar(auxiliar)),
        SecaoPainel(Icons.login, 'Receber cliente', PaginaReceberCliente(auxiliar)),
        SecaoPainel(Icons.task_alt, 'Concluir atendimento', PaginaConcluirAtendimento(auxiliar)),
        SecaoPainel(Icons.point_of_sale, 'Caixa', PaginaCaixa(area, auxiliar: auxiliar)),
      ],
    );
  }
}

// ───────────────────────── Receber cliente para atendimento ─────────────────────────

class PaginaReceberCliente extends StatefulWidget {
  const PaginaReceberCliente(this.auxiliar, {super.key});

  final Usuario auxiliar;

  @override
  State<PaginaReceberCliente> createState() => _PaginaReceberClienteState();
}

class _PaginaReceberClienteState extends State<PaginaReceberCliente> {
  final _busca = TextEditingController();
  String? _consulta; // null = ainda não buscou

  Usuario get _auxiliar => widget.auxiliar;
  Area get _area => widget.auxiliar.area;

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  List<Usuario> _resultados(String q) => dados.usuarios
      .where((u) =>
          u.area == _area &&
          u.perfil == Perfil.cliente &&
          u.nome.toLowerCase().contains(q.toLowerCase()))
      .toList();

  List<Atend> _agendamentosAbertos([Usuario? cliente]) => dados
      .doArea(_area)
      .where((x) => x.aberto && (cliente == null || x.cliente == cliente))
      .toList()
    ..sort((x, y) => x.quando.compareTo(y.quando));

  void _buscar() {
    final q = _busca.text.trim();
    if (q.length < 2) {
      msg(context, 'Digite pelo menos 2 letras do nome do cliente.');
      return;
    }
    setState(() => _consulta = q);
    if (_resultados(q).isEmpty) {
      dados.log('Recebimento impedido: cliente "$q" não cadastrado', _area, _auxiliar.nome);
    }
  }

  void _impedido(Usuario cliente) {
    alerta(context, 'Atendimento impedido',
        'Cliente não cadastrado ou desativado. O sistema impede o atendimento: solicite o cadastro prévio ao Administrador.');
    dados.log('Recebimento impedido: cliente ${cliente.nome} não cadastrado/ativo', _area,
        _auxiliar.nome);
  }

  void _receber(Atend x) {
    if (!dados.usuarios.contains(x.cliente) || !x.cliente.ativo) {
      _impedido(x.cliente);
      return;
    }
    x.status = StatusAtend.emAtendimento;
    dados.log('Cliente recebido para atendimento: ${x.cliente.nome} (#${x.id})', _area,
        _auxiliar.nome);
    msg(context, 'Recebimento registrado: atendimento de ${x.cliente.nome} iniciado.');
  }

  Future<void> _semAgendamento(Usuario cliente) async {
    if (!cliente.ativo) {
      _impedido(cliente);
      return;
    }
    final servs = servicosDe(_area);
    final profs = dados.profissionais(_area);
    if (profs.isEmpty) {
      alerta(context, 'Sem profissional', 'Não há profissional cadastrado nesta área.');
      return;
    }
    var serv = servs.first;
    var prof = profs.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Receber ${cliente.nome}'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Cliente sem agendamento. Escolha o serviço que será realizado.'),
              const SizedBox(height: 12),
              seletor<String>('Tipo de serviço', serv, servs, (v) => set(() => serv = v!)),
              const SizedBox(height: 12),
              seletor<Usuario>('Profissional responsável', prof, profs,
                  (v) => set(() => prof = v!), (u) => u.nome),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Registrar recebimento')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    dados.atendimentos.add(Atend(dados.proximoId(), _area, cliente, prof, serv,
        DateTime.now(), StatusAtend.emAtendimento));
    dados.log('Cliente recebido sem agendamento: ${cliente.nome} • $serv com ${prof.nome}', _area,
        _auxiliar.nome);
    msg(context, 'Recebimento registrado: atendimento de ${cliente.nome} iniciado.');
  }

  Widget _cartaoCliente(Usuario cl) {
    final abertos = _agendamentosAbertos(cl);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(cl.nome, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            cl.ativo
                ? chipRotulo('Cadastro confirmado', Colors.green, icone: Icons.verified_user_outlined)
                : chipRotulo('Cadastro desativado', Colors.grey, icone: Icons.block),
            Text(cl.contato),
          ]),
          const SizedBox(height: 12),
          if (!cl.ativo)
            const Text('Atendimento impedido: o cadastro está desativado. Solicite ao Administrador.')
          else ...[
            if (abertos.isEmpty)
              const Text('Nenhum agendamento em aberto.')
            else
              for (final x in abertos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${formatarDataHora(x.quando)} • ${x.servico}'),
                    FilledButton.icon(
                      onPressed: () => _receber(x),
                      icon: const Icon(Icons.login),
                      label: const Text('Registrar recebimento'),
                    ),
                  ]),
                ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => _semAgendamento(cl),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Receber sem agendamento'),
            ),
          ],
        ]),
      ),
    );
  }

  List<Widget> _resultadoBusca(String q, List<Usuario> resultados) {
    if (resultados.isEmpty) {
      return [
        Card(
          color: Colors.red.shade50,
          child: ListTile(
            leading: const Icon(Icons.person_off, color: Colors.red),
            title: const Text('Cliente não cadastrado'),
            subtitle: Text(
                'Não encontramos "$q" nesta área. O sistema impede o atendimento de clientes sem cadastro: solicite o cadastro prévio ao Administrador.'),
          ),
        ),
      ];
    }
    return [for (final cl in resultados) _cartaoCliente(cl)];
  }

  @override
  Widget build(BuildContext context) => Obs((c) {
        final q = _consulta;
        final abertos = _agendamentosAbertos();
        return Pagina(
          titulo: 'Receber cliente – ${_area.nome}',
          sub: 'Busque o cliente no sistema, confirme o cadastro e registre o recebimento. Só clientes cadastrados são atendidos; sem cadastro, solicite o cadastro prévio ao Administrador.',
          filhos: [
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _busca,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _buscar(),
                  decoration: decoracaoCampo('Buscar cliente por nome', icone: Icons.search),
                ),
              ),
              FilledButton.icon(
                  onPressed: _buscar, icon: const Icon(Icons.search), label: const Text('Buscar')),
            ]),
            const SizedBox(height: 16),
            if (q != null) ..._resultadoBusca(q, _resultados(q)),
            const SizedBox(height: 24),
            Text('Agendamentos em aberto', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            tabela(
              ['Nº', 'Data/hora', 'Cliente', 'Serviço', 'Status', 'Ação'],
              [
                for (final x in abertos)
                  [
                    Text('#${x.id}'),
                    Text(formatarDataHora(x.quando)),
                    Text(x.cliente.nome),
                    Text(x.servico),
                    chipStatus(x.status),
                    TextButton.icon(
                        onPressed: () => _receber(x),
                        icon: const Icon(Icons.login),
                        label: const Text('Receber')),
                  ]
              ],
            ),
          ],
        );
      });
}

// ───────────────────────── Concluir atendimento ─────────────────────────

class PaginaConcluirAtendimento extends StatelessWidget {
  const PaginaConcluirAtendimento(this.auxiliar, {super.key});

  final Usuario auxiliar;

  Area get _area => auxiliar.area;

  Future<void> _concluir(BuildContext c, Atend x) async {
    final ok = await showDialog<bool>(
        context: c, builder: (_) => _ConcluirDialog(x: x, auxiliar: auxiliar));
    if (ok == true && c.mounted) {
      msg(c, 'Atendimento concluído. Disponível para lançamento no caixa.');
    }
  }

  @override
  Widget build(BuildContext context) => Obs((c) {
        final meus = dados.doArea(_area).toList();
        final andamento = meus.where((x) => x.status == StatusAtend.emAtendimento).toList()
          ..sort((x, y) => x.quando.compareTo(y.quando));
        final hoje = meus
            .where((x) => x.status == StatusAtend.concluido && mesmoDia(x.quando, DateTime.now()))
            .toList()
          ..sort((x, y) => y.quando.compareTo(x.quando));
        return Pagina(
          titulo: 'Concluir atendimento – ${_area.nome}',
          sub: 'Ao finalizar o serviço, confirme no sistema que o atendimento foi realizado. Sem a confirmação, o sistema bloqueia a conclusão. Depois de concluído, o serviço fica disponível para lançamento no caixa.',
          filhos: [
            Wrap(spacing: 16, runSpacing: 16, children: [
              kpi(Icons.play_circle_outline, 'Em andamento', '${andamento.length}', Colors.orange),
              kpi(Icons.task_alt, 'Concluídos hoje', '${hoje.length}', Colors.green),
            ]),
            const SizedBox(height: 24),
            Text('Atendimentos em andamento', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            tabela(
              ['Nº', 'Início', 'Cliente', 'Serviço', 'Status', 'Ação'],
              [
                for (final x in andamento)
                  [
                    Text('#${x.id}'),
                    Text(formatarDataHora(x.quando)),
                    Text(x.cliente.nome),
                    Text(x.servico),
                    chipStatus(x.status),
                    FilledButton.icon(
                        onPressed: () => _concluir(c, x),
                        icon: const Icon(Icons.check),
                        label: const Text('Concluir')),
                  ]
              ],
            ),
            const SizedBox(height: 24),
            Text('Concluídos hoje', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            tabela(
              ['Nº', 'Data/hora', 'Cliente', 'Serviço', 'Caixa'],
              [
                for (final x in hoje)
                  [
                    Text('#${x.id}'),
                    Text(formatarDataHora(x.quando)),
                    Text(x.cliente.nome),
                    Text(x.servico),
                    Text(x.lancado ? '${formatarReais(x.valorPago)} (${x.formasPagas})' : 'a lançar'),
                  ]
              ],
            ),
          ],
        );
      });
}

class _ConcluirDialog extends StatefulWidget {
  const _ConcluirDialog({required this.x, required this.auxiliar});

  final Atend x;
  final Usuario auxiliar;

  @override
  State<_ConcluirDialog> createState() => _ConcluirDialogState();
}

class _ConcluirDialogState extends State<_ConcluirDialog> {
  bool _confirmou = false;
  String? _erro;

  void _concluir() {
    final x = widget.x;
    final autor = widget.auxiliar.nome;
    if (!_confirmou) {
      setState(() =>
          _erro = 'Ação bloqueada: confirme no sistema que o atendimento foi realizado.');
      dados.log('Conclusão bloqueada sem confirmação: ${x.cliente.nome} (#${x.id})', x.area, autor);
      return;
    }
    x.status = StatusAtend.concluido;
    dados.log(
        'Atendimento concluído: ${x.cliente.nome} (#${x.id}), disponível para lançamento no caixa',
        x.area,
        autor);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.x;
    return AlertDialog(
      title: const Text('Concluir atendimento'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${x.cliente.nome} • ${x.servico}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
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

// ───────────────────────── Agendar serviço ─────────────────────────

class PaginaAgendarServico extends StatefulWidget {
  const PaginaAgendarServico(this.auxiliar, {super.key});

  final Usuario auxiliar;

  @override
  State<PaginaAgendarServico> createState() => _PaginaAgendarServicoState();
}

class _PaginaAgendarServicoState extends State<PaginaAgendarServico> {
  Usuario? _cli;
  late String _serv = servicosDe(_area).first;
  DateTime? _quando;
  String? _erro;

  Area get _area => widget.auxiliar.area;
  String get _autor => widget.auxiliar.nome;

  Future<void> _escolherData() async {
    final n = await escolherDataHora(context, _quando ?? emHoras(24));
    if (n != null && mounted) setState(() => _quando = n);
  }

  void _agendar() {
    final cli = _cli, q = _quando;
    if (cli == null || q == null) {
      setState(() => _erro = 'Escolha o cliente e a data/hora.');
      return;
    }
    if (q.isBefore(DateTime.now())) {
      setState(() => _erro = 'Escolha um horário futuro.');
      return;
    }
    // Distribuição aleatória entre os profissionais cadastrados e livres no horário.
    final profs = dados.usuarios
        .where((u) => u.area == _area && u.perfil == Perfil.atendente && u.ativo)
        .toList();
    if (profs.isEmpty) {
      setState(() => _erro = 'Não há profissional cadastrado nesta área.');
      return;
    }
    final livres = profs
        .where((p) => !dados.atendimentos.any(
            (x) => x.prof == p && x.aberto && x.quando.difference(q).abs().inMinutes < 60))
        .toList();
    if (livres.isEmpty) {
      setState(() => _erro =
          'Todos os profissionais estão ocupados nesse horário. Sugestão: ${formatarDataHora(q.add(const Duration(hours: 1)))}.');
      return;
    }
    final prof = livres[Random().nextInt(livres.length)];
    if (dados.faltas(cli) >= 3 && !dados.liberados.contains(cli.id)) {
      setState(() => _erro =
          '${cli.nome} atingiu 3 faltas. Novo agendamento bloqueado: depende da aprovação do Administrador.');
      dados.log('Agendamento bloqueado (cliente com 3 faltas): ${cli.nome}', _area, _autor);
      return;
    }
    dados.atendimentos.add(
        Atend(dados.proximoId(), _area, cli, prof, _serv, q, StatusAtend.agendado));
    dados.log(
        'Agendamento criado: ${cli.nome} com ${prof.nome} em ${formatarDataHora(q)}; lembrete programado',
        _area,
        _autor);
    setState(() {
      _cli = null;
      _quando = null;
      _erro = null;
    });
    msg(context, 'Agendamento criado com ${prof.nome}; lembrete programado.');
  }

  @override
  Widget build(BuildContext context) => Obs((c) {
        final clientes = dados.clientes(_area);
        final servs = servicosDe(_area);
        final futuros = dados
            .doArea(_area)
            .where((x) => x.aberto && x.quando.isAfter(DateTime.now()))
            .toList()
          ..sort((x, y) => x.quando.compareTo(y.quando));
        return Pagina(
          titulo: 'Agendar serviço – ${_area.nome}',
          sub: 'Escolha o cliente, o tipo de serviço e o horário. O sistema distribui o cliente aleatoriamente entre os profissionais cadastrados que estiverem livres nesse horário; clientes com 3 faltas dependem da aprovação do Administrador.',
          filhos: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 16, runSpacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SizedBox(
                        width: 280,
                        child: seletor<Usuario>(
                            'Cliente (cadastrado)',
                            clientes.contains(_cli) ? _cli : null,
                            clientes,
                            (v) => setState(() => _cli = v),
                            (u) => u.nome)),
                    SizedBox(
                        width: 240,
                        child: seletor<String>('Tipo de serviço', _serv, servs,
                            (v) => setState(() => _serv = v!))),
                    OutlinedButton.icon(
                      onPressed: _escolherData,
                      icon: const Icon(Icons.schedule),
                      label: Text(_quando == null ? 'Escolher data e hora' : formatarDataHora(_quando!)),
                    ),
                  ]),
                  if (_erro != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_erro!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _agendar,
                    icon: const Icon(Icons.event_available),
                    label: const Text('Agendar'),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            Text('Próximos agendamentos', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            tabela(
              ['Nº', 'Data/hora', 'Cliente', 'Profissional', 'Serviço', 'Status', 'Lembrete'],
              [
                for (final x in futuros)
                  [
                    Text('#${x.id}'),
                    Text(formatarDataHora(x.quando)),
                    Text(x.cliente.nome),
                    Text(x.prof.nome),
                    Text(x.servico),
                    chipStatus(x.status),
                    Text(x.lembrete.rotulo),
                  ]
              ],
            ),
          ],
        );
      });
}

// ───────────────────────── Remarcar/cancelar serviço ─────────────────────────

class PaginaRemarcarCancelar extends StatelessWidget {
  const PaginaRemarcarCancelar(this.auxiliar, {super.key});

  final Usuario auxiliar;

  Area get _area => auxiliar.area;
  String get _autor => auxiliar.nome;

  /// Regra de 24h: sem exceção para o auxiliar (só o Administrador autoriza).
  bool _antecedenciaOk(BuildContext c, Atend x, String acao) {
    if (x.quando.difference(DateTime.now()).inHours >= 24) return true;
    alerta(c, 'Ação bloqueada',
        'Não é possível $acao este agendamento: é preciso ter antecedência mínima de 24h em relação ao horário (${formatarDataHora(x.quando)}). Se for necessário, procure o Administrador.');
    dados.log('Solicitação de $acao bloqueada (menos de 24h): #${x.id} ${x.cliente.nome}', _area, _autor);
    return false;
  }

  Future<void> _remarcar(BuildContext c, Atend x) async {
    if (!_antecedenciaOk(c, x, 'remarcar')) return;
    final n = await escolherDataHora(c, x.quando);
    if (n == null || !c.mounted) return;
    if (n.isBefore(DateTime.now())) {
      alerta(c, 'Horário inválido', 'Escolha um horário futuro.');
      return;
    }
    if (!dentroDoExpediente(x.area, n)) {
      alerta(c, 'Fora do expediente',
          'O horário escolhido está fora do expediente da ${x.area.nome} (${descricaoExpediente(x.area)}). Escolha outro horário.');
      return;
    }
    final ocupado = dados.atendimentos.any((y) =>
        y != x && y.prof == x.prof && y.aberto && y.quando.difference(n).abs().inMinutes < 60);
    if (ocupado) {
      alerta(c, 'Horário ocupado',
          '${x.prof.nome} já tem agendamento próximo a esse horário. Sugestão: ${formatarDataHora(n.add(const Duration(hours: 1)))}.');
      return;
    }
    final antigo = x.quando;
    x.quando = n;
    x.status = StatusAtend.agendado;
    x.lembrete = StatusLembrete.naoEnviado;
    x.avisoClinica = 'A clínica remarcou o seu agendamento para ${formatarDataHora(n)}.';
    dados.log(
        'Agendamento #${x.id} remarcado de ${formatarDataHora(antigo)} para ${formatarDataHora(n)} (${x.cliente.nome})',
        _area,
        _autor);
    if (c.mounted) msg(c, 'Agendamento remarcado. Agenda atualizada.');
  }

  Future<void> _cancelar(BuildContext c, Atend x) async {
    if (!_antecedenciaOk(c, x, 'cancelar')) return;
    final ok = await confirmar(c, 'Cancelar agendamento?',
        '${x.cliente.nome} – ${x.servico} em ${formatarDataHora(x.quando)}',
        rotulo: 'Cancelar agendamento');
    if (!ok) return;
    x.status = StatusAtend.cancelado;
    x.avisoClinica = 'A clínica cancelou o seu agendamento de ${formatarDataHora(x.quando)}.';
    dados.log('Agendamento #${x.id} cancelado (${x.cliente.nome}, ${formatarDataHora(x.quando)})',
        _area, _autor);
    if (c.mounted) msg(c, 'Agendamento cancelado. Agenda atualizada.');
  }

  @override
  Widget build(BuildContext context) => Obs((c) {
        final l = dados.doArea(_area).where((x) => x.aberto).toList()
          ..sort((x, y) => x.quando.compareTo(y.quando));
        return Pagina(
          titulo: 'Remarcar/cancelar serviço – ${_area.nome}',
          sub: 'Selecione o agendamento e escolha alterar, remarcar ou cancelar. O sistema valida a antecedência mínima de 24h e o expediente; com menos que isso, a ação é bloqueada e o motivo é informado. A agenda interna e a página do cliente são atualizadas na hora.',
          filhos: [
            tabela(
              ['Nº', 'Data/hora', 'Cliente', 'Profissional', 'Serviço', 'Status', 'Ações'],
              [
                for (final x in l)
                  [
                    Text('#${x.id}'),
                    Text(formatarDataHora(x.quando)),
                    Text(x.cliente.nome),
                    Text(x.prof.nome),
                    Text(x.servico),
                    chipStatus(x.status),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          tooltip: 'Alterar agendamento',
                          icon: const Icon(Icons.edit),
                          onPressed: () =>
                              alterarAgendamento(c, x, autor: _autor, admin: false)),
                      IconButton(
                          tooltip: 'Remarcar',
                          icon: const Icon(Icons.edit_calendar),
                          onPressed: () => _remarcar(c, x)),
                      IconButton(
                          tooltip: 'Cancelar',
                          icon: const Icon(Icons.event_busy),
                          onPressed: () => _cancelar(c, x)),
                    ]),
                  ]
              ],
            ),
            ...secaoAlteracoesAgenda(c, _area),
          ],
        );
      });
}

// ───────────────────────── Login do auxiliar ─────────────────────────

class AuxiliarLoginPage extends StatefulWidget {
  const AuxiliarLoginPage({super.key});

  @override
  State<AuxiliarLoginPage> createState() => _AuxiliarLoginPageState();
}

class _AuxiliarLoginPageState extends State<AuxiliarLoginPage> {
  static const _maxTentativas = 5;
  static const _bloqueio = Duration(seconds: 30);

  final _email = TextEditingController();
  final _senha = TextEditingController();
  String? _erro;
  int _tentativas = 0;
  DateTime? _bloqueadoAte;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  void _entrar() {
    final agora = DateTime.now();
    final ate = _bloqueadoAte;
    if (ate != null && agora.isBefore(ate)) {
      final s = ate.difference(agora).inSeconds + 1;
      setState(() => _erro = 'Muitas tentativas. Tente novamente em ${s}s.');
      return;
    }

    // DEMO (sem backend): confere e-mail de um auxiliar cadastrado + senha de demonstração.
    // TODO: trocar pela autenticação real (a senha não pode ficar no app).
    final email = _email.text.trim().toLowerCase();
    final auxiliar = dados.usuarios
        .where((u) =>
            u.perfil == Perfil.auxiliar &&
            u.ativo &&
            (u.email?.toLowerCase() == email || u.contato.toLowerCase() == email))
        .firstOrNull;
    if (auxiliar != null && _senha.text == senhaDemoAuxiliar) {
      _tentativas = 0;
      dados.log('Login do auxiliar: ${auxiliar.nome}', auxiliar.area, auxiliar.nome);
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => AuxiliarPanel(auxiliar: auxiliar)));
      return;
    }

    dados.log('Acesso do auxiliar negado: e-mail ou senha inválidos');
    _tentativas++;
    if (_tentativas >= _maxTentativas) {
      _tentativas = 0;
      _bloqueadoAte = agora.add(_bloqueio);
      setState(() => _erro =
          'Muitas tentativas. Aguarde ${_bloqueio.inSeconds}s para tentar de novo.');
    } else {
      setState(() => _erro = 'E-mail ou senha inválidos');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FundoSuave(
      cores: [Area.estetica.corClara, Area.psicologia.corClara],
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: barra(acoes: [
        if (ehCelular(context))
          IconButton(
              tooltip: 'Voltar',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context))
        else
          TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Voltar')),
      ]),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 6,
              child: Padding(
                padding: EdgeInsets.all(ehCelular(context) ? 20 : 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.badge_outlined, size: 56, color: navy),
                    const SizedBox(height: 12),
                    const Text('Acesso do auxiliar',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: decoracaoCampo('E-mail', icone: Icons.email_outlined),
                    ),
                    const SizedBox(height: 16),
                    CampoSenha(controller: _senha, onSubmitted: (_) => _entrar()),
                    if (_erro != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_erro!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _entrar,
                      style: FilledButton.styleFrom(
                          backgroundColor: navy,
                          padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text('Entrar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}