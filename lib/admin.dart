import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'caixa.dart';
import 'main.dart';

// ───── admin/constantes.dart ─────
// TODO: em produção, valide o login do administrador no backend.
// Credenciais dentro do app web podem ser lidas por qualquer pessoa.
const admLogin = 'adm unipora';
const admSenha = 'Unipora5adm';

const navy = Color(0xFF00085E);

// DEMO: senha de teste do login do auxiliar. TODO: remover quando houver backend.
const senhaDemoAuxiliar = 'auxiliar123';


/// Procedimento oferecido por uma área. Valor em centavos (null = ainda não definido).
class Procedimento {
  const Procedimento(this.nome, [this.valorCentavos]);

  final String nome;
  final int? valorCentavos;
}

/// Lista oficial de procedimentos e valores. Altere aqui para atualizar o app todo.
List<Procedimento> procedimentosDe(Area a) => switch (a) {
      Area.estetica => const [
          Procedimento('Limpeza de pele', 5000),
          Procedimento('Massagem relaxante', 4000),
          Procedimento('Massagem modeladora', 4000),
          Procedimento('Drenagem linfática', 4000),
          Procedimento('Design de sobrancelha', 3000),
          Procedimento('Lavagem + escova + corte', 5000),
          Procedimento('Lavagem + escova', 3000),
          Procedimento('Lavagem + corte', 3000),
          Procedimento('Spa dos pés', 3000),
        ],
      // TODO: trocar pela lista oficial de Psicologia (com valores, se houver).
      Area.psicologia => const [
          Procedimento('Triagem inicial'),
          Procedimento('Consulta individual'),
          Procedimento('Avaliação psicológica'),
        ],
    };

List<String> servicosDe(Area a) => [for (final p in procedimentosDe(a)) p.nome];

/// Valor (centavos) do procedimento pelo nome, ou null se não houver.
int? valorDoProcedimento(Area a, String nome) {
  for (final p in procedimentosDe(a)) {
    if (p.nome == nome) return p.valorCentavos;
  }
  return null;
}

// ───── admin/models.dart ─────
enum Perfil { atendente, auxiliar, cliente }

class Usuario {
  Usuario(this.nome, this.perfil, this.contato, this.area) : id = _proximoId++;

  static int _proximoId = 1;

  /// Identificador único (evita confundir pessoas com o mesmo nome).
  final int id;
  String nome, contato;
  Perfil perfil;
  final Area area;
  bool ativo = true;

  /// Dados do autocadastro do cliente.
  String? email, cpf, senha, responsavel, observacoes;
  DateTime? nascimento;
  bool aceitaLembretes = true;

  String get primeiroNome => nome.trim().split(' ').first;
}

enum StatusAtend { agendado, confirmado, emAtendimento, concluido, ausente, cancelado }

extension StatusAtendInfo on StatusAtend {
  String get rotulo => switch (this) {
        StatusAtend.agendado => 'agendado',
        StatusAtend.confirmado => 'confirmado',
        StatusAtend.emAtendimento => 'em atendimento',
        StatusAtend.concluido => 'concluído',
        StatusAtend.ausente => 'ausente',
        StatusAtend.cancelado => 'cancelado',
      };

  Color get cor => switch (this) {
        StatusAtend.agendado => Colors.blue,
        StatusAtend.confirmado => Colors.green,
        StatusAtend.emAtendimento => Colors.orange,
        StatusAtend.concluido => Colors.green,
        StatusAtend.ausente => Colors.red,
        StatusAtend.cancelado => Colors.grey,
      };

  IconData get icone => switch (this) {
        StatusAtend.agendado => Icons.schedule,
        StatusAtend.confirmado => Icons.check_circle_outline,
        StatusAtend.emAtendimento => Icons.play_circle_outline,
        StatusAtend.concluido => Icons.task_alt,
        StatusAtend.ausente => Icons.person_off,
        StatusAtend.cancelado => Icons.cancel_outlined,
      };
}

enum StatusLembrete { naoEnviado, enviado, confirmado, semResposta }

extension StatusLembreteInfo on StatusLembrete {
  String get rotulo => switch (this) {
        StatusLembrete.naoEnviado => 'não enviado',
        StatusLembrete.enviado => 'enviado',
        StatusLembrete.confirmado => 'confirmado',
        StatusLembrete.semResposta => 'sem resposta',
      };

  Color get cor => switch (this) {
        StatusLembrete.confirmado => Colors.green,
        StatusLembrete.semResposta => Colors.red,
        _ => Colors.blueGrey,
      };
}

/// Agendamento + atendimento no mesmo registro (o status muda ao longo do fluxo).
/// Valores em centavos.
class Atend {
  Atend(
    this.id,
    this.area,
    this.cliente,
    this.prof,
    this.servico,
    this.quando,
    this.status, {
    this.lembrete = StatusLembrete.naoEnviado,
  });

  final int id;
  final Area area;
  final Usuario cliente, prof;
  final String servico;
  DateTime quando;
  StatusAtend status;
  StatusLembrete lembrete;

  bool get aberto =>
      status == StatusAtend.agendado || status == StatusAtend.confirmado;

  /// Lançamentos válidos (não estornados) deste atendimento no caixa.
  List<Lancamento> get pagamentos =>
      dados.lancamentos.where((l) => l.atend == this && !l.estornado).toList();

  /// Já tem valor lançado no caixa?
  bool get lancado => pagamentos.isNotEmpty;

  int get valorPago => pagamentos.fold(0, (s, l) => s + l.valorCentavos);

  String get formasPagas => {for (final l in pagamentos) l.forma.rotulo}.join(' + ');
}

// ───── admin/dados.dart ─────
/// Dados de exemplo em memória. Troque pelo seu backend.
class Dados extends ChangeNotifier {
  Dados() {
    _semear();
  }

  static const _maxLogs = 500;

  final usuarios = <Usuario>[];
  final triagem = <String>[];
  final atendimentos = <Atend>[];
  final lancamentos = <Lancamento>[];

  /// ids de clientes liberados pelo administrador após 3 faltas.
  final liberados = <int>{};

  /// Fechamentos do caixa (inclui os reabertos, para o histórico).
  final fechamentos = <Fechamento>[];

  final _logs = <String>[];
  int _seq = 100;

  int proximoId() => ++_seq;

  /// Log somente de leitura (só é possível adicionar registros).
  List<String> get logs => List.unmodifiable(_logs);

  void log(String acao, [Area? area, String? ator]) {
    final tag = area == null ? '' : '[${area.nome}] ';
    _logs.insert(0, '${formatarDataHora(DateTime.now())} • ${ator ?? admLogin} • $tag$acao');
    if (_logs.length > _maxLogs) _logs.removeLast();
    notifyListeners();
  }

  void atualizar() => notifyListeners();

  // ───────── consultas ─────────

  List<Atend> doArea(Area a) => atendimentos.where((x) => x.area == a).toList();

  /// Clientes ativos da área (cadastrados nela ou que já agendaram nela).
  List<Usuario> clientes(Area a) => usuarios
      .where((u) =>
          u.perfil == Perfil.cliente &&
          u.ativo &&
          (u.area == a || atendimentos.any((x) => x.cliente == u && x.area == a)))
      .toList();

  List<Usuario> profissionais(Area a) => usuarios
      .where((u) => u.area == a && u.perfil != Perfil.cliente && u.ativo)
      .toList();

  int faltas(Usuario cliente) => atendimentos
      .where((x) => x.cliente == cliente && x.status == StatusAtend.ausente)
      .length;

  int futuros(Usuario u) => atendimentos
      .where((x) =>
          x.aberto &&
          x.quando.isAfter(DateTime.now()) &&
          (x.cliente == u || x.prof == u))
      .length;

  /// Atendimentos concluídos que ainda não têm lançamento no caixa.
  List<Atend> pendentes(Area a) => atendimentos
      .where((x) => x.area == a && x.status == StatusAtend.concluido && !x.lancado)
      .toList();

  List<Lancamento> lancamentosDoDia(Area a, DateTime dia, {bool incluirEstornados = true}) =>
      lancamentos
          .where((l) =>
              l.area == a && mesmoDia(l.data, dia) && (incluirEstornados || !l.estornado))
          .toList()
        ..sort((x, y) => x.data.compareTo(y.data));

  /// Lançamentos sem vínculo (de um dia, ou de todos os dias se [dia] for null).
  List<Lancamento> semVinculoDe(Area a, [DateTime? dia]) => lancamentos
      .where((l) => l.area == a && l.semVinculo && (dia == null || mesmoDia(l.data, dia)))
      .toList();

  int totalDoDia(Area a, DateTime dia) => lancamentosDoDia(a, dia, incluirEstornados: false)
      .fold(0, (s, l) => s + l.valorCentavos);

  int totalDia(Area a) => totalDoDia(a, DateTime.now());

  /// Fechamento em vigor do dia (ignora os reabertos).
  Fechamento? fechamentoDe(Area a, DateTime dia) {
    for (final f in fechamentos) {
      if (f.area == a && !f.reaberto && mesmoDia(f.dia, dia)) return f;
    }
    return null;
  }

  bool caixaFechado(Area a, DateTime dia) => fechamentoDe(a, dia) != null;

  Usuario? clientePorEmail(String email) {
    final e = email.trim().toLowerCase();
    for (final u in usuarios) {
      if (u.perfil == Perfil.cliente && u.email?.toLowerCase() == e) return u;
    }
    return null;
  }

  /// E-mail, CPF (só dígitos) ou telefone já cadastrados?
  bool cadastroDuplicado({required String email, required String cpf, required String telefone}) {
    final e = email.trim().toLowerCase();
    return usuarios.any((u) =>
        (u.email != null && u.email!.toLowerCase() == e) ||
        (u.cpf != null && u.cpf == cpf) ||
        u.contato == telefone);
  }

  // ───────── dados de exemplo ─────────

  void _semear() {
    final ana = Usuario('Ana Souza', Perfil.atendente, 'ana@email.com', Area.estetica);
    final bia = Usuario('Bia Costa', Perfil.auxiliar, '(64) 99911-2233', Area.estetica);
    final julia = Usuario('Julia Rocha', Perfil.cliente, '(64) 99100-0001', Area.estetica);
    final fernanda = Usuario('Fernanda Lima', Perfil.cliente, '(64) 99100-0002', Area.estetica);
    final renata = Usuario('Renata Dias', Perfil.cliente, '(64) 99100-0003', Area.estetica);
    final paula = Usuario('Dra. Paula', Perfil.atendente, 'paula@email.com', Area.psicologia);
    final rafael = Usuario('Dr. Rafael', Perfil.atendente, 'rafael@email.com', Area.psicologia);
    final marina = Usuario('Marina Alves', Perfil.cliente, '(64) 99200-0001', Area.psicologia);
    final joao = Usuario('João Pereira', Perfil.cliente, '(64) 99200-0002', Area.psicologia);
    final luiza = Usuario('Luiza Prado', Perfil.cliente, '(64) 99200-0003', Area.psicologia);
    final maria = Usuario('Maria Santos', Perfil.cliente, '(64) 99200-0004', Area.psicologia);
    final carla = Usuario('Carla Mendes', Perfil.auxiliar, '(64) 99933-4455', Area.psicologia);
    usuarios.addAll([ana, bia, julia, fernanda, renata, paula, rafael, marina, joao, luiza, maria, carla]);

    // E-mails de acesso dos auxiliares (login do auxiliar; senha de demonstração em senhaDemoAuxiliar).
    bia.email = 'bia@email.com';
    carla.email = 'carla@email.com';

    // Contas de DEMONSTRAÇÃO para testar o login do cliente (apague em produção).
    julia.email = 'julia@email.com';
    julia.senha = 'Cliente123';
    marina.email = 'marina@email.com';
    marina.senha = 'Cliente123';

    triagem.addAll([
      'Maria Santos • chegada 14:05',
      'João Pereira • chegada 14:12',
      'Luiza Prado • chegada 14:20',
    ]);

    const e = Area.estetica, p = Area.psicologia;
    atendimentos.addAll([
      Atend(1, e, julia, ana, 'Limpeza de pele', hojeAs(9), StatusAtend.concluido),
      Atend(2, e, fernanda, bia, 'Massagem relaxante', hojeAs(10), StatusAtend.concluido),
      Atend(3, e, renata, ana, 'Design de sobrancelha', emHoras(-30), StatusAtend.ausente),
      Atend(4, e, renata, bia, 'Drenagem linfática', emHoras(-120), StatusAtend.ausente),
      Atend(5, e, renata, ana, 'Limpeza de pele', emHoras(-200), StatusAtend.ausente),
      Atend(6, e, julia, bia, 'Drenagem linfática', emHoras(30), StatusAtend.confirmado,
          lembrete: StatusLembrete.confirmado),
      Atend(7, e, fernanda, ana, 'Limpeza de pele', emHoras(52), StatusAtend.agendado),
      Atend(8, p, marina, paula, 'Consulta individual', hojeAs(8), StatusAtend.concluido),
      Atend(9, p, joao, rafael, 'Triagem inicial', emHoras(-1), StatusAtend.emAtendimento),
      Atend(10, p, luiza, paula, 'Consulta individual', emHoras(40), StatusAtend.confirmado,
          lembrete: StatusLembrete.confirmado),
      Atend(11, p, maria, rafael, 'Avaliação psicológica', emHoras(28), StatusAtend.agendado,
          lembrete: StatusLembrete.semResposta),
      Atend(12, p, marina, paula, 'Consulta individual', emHoras(-100), StatusAtend.ausente),
      Atend(13, p, joao, paula, 'Consulta individual', emHoras(3), StatusAtend.agendado,
          lembrete: StatusLembrete.enviado),
      Atend(14, p, maria, paula, 'Triagem inicial', emHoras(-5), StatusAtend.agendado),
      // Atendimentos de dias anteriores (para consultar caixas passados).
      Atend(15, e, julia, ana, 'Limpeza de pele', diasAtras(1, 9), StatusAtend.concluido),
      Atend(16, e, fernanda, bia, 'Massagem modeladora', diasAtras(1, 11), StatusAtend.concluido),
      Atend(17, e, renata, ana, 'Spa dos pés', diasAtras(2, 15), StatusAtend.concluido),
      Atend(18, p, luiza, paula, 'Consulta individual', diasAtras(1, 14), StatusAtend.concluido),
      Atend(19, p, maria, rafael, 'Consulta individual', diasAtras(2, 10), StatusAtend.concluido),
    ]);

    // Caixa: lançamentos de exemplo (hoje e dias anteriores).
    Atend at(int id) => atendimentos.firstWhere((x) => x.id == id);
    void lanc(Area area, DateTime data, int valor, FormaPagamento forma,
        {int? atend,
        OrigemLancamento origem = OrigemLancamento.manual,
        String? aut,
        String? bandeira,
        int parcelas = 1}) {
      lancamentos.add(Lancamento(
        id: proximoId(),
        area: area,
        data: data,
        valorCentavos: valor,
        forma: forma,
        origem: origem,
        operador: admLogin,
        atend: atend == null ? null : at(atend),
        parcelas: parcelas,
        bandeira: bandeira,
        autorizacao: aut,
      )..registrar('Lançamento de exemplo'));
    }

    lanc(e, hojeAs(9), 5000, FormaPagamento.pix, atend: 1);
    lanc(p, hojeAs(8), 12000, FormaPagamento.pix, atend: 8);
    // Venda da maquininha SEM vínculo: aparece para você vincular no caixa.
    lanc(e, DateTime.now(), 8000, FormaPagamento.debito,
        origem: OrigemLancamento.maquininha, aut: '482913', bandeira: 'Visa');
    lanc(e, diasAtras(1, 9), 5000, FormaPagamento.pix, atend: 15);
    lanc(e, diasAtras(1, 11), 4000, FormaPagamento.debito,
        atend: 16, origem: OrigemLancamento.maquininha, aut: '771204', bandeira: 'Mastercard');
    lanc(e, diasAtras(2, 15), 3000, FormaPagamento.pix, atend: 17);
    lanc(p, diasAtras(1, 14), 12000, FormaPagamento.pix, atend: 18);
    lanc(p, diasAtras(2, 10), 12000, FormaPagamento.credito,
        atend: 19, origem: OrigemLancamento.maquininha, aut: '330918', bandeira: 'Elo', parcelas: 2);

    void fecha(Area area, int dias, Map<FormaPagamento, int> totais,
        Map<FormaPagamento, int?> conferidos, int qtd, [String? obs]) {
      final d = diasAtras(dias, 0);
      fechamentos.add(Fechamento(
        area: area,
        dia: d,
        fechadoEm: DateTime(d.year, d.month, d.day, 18, 5),
        responsavel: admLogin,
        qtd: qtd,
        totais: totais,
        conferidos: conferidos,
        estornosQtd: 0,
        estornosValor: 0,
        observacao: obs,
      ));
    }

    const px = FormaPagamento.pix, db = FormaPagamento.debito, cr = FormaPagamento.credito;
    fecha(e, 1, {px: 5000, db: 4000, cr: 0}, {px: 5000, db: 4000, cr: 0}, 2);
    fecha(e, 2, {px: 3000, db: 0, cr: 0}, {px: 3000, db: 0, cr: 0}, 1);
    fecha(p, 1, {px: 12000, db: 0, cr: 0}, {px: 11500, db: 0, cr: 0}, 1,
        'Diferença de R\$ 5,00 no extrato do Pix (tarifa bancária).');
    fecha(p, 2, {px: 0, db: 0, cr: 12000}, {px: 0, db: 0, cr: 12000}, 1);
  }
}

final dados = Dados();

// ───── admin/widgets/comuns.dart ─────
/// Etiqueta colorida (texto escurecido + ícone opcional para não depender só da cor).
Widget chipRotulo(String t, Color cor, {IconData? icone}) {
  final texto = Color.lerp(cor, Colors.black, 0.35)!;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
        color: cor.withAlpha(40), borderRadius: BorderRadius.circular(12)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icone != null) ...[
        Icon(icone, size: 14, color: texto),
        const SizedBox(width: 4),
      ],
      Text(t, style: TextStyle(color: texto, fontSize: 12, fontWeight: FontWeight.w600)),
    ]),
  );
}

Widget chipStatus(StatusAtend s) => chipRotulo(s.rotulo, s.cor, icone: s.icone);

Widget kpi(IconData i, String t, String v, Color cor) => Builder(builder: (context) {
      final w = MediaQuery.sizeOf(context).width;
      final cel = w < 600;
      final largura = cel ? ((w - 24 - 16) / 2).floorToDouble() : 220.0;
      return SizedBox(
        width: largura,
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(cel ? 12 : 16),
            child: Row(children: [
              CircleAvatar(
                  radius: cel ? 18 : 20,
                  backgroundColor: cor.withAlpha(40),
                  child: Icon(i, color: cor, size: cel ? 20 : 24)),
              SizedBox(width: cel ? 8 : 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v, style: TextStyle(fontSize: cel ? 17 : 22, fontWeight: FontWeight.bold)),
                  Text(t, style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
      );
    });

Widget tabela(List<String> cols, List<List<Widget>> linhas) {
  if (linhas.isEmpty) {
    return const Card(
        child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Nenhum registro encontrado.'))));
  }
  return Builder(builder: (context) {
    final cs = Theme.of(context).colorScheme;
    final cel = ehCelular(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: cel ? 16 : 28,
          horizontalMargin: cel ? 12 : 20,
          headingRowColor: WidgetStatePropertyAll(cs.primaryContainer.withAlpha(110)),
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
  });
}

/// Caixa de seleção (dropdown) com rótulo.
Widget seletor<T>(String label, T? valor, List<T> itens, ValueChanged<T?> onChanged,
    [String Function(T)? nome]) {
  return InputDecorator(
    decoration: decoracaoCampo(label),
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

void msg(BuildContext c, String t) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));

void alerta(BuildContext c, String titulo, String texto) => showDialog(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Entendi'))],
      ),
    );

Future<bool> confirmar(BuildContext c, String titulo, String texto,
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

Future<DateTime?> escolherDataHora(BuildContext c, DateTime ini) async {
  final d = await showDatePicker(
      context: c, initialDate: ini, firstDate: DateTime(2025), lastDate: DateTime(2028));
  if (d == null || !c.mounted) return null;
  final t = await showTimePicker(context: c, initialTime: TimeOfDay.fromDateTime(ini));
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

// ───── admin/widgets/estrutura.dart ─────
/// Reconstrói quando [dados] muda.
class Obs extends StatelessWidget {
  const Obs(this.builder, {super.key});

  final Widget Function(BuildContext) builder;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: dados, builder: (c, _) => builder(c));
}

/// Moldura padrão das páginas do painel (título, subtítulo, ações e conteúdo).
class Pagina extends StatelessWidget {
  const Pagina({
    super.key,
    required this.titulo,
    required this.sub,
    this.acoes = const [],
    required this.filhos,
  });

  final String titulo, sub;
  final List<Widget> acoes, filhos;

  @override
  Widget build(BuildContext context) {
    return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: ListView(padding: EdgeInsets.all(ehCelular(context) ? 12 : 24), children: [
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
                  style: (ehCelular(context)
                          ? Theme.of(context).textTheme.titleLarge
                          : Theme.of(context).textTheme.headlineSmall)
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(sub),
            ]),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: acoes),
        ],
      ),
      const SizedBox(height: 20),
      ...filhos,
    ]),
    ),
    );
  }
}

/// Barra superior com a logo da Uniporá no canto esquerdo.
PreferredSizeWidget barra({List<Widget>? acoes}) {
  return AppBar(
    automaticallyImplyLeading: false,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    titleSpacing: 16,
    title: Builder(
      builder: (c) => Align(
        alignment: Alignment.centerLeft,
        child: LogoUnipora(altura: ehCelular(c) ? 28 : 36),
      ),
    ),
    actions: acoes,
  );
}

/// Botão de sair. Usado pelo administrador (padrão) e pelo auxiliar (com [acao], [area] e [autor]).
Widget botaoSair(BuildContext context, {String? acao, Area? area, String? autor}) {
  void sair() {
    dados.log(acao ?? 'Logout do administrador', area, autor);
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  return ehCelular(context)
      ? IconButton(tooltip: 'Sair', icon: const Icon(Icons.logout), onPressed: sair)
      : TextButton.icon(
          onPressed: sair, icon: const Icon(Icons.logout), label: const Text('Sair'));
}

/// Fundo em degradê suave (mesmo estilo da tela de login).
class FundoSuave extends StatelessWidget {
  const FundoSuave({super.key, required this.cores, required this.child});

  final List<Color> cores;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: cores,
        ),
      ),
      child: child,
    );
  }
}

// ───── admin/paginas/acesso.dart ─────
/// (funcionalidade, quem pode): T = atendente, X = auxiliar, C = cliente. Administrador sempre pode.
const _matriz = <(String, String)>[
  ('Gerenciar usuários', ''),
  ('Alterar ordem da triagem', ''),
  ('Consultar indicadores e relatórios', ''),
  ('Consultar log de auditoria', ''),
  ('Fechar caixa diário', 'X'),
  ('Lançar valor no caixa', 'TX'),
  ('Receber cliente', 'TX'),
  ('Registrar atendimento', 'TX'),
  ('Concluir atendimento de estética', 'TX'),
  ('Agendar serviço', 'TX'),
  ('Remarcar/cancelar serviço', 'TXC'),
];

class PaginaAcesso extends StatelessWidget {
  const PaginaAcesso({super.key});

  Widget _icone(bool ok) => Semantics(
        label: ok ? 'Permitido' : 'Não permitido',
        child: Icon(ok ? Icons.check_circle : Icons.cancel,
            color: ok ? Colors.green : Colors.grey.shade400),
      );

  @override
  Widget build(BuildContext context) => Obs((c) {
        final neg = dados.logs
            .where((e) => e.contains('negado') || e.contains('negada'))
            .take(8)
            .toList();
        return Pagina(
          titulo: 'Controle de acesso por perfil',
          sub: 'Após o login, o sistema identifica o perfil e libera só as funcionalidades permitidas. Tentativa de acesso indevido é bloqueada e registrada. O administrador tem acesso a tudo.',
          acoes: [
            OutlinedButton.icon(
              onPressed: () {
                dados.log(
                    'Acesso negado: perfil atendente tentou abrir "Gerenciar usuários" por URL direta (simulação)');
                msg(c, 'Tentativa bloqueada e registrada no log.');
              },
              icon: const Icon(Icons.gpp_bad),
              label: const Text('Simular acesso indevido'),
            ),
          ],
          filhos: [
            tabela(
              ['Funcionalidade', 'Administrador', 'Atendente', 'Auxiliar', 'Cliente'],
              [
                for (final (nome, quem) in _matriz)
                  [
                    Text(nome),
                    _icone(true),
                    _icone(quem.contains('T')),
                    _icone(quem.contains('X')),
                    _icone(quem.contains('C')),
                  ]
              ],
            ),
            const SizedBox(height: 24),
            Text('Tentativas negadas recentes', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (neg.isEmpty)
              const Text('Nenhuma tentativa negada registrada.')
            else
              for (final e in neg) Text('• $e'),
          ],
        );
      });
}

// ───── admin/paginas/agenda.dart ─────
/// Regra de 24h: ações com menos de 24h de antecedência exigem autorização do administrador.
Future<bool> _prazo24h(BuildContext c, Atend a, String acao) async {
  if (a.quando.difference(DateTime.now()).inHours >= 24) return true;
  final ok = await confirmar(
    c,
    'Ação bloqueada pela regra de 24h',
    'O sistema bloqueia $acao com menos de 24h de antecedência (horário: ${formatarDataHora(a.quando)}). '
        'Como administrador, você pode autorizar uma exceção, que ficará registrada no log.',
    rotulo: 'Autorizar exceção',
  );
  if (ok) {
    dados.log('Exceção da regra de 24h autorizada para $acao (#${a.id} ${a.cliente.nome})', a.area);
  }
  return ok;
}

Future<void> _remarcar(BuildContext c, Atend a) async {
  if (!await _prazo24h(c, a, 'remarcação')) return;
  if (!c.mounted) return;
  final n = await escolherDataHora(
      c, a.quando.isAfter(DateTime.now()) ? a.quando : emHoras(24));
  if (n == null || !c.mounted) return;
  final conflito = dados.atendimentos.any((x) =>
      x != a && x.prof == a.prof && x.aberto && x.quando.difference(n).abs().inMinutes < 60);
  if (conflito) {
    alerta(c, 'Horário ocupado',
        '${a.prof.nome} já tem agendamento próximo a esse horário. Sugestão: ${formatarDataHora(n.add(const Duration(hours: 1)))}.');
    return;
  }
  final antigo = a.quando;
  a.quando = n;
  a.status = StatusAtend.agendado;
  a.lembrete = StatusLembrete.naoEnviado;
  dados.log(
      'Agendamento #${a.id} remarcado de ${formatarDataHora(antigo)} para ${formatarDataHora(n)} (${a.cliente.nome})',
      a.area);
}

Future<void> _cancelar(BuildContext c, Atend a) async {
  if (!await _prazo24h(c, a, 'cancelamento')) return;
  if (!c.mounted) return;
  final ok = await confirmar(
      c, 'Cancelar agendamento?', '${a.cliente.nome} – ${a.servico} em ${formatarDataHora(a.quando)}',
      rotulo: 'Cancelar agendamento');
  if (!ok) return;
  a.status = StatusAtend.cancelado;
  dados.log('Agendamento #${a.id} cancelado (${a.cliente.nome}, ${formatarDataHora(a.quando)})', a.area);
}

class PaginaAgenda extends StatelessWidget {
  const PaginaAgenda(this.a, {super.key});

  final Area a;

  @override
  Widget build(BuildContext context) => Obs((c) {
        final l = dados
            .doArea(a)
            .where((x) => x.aberto || x.status == StatusAtend.cancelado)
            .toList()
          ..sort((x, y) => x.quando.compareTo(y.quando));
        return Pagina(
          titulo: 'Agenda – ${a.nome}',
          sub: 'Agendar, remarcar e cancelar. O sistema impede conflitos de horário e bloqueia remarcação/cancelamento com menos de 24h (exceção só com sua autorização).',
          acoes: [
            FilledButton.icon(
                onPressed: () => abrirFormAtend(c, a, agendar: true),
                icon: const Icon(Icons.add),
                label: const Text('Novo agendamento')),
          ],
          filhos: [
            tabela(
              ['Nº', 'Data/hora', 'Cliente', 'Profissional', 'Serviço', 'Status', 'Lembrete', 'Ações'],
              [
                for (final x in l)
                  [
                    Text('#${x.id}'),
                    Text(formatarDataHora(x.quando)),
                    Text(x.cliente.nome),
                    Text(x.prof.nome),
                    Text(x.servico),
                    chipStatus(x.status),
                    Text(x.lembrete.rotulo),
                    x.aberto
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                tooltip: 'Remarcar',
                                icon: const Icon(Icons.edit_calendar),
                                onPressed: () => _remarcar(c, x)),
                            IconButton(
                                tooltip: 'Cancelar',
                                icon: const Icon(Icons.event_busy),
                                onPressed: () => _cancelar(c, x)),
                          ])
                        : const Text('—'),
                  ]
              ],
            ),
          ],
        );
      });
}

// ───── admin/paginas/atendimentos.dart ─────
Future<void> _receber(BuildContext c, Atend x) async {
  final ok = dados.usuarios.contains(x.cliente) && x.cliente.ativo;
  if (!ok) {
    alerta(c, 'Atendimento impedido',
        'Cliente não cadastrado ou desativado. Faça o cadastro prévio em Usuários antes de iniciar o atendimento.');
    dados.log('Recebimento impedido: cliente ${x.cliente.nome} não cadastrado/ativo', x.area);
    return;
  }
  x.status = StatusAtend.emAtendimento;
  dados.log('Cliente recebido para atendimento: ${x.cliente.nome} (#${x.id})', x.area);
}

Future<void> _concluir(BuildContext c, Atend x) async {
  final ok = await confirmar(c, 'Concluir atendimento',
      'Confirma que o serviço de ${x.cliente.nome} (${x.servico}) foi realizado?',
      rotulo: 'Confirmar realização');
  if (!ok) {
    if (c.mounted) {
      msg(c, 'Conclusão bloqueada: é necessário confirmar que o atendimento foi realizado.');
    }
    return;
  }
  x.status = StatusAtend.concluido;
  dados.log(
      'Atendimento concluído: ${x.cliente.nome} (#${x.id}), disponível para lançamento no caixa',
      x.area);
}

class PaginaAtendimentos extends StatefulWidget {
  const PaginaAtendimentos(this.a, {super.key});

  final Area a;

  @override
  State<PaginaAtendimentos> createState() => _PaginaAtendimentosState();
}

class _PaginaAtendimentosState extends State<PaginaAtendimentos> {
  StatusAtend? _st; // null = todos

  @override
  Widget build(BuildContext context) => Obs((c) {
        final l = dados
            .doArea(widget.a)
            .where((x) => _st == null || x.status == _st)
            .toList()
          ..sort((x, y) => y.quando.compareTo(x.quando));
        return Pagina(
          titulo: 'Atendimentos – ${widget.a.nome}',
          sub: 'Receber o cliente, registrar e concluir atendimentos. Só clientes cadastrados são atendidos; a conclusão exige confirmação.',
          acoes: [
            FilledButton.icon(
                onPressed: () => abrirFormAtend(c, widget.a, agendar: false),
                icon: const Icon(Icons.edit_note),
                label: const Text('Registrar atendimento')),
          ],
          filhos: [
            SizedBox(
                width: 260,
                child: seletor<StatusAtend?>('Status', _st, [null, ...StatusAtend.values],
                    (v) => setState(() => _st = v), (s) => s?.rotulo ?? 'Todos')),
            const SizedBox(height: 12),
            tabela(
              ['Nº', 'Data/hora', 'Cliente', 'Responsável', 'Serviço', 'Status', 'Valor', 'Ações'],
              [
                for (final x in l)
                  [
                    Text('#${x.id}'),
                    Text(formatarDataHora(x.quando)),
                    Text(x.cliente.nome),
                    Text(x.prof.nome),
                    Text(x.servico),
                    chipStatus(x.status),
                    Text(x.lancado
                        ? '${formatarReais(x.valorPago)} (${x.formasPagas})'
                        : (x.status == StatusAtend.concluido ? 'a lançar' : '—')),
                    x.aberto
                        ? TextButton.icon(
                            onPressed: () => _receber(c, x),
                            icon: const Icon(Icons.login),
                            label: const Text('Receber'))
                        : x.status == StatusAtend.emAtendimento
                            ? TextButton.icon(
                                onPressed: () => _concluir(c, x),
                                icon: const Icon(Icons.check),
                                label: const Text('Concluir'))
                            : const Text('—'),
                  ]
              ],
            ),
          ],
        );
      });
}

// ───── admin/paginas/auditoria.dart ─────
class PaginaAuditoria extends StatefulWidget {
  const PaginaAuditoria(this.a, {super.key});

  final Area a;

  @override
  State<PaginaAuditoria> createState() => _PaginaAuditoriaState();
}

class _PaginaAuditoriaState extends State<PaginaAuditoria> {
  String _busca = '';

  @override
  Widget build(BuildContext context) => Obs((c) {
        final l = dados.logs
            .where((e) =>
                (!e.contains('[') || e.contains('[${widget.a.nome}]')) &&
                e.toLowerCase().contains(_busca.toLowerCase()))
            .toList();
        return Pagina(
          titulo: 'Auditoria – ${widget.a.nome}',
          sub: ' Registro imutável: usuário responsável, data/hora e detalhes de cada ação (cadastros, cancelamentos, lançamentos, alterações de triagem). Somente leitura.',
          filhos: [
            SizedBox(
                width: 320,
                child: TextField(
                    decoration: decoracaoCampo('Buscar no log', icone: Icons.search),
                    onChanged: (v) => setState(() => _busca = v))),
            const SizedBox(height: 12),
            if (l.isEmpty)
              const Card(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Nenhum registro encontrado.'))))
            else
              Card(
                child: Column(children: [
                  for (final e in l)
                    ListTile(dense: true, leading: const Icon(Icons.lock_outline), title: Text(e)),
                ]),
              ),
          ],
        );
      });
}

// ───── admin/paginas/faltas.dart ─────
class PaginaFaltas extends StatelessWidget {
  const PaginaFaltas(this.a, {super.key});

  final Area a;

  void _processar(BuildContext c) {
    final agora = DateTime.now();
    var n = 0;
    for (final x in dados.doArea(a)) {
      if (x.aberto && x.quando.isBefore(agora)) {
        x.status = StatusAtend.ausente;
        n++;
        final f = dados.faltas(x.cliente);
        dados.log('Ausência registrada: ${x.cliente.nome} (#${x.id}); total de faltas: $f', a);
        if (f == 3) dados.log('ALERTA: ${x.cliente.nome} atingiu 3 faltas', a);
      }
    }
    msg(c, n == 0 ? 'Nenhum agendamento vencido sem check-in.' : '$n ausência(s) registrada(s).');
    dados.atualizar();
  }

  void _alternarLiberacao(Usuario u) {
    final lib = dados.liberados.contains(u.id);
    lib ? dados.liberados.remove(u.id) : dados.liberados.add(u.id);
    dados.log(
        '${lib ? 'Bloqueio restabelecido' : 'Liberação concedida'} para ${u.nome} (3 faltas)', a);
  }

  @override
  Widget build(BuildContext context) => Obs((c) {
        final aus = dados.doArea(a).where((x) => x.status == StatusAtend.ausente).toList()
          ..sort((x, y) => y.quando.compareTo(x.quando));
        return Pagina(
          titulo: 'Faltas – ${a.nome}',
          sub: 'Agendamentos vencidos sem check-in viram "ausência" e somam ao contador do cliente. Com 3 faltas, o sistema alerta/bloqueia; você pode liberar.',
          acoes: [
            FilledButton.icon(
                onPressed: () => _processar(c),
                icon: const Icon(Icons.rule),
                label: const Text('Processar ausências')),
          ],
          filhos: [
            tabela(
              ['Cliente', 'Faltas', 'Situação', 'Ação do administrador'],
              [
                for (final u in dados.clientes(a))
                  [
                    Text(u.nome),
                    Text('${dados.faltas(u)}'),
                    dados.faltas(u) < 3
                        ? chipRotulo('Regular', Colors.green, icone: Icons.check_circle_outline)
                        : dados.liberados.contains(u.id)
                            ? chipRotulo('Liberado pelo administrador', Colors.orange,
                                icone: Icons.lock_open)
                            : chipRotulo('Alerta / bloqueio', Colors.red, icone: Icons.block),
                    dados.faltas(u) < 3
                        ? const Text('—')
                        : TextButton(
                            onPressed: () => _alternarLiberacao(u),
                            child: Text(dados.liberados.contains(u.id)
                                ? 'Restabelecer bloqueio'
                                : 'Liberar novos agendamentos'),
                          ),
                  ]
              ],
            ),
            const SizedBox(height: 24),
            Text('Histórico de ausências', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            tabela(
              ['Nº', 'Data/hora', 'Cliente', 'Profissional', 'Serviço'],
              [
                for (final x in aus)
                  [
                    Text('#${x.id}'),
                    Text(formatarDataHora(x.quando)),
                    Text(x.cliente.nome),
                    Text(x.prof.nome),
                    Text(x.servico),
                  ]
              ],
            ),
          ],
        );
      });
}

// ───── admin/paginas/form_atend.dart ─────
Future<void> abrirFormAtend(BuildContext c, Area area, {required bool agendar}) =>
    showDialog(
        context: c, builder: (_) => FormAtendDialog(area: area, agendar: agendar));

/// Novo agendamento (agendar = true) ou registro de atendimento.
class FormAtendDialog extends StatefulWidget {
  const FormAtendDialog({super.key, required this.area, required this.agendar});

  final Area area;
  final bool agendar;

  @override
  State<FormAtendDialog> createState() => _FormAtendDialogState();
}

class _FormAtendDialogState extends State<FormAtendDialog> {
  late final List<Usuario> _clientes = dados.clientes(widget.area);
  late final List<Usuario> _profs = dados.profissionais(widget.area);
  late final List<String> _servs = servicosDe(widget.area);
  Usuario? _cli, _prof;
  late String _serv = _servs.first;
  DateTime? _quando;
  String? _erro;

  Future<void> _escolherData() async {
    final n = await escolherDataHora(context, _quando ?? DateTime.now());
    if (n != null && mounted) setState(() => _quando = n);
  }

  Future<void> _salvar() async {
    final cli = _cli, prof = _prof, q = _quando;
    final agendar = widget.agendar;
    if (cli == null || prof == null || q == null) {
      setState(() => _erro =
          'Campo obrigatório ausente (cliente, responsável, data/hora). Nada foi salvo.');
      return;
    }
    if (agendar && q.isBefore(DateTime.now())) {
      setState(() => _erro = 'Escolha um horário futuro.');
      return;
    }
    if (agendar &&
        dados.atendimentos.any((x) =>
            x.prof == prof && x.aberto && x.quando.difference(q).abs().inMinutes < 60)) {
      setState(() => _erro =
          'Horário já ocupado por ${prof.nome}. Sugestão: ${formatarDataHora(q.add(const Duration(hours: 1)))}.');
      return;
    }
    if (agendar && dados.faltas(cli) >= 3 && !dados.liberados.contains(cli.id)) {
      final ok = await confirmar(
          context,
          'Cliente com 3 faltas',
          '${cli.nome} atingiu 3 faltas. O novo agendamento depende da sua aprovação. Aprovar mesmo assim?',
          rotulo: 'Aprovar');
      if (!ok || !mounted) return;
      dados.log('Agendamento aprovado pelo administrador (cliente com 3 faltas): ${cli.nome}',
          widget.area);
    }
    dados.atendimentos.add(Atend(dados.proximoId(), widget.area, cli, prof, _serv, q,
        agendar ? StatusAtend.agendado : StatusAtend.emAtendimento));
    dados.log(
        agendar
            ? 'Agendamento criado: ${cli.nome} com ${prof.nome} em ${formatarDataHora(q)}'
            : 'Atendimento registrado: ${cli.nome} com ${prof.nome} em ${formatarDataHora(q)}',
        widget.area);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.agendar ? 'Novo agendamento' : 'Registrar atendimento'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            seletor<Usuario>('Cliente (cadastrado)', _cli, _clientes,
                (v) => setState(() => _cli = v), (u) => u.nome),
            const SizedBox(height: 12),
            seletor<Usuario>('Profissional responsável', _prof, _profs,
                (v) => setState(() => _prof = v), (u) => u.nome),
            const SizedBox(height: 12),
            seletor<String>('Tipo de serviço', _serv, _servs,
                (v) => setState(() => _serv = v!)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _escolherData,
              icon: const Icon(Icons.schedule),
              label: Text(_quando == null ? 'Escolher data e hora' : formatarDataHora(_quando!)),
            ),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_erro!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ],
    );
  }
}

// ───── admin/paginas/indicadores.dart ─────
class PaginaIndicadores extends StatefulWidget {
  const PaginaIndicadores(this.a, {super.key});

  final Area a;

  @override
  State<PaginaIndicadores> createState() => _PaginaIndicadoresState();
}

class _PaginaIndicadoresState extends State<PaginaIndicadores> {
  Usuario? _prof; // null = todos
  String? _serv; // null = todos
  DateTimeRange? _per;

  Future<void> _escolherPeriodo(BuildContext c) async {
    final p = await showDateRangePicker(
        context: c, firstDate: DateTime(2025), lastDate: DateTime(2028));
    if (p != null && mounted) setState(() => _per = p);
  }

  void _exportar(BuildContext c, List<Atend> r) {
    final a = widget.a;
    final csv = StringBuffer('Data;Cliente;Profissional;Serviço;Status;Valor\n');
    for (final x in r) {
      final valor = x.lancado ? (x.valorPago / 100).toStringAsFixed(2) : '';
      csv.writeln(
          '${formatarDataHora(x.quando)};${x.cliente.nome};${x.prof.nome};${x.servico};${x.status.rotulo};$valor');
    }
    Clipboard.setData(ClipboardData(text: csv.toString()));
    msg(c, 'Relatório copiado (CSV). Cole no Excel ou Planilhas.');
    dados.log('Relatório exportado (${r.length} registros)', a);
  }

  @override
  Widget build(BuildContext context) => Obs((c) {
        final a = widget.a;
        final r = dados
            .doArea(a)
            .where((x) => x.status == StatusAtend.concluido || x.status == StatusAtend.ausente)
            .where((x) =>
                (_prof == null || x.prof == _prof) &&
                (_serv == null || x.servico == _serv) &&
                (_per == null ||
                    (!x.quando.isBefore(_per!.start) &&
                        x.quando.isBefore(_per!.end.add(const Duration(days: 1))))))
            .toList();
        final conc = r.where((x) => x.status == StatusAtend.concluido).length;
        final falt = r.where((x) => x.status == StatusAtend.ausente).length;
        final valor = r.fold(0, (s, x) => s + x.valorPago);
        final taxa = r.isEmpty ? 0.0 : falt * 100 / r.length;
        final profs = {for (final x in r) x.prof}.toList();
        final todosProfs = {for (final x in dados.doArea(a)) x.prof}.toList();

        return Pagina(
          titulo: 'Indicadores e relatórios – ${a.nome}',
          sub: 'Filtre por profissional, tipo de serviço e período para ver atendimentos, faltas e valor arrecadado.',
          acoes: [
            OutlinedButton.icon(
              onPressed: r.isEmpty ? null : () => _exportar(c, r),
              icon: const Icon(Icons.download),
              label: const Text('Exportar CSV'),
            ),
          ],
          filhos: [
            Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                      width: 240,
                      child: seletor<Usuario?>('Profissional', _prof, [null, ...todosProfs],
                          (v) => setState(() => _prof = v), (u) => u?.nome ?? 'Todos')),
                  SizedBox(
                      width: 240,
                      child: seletor<String?>('Tipo de serviço', _serv, [null, ...servicosDe(a)],
                          (v) => setState(() => _serv = v), (s) => s ?? 'Todos')),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.date_range),
                    label: Text(_per == null
                        ? 'Período'
                        : '${formatarData(_per!.start)} – ${formatarData(_per!.end)}'),
                    onPressed: () => _escolherPeriodo(c),
                  ),
                  TextButton(
                      onPressed: () => setState(() {
                            _prof = null;
                            _serv = null;
                            _per = null;
                          }),
                      child: const Text('Limpar filtros')),
                ]),
            const SizedBox(height: 20),
            if (r.isEmpty)
              const Card(
                  child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Sem resultados para os filtros selecionados.'))))
            else ...[
              Wrap(spacing: 16, runSpacing: 16, children: [
                kpi(Icons.event_available, 'Atendimentos concluídos', '$conc', Colors.green),
                kpi(Icons.event_busy, 'Faltas', '$falt', Colors.red),
                kpi(Icons.percent, 'Taxa de faltas', '${taxa.toStringAsFixed(0)}%', Colors.orange),
                kpi(Icons.payments, 'Valor arrecadado', formatarReais(valor), Colors.indigo),
              ]),
              const SizedBox(height: 24),
              Text('Por profissional', style: Theme.of(c).textTheme.titleMedium),
              const SizedBox(height: 8),
              tabela(
                ['Profissional', 'Concluídos', 'Faltas', 'Valor arrecadado'],
                [
                  for (final p in profs)
                    [
                      Text(p.nome),
                      Text('${r.where((x) => x.prof == p && x.status == StatusAtend.concluido).length}'),
                      Text('${r.where((x) => x.prof == p && x.status == StatusAtend.ausente).length}'),
                      Text(formatarReais(r
                          .where((x) => x.prof == p)
                          .fold(0, (s, x) => s + x.valorPago))),
                    ]
                ],
              ),
            ],
          ],
        );
      });
}

// ───── admin/paginas/lembretes.dart ─────
class PaginaLembretes extends StatelessWidget {
  const PaginaLembretes(this.a, {super.key});

  final Area a;

  void _verificar(BuildContext c) {
    var n = 0;
    for (final x in dados.doArea(a)) {
      if (x.aberto &&
          x.lembrete == StatusLembrete.enviado &&
          x.quando.difference(DateTime.now()).inHours < 24) {
        x.lembrete = StatusLembrete.semResposta;
        n++;
        dados.log(
            'Alerta ao atendente ${x.prof.nome}: ${x.cliente.nome} não confirmou o lembrete (#${x.id})',
            a);
      }
    }
    msg(c, n == 0 ? 'Todos os lembretes estão dentro do prazo.' : '$n alerta(s) enviado(s) ao atendente responsável.');
    dados.atualizar();
  }

  void _enviar(Atend x) {
    // TODO: disparar mensagem pela API do WhatsApp
    x.lembrete = StatusLembrete.enviado;
    dados.log('Lembrete enviado por WhatsApp para ${x.cliente.nome} (#${x.id})', a);
  }

  void _confirmar(Atend x) {
    x.lembrete = StatusLembrete.confirmado;
    x.status = StatusAtend.confirmado;
    dados.log('Confirmação recebida de ${x.cliente.nome} (#${x.id})', a);
  }

  @override
  Widget build(BuildContext context) => Obs((c) {
        final l = dados.doArea(a).where((x) => x.aberto).toList()
          ..sort((x, y) => x.quando.compareTo(y.quando));
        return Pagina(
          titulo: 'Lembretes WhatsApp – ${a.nome}',
          sub: 'Lembrete automático dos próximos agendamentos. Sem confirmação no prazo, o atendente responsável é alertado. (Envio real pelo WhatsApp depende de integração com a API.)',
          acoes: [
            FilledButton.icon(
                onPressed: () => _verificar(c),
                icon: const Icon(Icons.notification_important),
                label: const Text('Verificar confirmações')),
          ],
          filhos: [
            tabela(
              ['Nº', 'Data/hora', 'Cliente', 'WhatsApp', 'Atendente', 'Lembrete', 'Ações'],
              [
                for (final x in l)
                  [
                    Text('#${x.id}'),
                    Text(formatarDataHora(x.quando)),
                    Text(x.cliente.nome),
                    Text(x.cliente.contato),
                    Text(x.prof.nome),
                    chipRotulo(x.lembrete.rotulo, x.lembrete.cor),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      TextButton(
                        onPressed: x.lembrete == StatusLembrete.naoEnviado ? () => _enviar(x) : null,
                        child: const Text('Enviar'),
                      ),
                      TextButton(
                        onPressed: x.lembrete == StatusLembrete.enviado ||
                                x.lembrete == StatusLembrete.semResposta
                            ? () => _confirmar(x)
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

// ───── admin/paginas/triagem.dart ─────
class PaginaTriagem extends StatelessWidget {
  const PaginaTriagem({super.key});

  @override
  Widget build(BuildContext context) => Obs((c) {
        final alt = dados.logs.where((e) => e.contains('Triagem alterada')).take(5).toList();
        return Pagina(
          titulo: 'Triagem – Psicologia',
          sub: 'A fila é organizada automaticamente pelo sistema. Só o administrador pode alterar a ordem (arraste); o atendente não escolhe o paciente. Toda alteração é registrada em log.',
          filhos: [
            Card(
              child: ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                // onReorderItem já entrega newIndex ajustado (não precisa de "newIndex--").
                onReorderItem: (oldIndex, newIndex) {
                  final item = dados.triagem.removeAt(oldIndex);
                  dados.triagem.insert(newIndex, item);
                  dados.log(
                    'Triagem alterada: "$item" da posição ${oldIndex + 1} para ${newIndex + 1}',
                    Area.psicologia,
                  );
                },
                children: [
                  for (var i = 0; i < dados.triagem.length; i++)
                    ListTile(
                      key: ValueKey(dados.triagem[i]),
                      leading: CircleAvatar(
                        backgroundColor: Area.psicologia.cor,
                        child: Text('${i + 1}', style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(dados.triagem[i]),
                      trailing: const Icon(Icons.drag_handle),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Últimas alterações manuais', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (alt.isEmpty)
              const Text('Nenhuma alteração manual registrada.')
            else
              for (final e in alt) Text('• $e'),
          ],
        );
      });
}

// ───── admin/paginas/usuarios.dart ─────
Future<void> abrirFormUsuario(BuildContext c, Area area, [Usuario? u]) =>
    showDialog(context: c, builder: (_) => _FormUsuarioDialog(area: area, usuario: u));

/// Criar/editar usuário. Os controllers vivem (e morrem) junto com o diálogo.
class _FormUsuarioDialog extends StatefulWidget {
  const _FormUsuarioDialog({required this.area, this.usuario});

  final Area area;
  final Usuario? usuario;

  @override
  State<_FormUsuarioDialog> createState() => _FormUsuarioDialogState();
}

class _FormUsuarioDialogState extends State<_FormUsuarioDialog> {
  late final TextEditingController _nome;
  late final TextEditingController _contato;
  late Perfil _perfil;
  String? _erro;

  @override
  void initState() {
    super.initState();
    final u = widget.usuario;
    _nome = TextEditingController(text: u?.nome);
    _contato = TextEditingController(text: u?.contato);
    _perfil = u?.perfil ?? Perfil.cliente;
  }

  @override
  void dispose() {
    _nome.dispose();
    _contato.dispose();
    super.dispose();
  }

  void _salvar() {
    final n = _nome.text.trim(), t = _contato.text.trim();
    if (n.length < 3 || t.length < 5) {
      setState(() => _erro = 'Dados inválidos: informe nome e contato. Nada foi salvo.');
      return;
    }
    final u = widget.usuario;
    if (dados.usuarios.any((x) => x != u && x.contato.toLowerCase() == t.toLowerCase())) {
      setState(() => _erro = 'Dados duplicados: já existe um usuário com este contato.');
      return;
    }
    if (u == null) {
      dados.usuarios.add(Usuario(n, _perfil, t, widget.area));
      dados.log('Usuário criado: $n (${_perfil.name}, $t)', widget.area);
    } else {
      final antigo = u.nome;
      u.nome = n;
      u.perfil = _perfil;
      u.contato = t;
      dados.log('Usuário editado: $antigo → $n (${_perfil.name}, $t)', widget.area);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.usuario == null ? 'Novo usuário' : 'Editar usuário'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _nome, decoration: decoracaoCampo('Nome completo')),
          const SizedBox(height: 12),
          seletor<Perfil>('Perfil', _perfil, Perfil.values,
              (v) => setState(() => _perfil = v!), (p) => p.name),
          const SizedBox(height: 12),
          TextField(
              controller: _contato,
              decoration: decoracaoCampo('Contato (e-mail ou WhatsApp)')),
          if (_erro != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_erro!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
      ],
    );
  }
}

class PaginaUsuarios extends StatefulWidget {
  const PaginaUsuarios(this.a, {super.key});

  final Area a;

  @override
  State<PaginaUsuarios> createState() => _PaginaUsuariosState();
}

class _PaginaUsuariosState extends State<PaginaUsuarios> {
  String _busca = '';
  Perfil? _perfil; // null = todos

  Future<void> _alternar(Usuario u) async {
    if (u.ativo) {
      final f = dados.futuros(u);
      final ok = await confirmar(
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
  Widget build(BuildContext context) => Obs((c) {
        final l = dados.usuarios
            .where((u) =>
                u.area == widget.a &&
                (_perfil == null || u.perfil == _perfil) &&
                u.nome.toLowerCase().contains(_busca.toLowerCase()))
            .toList();
        return Pagina(
          titulo: 'Usuários – ${widget.a.nome}',
          sub: 'Cadastrar, editar e desativar usuários (atendente, auxiliar ou cliente). Toda ação gera log de auditoria.',
          acoes: [
            FilledButton.icon(
                onPressed: () => abrirFormUsuario(c, widget.a),
                icon: const Icon(Icons.person_add),
                label: const Text('Novo usuário')),
          ],
          filhos: [
            Wrap(spacing: 16, runSpacing: 12, children: [
              SizedBox(
                  width: 280,
                  child: TextField(
                      decoration: decoracaoCampo('Buscar por nome', icone: Icons.search),
                      onChanged: (v) => setState(() => _busca = v))),
              SizedBox(
                  width: 220,
                  child: seletor<Perfil?>(
                      'Perfil',
                      _perfil,
                      [null, ...Perfil.values],
                      (v) => setState(() => _perfil = v),
                      (p) => p?.name ?? 'Todos')),
            ]),
            const SizedBox(height: 12),
            tabela(
              ['Nome', 'Perfil', 'Contato', 'Faltas', 'Atend. futuros', 'Situação', 'Ações'],
              [
                for (final u in l)
                  [
                    Text(u.nome),
                    chipRotulo(u.perfil.name, Colors.indigo),
                    Text(u.contato),
                    Text(u.perfil == Perfil.cliente ? '${dados.faltas(u)}' : '—'),
                    Text('${dados.futuros(u)}'),
                    chipRotulo(u.ativo ? 'Ativo' : 'Desativado',
                        u.ativo ? Colors.green : Colors.grey,
                        icone: u.ativo ? Icons.check_circle_outline : Icons.block),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          tooltip: 'Editar',
                          icon: const Icon(Icons.edit),
                          onPressed: () => abrirFormUsuario(c, u.area, u)),
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

// ───── admin/paginas/visao_geral.dart ─────
class VisaoGeral extends StatelessWidget {
  const VisaoGeral(this.a, {super.key});

  final Area a;

  @override
  Widget build(BuildContext context) => Obs((c) {
        final agora = DateTime.now();
        final l = dados.doArea(a);
        final hoje = l
            .where((x) => mesmoDia(x.quando, agora) && x.status != StatusAtend.cancelado)
            .length;
        final futuros = l.where((x) => x.aberto && x.quando.isAfter(agora)).length;
        final faltas = l.where((x) => x.status == StatusAtend.ausente).length;
        final ativos = dados.usuarios.where((u) => u.area == a && u.ativo).length;
        final fechado = dados.caixaFechado(a, DateTime.now());
        final alertas = <String>[
          for (final u in dados.clientes(a))
            if (dados.faltas(u) >= 3 && !dados.liberados.contains(u.id))
              '${u.nome} atingiu 3 faltas: novo agendamento bloqueado ou dependente da sua aprovação.',
          if (l.any((x) => x.aberto && x.quando.isBefore(agora)))
            'Há agendamentos vencidos sem check-in: processe as ausências na aba Faltas.',
          if (l.any((x) => x.lembrete == StatusLembrete.semResposta && x.aberto))
            'Há clientes que não confirmaram o lembrete no prazo.',
          if (dados.semVinculoDe(a).isNotEmpty)
            'Existe valor lançado sem vínculo a atendimento: impede o fechamento do caixa.',
          if (dados.pendentes(a).isNotEmpty)
            '${dados.pendentes(a).length} atendimento(s) concluído(s) aguardando lançamento no caixa.',
          if (!fechado) 'O caixa de hoje ainda está aberto.',
        ];
        return Pagina(
          titulo: 'Visão geral – ${a.nome}',
          sub: 'Resumo de tudo o que acontece na área. O administrador tem acesso e controle sobre todos os módulos.',
          filhos: [
            Wrap(spacing: 16, runSpacing: 16, children: [
              kpi(Icons.today, 'Atendimentos hoje', '$hoje', a.cor),
              kpi(Icons.event, 'Agendamentos futuros', '$futuros', Colors.blue),
              kpi(Icons.event_busy, 'Faltas registradas', '$faltas', Colors.red),
              kpi(Icons.payments, 'Caixa de hoje', formatarReais(dados.totalDia(a)), Colors.green),
              kpi(Icons.people, 'Usuários ativos', '$ativos', Colors.indigo),
            ]),
            const SizedBox(height: 24),
            Text('Alertas e pendências', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (alertas.isEmpty)
              const Text('Nenhuma pendência.')
            else
              for (final t in alertas)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber, color: Colors.orange),
                    title: Text(t),
                  ),
                ),
          ],
        );
      });
}

// ───── admin/admin_login_page.dart ─────
class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  static const _maxTentativas = 5;
  static const _bloqueio = Duration(seconds: 30);

  final _u = TextEditingController();
  final _s = TextEditingController();
  String? _erro;
  int _tentativas = 0;
  DateTime? _bloqueadoAte;

  @override
  void dispose() {
    _u.dispose();
    _s.dispose();
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

    if (_u.text.trim().toLowerCase() == admLogin && _s.text == admSenha) {
      _tentativas = 0;
      dados.log('Login do administrador');
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const AdminHome()));
      return;
    }

    dados.log('Acesso administrativo negado: usuário ou senha inválidos');
    _tentativas++;
    if (_tentativas >= _maxTentativas) {
      _tentativas = 0;
      _bloqueadoAte = agora.add(_bloqueio);
      setState(() => _erro =
          'Muitas tentativas. Aguarde ${_bloqueio.inSeconds}s para tentar de novo.');
    } else {
      setState(() => _erro = 'Usuário ou senha inválidos');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FundoSuave(
      cores: [Area.estetica.corClara, Area.psicologia.corClara],
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: barra(acoes: [
        TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Voltar')),
      ]),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(ehCelular(context) ? 16 : 24),
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
                    const Icon(Icons.admin_panel_settings, size: 56, color: navy),
                    const SizedBox(height: 12),
                    const Text('Acesso do administrador',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _u,
                      textInputAction: TextInputAction.next,
                      decoration: decoracaoCampo('Usuário', icone: Icons.person_outline),
                    ),
                    const SizedBox(height: 16),
                    CampoSenha(controller: _s, onSubmitted: (_) => _entrar()),
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

// ───── admin/admin_home.dart ─────
/// Escolha da área a administrar.
class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return FundoSuave(
      cores: [Area.estetica.corClara, Area.psicologia.corClara],
      child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: barra(acoes: [botaoSair(context)]),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(ehCelular(context) ? 16 : 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Painel do administrador',
                style: (ehCelular(context)
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.headlineSmall)
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Acesso total. Escolha a área que deseja administrar.'),
            const SizedBox(height: 32),
            Wrap(
              spacing: ehCelular(context) ? 16 : 32,
              runSpacing: ehCelular(context) ? 16 : 24,
              alignment: WrapAlignment.center,
              children: [for (final a in Area.values) _CardArea(a)],
            ),
          ]),
        ),
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
    final cel = ehCelular(context);
    return Card(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => AdminPanel(area: area))),
        child: Padding(
          padding: EdgeInsets.all(cel ? 16 : 32),
          child: SizedBox(
            width: cel ? 108 : 160,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                  radius: cel ? 32 : 44,
                  backgroundColor: area.cor,
                  child: Icon(area.icone, size: cel ? 34 : 48, color: Colors.white)),
              const SizedBox(height: 16),
              Text(area.nome,
                  style: TextStyle(
                      fontSize: cel ? 17 : 20, fontWeight: FontWeight.w600, color: area.cor)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ───── admin/admin_panel.dart ─────
class SecaoPainel {
  const SecaoPainel(this.icone, this.nome, this.pagina);

  final IconData icone;
  final String nome;
  final Widget pagina;
}

/// Layout comum dos painéis (administrador e auxiliar): logo no topo, menu lateral
/// (gaveta em telas estreitas) e as cores da área (rosa na Estética, azul na Psicologia).
class PainelComMenu extends StatefulWidget {
  const PainelComMenu({
    super.key,
    required this.area,
    required this.titulo,
    required this.secoes,
    required this.sair,
    this.podeTrocarArea = true,
  });

  final Area area;
  final String titulo;
  final List<SecaoPainel> secoes;
  final Widget Function(BuildContext) sair;
  final bool podeTrocarArea;

  @override
  State<PainelComMenu> createState() => _PainelComMenuState();
}

class _PainelComMenuState extends State<PainelComMenu> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    final a = widget.area;
    final s = widget.secoes;
    final largo = MediaQuery.of(context).size.width >= 900;
    if (_i >= s.length) _i = 0;
    // Menu com o mesmo rosa/azul claro da tela de login; item selecionado na cor escura da área.
    final fundoMenu = a.corClara;

    Widget menu() => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (var k = 0; k < s.length; k++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: ListTile(
                  selected: k == _i,
                  selectedColor: Colors.white,
                  selectedTileColor: a.cor,
                  hoverColor: a.cor.withAlpha(30),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  leading: Icon(s[k].icone),
                  title: Text(s[k].nome,
                      style: TextStyle(fontWeight: k == _i ? FontWeight.bold : FontWeight.normal)),
                  onTap: () {
                    setState(() => _i = k);
                    if (!largo) Navigator.pop(context);
                  },
                ),
              ),
          ],
        );

    final cel = ehCelular(context);
    final Widget? trocar = !widget.podeTrocarArea
        ? null
        : cel
            ? IconButton(
                tooltip: 'Trocar área',
                icon: const Icon(Icons.swap_horiz),
                onPressed: () => Navigator.pop(context))
            : TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Trocar área'));

    return Theme(
      data: criarTema(a.cor),
      child: FundoSuave(
        cores: [a.corClara, Colors.white],
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: barra(acoes: [
            if (!largo)
              Builder(
                  builder: (c) => IconButton(
                      tooltip: 'Menu',
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(c).openDrawer())),
            if (largo)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(widget.titulo,
                    style: TextStyle(color: a.cor, fontWeight: FontWeight.bold)),
              ),
            if (trocar != null) trocar,
            widget.sair(context),
          ]),
          drawer: largo ? null : Drawer(backgroundColor: fundoMenu, child: SafeArea(child: menu())),
          body: Row(children: [
            if (largo)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 0, 12),
                child: SizedBox(
                  width: 250,
                  child: Material(
                    color: fundoMenu,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: a.cor.withAlpha(50)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: menu(),
                  ),
                ),
              ),
            Expanded(child: s[_i].pagina),
          ]),
        ),
      ),
    );
  }
}

/// Painel do administrador de uma área.
class AdminPanel extends StatelessWidget {
  const AdminPanel({super.key, required this.area});

  final Area area;

  @override
  Widget build(BuildContext context) {
    final a = area;
    return PainelComMenu(
      area: a,
      titulo: 'Administração de ${a.nome}',
      sair: botaoSair,
      secoes: [
        SecaoPainel(Icons.dashboard, 'Visão geral', VisaoGeral(a)),
        SecaoPainel(Icons.people, 'Usuários', PaginaUsuarios(a)),
        SecaoPainel(Icons.calendar_month, 'Agenda', PaginaAgenda(a)),
        SecaoPainel(Icons.assignment_ind, 'Atendimentos', PaginaAtendimentos(a)),
        SecaoPainel(Icons.event_busy, 'Faltas', PaginaFaltas(a)),
        SecaoPainel(Icons.notifications_active, 'Lembretes WhatsApp', PaginaLembretes(a)),
        SecaoPainel(Icons.point_of_sale, 'Caixa', PaginaCaixa(a)),
        if (a == Area.psicologia)
          const SecaoPainel(Icons.low_priority, 'Triagem', PaginaTriagem()),
        SecaoPainel(Icons.bar_chart, 'Indicadores e relatórios', PaginaIndicadores(a)),
        const SecaoPainel(Icons.shield, 'Controle de acesso', PaginaAcesso()),
        SecaoPainel(Icons.history, 'Auditoria', PaginaAuditoria(a)),
      ],
    );
  }
}