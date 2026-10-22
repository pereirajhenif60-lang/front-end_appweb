import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'admin.dart';
import 'main.dart';

// ───── caixa/modelos.dart ─────
/// Formas de pagamento aceitas. Dinheiro NÃO é aceito.
enum FormaPagamento {
  pix('Pix', Icons.pix),
  debito('Cartão de débito', Icons.credit_card),
  credito('Cartão de crédito', Icons.credit_score);

  const FormaPagamento(this.rotulo, this.icone);
  final String rotulo;
  final IconData icone;
}

enum OrigemLancamento {
  manual('Manual'),
  maquininha('Maquininha');

  const OrigemLancamento(this.rotulo);
  final String rotulo;
}

const bandeiras = ['Visa', 'Mastercard', 'Elo', 'Hipercard', 'American Express', 'Outra'];

/// Entrada no caixa. Valores em centavos.
class Lancamento {
  Lancamento({
    required this.id,
    required this.area,
    required this.data,
    required this.valorCentavos,
    required this.forma,
    required this.origem,
    required this.operador,
    this.atend,
    this.parcelas = 1,
    this.bandeira,
    this.autorizacao,
    this.terminal,
    this.observacao,
  });

  final int id;
  final Area area;
  final DateTime data;
  final OrigemLancamento origem;
  final String operador;
  int valorCentavos;
  FormaPagamento forma;

  /// null = lançamento sem vínculo (impede o fechamento do caixa do dia).
  Atend? atend;
  int parcelas;
  String? bandeira, autorizacao, terminal, observacao;

  bool estornado = false;
  String? motivoEstorno;

  /// Histórico de alterações (mais recente primeiro).
  final historico = <String>[];

  bool get ativo => !estornado;
  bool get semVinculo => ativo && atend == null;

  void registrar(String texto) =>
      historico.insert(0, '${formatarDataHora(DateTime.now())} • $texto');
}

/// Comprovante de pagamento anexado no fechamento do caixa.
class Comprovante {
  Comprovante(this.nome, this.tamanho, this.bytes);

  final String nome;
  final int tamanho;

  /// Conteúdo do arquivo (para enviar ao backend depois).
  final Uint8List? bytes;
}

String formatarTamanho(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Fechamento detalhado do caixa de um dia.
class Fechamento {
  Fechamento({
    required this.area,
    required this.dia,
    required this.fechadoEm,
    required this.responsavel,
    required this.qtd,
    required this.totais,
    required this.conferidos,
    required this.estornosQtd,
    required this.estornosValor,
    this.pendentesIgnorados = 0,
    this.observacao,
    this.comprovantes = const [],
  });

  final Area area;
  final DateTime dia, fechadoEm;
  final String responsavel;
  final int qtd, estornosQtd, estornosValor, pendentesIgnorados;

  /// Lançado por forma de pagamento.
  final Map<FormaPagamento, int> totais;

  /// Valor conferido por forma (extrato do Pix, relatório das maquininhas). null = não informado.
  final Map<FormaPagamento, int?> conferidos;
  final String? observacao;

  /// Comprovantes de pagamento anexados no fechamento.
  final List<Comprovante> comprovantes;

  bool reaberto = false;
  DateTime? reabertoEm;
  String? motivoReabertura;

  int get total => totais.values.fold(0, (s, v) => s + v);

  int get divergencia => FormaPagamento.values.fold(0, (s, f) {
        final c = conferidos[f];
        return c == null ? s : s + (c - (totais[f] ?? 0));
      });
}

// ───── caixa/utilidades.dart ─────
String _descAtend(Atend x) => '#${x.id} • ${x.cliente.nome} • ${x.servico}';

String _fmtValor(int v) => '${v ~/ 100},${doisDigitos(v % 100)}';

String _valorTabela(Atend x) {
  final v = valorDoProcedimento(x.area, x.servico);
  return v == null ? '' : _fmtValor(v);
}

String _rotuloForma(Lancamento l) => l.forma == FormaPagamento.credito && l.parcelas > 1
    ? '${l.forma.rotulo} ${l.parcelas}x'
    : l.forma.rotulo;

String _sinal(int v) => v == 0 ? 'R\$ 0,00' : '${v > 0 ? '+' : '-'}${formatarReais(v.abs())}';

Color _corDif(int v) => v == 0 ? Colors.green : Colors.red;

/// Concluídos sem lançamento. Para hoje mostra todos os pendentes; para dias passados, só os do dia.
List<Atend> pendentesDoDia(Area a, DateTime dia) => dados
    .pendentes(a)
    .where((x) => mesmoDia(dia, DateTime.now()) || mesmoDia(x.quando, dia))
    .toList();

Future<String?> _pedirMotivo(BuildContext c, String titulo, String texto, String rotulo) {
  final ctrl = TextEditingController();
  String? erro;
  return showDialog<String>(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(titulo),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(texto),
            const SizedBox(height: 12),
            TextField(
                controller: ctrl, maxLines: 2, decoration: decoracaoCampo('Motivo (obrigatório)')),
            if (erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(erro!, style: TextStyle(color: Theme.of(d).colorScheme.error)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final m = ctrl.text.trim();
              if (m.length < 5) {
                set(() => erro = 'Explique o motivo (mínimo de 5 caracteres).');
                return;
              }
              Navigator.pop(d, m);
            },
            child: Text(rotulo),
          ),
        ],
      ),
    ),
  );
}

Widget _erroTexto(BuildContext c, String? erro) => erro == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(erro, style: TextStyle(color: Theme.of(c).colorScheme.error)),
      );

// ───── caixa/lancar_valor.dart ─────
/// Lançar valor recebido sobre um atendimento concluído.
class _LancarValorDialog extends StatefulWidget {
  const _LancarValorDialog(
      {required this.area, required this.pendentes, this.inicial, this.autor = admLogin});

  final Area area;
  final List<Atend> pendentes;
  final Atend? inicial;
  final String autor;

  @override
  State<_LancarValorDialog> createState() => _LancarValorDialogState();
}

class _LancarValorDialogState extends State<_LancarValorDialog> {
  final _valor = TextEditingController();
  final _obs = TextEditingController();
  late Atend _sel = widget.inicial ?? widget.pendentes.first;
  FormaPagamento _forma = FormaPagamento.pix;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _valor.text = _valorTabela(_sel);
  }

  @override
  void dispose() {
    _valor.dispose();
    _obs.dispose();
    super.dispose();
  }

  void _lancar() {
    final v = parseCentavos(_valor.text);
    if (v == null || v <= 0) {
      setState(() => _erro = 'Informe um valor válido.');
      return;
    }
    final obs = _obs.text.trim();
    final l = Lancamento(
      id: dados.proximoId(),
      area: widget.area,
      data: DateTime.now(),
      valorCentavos: v,
      forma: _forma,
      origem: OrigemLancamento.manual,
      operador: widget.autor,
      atend: _sel,
      observacao: obs.isEmpty ? null : obs,
    )..registrar('Lançado manualmente (${formatarReais(v)}, ${_forma.rotulo})');
    dados.lancamentos.add(l);
    dados.log(
        'Valor lançado: ${formatarReais(v)} (${_forma.rotulo}) • atendimento #${_sel.id}',
        widget.area,
        widget.autor);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Lançar valor no caixa'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            seletor<Atend>('Atendimento concluído', _sel, widget.pendentes,
                (v) => setState(() {
                      _sel = v!;
                      _valor.text = _valorTabela(v);
                    }), _descAtend),
            const SizedBox(height: 12),
            TextField(
              controller: _valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: decoracaoCampo('Valor recebido (R\$)'),
            ),
            const SizedBox(height: 12),
            seletor<FormaPagamento>('Forma de pagamento', _forma, FormaPagamento.values,
                (v) => setState(() => _forma = v!), (f) => f.rotulo),
            const SizedBox(height: 12),
            TextField(controller: _obs, decoration: decoracaoCampo('Observação (opcional)')),
            _erroTexto(context, _erro),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _lancar, child: const Text('Lançar')),
      ],
    );
  }
}

// ───── caixa/venda_maquininha.dart ─────
/// Venda feita na maquininha de cartão (lançamento manual por enquanto).
class _VendaMaquininhaDialog extends StatefulWidget {
  const _VendaMaquininhaDialog(
      {required this.area, required this.pendentes, this.autor = admLogin});

  final Area area;
  final List<Atend> pendentes;
  final String autor;

  @override
  State<_VendaMaquininhaDialog> createState() => _VendaMaquininhaDialogState();
}

class _VendaMaquininhaDialogState extends State<_VendaMaquininhaDialog> {
  final _valor = TextEditingController();
  final _aut = TextEditingController();
  final _terminal = TextEditingController();
  final _obs = TextEditingController();
  FormaPagamento _forma = FormaPagamento.debito;
  int _parcelas = 1;
  String _bandeira = bandeiras.first;
  Atend? _atend;
  String? _erro;

  @override
  void dispose() {
    _valor.dispose();
    _aut.dispose();
    _terminal.dispose();
    _obs.dispose();
    super.dispose();
  }

  void _salvar() {
    final v = parseCentavos(_valor.text);
    final aut = _aut.text.trim();
    if (v == null || v <= 0) {
      setState(() => _erro = 'Informe um valor válido.');
      return;
    }
    if (aut.length < 4) {
      setState(() => _erro = 'Informe o código de autorização/NSU do comprovante (mínimo 4 caracteres).');
      return;
    }
    final hoje = DateTime.now();
    if (dados.lancamentos.any((l) =>
        l.area == widget.area &&
        l.autorizacao?.toLowerCase() == aut.toLowerCase() &&
        mesmoDia(l.data, hoje))) {
      setState(() => _erro = 'Já existe um lançamento com esta autorização hoje.');
      return;
    }
    final terminal = _terminal.text.trim();
    final obs = _obs.text.trim();
    final l = Lancamento(
      id: dados.proximoId(),
      area: widget.area,
      data: hoje,
      valorCentavos: v,
      forma: _forma,
      origem: OrigemLancamento.maquininha,
      operador: widget.autor,
      atend: _atend,
      parcelas: _forma == FormaPagamento.credito ? _parcelas : 1,
      bandeira: _bandeira,
      autorizacao: aut,
      terminal: terminal.isEmpty ? null : terminal,
      observacao: obs.isEmpty ? null : obs,
    )..registrar(
        'Venda da maquininha lançada (${formatarReais(v)}, ${_forma.rotulo})'
        '${_atend == null ? ', sem vínculo' : ', vinculada ao atendimento #${_atend!.id}'}');
    dados.lancamentos.add(l);
    dados.log(
        'Venda da maquininha: ${formatarReais(v)} (${_rotuloForma(l)}, $_bandeira)'
        '${_atend == null ? ' • SEM VÍNCULO' : ' • atendimento #${_atend!.id}'}',
        widget.area,
        widget.autor);
    Navigator.pop(context, l);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Venda na maquininha'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withAlpha(90),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Por enquanto o lançamento é manual, a partir do comprovante. No futuro, '
                    'a maquininha vinculada enviará as vendas automaticamente para cá.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: decoracaoCampo('Valor da venda (R\$)'),
            ),
            const SizedBox(height: 12),
            seletor<FormaPagamento>(
                'Tipo',
                _forma,
                const [FormaPagamento.debito, FormaPagamento.credito],
                (v) => setState(() {
                      _forma = v!;
                      if (_forma != FormaPagamento.credito) _parcelas = 1;
                    }),
                (f) => f.rotulo),
            if (_forma == FormaPagamento.credito) ...[
              const SizedBox(height: 12),
              seletor<int>('Parcelas', _parcelas, [for (var i = 1; i <= 12; i++) i],
                  (v) => setState(() => _parcelas = v!),
                  (n) => n == 1 ? '1x (à vista)' : '${n}x'),
            ],
            const SizedBox(height: 12),
            seletor<String>('Bandeira', _bandeira, bandeiras, (v) => setState(() => _bandeira = v!)),
            const SizedBox(height: 12),
            TextField(controller: _aut, decoration: decoracaoCampo('Código de autorização / NSU')),
            const SizedBox(height: 12),
            TextField(
              controller: _terminal,
              decoration: decoracaoCampo('Maquininha / nº de série (opcional)',
                  ajuda: 'Será preenchido automaticamente quando houver integração'),
            ),
            const SizedBox(height: 12),
            seletor<Atend?>(
              'Vincular ao atendimento',
              _atend,
              <Atend?>[null, ...widget.pendentes],
              (v) => setState(() {
                _atend = v;
                if (v != null && _valor.text.trim().isEmpty) _valor.text = _valorTabela(v);
              }),
              (x) => x == null ? 'Sem vínculo (vincular depois)' : _descAtend(x),
            ),
            const SizedBox(height: 12),
            TextField(controller: _obs, decoration: decoracaoCampo('Observação (opcional)')),
            _erroTexto(context, _erro),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _salvar, child: const Text('Lançar venda')),
      ],
    );
  }
}

// ───── caixa/vincular.dart ─────
/// Corrige um lançamento sem vínculo: escolhe a pessoa e o atendimento.
class _VincularDialog extends StatefulWidget {
  const _VincularDialog(this.l, {this.autor = admLogin});

  final Lancamento l;
  final String autor;

  @override
  State<_VincularDialog> createState() => _VincularDialogState();
}

class _VincularDialogState extends State<_VincularDialog> {
  late final List<Atend> _cand;
  Usuario? _cliente;
  Atend? _atend;

  @override
  void initState() {
    super.initState();
    final l = widget.l;
    _cand = dados.atendimentos
        .where((x) =>
            x.area == l.area &&
            x.status == StatusAtend.concluido &&
            (!x.lancado || mesmoDia(x.quando, l.data)))
        .toList()
      ..sort((a, b) => (a.lancado ? 1 : 0).compareTo(b.lancado ? 1 : 0));
    // Sugestão: atendimento pendente cujo valor de tabela é igual ao do lançamento.
    for (final x in _cand) {
      if (!x.lancado && valorDoProcedimento(x.area, x.servico) == l.valorCentavos) {
        _cliente = x.cliente;
        _atend = x;
        break;
      }
    }
  }

  List<Atend> get _doCliente => _cand.where((x) => x.cliente == _cliente).toList();

  @override
  Widget build(BuildContext context) {
    final clientes = {for (final x in _cand) x.cliente}.toList();
    return AlertDialog(
      title: Text('Vincular ${formatarReais(widget.l.valorCentavos)}'),
      content: SizedBox(
        width: 420,
        child: _cand.isEmpty
            ? const Text('Não há atendimentos concluídos para vincular a este lançamento.')
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${_rotuloForma(widget.l)} • ${formatarDataHora(widget.l.data)}',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                seletor<Usuario>('Pessoa (cliente)', _cliente, clientes,
                    (v) => setState(() {
                          _cliente = v;
                          _atend = null;
                        }), (u) => u.nome),
                const SizedBox(height: 12),
                seletor<Atend>(
                    'Atendimento',
                    _atend,
                    _doCliente,
                    (v) => setState(() => _atend = v),
                    (x) => '#${x.id} • ${x.servico}${x.lancado ? ' (já tem lançamento)' : ''}'),
              ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _atend == null
              ? null
              : () {
                  final l = widget.l;
                  final x = _atend!;
                  l.atend = x;
                  l.registrar('Vinculado ao atendimento #${x.id} (${x.cliente.nome})');
                  dados.log(
                      'Lançamento #${l.id} (${formatarReais(l.valorCentavos)}) vinculado ao atendimento #${x.id}',
                      l.area,
                      widget.autor);
                  Navigator.pop(context);
                },
          child: const Text('Vincular'),
        ),
      ],
    );
  }
}

// ───── caixa/corrigir.dart ─────
class _CorrigirDialog extends StatefulWidget {
  const _CorrigirDialog(this.l);

  final Lancamento l;

  @override
  State<_CorrigirDialog> createState() => _CorrigirDialogState();
}

class _CorrigirDialogState extends State<_CorrigirDialog> {
  late final _valor = TextEditingController(text: _fmtValor(widget.l.valorCentavos));
  final _motivo = TextEditingController();
  late FormaPagamento _forma = widget.l.forma;
  String? _erro;

  List<FormaPagamento> get _formas => widget.l.origem == OrigemLancamento.maquininha
      ? const [FormaPagamento.debito, FormaPagamento.credito]
      : FormaPagamento.values;

  @override
  void dispose() {
    _valor.dispose();
    _motivo.dispose();
    super.dispose();
  }

  void _salvar() {
    final l = widget.l;
    final v = parseCentavos(_valor.text);
    final m = _motivo.text.trim();
    if (v == null || v <= 0) {
      setState(() => _erro = 'Informe um valor válido.');
      return;
    }
    if (v == l.valorCentavos && _forma == l.forma) {
      setState(() => _erro = 'Nenhuma alteração foi feita.');
      return;
    }
    if (m.length < 5) {
      setState(() => _erro = 'Explique o motivo da correção (mínimo de 5 caracteres).');
      return;
    }
    final antes = '${formatarReais(l.valorCentavos)} (${l.forma.rotulo})';
    l.valorCentavos = v;
    l.forma = _forma;
    if (_forma != FormaPagamento.credito) l.parcelas = 1;
    final depois = '${formatarReais(v)} (${_forma.rotulo})';
    l.registrar('Corrigido de $antes para $depois. Motivo: $m');
    dados.log('Lançamento #${l.id} corrigido de $antes para $depois. Motivo: $m', l.area);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Corrigir lançamento #${widget.l.id}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: decoracaoCampo('Valor (R\$)'),
            ),
            const SizedBox(height: 12),
            seletor<FormaPagamento>('Forma de pagamento', _forma, _formas,
                (v) => setState(() => _forma = v!), (f) => f.rotulo),
            const SizedBox(height: 12),
            TextField(
                controller: _motivo, maxLines: 2, decoration: decoracaoCampo('Motivo (obrigatório)')),
            _erroTexto(context, _erro),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _salvar, child: const Text('Salvar correção')),
      ],
    );
  }
}

// ───── caixa/detalhes.dart ─────
class _DetalhesDialog extends StatelessWidget {
  const _DetalhesDialog(this.l);

  final Lancamento l;

  Widget _linha(String t, String? v) => v == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$t: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: v),
          ])),
        );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Lançamento #${l.id}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _linha('Data/hora', formatarDataHora(l.data)),
            _linha('Valor', formatarReais(l.valorCentavos)),
            _linha('Forma', _rotuloForma(l)),
            _linha('Origem', l.origem.rotulo),
            _linha('Bandeira', l.bandeira),
            _linha('Autorização / NSU', l.autorizacao),
            _linha('Maquininha', l.terminal ?? (l.origem == OrigemLancamento.maquininha ? 'não vinculada' : null)),
            _linha('Atendimento', l.atend == null ? 'SEM VÍNCULO' : _descAtend(l.atend!)),
            _linha('Lançado por', l.operador),
            _linha('Observação', l.observacao),
            if (l.estornado) _linha('Estornado', l.motivoEstorno),
            const SizedBox(height: 8),
            const Text('Histórico', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            if (l.historico.isEmpty) const Text('Sem alterações.') else for (final h in l.historico) Text('• $h', style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    );
  }
}

// ───── caixa/fechar_caixa.dart ─────
class _FecharCaixaDialog extends StatefulWidget {
  const _FecharCaixaDialog({required this.area, required this.dia, this.autor = admLogin});

  final Area area;
  final DateTime dia;
  final String autor;

  @override
  State<_FecharCaixaDialog> createState() => _FecharCaixaDialogState();
}

class _FecharCaixaDialogState extends State<_FecharCaixaDialog> {
  late final List<Lancamento> _ativos;
  late final List<Lancamento> _estornos;
  late final List<Lancamento> _semVinc;
  late final List<Atend> _pend;
  final _conf = {for (final f in FormaPagamento.values) f: TextEditingController()};
  final _obs = TextEditingController();
  bool _ciente = false;
  String? _erro;

  static const _maxBytes = 5 * 1024 * 1024;
  final _anexos = <Comprovante>[];
  String? _erroAnexo;

  Future<void> _anexar() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      allowMultiple: true,
      withData: true,
    );
    if (r == null || !mounted) return;
    final recusados = <String>[];
    setState(() {
      for (final f in r.files) {
        if (f.size > _maxBytes) {
          recusados.add(f.name);
        } else {
          _anexos.add(Comprovante(f.name, f.size, f.bytes));
        }
      }
      _erroAnexo = recusados.isEmpty ? null : 'Não anexado (maior que 5 MB): ${recusados.join(', ')}';
    });
  }

  @override
  void initState() {
    super.initState();
    final todos = dados.lancamentosDoDia(widget.area, widget.dia);
    _ativos = todos.where((l) => l.ativo).toList();
    _estornos = todos.where((l) => l.estornado).toList();
    _semVinc = dados.semVinculoDe(widget.area, widget.dia);
    _pend = pendentesDoDia(widget.area, widget.dia);
  }

  @override
  void dispose() {
    for (final c in _conf.values) {
      c.dispose();
    }
    _obs.dispose();
    super.dispose();
  }

  int _total(FormaPagamento f) =>
      _ativos.where((l) => l.forma == f).fold(0, (s, l) => s + l.valorCentavos);

  int? _conferido(FormaPagamento f) {
    final t = _conf[f]!.text.trim();
    return t.isEmpty ? null : parseCentavos(t);
  }

  int get _divergencia => FormaPagamento.values.fold(0, (s, f) {
        final c = _conferido(f);
        return c == null ? s : s + (c - _total(f));
      });

  void _fechar() {
    for (final f in FormaPagamento.values) {
      final t = _conf[f]!.text.trim();
      if (t.isNotEmpty && parseCentavos(t) == null) {
        setState(() => _erro = 'Valor conferido de ${f.rotulo} inválido.');
        return;
      }
      if (t.isEmpty && _total(f) > 0) {
        setState(() => _erro = 'Informe o valor conferido de ${f.rotulo}.');
        return;
      }
    }
    if (_pend.isNotEmpty && !_ciente) {
      setState(() => _erro = 'Confirme que os atendimentos sem lançamento não tiveram cobrança.');
      return;
    }
    final obs = _obs.text.trim();
    if ((_divergencia != 0 || _pend.isNotEmpty) && obs.length < 5) {
      setState(() => _erro = 'Explique a divergência ou as pendências na observação.');
      return;
    }
    final f = Fechamento(
      area: widget.area,
      dia: DateUtils.dateOnly(widget.dia),
      fechadoEm: DateTime.now(),
      responsavel: widget.autor,
      qtd: _ativos.length,
      totais: {for (final x in FormaPagamento.values) x: _total(x)},
      conferidos: {for (final x in FormaPagamento.values) x: _conferido(x)},
      estornosQtd: _estornos.length,
      estornosValor: _estornos.fold(0, (s, l) => s + l.valorCentavos),
      pendentesIgnorados: _pend.length,
      observacao: obs.isEmpty ? null : obs,
      comprovantes: List<Comprovante>.of(_anexos),
    );
    dados.fechamentos.add(f);
    dados.log(
        'Caixa de ${formatarData(f.dia)} fechado: total ${formatarReais(f.total)}, '
        '${f.qtd} lançamento(s), divergência ${_sinal(f.divergencia)}'
        '${_anexos.isEmpty ? '' : ', ${_anexos.length} comprovante(s) anexado(s)'}',
        widget.area,
        widget.autor);
    Navigator.pop(context, true);
  }

  Widget _verif(IconData i, Color cor, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 18, color: cor),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 13))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final lancado = _ativos.fold(0, (s, l) => s + l.valorCentavos);
    final dif = _divergencia;
    final bloqueado = _semVinc.isNotEmpty;
    final valorPend = _pend.fold(0, (s, x) => s + (valorDoProcedimento(x.area, x.servico) ?? 0));

    return AlertDialog(
      title: Text('Fechar caixa • ${formatarData(widget.dia)}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Verificações', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            bloqueado
                ? _verif(Icons.block, Colors.red,
                    '${_semVinc.length} lançamento(s) sem vínculo (${formatarReais(_semVinc.fold(0, (s, l) => s + l.valorCentavos))}). Vincule antes de fechar o caixa.')
                : _verif(Icons.check_circle, Colors.green, 'Todos os lançamentos estão vinculados a atendimentos.'),
            _pend.isEmpty
                ? _verif(Icons.check_circle, Colors.green, 'Todos os atendimentos concluídos têm lançamento.')
                : _verif(Icons.warning_amber, Colors.orange,
                    '${_pend.length} atendimento(s) concluído(s) sem lançamento'
                    '${valorPend > 0 ? ' (valor de tabela ${formatarReais(valorPend)})' : ''}.'),
            _verif(Icons.undo, Colors.blueGrey,
                '${_estornos.length} lançamento(s) estornado(s): não entram no total.'),
            const SizedBox(height: 12),
            const Text('Conferência por forma de pagamento', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Informe o valor conferido no extrato do Pix e no relatório das maquininhas.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            for (final f in FormaPagamento.values) ...[
              Row(children: [
                Icon(f.icone, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(f.rotulo)),
                Text('Lançado: ${formatarReais(_total(f))}', style: const TextStyle(fontSize: 12)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _conf[f],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: decoracaoCampo('Conferido (R\$)'),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: Builder(builder: (_) {
                    final c = _conferido(f);
                    if (c == null) return const Text('—');
                    final d = c - _total(f);
                    return Text(_sinal(d),
                        style: TextStyle(fontWeight: FontWeight.bold, color: _corDif(d)));
                  }),
                ),
              ]),
              const SizedBox(height: 12),
            ],
            const Divider(),
            Row(children: [
              const Expanded(child: Text('Total lançado (líquido)')),
              Text(formatarReais(lancado), style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            Row(children: [
              const Expanded(child: Text('Divergência total')),
              Text(_sinal(dif), style: TextStyle(fontWeight: FontWeight.bold, color: _corDif(dif))),
            ]),
            const SizedBox(height: 12),
            if (_pend.isNotEmpty)
              CheckboxListTile(
                value: _ciente,
                onChanged: (v) => setState(() => _ciente = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Confirmo que os atendimentos concluídos sem lançamento não tiveram cobrança.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            const Text('Comprovantes de pagamento (opcional)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _anexar,
              icon: const Icon(Icons.upload_file),
              label: const Text('Anexar comprovante'),
            ),
            const SizedBox(height: 4),
            const Text('PDF, PNG ou JPG, até 5 MB cada.', style: TextStyle(fontSize: 12)),
            for (var i = 0; i < _anexos.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file),
                title: Text(_anexos[i].nome),
                subtitle: Text(formatarTamanho(_anexos[i].tamanho)),
                trailing: IconButton(
                  tooltip: 'Remover',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _anexos.removeAt(i)),
                ),
              ),
            _erroTexto(context, _erroAnexo),
            const SizedBox(height: 12),
            TextField(
              controller: _obs,
              maxLines: 3,
              decoration: decoracaoCampo(
                  (dif != 0 || _pend.isNotEmpty) ? 'Observação (obrigatória)' : 'Observação (opcional)'),
            ),
            _erroTexto(context, _erro),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: bloqueado ? null : _fechar,
          child: const Text('Confirmar fechamento'),
        ),
      ],
    );
  }
}

class FileType {
  static get custom => null;
}

class FilePicker {
  static get platform => null;
}

// ───── caixa/pagina_caixa.dart ─────
class PaginaCaixa extends StatefulWidget {
  const PaginaCaixa(this.a, {this.auxiliar, super.key});

  final Area a;

  /// Quando preenchido, o caixa é aberto pelo auxiliar (sem corrigir, estornar nem reabrir).
  final Usuario? auxiliar;

  @override
  State<PaginaCaixa> createState() => _PaginaCaixaState();
}

class _PaginaCaixaState extends State<PaginaCaixa> {
  DateTime _dia = DateUtils.dateOnly(DateTime.now());

  String get _autor => widget.auxiliar?.nome ?? admLogin;
  bool get _admin => widget.auxiliar == null;

  bool get _hoje => mesmoDia(_dia, DateTime.now());

  void _irPara(DateTime d) {
    final hoje = DateUtils.dateOnly(DateTime.now());
    final alvo = DateUtils.dateOnly(d);
    if (alvo.isAfter(hoje)) return;
    setState(() => _dia = alvo);
  }

  DateTime _deslocar(int dias) => DateTime(_dia.year, _dia.month, _dia.day + dias);

  Future<void> _escolherDia(BuildContext c) async {
    final hoje = DateUtils.dateOnly(DateTime.now());
    final d = await showDatePicker(
      context: c,
      initialDate: _dia,
      firstDate: DateTime(2025),
      lastDate: hoje,
      helpText: 'Ver caixa do dia',
    );
    if (d != null) _irPara(d);
  }

  Future<void> _lancar(BuildContext c, [Atend? inicial]) async {
    final pend = pendentesDoDia(widget.a, DateTime.now());
    if (pend.isEmpty) {
      alerta(c, 'Nada a lançar',
          'Não há atendimentos concluídos aguardando lançamento. Para registrar uma venda ainda sem atendimento identificado, use "Venda na maquininha": ela pode ficar sem vínculo até ser corrigida.');
      return;
    }
    await showDialog<void>(
        context: c,
        builder: (_) => _LancarValorDialog(
            area: widget.a, pendentes: pend, inicial: inicial, autor: _autor));
  }

  Future<void> _maquininha(BuildContext c) async {
    final l = await showDialog<Lancamento>(
        context: c,
        builder: (_) => _VendaMaquininhaDialog(
            area: widget.a,
            pendentes: pendentesDoDia(widget.a, DateTime.now()),
            autor: _autor));
    if (l != null && l.semVinculo && c.mounted) {
      msg(c, 'Venda lançada sem vínculo. Vincule a um atendimento antes de fechar o caixa.');
    }
  }

  Future<void> _fechar(BuildContext c) async {
    final ok = await showDialog<bool>(
        context: c, builder: (_) => _FecharCaixaDialog(area: widget.a, dia: _dia, autor: _autor));
    if (ok == true && c.mounted) msg(c, 'Caixa fechado com sucesso.');
  }

  Future<void> _reabrir(BuildContext c, Fechamento f) async {
    final m = await _pedirMotivo(
        c,
        'Reabrir caixa de ${formatarData(f.dia)}',
        'O fechamento fica no histórico como "reaberto" e será preciso fechar o caixa novamente.',
        'Reabrir caixa');
    if (m == null) return;
    f.reaberto = true;
    f.reabertoEm = DateTime.now();
    f.motivoReabertura = m;
    dados.log('Caixa de ${formatarData(f.dia)} reaberto. Motivo: $m', f.area);
  }

  Future<void> _estornar(BuildContext c, Lancamento l) async {
    final m = await _pedirMotivo(
        c,
        'Estornar lançamento #${l.id}',
        'O valor de ${formatarReais(l.valorCentavos)} deixa de contar no caixa e o atendimento volta a ficar sem lançamento. A ação fica registrada.',
        'Estornar');
    if (m == null) return;
    l.estornado = true;
    l.motivoEstorno = m;
    l.registrar('Estornado. Motivo: $m');
    dados.log('Lançamento #${l.id} estornado (${formatarReais(l.valorCentavos)}). Motivo: $m', l.area);
  }

  Widget _detalheFechamento(Fechamento f) {
    final dif = f.divergencia;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Fechado em ${formatarDataHora(f.fechadoEm)} por ${f.responsavel}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          tabela(
            ['Forma', 'Lançado', 'Conferido', 'Diferença'],
            [
              for (final forma in FormaPagamento.values)
                [
                  Text(forma.rotulo),
                  Text(formatarReais(f.totais[forma] ?? 0)),
                  Text(f.conferidos[forma] == null ? 'não informado' : formatarReais(f.conferidos[forma]!)),
                  f.conferidos[forma] == null
                      ? const Text('—')
                      : Text(_sinal(f.conferidos[forma]! - (f.totais[forma] ?? 0)),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _corDif(f.conferidos[forma]! - (f.totais[forma] ?? 0)))),
                ],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            chipRotulo('Total líquido ${formatarReais(f.total)}', Colors.green),
            chipRotulo('${f.qtd} lançamento(s)', Colors.blueGrey),
            chipRotulo('Divergência ${_sinal(dif)}', _corDif(dif)),
            if (f.estornosQtd > 0)
              chipRotulo('${f.estornosQtd} estorno(s) • ${formatarReais(f.estornosValor)}', Colors.grey),
            if (f.pendentesIgnorados > 0)
              chipRotulo('${f.pendentesIgnorados} atendimento(s) sem cobrança', Colors.orange),
          ]),
          if (f.observacao != null) ...[
            const SizedBox(height: 12),
            Text('Observação: ${f.observacao}'),
          ],
          if (f.comprovantes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Comprovantes anexados', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final x in f.comprovantes)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file),
                title: Text(x.nome),
                subtitle: Text(formatarTamanho(x.tamanho)),
              ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Obs((c) {
        final a = widget.a;
        final fech = dados.fechamentoDe(a, _dia);
        final aberto = fech == null;
        final lancs = dados.lancamentosDoDia(a, _dia);
        final ativos = lancs.where((l) => l.ativo).toList();
        final estornados = lancs.where((l) => l.estornado).toList();
        final semVinc = dados.semVinculoDe(a, _dia);
        final pend = pendentesDoDia(a, _dia);
        final total = ativos.fold(0, (s, l) => s + l.valorCentavos);
        int porForma(FormaPagamento f) =>
            ativos.where((l) => l.forma == f).fold(0, (s, l) => s + l.valorCentavos);
        int qtdForma(FormaPagamento f) => ativos.where((l) => l.forma == f).length;
        String pct(int v) => total == 0 ? '—' : '${(v * 100 / total).round()}%';
        final historico = dados.fechamentos.where((f) => f.area == a).toList()
          ..sort((x, y) => y.fechadoEm.compareTo(x.fechadoEm));

        return Pagina(
          titulo: 'Caixa – ${a.nome}',
          sub: 'Controle completo do caixa: lançamentos, vendas da maquininha, correção de lançamentos sem vínculo, estornos e fechamento diário com conferência. Consulte qualquer dia pela data.',
          acoes: [
            if (fech == null) ...[
              FilledButton.icon(
                  onPressed: _hoje ? () => _lancar(c) : null,
                  icon: const Icon(Icons.add_card),
                  label: const Text('Lançar valor')),
              FilledButton.tonalIcon(
                  onPressed: _hoje ? () => _maquininha(c) : null,
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('Venda na maquininha')),
              OutlinedButton.icon(
                  onPressed: () => _fechar(c),
                  icon: const Icon(Icons.lock),
                  label: const Text('Fechar caixa')),
            ] else if (_admin)
              OutlinedButton.icon(
                  onPressed: () => _reabrir(c, fech),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Reabrir caixa')),
          ],
          filhos: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  IconButton(
                      tooltip: 'Dia anterior',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _irPara(_deslocar(-1))),
                  OutlinedButton.icon(
                      onPressed: () => _escolherDia(c),
                      icon: const Icon(Icons.calendar_month),
                      label: Text('${formatarData(_dia)}${_hoje ? ' (hoje)' : ''}')),
                  IconButton(
                      tooltip: 'Próximo dia',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _hoje ? null : () => _irPara(_deslocar(1))),
                  if (!_hoje)
                    TextButton(onPressed: () => _irPara(DateTime.now()), child: const Text('Voltar para hoje')),
                  aberto
                      ? chipRotulo('Caixa aberto', Colors.orange, icone: Icons.lock_open)
                      : chipRotulo('Caixa fechado', Colors.green, icone: Icons.lock),
                ]),
              ),
            ),
            if (!aberto)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    _admin
                        ? 'Caixa fechado: não é possível lançar nem corrigir. Para alterar algo, reabra o caixa (fica registrado).'
                        : 'Caixa fechado: não é possível lançar nem corrigir. Somente o Administrador pode reabrir o caixa.',
                    style: const TextStyle(fontSize: 12)),
              )
            else if (!_hoje)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Novos lançamentos só podem ser feitos no dia atual. Neste dia você pode corrigir, vincular, estornar e fechar o caixa.',
                    style: TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 16),
            Wrap(spacing: 16, runSpacing: 16, children: [
              kpi(Icons.payments, 'Total líquido', formatarReais(total), Colors.green),
              kpi(Icons.receipt_long, 'Lançamentos', '${ativos.length}', Colors.blue),
              kpi(Icons.pix, 'Pix', formatarReais(porForma(FormaPagamento.pix)), Colors.teal),
              kpi(Icons.credit_card, 'Débito', formatarReais(porForma(FormaPagamento.debito)), Colors.indigo),
              kpi(Icons.credit_score, 'Crédito', formatarReais(porForma(FormaPagamento.credito)), Colors.deepPurple),
              kpi(Icons.hourglass_bottom, 'Concluídos a lançar', '${pend.length}', Colors.orange),
              kpi(Icons.link_off, 'Sem vínculo', '${semVinc.length}', semVinc.isEmpty ? Colors.grey : Colors.red),
              kpi(Icons.undo, 'Estornados', '${estornados.length}', Colors.blueGrey),
            ]),
            const SizedBox(height: 24),
            Text('Resumo por forma de pagamento', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            tabela(
              ['Forma', 'Lançamentos', 'Total', '% do total'],
              [
                for (final f in FormaPagamento.values)
                  [
                    Row(mainAxisSize: MainAxisSize.min, children: [Icon(f.icone, size: 18), const SizedBox(width: 8), Text(f.rotulo)]),
                    Text('${qtdForma(f)}'),
                    Text(formatarReais(porForma(f))),
                    Text(pct(porForma(f))),
                  ],
                [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${ativos.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(formatarReais(total), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Text('100%', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ],
            ),
            const SizedBox(height: 8),
            tabela(
              ['Origem', 'Lançamentos', 'Total'],
              [
                for (final o in OrigemLancamento.values)
                  [
                    Text(o.rotulo),
                    Text('${ativos.where((l) => l.origem == o).length}'),
                    Text(formatarReais(ativos.where((l) => l.origem == o).fold(0, (s, l) => s + l.valorCentavos))),
                  ],
              ],
            ),
            const SizedBox(height: 24),
            Text('Lançamentos do dia', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            tabela(
              ['Hora', 'Cliente / atendimento', 'Forma', 'Origem', 'Valor', 'Vínculo', 'Situação', 'Ações'],
              [
                for (final l in lancs)
                  [
                    Text(formatarHora(l.data)),
                    Text(l.atend == null ? '— (sem vínculo)' : '${l.atend!.cliente.nome} • ${l.atend!.servico}'),
                    Text(_rotuloForma(l)),
                    chipRotulo(l.origem.rotulo, l.origem == OrigemLancamento.maquininha ? Colors.indigo : Colors.blueGrey),
                    Text(formatarReais(l.valorCentavos),
                        style: l.estornado ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
                    l.atend != null
                        ? chipRotulo('Atend. #${l.atend!.id}', Colors.green, icone: Icons.link)
                        : (l.estornado
                            ? chipRotulo('—', Colors.grey)
                            : chipRotulo('SEM VÍNCULO', Colors.red, icone: Icons.link_off)),
                    l.estornado
                        ? chipRotulo('Estornado', Colors.grey, icone: Icons.undo)
                        : chipRotulo('Válido', Colors.green, icone: Icons.check),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          tooltip: 'Detalhes',
                          icon: const Icon(Icons.info_outline),
                          onPressed: () => showDialog<void>(context: c, builder: (_) => _DetalhesDialog(l))),
                      if (aberto && !l.estornado) ...[
                        if (l.semVinculo)
                          IconButton(
                              tooltip: 'Vincular a um atendimento',
                              icon: const Icon(Icons.link),
                              onPressed: () => showDialog<void>(context: c, builder: (_) => _VincularDialog(l, autor: _autor))),
                        if (_admin)
                          IconButton(
                            tooltip: 'Corrigir',
                            icon: const Icon(Icons.edit),
                            onPressed: () => showDialog<void>(context: c, builder: (_) => _CorrigirDialog(l))),
                        if (_admin)
                          IconButton(
                            tooltip: 'Estornar',
                            icon: const Icon(Icons.undo),
                            onPressed: () => _estornar(c, l)),
                      ],
                    ]),
                  ],
              ],
            ),
            if (pend.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Atendimentos concluídos aguardando lançamento', style: Theme.of(c).textTheme.titleMedium),
              const SizedBox(height: 8),
              tabela(
                ['Nº', 'Data', 'Cliente', 'Procedimento', 'Valor de tabela', 'Ação'],
                [
                  for (final x in pend)
                    [
                      Text('#${x.id}'),
                      Text(formatarData(x.quando)),
                      Text(x.cliente.nome),
                      Text(x.servico),
                      Text(valorDoProcedimento(x.area, x.servico) == null
                          ? '—'
                          : formatarReais(valorDoProcedimento(x.area, x.servico)!)),
                      (aberto && _hoje)
                          ? TextButton.icon(
                              onPressed: () => _lancar(c, x),
                              icon: const Icon(Icons.add_card),
                              label: const Text('Lançar'))
                          : const Text('—'),
                    ],
                ],
              ),
            ],
            const SizedBox(height: 24),
            Text('Fechamento do dia', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (fech != null)
              _detalheFechamento(fech)
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(semVinc.isEmpty ? Icons.check_circle : Icons.block,
                          color: semVinc.isEmpty ? Colors.green : Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(semVinc.isEmpty
                              ? 'Nenhum lançamento sem vínculo.'
                              : '${semVinc.length} lançamento(s) sem vínculo: corrija antes de fechar.')),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(pend.isEmpty ? Icons.check_circle : Icons.warning_amber,
                          color: pend.isEmpty ? Colors.green : Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(pend.isEmpty
                              ? 'Todos os atendimentos concluídos têm lançamento.'
                              : '${pend.length} atendimento(s) concluído(s) sem lançamento.')),
                    ]),
                    const SizedBox(height: 12),
                    const Text('No fechamento você confere o valor de cada forma de pagamento (extrato do Pix e relatório das maquininhas) e registra qualquer divergência.',
                        style: TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
            const SizedBox(height: 24),
            Text('Histórico de fechamentos', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            tabela(
              ['Data', 'Fechado em', 'Total líquido', 'Divergência', 'Lançamentos', 'Responsável', 'Situação', ''],
              [
                for (final f in historico)
                  [
                    Text(formatarData(f.dia)),
                    Text(formatarDataHora(f.fechadoEm)),
                    Text(formatarReais(f.total)),
                    Text(_sinal(f.divergencia),
                        style: TextStyle(fontWeight: FontWeight.bold, color: _corDif(f.divergencia))),
                    Text('${f.qtd}'),
                    Text(f.responsavel),
                    f.reaberto
                        ? chipRotulo('Reaberto', Colors.orange, icone: Icons.lock_open)
                        : chipRotulo('Fechado', Colors.green, icone: Icons.lock),
                    TextButton(onPressed: () => _irPara(f.dia), child: const Text('Ver dia')),
                  ],
              ],
            ),
          ],
        );
      });
}