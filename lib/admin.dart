import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart';

// TODO: em produção, valide o login do administrador no backend.
// Credenciais dentro do app web podem ser lidas por qualquer pessoa.
const _admLogin = 'adm unipora';
const _admSenha = 'Unipora5adm';
const _navy = Color(0xFF00085E);
const _formas = ['Dinheiro', 'Pix', 'Cartão de débito', 'Cartão de crédito'];

List<String> _servicos(Area a) => a == Area.estetica
    ? ['Limpeza de pele', 'Drenagem linfática', 'Massagem relaxante', 'Design de sobrancelhas']
    : ['Triagem inicial', 'Consulta individual', 'Avaliação psicológica'];

// ───────────────────────────── utilidades ─────────────────────────────

String _p(int n) => n.toString().padLeft(2, '0');
String _data(DateTime d) => '${_p(d.day)}/${_p(d.month)}/${d.year}';
String _hora(DateTime d) => '${_p(d.hour)}:${_p(d.minute)}';
String _dh(DateTime d) => '${_data(d)} ${_hora(d)}';
String _rs(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';
bool _mesmoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
DateTime _hoje(int h, [int m = 0]) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h, m);
}

DateTime _h(int horas) => DateTime.now().add(Duration(hours: horas));

InputDecoration _dec(String label) =>
    InputDecoration(labelText: label, border: const OutlineInputBorder());

Color _corStatus(String s) {
  switch (s) {
    case 'confirmado':
    case 'concluído':
      return Colors.green;
    case 'em atendimento':
      return Colors.orange;
    case 'ausente':
      return Colors.red;
    case 'cancelado':
      return Colors.grey;
    default:
      return Colors.blue;
  }
}

Widget _chip(String t, Color cor) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: cor.withAlpha(40), borderRadius: BorderRadius.circular(12)),
      child: Text(t,
          style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w600)),
    );

Widget _kpi(IconData i, String t, String v, Color cor) => SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(backgroundColor: cor.withAlpha(40), child: Icon(i, color: cor)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text(t, style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ),
    );

Widget _tabela(List<String> cols, List<List<Widget>> linhas) {
  if (linhas.isEmpty) {
    return const Card(
        child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Nenhum registro encontrado.'))));
  }
  return Card(
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          for (final c in cols)
            DataColumn(label: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)))
        ],
        rows: [
          for (final l in linhas) DataRow(cells: [for (final w in l) DataCell(w)])
        ],
      ),
    ),
  );
}

Widget _sel<T>(String label, T? valor, List<T> itens, ValueChanged<T?> onChanged,
    [String Function(T)? nome]) {
  return InputDecorator(
    decoration: _dec(label),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        isExpanded: true,
        isDense: true,
        value: valor,
        items: [
          for (final i in itens)
            DropdownMenuItem<T>(value: i, child: Text(nome == null ? '$i' : nome(i)))
        ],
        onChanged: onChanged,
      ),
    ),
  );
}

void _msg(BuildContext c, String t) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));

void _alerta(BuildContext c, String titulo, String texto) => showDialog(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Entendi'))],
      ),
    );

Future<bool> _conf(BuildContext c, String titulo, String texto,
    {String rotulo = 'Confirmar'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(rotulo)),
      ],
    ),
  );
  return r == true;
}

Future<DateTime?> _pickDH(BuildContext c, DateTime ini) async {
  final d = await showDatePicker(
      context: c, initialDate: ini, firstDate: DateTime(2025), lastDate: DateTime(2028));
  if (d == null || !c.mounted) return null;
  final t = await showTimePicker(context: c, initialTime: TimeOfDay.fromDateTime(ini));
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

// ───────────────────────────── modelos e dados ─────────────────────────────

class Usuario {
  Usuario(this.nome, this.perfil, this.contato, this.area);
  String nome, perfil, contato;
  final Area area;
  bool ativo = true;
}

/// Agendamento + atendimento no mesmo registro (status muda ao longo do fluxo).
/// status: agendado, confirmado, em atendimento, concluído, ausente, cancelado
class Atend {
  Atend(this.id, this.area, this.cliente, this.prof, this.servico, this.quando, this.status,
      {this.valor = 0, this.forma, this.lembrete = 'não enviado'});
  final int id;
  final Area area;
  final String cliente, prof, servico;
  DateTime quando;
  String status, lembrete; // lembrete: não enviado, enviado, confirmado, sem resposta
  double valor;
  String? forma;
  bool get aberto => status == 'agendado' || status == 'confirmado';
}

/// Valor lançado sem vínculo a atendimento (impede fechar o caixa).
class Avulso {
  Avulso(this.area, this.valor, this.forma, this.data);
  final Area area;
  final double valor;
  final String forma;
  final DateTime data;
}

/// Dados de exemplo em memória. Troque pelo seu backend.
class Dados extends ChangeNotifier {
  final usuarios = <Usuario>[
    Usuario('Ana Souza', 'atendente', 'ana@email.com', Area.estetica),
    Usuario('Bia Costa', 'auxiliar', '(64) 99911-2233', Area.estetica),
    Usuario('Julia Rocha', 'cliente', '(64) 99100-0001', Area.estetica),
    Usuario('Fernanda Lima', 'cliente', '(64) 99100-0002', Area.estetica),
    Usuario('Renata Dias', 'cliente', '(64) 99100-0003', Area.estetica),
    Usuario('Dra. Paula', 'atendente', 'paula@email.com', Area.psicologia),
    Usuario('Dr. Rafael', 'atendente', 'rafael@email.com', Area.psicologia),
    Usuario('Marina Alves', 'cliente', '(64) 99200-0001', Area.psicologia),
    Usuario('João Pereira', 'cliente', '(64) 99200-0002', Area.psicologia),
    Usuario('Luiza Prado', 'cliente', '(64) 99200-0003', Area.psicologia),
    Usuario('Maria Santos', 'cliente', '(64) 99200-0004', Area.psicologia),
  ];
  final triagem = <String>[
    'Maria Santos • chegada 14:05',
    'João Pereira • chegada 14:12',
    'Luiza Prado • chegada 14:20',
  ];
  final atendimentos = <Atend>[
    Atend(1, Area.estetica, 'Julia Rocha', 'Ana Souza', 'Limpeza de pele', _hoje(9), 'concluído', valor: 150, forma: 'Pix'),
    Atend(2, Area.estetica, 'Fernanda Lima', 'Bia Costa', 'Massagem relaxante', _hoje(10), 'concluído'),
    Atend(3, Area.estetica, 'Renata Dias', 'Ana Souza', 'Design de sobrancelhas', _h(-30), 'ausente'),
    Atend(4, Area.estetica, 'Renata Dias', 'Bia Costa', 'Drenagem linfática', _h(-120), 'ausente'),
    Atend(5, Area.estetica, 'Renata Dias', 'Ana Souza', 'Limpeza de pele', _h(-200), 'ausente'),
    Atend(6, Area.estetica, 'Julia Rocha', 'Bia Costa', 'Drenagem linfática', _h(30), 'confirmado', lembrete: 'confirmado'),
    Atend(7, Area.estetica, 'Fernanda Lima', 'Ana Souza', 'Limpeza de pele', _h(52), 'agendado'),
    Atend(8, Area.psicologia, 'Marina Alves', 'Dra. Paula', 'Consulta individual', _hoje(8), 'concluído', valor: 120, forma: 'Pix'),
    Atend(9, Area.psicologia, 'João Pereira', 'Dr. Rafael', 'Triagem inicial', _h(-1), 'em atendimento'),
    Atend(10, Area.psicologia, 'Luiza Prado', 'Dra. Paula', 'Consulta individual', _h(40), 'confirmado', lembrete: 'confirmado'),
    Atend(11, Area.psicologia, 'Maria Santos', 'Dr. Rafael', 'Avaliação psicológica', _h(28), 'agendado', lembrete: 'sem resposta'),
    Atend(12, Area.psicologia, 'Marina Alves', 'Dra. Paula', 'Consulta individual', _h(-100), 'ausente'),
    Atend(13, Area.psicologia, 'João Pereira', 'Dra. Paula', 'Consulta individual', _h(3), 'agendado', lembrete: 'enviado'),
    Atend(14, Area.psicologia, 'Maria Santos', 'Dra. Paula', 'Triagem inicial', _h(-5), 'agendado'),
  ];
  final avulsos = <Avulso>[Avulso(Area.estetica, 80, 'Dinheiro', DateTime.now())];
  final liberados = <String>{};
  final fechamentos = <String, double>{};
  final _logs = <String>[];
  int _seq = 100;

  int proximoId() => ++_seq;

  /// Log somente de leitura (só é possível adicionar registros).
  List<String> get logs => List.unmodifiable(_logs);

  void log(String acao, [Area? area]) {
    final tag = area == null ? '' : '[${area.nome}] ';
    _logs.insert(0, '${_dh(DateTime.now())} • $_admLogin • $tag$acao');
    notifyListeners();
  }

  List<Atend> doArea(Area a) => atendimentos.where((x) => x.area == a).toList();
  List<Usuario> clientes(Area a) =>
      usuarios.where((u) => u.area == a && u.perfil == 'cliente' && u.ativo).toList();
  List<Usuario> profissionais(Area a) =>
      usuarios.where((u) => u.area == a && u.perfil != 'cliente' && u.ativo).toList();
  int faltas(String cliente, Area a) =>
      atendimentos.where((x) => x.area == a && x.cliente == cliente && x.status == 'ausente').length;
  int futuros(Usuario u) => atendimentos
      .where((x) => x.aberto && x.quando.isAfter(DateTime.now()) && (x.cliente == u.nome || x.prof == u.nome))
      .length;
  String contato(String nome) {
    for (final u in usuarios) {
      if (u.nome == nome) return u.contato;
    }
    return '—';
  }

  List<Atend> pendentes(Area a) =>
      atendimentos.where((x) => x.area == a && x.status == 'concluído' && x.forma == null).toList();
  List<Atend> lancadosHoje(Area a) => atendimentos
      .where((x) => x.area == a && x.forma != null && _mesmoDia(x.quando, DateTime.now()))
      .toList();
  List<Avulso> avulsosDe(Area a) => avulsos.where((v) => v.area == a).toList();
  double totalDia(Area a) => lancadosHoje(a).fold(0.0, (s, x) => s + x.valor);
  String chaveCaixa(Area a) => '${a.name}-${_data(DateTime.now())}';

  void atualizar() => notifyListeners();
}

final dados = Dados();

class _Obs extends StatelessWidget {
  const _Obs(this.b);
  final Widget Function(BuildContext) b;
  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: dados, builder: (c, _) => b(c));
}

class _Pagina extends StatelessWidget {
  const _Pagina({required this.titulo, required this.sub, this.acoes = const [], required this.filhos});
  final String titulo, sub;
  final List<Widget> acoes, filhos;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(24), children: [
      Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(sub),
            ]),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: acoes),
        ],
      ),
      const SizedBox(height: 20),
      ...filhos,
    ]);
  }
}

/// Barra superior com a logo da Uniporá no canto esquerdo.
PreferredSizeWidget _barra({List<Widget>? acoes}) {
  return AppBar(
    automaticallyImplyLeading: false,
    backgroundColor: Colors.white,
    titleSpacing: 16,
    title: Align(
      alignment: Alignment.centerLeft,
      child: Image.asset('assets/logo_unipora.png', height: 36),
    ),
    actions: acoes,
  );
}

Widget _sair(BuildContext context) => TextButton.icon(
      onPressed: () {
        dados.log('Logout do administrador');
        Navigator.popUntil(context, (r) => r.isFirst);
      },
      icon: const Icon(Icons.logout),
      label: const Text('Sair'),
    );

// ───────────────────────── Login do administrador ─────────────────────────

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _u = TextEditingController();
  final _s = TextEditingController();
  bool _oculta = true;
  String? _erro;

  @override
  void dispose() {
    _u.dispose();
    _s.dispose();
    super.dispose();
  }

  void _entrar() {
    if (_u.text.trim().toLowerCase() == _admLogin && _s.text == _admSenha) {
      dados.log('Login do administrador');
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminHome()));
    } else {
      dados.log('Acesso administrativo negado: usuário ou senha inválidos');
      setState(() => _erro = 'Usuário ou senha inválidos');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _barra(acoes: [
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
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.admin_panel_settings, size: 56, color: _navy),
                    const SizedBox(height: 12),
                    const Text('Acesso do administrador',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    TextField(controller: _u, decoration: _dec('Usuário')),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _s,
                      obscureText: _oculta,
                      onSubmitted: (_) => _entrar(),
                      decoration: _dec('Senha').copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(_oculta ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _oculta = !_oculta),
                        ),
                      ),
                    ),
                    if (_erro != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_erro!, style: const TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _entrar,
                      style: FilledButton.styleFrom(
                          backgroundColor: _navy, padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: const Text('Entrar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Escolha da área ─────────────────────────

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _barra(acoes: [_sair(context)]),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Painel do administrador',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Acesso total. Escolha a área que deseja administrar.'),
            const SizedBox(height: 32),
            Wrap(
              spacing: 32,
              runSpacing: 24,
              alignment: WrapAlignment.center,
              children: [for (final a in Area.values) _CardArea(a)],
            ),
          ]),
        ),
      ),
    );
  }
}

class _CardArea extends StatelessWidget {
  const _CardArea(this.area);
  final Area area;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => AdminPanel(area: area))),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: SizedBox(
            width: 160,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                  radius: 44,
                  backgroundColor: area.cor,
                  child: Icon(area.icone, size: 48, color: Colors.white)),
              const SizedBox(height: 16),
              Text(area.nome,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: area.cor)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Painel da área ─────────────────────────

class _Sec {
  const _Sec(this.icone, this.nome, this.pagina);
  final IconData icone;
  final String nome;
  final Widget pagina;
}

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key, required this.area});
  final Area area;

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  int _i = 0;

  List<_Sec> get _secoes {
    final a = widget.area;
    return [
      _Sec(Icons.dashboard, 'Visão geral', _VisaoGeral(a)),
      _Sec(Icons.people, 'Usuários', _Usuarios(a)),
      _Sec(Icons.calendar_month, 'Agenda', _Agenda(a)),
      _Sec(Icons.assignment_ind, 'Atendimentos', _Atendimentos(a)),
      _Sec(Icons.event_busy, 'Faltas', _Faltas(a)),
      _Sec(Icons.notifications_active, 'Lembretes WhatsApp', _Lembretes(a)),
      _Sec(Icons.point_of_sale, 'Caixa', _Caixa(a)),
      if (a == Area.psicologia) const _Sec(Icons.low_priority, 'Triagem', _Triagem()),
      _Sec(Icons.bar_chart, 'Indicadores e relatórios', _Indicadores(a)),
      const _Sec(Icons.shield, 'Controle de acesso', _Acesso()),
      _Sec(Icons.history, 'Auditoria', _Auditoria(a)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.area;
    final s = _secoes;
    final largo = MediaQuery.of(context).size.width >= 900;
    if (_i >= s.length) _i = 0;

    Widget menu() => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (var k = 0; k < s.length; k++)
              ListTile(
                selected: k == _i,
                selectedColor: a.cor,
                selectedTileColor: a.cor.withAlpha(25),
                leading: Icon(s[k].icone),
                title: Text(s[k].nome),
                onTap: () {
                  setState(() => _i = k);
                  if (!largo) Navigator.pop(context);
                },
              ),
          ],
        );

    return Scaffold(
      appBar: _barra(acoes: [
        if (!largo)
          Builder(
              builder: (c) => IconButton(
                  icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(c).openDrawer())),
        if (largo)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('Administração de ${a.nome}',
                style: TextStyle(color: a.cor, fontWeight: FontWeight.bold)),
          ),
        TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Trocar área')),
        _sair(context),
      ]),
      drawer: largo ? null : Drawer(child: SafeArea(child: menu())),
      body: Row(children: [
        if (largo) SizedBox(width: 250, child: menu()),
        if (largo) const VerticalDivider(width: 1),
        Expanded(child: s[_i].pagina),
      ]),
    );
  }
}

// ───────────────────────── Visão geral ─────────────────────────

class _VisaoGeral extends StatelessWidget {
  const _VisaoGeral(this.a);
  final Area a;

  @override
  Widget build(BuildContext context) => _Obs((c) {
        final agora = DateTime.now();
        final l = dados.doArea(a);
        final hoje = l.where((x) => _mesmoDia(x.quando, agora) && x.status != 'cancelado').length;
        final futuros = l.where((x) => x.aberto && x.quando.isAfter(agora)).length;
        final faltas = l.where((x) => x.status == 'ausente').length;
        final ativos = dados.usuarios.where((u) => u.area == a && u.ativo).length;
        final fechado = dados.fechamentos.containsKey(dados.chaveCaixa(a));
        final alertas = <String>[
          for (final u in dados.clientes(a))
            if (dados.faltas(u.nome, a) >= 3 && !dados.liberados.contains(u.nome))
              '${u.nome} atingiu 3 faltas: novo agendamento bloqueado ou dependente da sua aprovação.',
          if (l.any((x) => x.aberto && x.quando.isBefore(agora)))
            'Há agendamentos vencidos sem check-in: processe as ausências na aba Faltas.',
          if (l.any((x) => x.lembrete == 'sem resposta' && x.aberto))
            'Há clientes que não confirmaram o lembrete no prazo.',
          if (dados.avulsosDe(a).isNotEmpty)
            'Existe valor lançado sem vínculo a atendimento: impede o fechamento do caixa.',
          if (dados.pendentes(a).isNotEmpty)
            '${dados.pendentes(a).length} atendimento(s) concluído(s) aguardando lançamento no caixa.',
          if (!fechado) 'O caixa de hoje ainda está aberto.',
        ];
        return _Pagina(
          titulo: 'Visão geral – ${a.nome}',
          sub: 'Resumo de tudo o que acontece na área. O administrador tem acesso e controle sobre todos os módulos.',
          filhos: [
            Wrap(spacing: 16, runSpacing: 16, children: [
              _kpi(Icons.today, 'Atendimentos hoje', '$hoje', a.cor),
              _kpi(Icons.event, 'Agendamentos futuros', '$futuros', Colors.blue),
              _kpi(Icons.event_busy, 'Faltas registradas', '$faltas', Colors.red),
              _kpi(Icons.payments, 'Caixa de hoje', _rs(dados.totalDia(a)), Colors.green),
              _kpi(Icons.people, 'Usuários ativos', '$ativos', Colors.indigo),
            ]),
            const SizedBox(height: 24),
            Text('Alertas e pendências', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (alertas.isEmpty)
              const Text('Nenhuma pendência.')
            else
              for (final t in alertas)
                Card(child: ListTile(leading: const Icon(Icons.warning_amber, color: Colors.orange), title: Text(t))),
          ],
        );
      });
}

// ───────────────────────── Usuários ─────────────────────────

void _formUsuario(BuildContext c, Area area, [Usuario? u]) {
  final nome = TextEditingController(text: u?.nome);
  final contato = TextEditingController(text: u?.contato);
  var perfil = u?.perfil ?? 'cliente';
  String? erro;
  showDialog(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(u == null ? 'Novo usuário' : 'Editar usuário'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nome, decoration: _dec('Nome completo')),
            const SizedBox(height: 12),
            _sel<String>('Perfil', perfil, const ['atendente', 'auxiliar', 'cliente'],
                (v) => set(() => perfil = v!)),
            const SizedBox(height: 12),
            TextField(controller: contato, decoration: _dec('Contato (e-mail ou WhatsApp)')),
            if (erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(erro!, style: const TextStyle(color: Colors.red)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final n = nome.text.trim(), t = contato.text.trim();
              if (n.length < 3 || t.length < 5) {
                set(() => erro = 'Dados inválidos: informe nome e contato. Nada foi salvo.');
                return;
              }
              if (dados.usuarios.any((x) => x != u && x.contato.toLowerCase() == t.toLowerCase())) {
                set(() => erro = 'Dados duplicados: já existe um usuário com este contato.');
                return;
              }
              if (u == null) {
                dados.usuarios.add(Usuario(n, perfil, t, area));
                dados.log('Usuário criado: $n ($perfil, $t)', area);
              } else {
                dados.log('Usuário editado: ${u.nome} → $n ($perfil, $t)', area);
                u.nome = n;
                u.perfil = perfil;
                u.contato = t;
              }
              Navigator.pop(d);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}

class _Usuarios extends StatefulWidget {
  const _Usuarios(this.a);
  final Area a;

  @override
  State<_Usuarios> createState() => _UsuariosState();
}

class _UsuariosState extends State<_Usuarios> {
  String _busca = '', _perfil = 'Todos';

  Future<void> _alternar(Usuario u) async {
    if (u.ativo) {
      final f = dados.futuros(u);
      final ok = await _conf(
        context,
        'Desativar ${u.nome}?',
        f > 0
            ? 'Atenção: este usuário tem $f atendimento(s) futuro(s) em aberto. Deseja desativar mesmo assim?'
            : 'O usuário perderá o acesso ao sistema.',
        rotulo: 'Desativar',
      );
      if (!ok) return;
    }
    u.ativo = !u.ativo;
    dados.log('Usuário ${u.ativo ? 'reativado' : 'desativado'}: ${u.nome}', u.area);
  }

  @override
  Widget build(BuildContext context) => _Obs((c) {
        final l = dados.usuarios
            .where((u) =>
                u.area == widget.a &&
                (_perfil == 'Todos' || u.perfil == _perfil) &&
                u.nome.toLowerCase().contains(_busca.toLowerCase()))
            .toList();
        return _Pagina(
          titulo: 'Usuários – ${widget.a.nome}',
          sub: ' Cadastrar, editar e desativar usuários (atendente, auxiliar ou cliente). Toda ação gera log de auditoria.',
          acoes: [
            FilledButton.icon(
                onPressed: () => _formUsuario(c, widget.a),
                icon: const Icon(Icons.person_add),
                label: const Text('Novo usuário')),
          ],
          filhos: [
            Wrap(spacing: 16, runSpacing: 12, children: [
              SizedBox(
                  width: 280,
                  child: TextField(
                      decoration: _dec('Buscar por nome').copyWith(prefixIcon: const Icon(Icons.search)),
                      onChanged: (v) => setState(() => _busca = v))),
              SizedBox(
                  width: 220,
                  child: _sel<String>('Perfil', _perfil,
                      const ['Todos', 'atendente', 'auxiliar', 'cliente'], (v) => setState(() => _perfil = v!))),
            ]),
            const SizedBox(height: 12),
            _tabela(
              ['Nome', 'Perfil', 'Contato', 'Faltas', 'Atend. futuros', 'Situação', 'Ações'],
              [
                for (final u in l)
                  [
                    Text(u.nome),
                    _chip(u.perfil, Colors.indigo),
                    Text(u.contato),
                    Text(u.perfil == 'cliente' ? '${dados.faltas(u.nome, u.area)}' : '—'),
                    Text('${dados.futuros(u)}'),
                    _chip(u.ativo ? 'Ativo' : 'Desativado', u.ativo ? Colors.green : Colors.grey),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          tooltip: 'Editar',
                          icon: const Icon(Icons.edit),
                          onPressed: () => _formUsuario(c, u.area, u)),
                      IconButton(
                          tooltip: u.ativo ? 'Desativar' : 'Reativar',
                          icon: Icon(u.ativo ? Icons.block : Icons.check_circle),
                          onPressed: () => _alternar(u)),
                    ]),
                  ]
              ],
            ),
          ],
        );
      });
}

// ───────────────────────── formulário de agendamento/atendimento ─────────────────────────

void _formAtend(BuildContext c, Area area, {required bool agendar}) {
  final clientes = dados.clientes(area).map((u) => u.nome).toList();
  final profs = dados.profissionais(area).map((u) => u.nome).toList();
  final servs = _servicos(area);
  String? cli, prof, serv = servs.first;
  DateTime? quando;
  String? erro;
  showDialog(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(agendar ? 'Novo agendamento (UC07)' : 'Registrar atendimento'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _sel<String>('Cliente (cadastrado)', cli, clientes, (v) => set(() => cli = v)),
              const SizedBox(height: 12),
              _sel<String>('Profissional responsável', prof, profs, (v) => set(() => prof = v)),
              const SizedBox(height: 12),
              _sel<String>('Tipo de serviço', serv, servs, (v) => set(() => serv = v)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final n = await _pickDH(d, quando ?? DateTime.now());
                  if (n != null) set(() => quando = n);
                },
                icon: const Icon(Icons.schedule),
                label: Text(quando == null ? 'Escolher data e hora' : _dh(quando!)),
              ),
              if (erro != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(erro!, style: const TextStyle(color: Colors.red)),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              if (cli == null || prof == null || quando == null) {
                set(() => erro = 'Campo obrigatório ausente (cliente, responsável, data/hora). Nada foi salvo.');
                return;
              }
              final q = quando!;
              if (agendar && q.isBefore(DateTime.now())) {
                set(() => erro = 'Escolha um horário futuro.');
                return;
              }
              if (agendar &&
                  dados.atendimentos.any((x) =>
                      x.prof == prof && x.aberto && x.quando.difference(q).abs().inMinutes < 60)) {
                set(() => erro = 'Horário já ocupado por $prof. Sugestão: ${_dh(q.add(const Duration(hours: 1)))}.');
                return;
              }
              if (agendar && dados.faltas(cli!, area) >= 3 && !dados.liberados.contains(cli)) {
                final ok = await _conf(
                    d,
                    'Cliente com 3 faltas',
                    '$cli atingiu 3 faltas. O novo agendamento depende da sua aprovação. Aprovar mesmo assim?',
                    rotulo: 'Aprovar');
                if (!ok) return;
                dados.log('Agendamento aprovado pelo administrador (cliente com 3 faltas): $cli', area);
              }
              dados.atendimentos.add(Atend(dados.proximoId(), area, cli!, prof!, serv!, q,
                  agendar ? 'agendado' : 'em atendimento'));
              dados.log(
                  agendar
                      ? 'Agendamento criado: $cli com $prof em ${_dh(q)}'
                      : 'Atendimento registrado: $cli com $prof em ${_dh(q)}',
                  area);
              if (d.mounted) Navigator.pop(d);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
}

// ───────────────────────── Agenda ─────────────────────────

Future<bool> _prazo24h(BuildContext c, Atend a, String acao) async {
  if (a.quando.difference(DateTime.now()).inHours >= 24) return true;
  final ok = await _conf(
    c,
    'Ação bloqueada pela regra de 24h',
    'O sistema bloqueia $acao com menos de 24h de antecedência (horário: ${_dh(a.quando)}). '
        'Como administrador, você pode autorizar uma exceção, que ficará registrada no log.',
    rotulo: 'Autorizar exceção',
  );
  if (ok) dados.log('Exceção da regra de 24h autorizada para $acao (#${a.id} ${a.cliente})', a.area);
  return ok;
}

Future<void> _remarcar(BuildContext c, Atend a) async {
  if (!await _prazo24h(c, a, 'remarcação')) return;
  if (!c.mounted) return;
  final n = await _pickDH(c, a.quando.isAfter(DateTime.now()) ? a.quando : _h(24));
  if (n == null || !c.mounted) return;
  if (dados.atendimentos.any((x) => x != a && x.prof == a.prof && x.aberto && x.quando.difference(n).abs().inMinutes < 60)) {
    _alerta(c, 'Horário ocupado',
        '${a.prof} já tem agendamento próximo a esse horário. Sugestão: ${_dh(n.add(const Duration(hours: 1)))}.');
    return;
  }
  final antigo = a.quando;
  a.quando = n;
  a.status = 'agendado';
  a.lembrete = 'não enviado';
  dados.log('Agendamento #${a.id} remarcado de ${_dh(antigo)} para ${_dh(n)} (${a.cliente})', a.area);
}

Future<void> _cancelar(BuildContext c, Atend a) async {
  if (!await _prazo24h(c, a, 'cancelamento')) return;
  if (!c.mounted) return;
  if (!await _conf(c, 'Cancelar agendamento?', '${a.cliente} – ${a.servico} em ${_dh(a.quando)}', rotulo: 'Cancelar agendamento')) return;
  a.status = 'cancelado';
  dados.log('Agendamento #${a.id} cancelado (${a.cliente}, ${_dh(a.quando)})', a.area);
}

class _Agenda extends StatelessWidget {
  const _Agenda(this.a);
  final Area a;

  @override
  Widget build(BuildContext context) => _Obs((c) {
        final l = dados.doArea(a).where((x) => x.aberto || x.status == 'cancelado').toList()
          ..sort((x, y) => x.quando.compareTo(y.quando));
        return _Pagina(
          titulo: 'Agenda – ${a.nome}',
          sub: ' Agendar, remarcar e cancelar. O sistema impede conflitos de horário e bloqueia remarcação/cancelamento com menos de 24h (exceção só com sua autorização).',
          acoes: [
            FilledButton.icon(
                onPressed: () => _formAtend(c, a, agendar: true),
                icon: const Icon(Icons.add),
                label: const Text('Novo agendamento')),
          ],
          filhos: [
            _tabela(
              ['Nº', 'Data/hora', 'Cliente', 'Profissional', 'Serviço', 'Status', 'Lembrete', 'Ações'],
              [
                for (final x in l)
                  [
                    Text('#${x.id}'),
                    Text(_dh(x.quando)),
                    Text(x.cliente),
                    Text(x.prof),
                    Text(x.servico),
                    _chip(x.status, _corStatus(x.status)),
                    Text(x.lembrete),
                    x.aberto
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(tooltip: 'Remarcar', icon: const Icon(Icons.edit_calendar), onPressed: () => _remarcar(c, x)),
                            IconButton(tooltip: 'Cancelar', icon: const Icon(Icons.event_busy), onPressed: () => _cancelar(c, x)),
                          ])
                        : const Text('—'),
                  ]
              ],
            ),
          ],
        );
      });
}

// ───────────────────────── Atendimentos ─────────────────────────

Future<void> _receber(BuildContext c, Atend x) async {
  final ok = dados.usuarios.any((u) => u.nome == x.cliente && u.perfil == 'cliente' && u.ativo && u.area == x.area);
  if (!ok) {
    _alerta(c, 'Atendimento impedido',
        'Cliente não cadastrado ou desativado. Faça o cadastro prévio em Usuários antes de iniciar o atendimento.');
    dados.log('Recebimento impedido: cliente ${x.cliente} não cadastrado/ativo', x.area);
    return;
  }
  x.status = 'em atendimento';
  dados.log('Cliente recebido para atendimento: ${x.cliente} (#${x.id})', x.area);
}

Future<void> _concluir(BuildContext c, Atend x) async {
  final ok = await _conf(c, 'Concluir atendimento', 'Confirma que o serviço de ${x.cliente} (${x.servico}) foi realizado?', rotulo: 'Confirmar realização');
  if (!ok) {
    if (c.mounted) _msg(c, 'Conclusão bloqueada: é necessário confirmar que o atendimento foi realizado.');
    return;
  }
  x.status = 'concluído';
  dados.log('Atendimento concluído: ${x.cliente} (#${x.id}), disponível para lançamento no caixa', x.area);
}

class _Atendimentos extends StatefulWidget {
  const _Atendimentos(this.a);
  final Area a;

  @override
  State<_Atendimentos> createState() => _AtendimentosState();
}

class _AtendimentosState extends State<_Atendimentos> {
  String _st = 'Todos';

  @override
  Widget build(BuildContext context) => _Obs((c) {
        final l = dados.doArea(widget.a).where((x) => _st == 'Todos' || x.status == _st).toList()
          ..sort((x, y) => y.quando.compareTo(x.quando));
        return _Pagina(
          titulo: 'Atendimentos – ${widget.a.nome}',
          sub: ' Receber o cliente, registrar e concluir atendimentos. Só clientes cadastrados são atendidos; a conclusão exige confirmação.',
          acoes: [
            FilledButton.icon(
                onPressed: () => _formAtend(c, widget.a, agendar: false),
                icon: const Icon(Icons.edit_note),
                label: const Text('Registrar atendimento')),
          ],
          filhos: [
            SizedBox(
                width: 260,
                child: _sel<String>('Status', _st,
                    const ['Todos', 'agendado', 'confirmado', 'em atendimento', 'concluído', 'ausente', 'cancelado'],
                    (v) => setState(() => _st = v!))),
            const SizedBox(height: 12),
            _tabela(
              ['Nº', 'Data/hora', 'Cliente', 'Responsável', 'Serviço', 'Status', 'Valor', 'Ações'],
              [
                for (final x in l)
                  [
                    Text('#${x.id}'),
                    Text(_dh(x.quando)),
                    Text(x.cliente),
                    Text(x.prof),
                    Text(x.servico),
                    _chip(x.status, _corStatus(x.status)),
                    Text(x.forma != null ? '${_rs(x.valor)} (${x.forma})' : (x.status == 'concluído' ? 'a lançar' : '—')),
                    x.aberto
                        ? TextButton.icon(onPressed: () => _receber(c, x), icon: const Icon(Icons.login), label: const Text('Receber'))
                        : x.status == 'em atendimento'
                            ? TextButton.icon(onPressed: () => _concluir(c, x), icon: const Icon(Icons.check), label: const Text('Concluir'))
                            : const Text('—'),
                  ]
              ],
            ),
          ],
        );
      });
}

// ───────────────────────── Faltas ─────────────────────────

class _Faltas extends StatelessWidget {
  const _Faltas(this.a);
  final Area a;

  void _processar(BuildContext c) {
    final agora = DateTime.now();
    var n = 0;
    for (final x in dados.doArea(a)) {
      if (x.aberto && x.quando.isBefore(agora)) {
        x.status = 'ausente';
        n++;
        final f = dados.faltas(x.cliente, a);
        dados.log('Ausência registrada: ${x.cliente} (#${x.id}); total de faltas: $f', a);
        if (f == 3) dados.log('ALERTA: ${x.cliente} atingiu 3 faltas', a);
      }
    }
    _msg(c, n == 0 ? 'Nenhum agendamento vencido sem check-in.' : '$n ausência(s) registrada(s).');
    dados.atualizar();
  }

  @override
  Widget build(BuildContext context) => _Obs((c) {
        final aus = dados.doArea(a).where((x) => x.status == 'ausente').toList()
          ..sort((x, y) => y.quando.compareTo(x.quando));
        return _Pagina(
          titulo: 'Faltas – ${a.nome}',
          sub: ' Agendamentos vencidos sem check-in viram "ausência" e somam ao contador do cliente. Com 3 faltas, o sistema alerta/bloqueia; você pode liberar.',
          acoes: [
            FilledButton.icon(
                onPressed: () => _processar(c),
                icon: const Icon(Icons.rule),
                label: const Text('Processar ausências')),
          ],
          filhos: [
            _tabela(
              ['Cliente', 'Faltas', 'Situação', 'Ação do administrador'],
              [
                for (final u in dados.clientes(a))
                  [
                    Text(u.nome),
                    Text('${dados.faltas(u.nome, a)}'),
                    dados.faltas(u.nome, a) < 3
                        ? _chip('Regular', Colors.green)
                        : dados.liberados.contains(u.nome)
                            ? _chip('Liberado pelo administrador', Colors.orange)
                            : _chip('Alerta / bloqueio', Colors.red),
                    dados.faltas(u.nome, a) < 3
                        ? const Text('—')
                        : TextButton(
                            onPressed: () {
                              final lib = dados.liberados.contains(u.nome);
                              lib ? dados.liberados.remove(u.nome) : dados.liberados.add(u.nome);
                              dados.log('${lib ? 'Bloqueio restabelecido' : 'Liberação concedida'} para ${u.nome} (3 faltas)', a);
                            },
                            child: Text(dados.liberados.contains(u.nome) ? 'Restabelecer bloqueio' : 'Liberar novos agendamentos'),
                          ),
                  ]
              ],
            ),
            const SizedBox(height: 24),
            Text('Histórico de ausências', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            _tabela(
              ['Nº', 'Data/hora', 'Cliente', 'Profissional', 'Serviço'],
              [for (final x in aus) [Text('#${x.id}'), Text(_dh(x.quando)), Text(x.cliente), Text(x.prof), Text(x.servico)]],
            ),
          ],
        );
      });
}

// ───────────────────────── Lembretes WhatsApp ─────────────────────────

class _Lembretes extends StatelessWidget {
  const _Lembretes(this.a);
  final Area a;

  void _verificar(BuildContext c) {
    var n = 0;
    for (final x in dados.doArea(a)) {
      if (x.aberto && x.lembrete == 'enviado' && x.quando.difference(DateTime.now()).inHours < 24) {
        x.lembrete = 'sem resposta';
        n++;
        dados.log('Alerta ao atendente ${x.prof}: ${x.cliente} não confirmou o lembrete (#${x.id})', a);
      }
    }
    _msg(c, n == 0 ? 'Todos os lembretes estão dentro do prazo.' : '$n alerta(s) enviado(s) ao atendente responsável.');
    dados.atualizar();
  }

  @override
  Widget build(BuildContext context) => _Obs((c) {
        final l = dados.doArea(a).where((x) => x.aberto).toList()..sort((x, y) => x.quando.compareTo(y.quando));
        return _Pagina(
          titulo: 'Lembretes WhatsApp – ${a.nome}',
          sub: ' Lembrete automático dos próximos agendamentos. Sem confirmação no prazo, o atendente responsável é alertado. (Envio real pelo WhatsApp depende de integração com a API.)',
          acoes: [
            FilledButton.icon(
                onPressed: () => _verificar(c),
                icon: const Icon(Icons.notification_important),
                label: const Text('Verificar confirmações')),
          ],
          filhos: [
            _tabela(
              ['Nº', 'Data/hora', 'Cliente', 'WhatsApp', 'Atendente', 'Lembrete', 'Ações'],
              [
                for (final x in l)
                  [
                    Text('#${x.id}'),
                    Text(_dh(x.quando)),
                    Text(x.cliente),
                    Text(dados.contato(x.cliente)),
                    Text(x.prof),
                    _chip(x.lembrete,
                        x.lembrete == 'confirmado' ? Colors.green : x.lembrete == 'sem resposta' ? Colors.red : Colors.blueGrey),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      TextButton(
                        onPressed: x.lembrete == 'não enviado'
                            ? () {
                                // TODO: disparar mensagem pela API do WhatsApp
                                x.lembrete = 'enviado';
                                dados.log('Lembrete enviado por WhatsApp para ${x.cliente} (#${x.id})', a);
                              }
                            : null,
                        child: const Text('Enviar'),
                      ),
                      TextButton(
                        onPressed: x.lembrete == 'enviado' || x.lembrete == 'sem resposta'
                            ? () {
                                x.lembrete = 'confirmado';
                                x.status = 'confirmado';
                                dados.log('Confirmação recebida de ${x.cliente} (#${x.id})', a);
                              }
                            : null,
                        child: const Text('Registrar confirmação'),
                      ),
                    ]),
                  ]
              ],
            ),
          ],
        );
      });
}

// ───────────────────────── Caixa ─────────────────────────

class _Caixa extends StatelessWidget {
  const _Caixa(this.a);
  final Area a;

  void _lancar(BuildContext c) {
    final pend = dados.pendentes(a);
    if (pend.isEmpty) {
      _alerta(c, 'Lançamento bloqueado',
          'Não é possível lançar valor avulso. Selecione um atendimento concluído. Não há atendimentos concluídos aguardando lançamento.');
      return;
    }
    Atend? sel = pend.first;
    final valor = TextEditingController();
    var forma = _formas[1];
    String? erro;
    showDialog(
      context: c,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Lançar valor no caixa'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _sel<Atend>('Atendimento concluído', sel, pend, (v) => set(() => sel = v),
                  (x) => '#${x.id} • ${x.cliente} • ${x.servico}'),
              const SizedBox(height: 12),
              TextField(controller: valor, keyboardType: TextInputType.number, decoration: _dec('Valor recebido (R\$)')),
              const SizedBox(height: 12),
              _sel<String>('Forma de pagamento', forma, _formas, (v) => set(() => forma = v!)),
              if (erro != null)
                Padding(padding: const EdgeInsets.only(top: 12), child: Text(erro!, style: const TextStyle(color: Colors.red))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(valor.text.replaceAll(',', '.'));
                if (sel == null || v == null || v <= 0) {
                  set(() => erro = 'Informe um valor válido e o atendimento.');
                  return;
                }
                sel!.valor = v;
                sel!.forma = forma;
                dados.log('Valor lançado: ${_rs(v)} ($forma) vinculado ao atendimento #${sel!.id}', a);
                Navigator.pop(d);
              },
              child: const Text('Lançar'),
            ),
          ],
        ),
      ),
    );
  }

  void _vincular(BuildContext c, Avulso av) {
    final pend = dados.pendentes(a);
    if (pend.isEmpty) {
      _alerta(c, 'Sem atendimento para vincular', 'Não há atendimento concluído aguardando lançamento.');
      return;
    }
    Atend? sel = pend.first;
    showDialog(
      context: c,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Vincular ${_rs(av.valor)} (${av.forma})'),
          content: SizedBox(
            width: 400,
            child: _sel<Atend>('Atendimento', sel, pend, (v) => set(() => sel = v),
                (x) => '#${x.id} • ${x.cliente} • ${x.servico}'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                sel!.valor = av.valor;
                sel!.forma = av.forma;
                dados.avulsos.remove(av);
                dados.log('Valor sem vínculo ${_rs(av.valor)} vinculado ao atendimento #${sel!.id}', a);
                Navigator.pop(d);
              },
              child: const Text('Vincular'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fechar(BuildContext c) async {
    final chave = dados.chaveCaixa(a);
    if (dados.fechamentos.containsKey(chave)) {
      _msg(c, 'O caixa de hoje já foi fechado.');
      return;
    }
    final av = dados.avulsosDe(a);
    if (av.isNotEmpty) {
      _alerta(c, 'Fechamento impedido',
          'Existe valor sem vínculo a atendimento (${_rs(av.fold(0.0, (s, v) => s + v.valor))}). Corrija (vincule) antes de fechar o caixa (UC11).');
      return;
    }
    final total = dados.totalDia(a);
    final ok = await _conf(c, 'Fechar caixa de hoje?',
        '${dados.lancadosHoje(a).length} lançamento(s) • Total do dia: ${_rs(total)}', rotulo: 'Confirmar fechamento');
    if (!ok) return;
    dados.fechamentos[chave] = total;
    dados.log('Caixa diário fechado: total ${_rs(total)}', a);
  }

  @override
  Widget build(BuildContext context) => _Obs((c) {
        final hoje = dados.lancadosHoje(a);
        final av = dados.avulsosDe(a);
        final fechado = dados.fechamentos[dados.chaveCaixa(a)];
        return _Pagina(
          titulo: 'Caixa – ${a.nome}',
          sub: ' Valores só podem ser lançados sobre atendimentos concluídos. O fechamento diário é bloqueado se houver valor sem vínculo.',
          acoes: [
            OutlinedButton.icon(onPressed: () => _lancar(c), icon: const Icon(Icons.add_card), label: const Text('Lançar valor')),
            FilledButton.icon(onPressed: () => _fechar(c), icon: const Icon(Icons.lock), label: const Text('Fechar caixa')),
          ],
          filhos: [
            Wrap(spacing: 16, runSpacing: 16, children: [
              _kpi(Icons.payments, 'Total lançado hoje', _rs(dados.totalDia(a)), Colors.green),
              _kpi(Icons.receipt_long, 'Lançamentos hoje', '${hoje.length}', Colors.blue),
              _kpi(Icons.hourglass_bottom, 'Concluídos a lançar', '${dados.pendentes(a).length}', Colors.orange),
              _kpi(Icons.link_off, 'Sem vínculo', '${av.length}', av.isEmpty ? Colors.grey : Colors.red),
              _kpi(fechado == null ? Icons.lock_open : Icons.lock, 'Situação',
                  fechado == null ? 'Aberto' : 'Fechado ${_rs(fechado)}', fechado == null ? Colors.orange : Colors.green),
            ]),
            const SizedBox(height: 24),
            Text('Lançamentos', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            _tabela(
              ['Hora', 'Cliente / atendimento', 'Forma', 'Valor', 'Vínculo', 'Ação'],
              [
                for (final x in hoje)
                  [Text(_hora(x.quando)), Text('${x.cliente} • ${x.servico}'), Text(x.forma ?? ''), Text(_rs(x.valor)),
                    _chip('Atendimento #${x.id}', Colors.green), const Text('—')],
                for (final v in av)
                  [Text(_hora(v.data)), const Text('Valor avulso'), Text(v.forma), Text(_rs(v.valor)),
                    _chip('SEM VÍNCULO', Colors.red),
                    TextButton(onPressed: () => _vincular(c, v), child: const Text('Vincular'))],
              ],
            ),
          ],
        );
      });
}

// ───────────────────────── Triagem (Psicologia) ─────────────────────────

class _Triagem extends StatelessWidget {
  const _Triagem();

  @override
  Widget build(BuildContext context) => _Obs((c) {
        final alt = dados.logs.where((e) => e.contains('Triagem alterada')).take(5).toList();
        return _Pagina(
          titulo: 'Triagem – Psicologia',
          sub: ' A fila é organizada automaticamente pelo sistema. Só o administrador pode alterar a ordem (arraste); o atendente não escolhe o paciente. Toda alteração é registrada em log.',
          filhos: [
            Card(
              child: ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: (x, y) {
                  if (y > x) y--;
                  final item = dados.triagem.removeAt(x);
                  dados.triagem.insert(y, item);
                  dados.log('Triagem alterada: "$item" da posição ${x + 1} para ${y + 1}', Area.psicologia);
                },
                children: [
                  for (var i = 0; i < dados.triagem.length; i++)
                    ListTile(
                      key: ValueKey(dados.triagem[i]),
                      leading: CircleAvatar(backgroundColor: Area.psicologia.cor, child: Text('${i + 1}', style: const TextStyle(color: Colors.white))),
                      title: Text(dados.triagem[i]),
                      trailing: const Icon(Icons.drag_handle),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Últimas alterações manuais', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (alt.isEmpty) const Text('Nenhuma alteração manual registrada.') else for (final e in alt) Text('• $e'),
          ],
        );
      });
}

// ───────────────────────── Indicadores e relatórios ─────────────────────────

class _Indicadores extends StatefulWidget {
  const _Indicadores(this.a);
  final Area a;

  @override
  State<_Indicadores> createState() => _IndicadoresState();
}

class _IndicadoresState extends State<_Indicadores> {
  String _prof = 'Todos', _serv = 'Todos';
  DateTimeRange? _per;

  @override
  Widget build(BuildContext context) => _Obs((c) {
        final a = widget.a;
        final r = dados
            .doArea(a)
            .where((x) => x.status == 'concluído' || x.status == 'ausente')
            .where((x) =>
                (_prof == 'Todos' || x.prof == _prof) &&
                (_serv == 'Todos' || x.servico == _serv) &&
                (_per == null ||
                    (!x.quando.isBefore(_per!.start) && x.quando.isBefore(_per!.end.add(const Duration(days: 1))))))
            .toList();
        final conc = r.where((x) => x.status == 'concluído').length;
        final falt = r.where((x) => x.status == 'ausente').length;
        final valor = r.fold(0.0, (s, x) => s + (x.forma != null ? x.valor : 0));
        final taxa = r.isEmpty ? 0 : (falt * 100 / r.length);
        final profs = {for (final x in r) x.prof}.toList();
        return _Pagina(
          titulo: 'Indicadores e relatórios – ${a.nome}',
          sub: ' Filtre por profissional, tipo de serviço e período para ver atendimentos, faltas e valor arrecadado.',
          acoes: [
            OutlinedButton.icon(
              onPressed: r.isEmpty
                  ? null
                  : () {
                      final csv = StringBuffer('Data;Cliente;Profissional;Serviço;Status;Valor\n');
                      for (final x in r) {
                        csv.writeln('${_dh(x.quando)};${x.cliente};${x.prof};${x.servico};${x.status};${x.forma != null ? x.valor.toStringAsFixed(2) : ''}');
                      }
                      Clipboard.setData(ClipboardData(text: csv.toString()));
                      _msg(c, 'Relatório copiado (CSV). Cole no Excel ou Planilhas.');
                      dados.log('Relatório exportado (${r.length} registros)', a);
                    },
              icon: const Icon(Icons.download),
              label: const Text('Exportar CSV'),
            ),
          ],
          filhos: [
            Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                  width: 240,
                  child: _sel<String>('Profissional', _prof, ['Todos', ...dados.doArea(a).map((x) => x.prof).toSet()],
                      (v) => setState(() => _prof = v!))),
              SizedBox(
                  width: 240,
                  child: _sel<String>('Tipo de serviço', _serv, ['Todos', ..._servicos(a)], (v) => setState(() => _serv = v!))),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(_per == null ? 'Período' : '${_data(_per!.start)} – ${_data(_per!.end)}'),
                onPressed: () async {
                  final p = await showDateRangePicker(context: c, firstDate: DateTime(2025), lastDate: DateTime(2028));
                  if (p != null) setState(() => _per = p);
                },
              ),
              TextButton(
                  onPressed: () => setState(() {
                        _prof = 'Todos';
                        _serv = 'Todos';
                        _per = null;
                      }),
                  child: const Text('Limpar filtros')),
            ]),
            const SizedBox(height: 20),
            if (r.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Sem resultados para os filtros selecionados.'))))
            else ...[
              Wrap(spacing: 16, runSpacing: 16, children: [
                _kpi(Icons.event_available, 'Atendimentos concluídos', '$conc', Colors.green),
                _kpi(Icons.event_busy, 'Faltas', '$falt', Colors.red),
                _kpi(Icons.percent, 'Taxa de faltas', '${taxa.toStringAsFixed(0)}%', Colors.orange),
                _kpi(Icons.payments, 'Valor arrecadado', _rs(valor), Colors.indigo),
              ]),
              const SizedBox(height: 24),
              Text('Por profissional', style: Theme.of(c).textTheme.titleMedium),
              const SizedBox(height: 8),
              _tabela(
                ['Profissional', 'Concluídos', 'Faltas', 'Valor arrecadado'],
                [
                  for (final p in profs)
                    [
                      Text(p),
                      Text('${r.where((x) => x.prof == p && x.status == 'concluído').length}'),
                      Text('${r.where((x) => x.prof == p && x.status == 'ausente').length}'),
                      Text(_rs(r.where((x) => x.prof == p && x.forma != null).fold(0.0, (s, x) => s + x.valor))),
                    ]
                ],
              ),
            ],
          ],
        );
      });
}

// ───────────────────────── Controle de acesso por perfil ─────────────────────────

const _matriz = [
  ['Gerenciar usuários ', ''],
  ['Alterar ordem da triagem ', ''],
  ['Consultar indicadores e relatórios ', ''],
  ['Consultar log de auditoria ', ''],
  ['Fechar caixa diário ', 'X'],
  ['Lançar valor no caixa ', 'T'],
  ['Receber cliente ', 'T'],
  ['Registrar atendimento ', 'TX'],
  ['Concluir atendimento de estética ', 'T'],
  ['Agendar serviço ', 'T'],
  ['Remarcar/cancelar serviço ', 'TC'],
];

class _Acesso extends StatelessWidget {
  const _Acesso();

  Widget _ic(bool ok) =>
      Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : Colors.grey.shade400);

  @override
  Widget build(BuildContext context) => _Obs((c) {
        final neg = dados.logs.where((e) => e.contains('negado') || e.contains('negada')).take(8).toList();
        return _Pagina(
          titulo: 'Controle de acesso por perfil',
          sub: 'Após o login, o sistema identifica o perfil e libera só as funcionalidades permitidas. Tentativa de acesso indevido é bloqueada e registrada. O administrador tem acesso a tudo.',
          acoes: [
            OutlinedButton.icon(
              onPressed: () {
                dados.log('Acesso negado: perfil atendente tentou abrir "Gerenciar usuários" por URL direta (simulação)');
                _msg(c, 'Tentativa bloqueada e registrada no log.');
              },
              icon: const Icon(Icons.gpp_bad),
              label: const Text('Simular acesso indevido'),
            ),
          ],
          filhos: [
            _tabela(
              ['Funcionalidade', 'Administrador', 'Atendente', 'Auxiliar', 'Cliente'],
              [
                for (final m in _matriz)
                  [Text(m[0]), _ic(true), _ic(m[1].contains('T')), _ic(m[1].contains('X')), _ic(m[1].contains('C'))]
              ],
            ),
            const SizedBox(height: 24),
            Text('Tentativas negadas recentes', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (neg.isEmpty) const Text('Nenhuma tentativa negada registrada.') else for (final e in neg) Text('• $e'),
          ],
        );
      });
}

// ───────────────────────── UC14 – Auditoria ─────────────────────────

class _Auditoria extends StatefulWidget {
  const _Auditoria(this.a);
  final Area a;

  @override
  State<_Auditoria> createState() => _AuditoriaState();
}

class _AuditoriaState extends State<_Auditoria> {
  String _busca = '';

  @override
  Widget build(BuildContext context) => _Obs((c) {
        final l = dados.logs
            .where((e) =>
                (!e.contains('[') || e.contains('[${widget.a.nome}]')) &&
                e.toLowerCase().contains(_busca.toLowerCase()))
            .toList();
        return _Pagina(
          titulo: 'Auditoria – ${widget.a.nome}',
          sub: 'UC14 – Registro imutável: usuário responsável, data/hora e detalhes de cada ação (cadastros, cancelamentos, lançamentos, alterações de triagem). Somente leitura.',
          filhos: [
            SizedBox(
                width: 320,
                child: TextField(
                    decoration: _dec('Buscar no log').copyWith(prefixIcon: const Icon(Icons.search)),
                    onChanged: (v) => setState(() => _busca = v))),
            const SizedBox(height: 12),
            if (l.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nenhum registro encontrado.'))))
            else
              Card(
                child: Column(children: [
                  for (final e in l) ListTile(dense: true, leading: const Icon(Icons.lock_outline), title: Text(e)),
                ]),
              ),
          ],
        );
      });
}