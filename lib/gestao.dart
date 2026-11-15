import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin.dart';
import 'indicadores.dart';
import 'main.dart';
import 'recepcao.dart';

// ───── gestao/modelos.dart ─────
/// Para quem uma instrução ou orientação é dirigida.
enum PublicoAlvo {
  administrador('Administrador'),
  auxiliar('Auxiliares e atendentes'),
  cliente('Clientes');

  const PublicoAlvo(this.rotulo);
  final String rotulo;
}

PublicoAlvo publicoDe(Usuario u) =>
    u.perfil == Perfil.cliente ? PublicoAlvo.cliente : PublicoAlvo.auxiliar;

/// Guia de uso passo a passo.
class Instrucao {
  Instrucao(this.id, this.titulo, this.publico, this.passos, {this.dica, this.publicada = true});

  final int id;
  String titulo;
  PublicoAlvo publico;
  List<String> passos;
  String? dica;
  bool publicada;
  DateTime atualizadaEm = DateTime.now();
}

/// Aviso/orientação da clínica para um público. Aparece no painel do usuário até ele marcar "Ciente".
class Orientacao {
  Orientacao({
    required this.id,
    required this.titulo,
    required this.texto,
    required this.publicos,
    required this.autor,
    this.validaAte,
  }) : criadaEm = DateTime.now();

  final int id;
  final String titulo, texto, autor;
  final Set<PublicoAlvo> publicos;
  final DateTime criadaEm;
  final DateTime? validaAte;
  bool encerrada = false;

  /// Ids dos usuários que marcaram "Ciente".
  final Set<int> cientes = {};

  bool get vencida => validaAte != null && !validaAte!.isAfter(DateTime.now());
  bool get vigente => !encerrada && !vencida;
}

/// Fluxo operacional que o administrador revisa periodicamente.
class FluxoOperacional {
  const FluxoOperacional(this.id, this.nome, this.descricao, this.etapas, this.categoria);

  final String id, nome, descricao;
  final List<String> etapas;

  /// Categoria dos alertas de fluxo ligados a este fluxo.
  final CategoriaAlerta? categoria;
}

class RegistroRevisao {
  RegistroRevisao(this.area, this.fluxoId, this.autor, this.ok, this.observacao)
      : quando = DateTime.now();

  final Area area;
  final String fluxoId, autor;
  final bool ok;
  final String? observacao;
  final DateTime quando;
}

/// Tela operacional com a lista de critérios de revisão.
class TelaOperacional {
  TelaOperacional(this.id, this.nome, this.onde, this.criterios);

  final String id, nome, onde;
  final List<String> criterios;
  final Set<int> marcados = {};
  DateTime? revisadaEm;
  String? por, observacao;

  bool get completa => marcados.length == criterios.length;
}

const diasValidadeRevisao = 30; // depois disso a revisão do fluxo é considerada vencida

class Gestao {
  Gestao() {
    _semear();
  }

  int _seq = 0;
  int proximoId() => ++_seq;

  final instrucoes = <Instrucao>[];
  final orientacoes = <Orientacao>[];

  /// Revisões de fluxos (a mais recente primeiro).
  final revisoes = <RegistroRevisao>[];

  static const fluxos = [
    FluxoOperacional(
      'agendamento',
      'Agendamento do cliente',
      'Do cadastro até a confirmação da presença.',
      [
        'Cliente se cadastra',
        'Escolhe área e procedimento',
        'Escolhe dia e horário com vaga',
        'Sistema sorteia o profissional',
        'Lembrete por WhatsApp',
        'Cliente confirma',
      ],
      CategoriaAlerta.agenda,
    ),
    FluxoOperacional(
      'remarcacao',
      'Remarcação e cancelamento',
      'Cliente, auxiliar ou administrador mudam a agenda com as regras de 24h e de expediente.',
      [
        'Pedido de mudança',
        'Regra de 24h',
        'Conflito e expediente',
        'Agenda atualizada',
        'Aviso ao cliente',
        'Registro na auditoria',
      ],
      CategoriaAlerta.agenda,
    ),
    FluxoOperacional(
      'fila',
      'Check-in e fila',
      'Da chegada do cliente até o início do atendimento.',
      [
        'Cliente chega',
        'Check-in e senha',
        'Prioridade, se houver',
        'Chamada',
        'Início do atendimento',
      ],
      CategoriaAlerta.fila,
    ),
    FluxoOperacional(
      'atendimento',
      'Atendimento e conclusão',
      'Receber, atender e concluir com confirmação.',
      [
        'Receber o cliente',
        'Em atendimento',
        'Concluir (com confirmação)',
        'Disponível para pagamento',
      ],
      CategoriaAlerta.atendimento,
    ),
    FluxoOperacional(
      'presenca',
      'Confirmação e faltas',
      'Lembretes, confirmação, ausência e bloqueio com 3 faltas.',
      [
        'Lembrete enviado',
        'Confirmação ou sem resposta',
        'Alerta ao atendente',
        'Ausência registrada',
        'Contador de faltas',
        'Bloqueio ou liberação',
      ],
      CategoriaAlerta.presenca,
    ),
    FluxoOperacional(
      'pagamento',
      'Pagamento e fechamento do caixa',
      'Do recebimento do pagamento até o fechamento conferido do dia.',
      [
        'Atendimento concluído',
        'Receber pagamento (Pix, cartão ou maquininha)',
        'Vincular ao atendimento',
        'Conferir por forma de pagamento',
        'Fechar o caixa',
        'Relatórios',
      ],
      null,
    ),
  ];

  final telas = <TelaOperacional>[
    TelaOperacional('recepcao', 'Recepção e fila', 'Administrador e auxiliar', [
      'O check-in registra senha e prioridade',
      'Mostra a situação do cliente e a confirmação',
      'Chamar, iniciar e concluir funcionam em sequência',
      'Alertas de fila aparecem quando a espera passa do limite',
      'Legível e utilizável no celular',
    ]),
    TelaOperacional('agenda', 'Agenda', 'Administrador', [
      'Alterar, remarcar e cancelar respeitam a regra de 24h',
      'Conflitos de horário são impedidos',
      'Alterações recentes aparecem no fim da página',
      'O cliente é avisado das mudanças',
    ]),
    TelaOperacional('atendimentos', 'Atendimentos e conclusão', 'Administrador e auxiliar', [
      'Só cliente cadastrado e ativo é recebido',
      'A conclusão exige confirmação',
      'O tempo de atendimento é registrado',
      'O pagamento pode ser recebido a partir da lista',
    ]),
    TelaOperacional('caixa', 'Caixa e fechamento', 'Administrador e auxiliar', [
      'Dinheiro não aparece como forma de pagamento',
      'Lançamento sem vínculo bloqueia o fechamento',
      'O fechamento confere Pix, débito e crédito',
      'Caixa fechado não aceita alterações',
      'Corrigir, estornar e reabrir só para o administrador',
    ]),
    TelaOperacional('faltas', 'Faltas e lembretes', 'Administrador', [
      'Ausências são processadas sem afetar quem fez check-in',
      'Com 3 faltas o agendamento é bloqueado ou depende de aprovação',
      'Cliente sem resposta ao lembrete gera alerta',
    ]),
    TelaOperacional('indicadores', 'Painel de indicadores', 'Administrador', [
      'Os alertas de fluxo aparecem no topo',
      'Os períodos Hoje, 7 e 30 dias funcionam',
      'Os números batem com a agenda e o caixa',
    ]),
    TelaOperacional('cliente', 'Página do cliente', 'Cliente', [
      'Cadastro pede todos os dados obrigatórios',
      'Só aparecem dias e horários com vaga',
      'Mostra confirmação, senha e pagamento',
      'Funciona bem no celular',
    ]),
    TelaOperacional('acesso', 'Login e controle de acesso', 'Todos', [
      'Cada perfil vê só o que pode',
      'Tentativas negadas ficam na auditoria',
      'Senhas de demonstração foram removidas antes de usar de verdade',
    ]),
  ];

  RegistroRevisao? ultimaRevisao(Area a, String fluxoId) {
    for (final r in revisoes) {
      if (r.area == a && r.fluxoId == fluxoId) return r;
    }
    return null;
  }

  List<Instrucao> publicadas(PublicoAlvo p) =>
      instrucoes.where((i) => i.publicada && i.publico == p).toList();

  List<Orientacao> pendentesPara(PublicoAlvo p, Usuario u) => orientacoes
      .where((o) => o.vigente && o.publicos.contains(p) && !o.cientes.contains(u.id))
      .toList();

  Iterable<Usuario> destinatarios(Orientacao o) =>
      dados.usuarios.where((u) => u.ativo && o.publicos.contains(publicoDe(u)));

  /// Manual completo em texto (para copiar e imprimir).
  String manualEmTexto({bool soPublicadas = false}) {
    final b = StringBuffer('MANUAL DE USO\n');
    for (final p in PublicoAlvo.values) {
      final l = instrucoes.where((i) => i.publico == p && (!soPublicadas || i.publicada)).toList();
      if (l.isEmpty) continue;
      b.writeln('\n=== ${p.rotulo.toUpperCase()} ===');
      for (final i in l) {
        b.writeln('\n${i.titulo}');
        for (var n = 0; n < i.passos.length; n++) {
          b.writeln('  ${n + 1}. ${i.passos[n]}');
        }
        if (i.dica != null && i.dica!.isNotEmpty) b.writeln('  Dica: ${i.dica}');
      }
    }
    return b.toString();
  }

  void _semear() {
    Instrucao novo(String t, PublicoAlvo p, List<String> passos, [String? dica]) =>
        Instrucao(proximoId(), t, p, passos, dica: dica);

    instrucoes.addAll([
      // Administrador
      novo('Entrar e escolher a área', PublicoAlvo.administrador, [
        'Na tela inicial, toque em "Acesso administrativo" e entre com o seu usuário e senha.',
        'Escolha Estética ou Psicologia: cada área tem o seu painel, com cores próprias.',
        'Use o menu lateral (no celular, o botão de menu) para navegar. "Trocar área" volta à escolha.',
        'Ao terminar, use "Sair" para encerrar a sessão.',
      ], 'Tudo o que você faz fica registrado na Auditoria, com data, hora e responsável.'),
      novo('Gerenciar usuários', PublicoAlvo.administrador, [
        'Abra "Usuários" e use a busca ou o filtro por perfil.',
        'Para cadastrar, toque em "Novo usuário" e informe nome, perfil (atendente, auxiliar ou cliente) e contato.',
        'Para editar ou desativar, use os ícones na linha do usuário.',
        'Ao desativar quem tem atendimentos futuros, o sistema avisa antes de confirmar.',
      ], 'Dados repetidos (mesmo contato) não são aceitos.'),
      novo('Agenda: alterar, remarcar e cancelar', PublicoAlvo.administrador, [
        'Abra "Agenda" para ver os agendamentos em aberto e os cancelados.',
        'Use o lápis para alterar profissional, procedimento ou horário (o motivo é obrigatório).',
        'Remarcar e cancelar com menos de 24h de antecedência é bloqueado; só você pode autorizar a exceção.',
        'O cliente vê um aviso da mudança na página dele.',
      ], 'Veja "Alterações recentes da agenda" no fim da página.'),
      novo('Recepção, atendimento e conclusão', PublicoAlvo.administrador, [
        'Em "Recepção e fila", faça o check-in de quem chegou e marque a prioridade, se houver.',
        'Confira a situação do cliente e a confirmação do agendamento antes de iniciar.',
        'Use "Chamar próximo" e depois inicie o atendimento.',
        'Ao terminar, toque em "Concluir" e confirme que o serviço foi realizado.',
        'Na mensagem de conclusão, use "Receber pagamento".',
      ]),
      novo('Pagamento e fechamento do caixa', PublicoAlvo.administrador, [
        'Em "Caixa", lance o valor de um atendimento concluído ou registre uma venda da maquininha (dinheiro não é aceito).',
        'Se uma venda ficou sem vínculo, use o ícone de corrente para ligá-la ao cliente e ao atendimento.',
        'Para fechar, toque em "Fechar caixa", confira as verificações e informe o valor conferido de Pix, débito e crédito.',
        'Explique qualquer divergência na observação e, se quiser, anexe comprovantes.',
        'Para ver outro dia, use as setas ou o calendário. Para alterar um dia fechado, use "Reabrir caixa" com motivo.',
      ], 'Atendimento em andamento ou lançamento sem vínculo impede o fechamento.'),
      novo('Indicadores e alertas', PublicoAlvo.administrador, [
        'Abra "Painel de indicadores" e escolha Hoje, 7 dias ou 30 dias.',
        'Leia os alertas em "Revisar fluxo de clientes" e atue no que estiver crítico ou em atenção.',
        'Use "Revisar fluxos" e "Revisar telas operacionais" para registrar as revisões periódicas.',
        'Use "Indicadores e relatórios" para filtrar e exportar em CSV.',
      ], 'Os limites dos alertas ficam no início do arquivo indicadores.dart.'),

      // Auxiliares e atendentes
      novo('Entrar no painel', PublicoAlvo.auxiliar, [
        'Na tela inicial, toque em "Acesso do auxiliar" e entre com o seu e-mail e senha.',
        'Você vê apenas o painel da sua área.',
        'Use o menu lateral para trocar de tela e "Sair" ao terminar.',
      ]),
      novo('Check-in e fila', PublicoAlvo.auxiliar, [
        'Em "Recepção e fila", toque em "Fazer check-in" e busque o cliente.',
        'Confira a situação do cliente e a confirmação do agendamento.',
        'Marque a prioridade quando for idoso, gestante ou pessoa com deficiência.',
        'Chame o próximo, inicie o atendimento e conclua no mesmo lugar.',
      ], 'Quem fez check-in não é marcado como ausente.'),
      novo('Agendar, remarcar e cancelar', PublicoAlvo.auxiliar, [
        'Em "Agendar serviço", busque o cliente e escolha procedimento, dia e horário.',
        'Em "Remarcar/cancelar serviço", escolha o agendamento e a ação.',
        'Com menos de 24h de antecedência a ação é bloqueada: procure o Administrador.',
        'O lápis permite alterar profissional, procedimento ou horário, sempre com motivo.',
      ]),
      novo('Receber e concluir o atendimento', PublicoAlvo.auxiliar, [
        'Em "Receber cliente", busque pelo nome, e-mail ou telefone e toque em "Receber". Só clientes cadastrados e ativos são atendidos.',
        'Em "Concluir atendimento", toque em "Concluir" e confirme a realização do serviço.',
        'Depois, receba o pagamento direto da lista ("Receber" ou "Maquininha").',
      ]),
      novo('Caixa e fechamento', PublicoAlvo.auxiliar, [
        'Em "Caixa", lance valores e vendas da maquininha (dinheiro não é aceito).',
        'Corrija lançamentos sem vínculo ligando-os ao cliente e ao atendimento.',
        'Para fechar o caixa do dia, informe o valor conferido de cada forma de pagamento e explique divergências.',
        'Corrigir, estornar e reabrir o caixa são ações do Administrador.',
      ]),

      // Clientes
      novo('Criar a sua conta', PublicoAlvo.cliente, [
        'Na tela inicial, escolha Estética ou Psicologia e toque em "Cadastre-se".',
        'Preencha nome, e-mail, CPF, data de nascimento, telefone/WhatsApp e senha.',
        'Menores de 18 anos informam o nome do responsável.',
        'Aceite os termos de privacidade e toque em "Criar conta".',
      ], 'Use um WhatsApp ativo: é por ele que você recebe os lembretes.'),
      novo('Agendar um atendimento', PublicoAlvo.cliente, [
        'Escolha a área (Estética ou Psicologia).',
        'Selecione o procedimento (o valor aparece ao lado).',
        'Escolha um dia disponível no calendário e um horário livre.',
        'Confirme. O profissional é definido pela clínica.',
      ], 'Você pode agendar nas duas áreas com a mesma conta.'),
      novo('Remarcar ou cancelar', PublicoAlvo.cliente, [
        'Abra "Meus agendamentos".',
        'Toque em "Remarcar" ou "Cancelar".',
        'Só é possível com pelo menos 24h de antecedência; depois disso, fale com a clínica.',
      ]),
      novo('Confirmar presença e acompanhar o atendimento', PublicoAlvo.cliente, [
        'Quando receber o lembrete, toque em "Confirmar presença".',
        'Ao chegar, informe o nome na recepção para fazer o check-in.',
        'Acompanhe a sua senha e a situação em "Meus agendamentos".',
        'Depois do atendimento, confira se o pagamento aparece como "Pago".',
      ]),
    ]);

    orientacoes.addAll([
      Orientacao(
        id: proximoId(),
        titulo: 'Confira a situação e a confirmação antes de iniciar',
        texto:
            'Antes de iniciar um atendimento, olhe a situação do cliente (faltas e bloqueio) e a confirmação do agendamento. Em caso de dúvida, chame o Administrador.',
        publicos: {PublicoAlvo.auxiliar},
        autor: admLogin,
      ),
      Orientacao(
        id: proximoId(),
        titulo: 'Faça o check-in ao chegar',
        texto:
            'Ao chegar, informe o seu nome na recepção para fazer o check-in e receber a sua senha. Quem faz check-in não é marcado como ausente.',
        publicos: {PublicoAlvo.cliente},
        autor: admLogin,
      ),
    ]);
  }
}

final gestao = Gestao();

// ───── gestao/comuns.dart ─────
class _ResultadoRevisao {
  _ResultadoRevisao(this.ok, this.observacao);

  final bool ok;
  final String? observacao;
}

Future<_ResultadoRevisao?> _pedirRevisao(BuildContext c, String titulo) {
  final ctrl = TextEditingController();
  var ok = true;
  String? erro;
  return showDialog<_ResultadoRevisao>(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(titulo),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Sem ajustes')),
                ButtonSegment(value: false, label: Text('Precisa de ajustes')),
              ],
              selected: {ok},
              onSelectionChanged: (s) => set(() => ok = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: decoracaoCampo(
                  ok ? 'Observação (opcional)' : 'O que precisa ser ajustado? (obrigatório)'),
            ),
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
              final o = ctrl.text.trim();
              if (!ok && o.length < 5) {
                set(() => erro = 'Descreva o ajuste necessário.');
                return;
              }
              Navigator.pop(d, _ResultadoRevisao(ok, o.isEmpty ? null : o));
            },
            child: const Text('Registrar revisão'),
          ),
        ],
      ),
    ),
  );
}

// ───── gestao/revisar_fluxos.dart ─────
class PaginaRevisaoFluxos extends StatelessWidget {
  const PaginaRevisaoFluxos(this.a, {super.key});

  final Area a;

  List<String> _agora(FluxoOperacional f) {
    switch (f.id) {
      case 'agendamento':
        final futuros = dados.doArea(a).where((x) => x.aberto && x.quando.isAfter(DateTime.now())).length;
        return ['$futuros agendamento(s) futuro(s)'];
      case 'fila':
        return [
          '${filaAtendimento.aguardando(a).length} aguardando • ${filaAtendimento.chamados(a).length} chamado(s)'
        ];
      case 'atendimento':
        final andamento = dados.doArea(a).where((x) => x.status == StatusAtend.emAtendimento).length;
        return ['$andamento atendimento(s) em andamento'];
      case 'presenca':
        final semResposta = dados.doArea(a).where((x) => x.aberto && x.lembrete == StatusLembrete.semResposta).length;
        return ['$semResposta cliente(s) sem resposta ao lembrete'];
      case 'pagamento':
        return [
          '${dados.pendentes(a).length} concluído(s) sem lançamento • ${dados.semVinculoDe(a).length} lançamento(s) sem vínculo',
          dados.caixaFechado(a, DateTime.now()) ? 'Caixa de hoje fechado' : 'Caixa de hoje aberto',
        ];
      default:
        return [];
    }
  }

  Future<void> _registrar(BuildContext c, FluxoOperacional f) async {
    final r = await _pedirRevisao(c, 'Revisão: ${f.nome}');
    if (r == null) return;
    gestao.revisoes.insert(0, RegistroRevisao(a, f.id, admLogin, r.ok, r.observacao));
    dados.log(
        'Fluxo "${f.nome}" revisado: ${r.ok ? 'sem ajustes' : 'precisa de ajustes'}${r.observacao == null ? '' : '. ${r.observacao}'}',
        a);
  }

  @override
  Widget build(BuildContext context) => Obs((c) {
        final agora = DateTime.now();
        final alertas = alertasDeFluxo(a);
        final revisados = Gestao.fluxos.where((f) {
          final r = gestao.ultimaRevisao(a, f.id);
          return r != null && r.ok && agora.difference(r.quando).inDays <= diasValidadeRevisao;
        }).length;
        final ajustes = Gestao.fluxos.where((f) => gestao.ultimaRevisao(a, f.id)?.ok == false).length;

        return Pagina(
          titulo: 'Revisar fluxos – ${a.nome}',
          sub: 'Revise periodicamente cada fluxo de clientes: veja as etapas, a situação de agora e os alertas ligados a ele, e registre o resultado da revisão. Revisões com mais de $diasValidadeRevisao dias aparecem como vencidas.',
          filhos: [
            Wrap(spacing: 16, runSpacing: 16, children: [
              kpi(Icons.account_tree_outlined, 'Fluxos revisados', '$revisados de ${Gestao.fluxos.length}', Colors.green),
              kpi(Icons.build_circle_outlined, 'Ajustes pendentes', '$ajustes', ajustes > 0 ? Colors.orange : Colors.teal),
              kpi(Icons.notification_important_outlined, 'Alertas de fluxo', '${alertas.length}',
                  alertas.isEmpty ? Colors.teal : Colors.red),
            ]),
            const SizedBox(height: 24),
            ...secaoAlertasFluxo(c, a),
            const SizedBox(height: 8),
            for (final f in Gestao.fluxos) ..._cartao(c, f, alertas, agora),
          ],
        );
      });

  List<Widget> _cartao(BuildContext c, FluxoOperacional f, List<AlertaFluxo> alertas, DateTime agora) {
    final ult = gestao.ultimaRevisao(a, f.id);
    final hist = gestao.revisoes.where((r) => r.area == a && r.fluxoId == f.id).toList();
    final ligados = alertas.where((x) => f.categoria != null && x.categoria == f.categoria).toList();
    final vencida = ult != null && agora.difference(ult.quando).inDays > diasValidadeRevisao;
    final Widget status = ult == null
        ? chipRotulo('Nunca revisado', Colors.grey, icone: Icons.help_outline)
        : !ult.ok
            ? chipRotulo('Ajustes pendentes', Colors.orange, icone: Icons.build_circle_outlined)
            : vencida
                ? chipRotulo('Revisão vencida', Colors.orange, icone: Icons.schedule)
                : chipRotulo('Revisado em ${formatarData(ult.quando)}', Colors.green, icone: Icons.check_circle);

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(f.nome, style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              status,
            ]),
            const SizedBox(height: 4),
            Text(f.descricao, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (var i = 0; i < f.etapas.length; i++) ...[
                Chip(
                  label: Text('${i + 1}. ${f.etapas[i]}', style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                ),
                if (i < f.etapas.length - 1) const Icon(Icons.arrow_forward, size: 16),
              ],
            ]),
            const SizedBox(height: 12),
            const Text('Situação agora', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            for (final t in _agora(f)) Text('• $t', style: const TextStyle(fontSize: 13)),
            if (ligados.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final x in ligados)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(x.nivel.icone, size: 18, color: x.nivel.cor),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${x.titulo}: ${x.detalhe}', style: const TextStyle(fontSize: 13))),
                ]),
            ],
            if (ult != null && ult.observacao != null) ...[
              const SizedBox(height: 8),
              Text('Última observação (${ult.autor}): ${ult.observacao}', style: const TextStyle(fontSize: 12)),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilledButton.tonalIcon(
                onPressed: () => _registrar(c, f),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Registrar revisão'),
              ),
            ]),
            if (hist.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Histórico de revisões (${hist.length})', style: const TextStyle(fontSize: 13)),
                children: [
                  for (final r in hist)
                    ListTile(
                      dense: true,
                      leading: Icon(r.ok ? Icons.check_circle : Icons.build_circle_outlined,
                          color: r.ok ? Colors.green : Colors.orange, size: 20),
                      title: Text('${formatarDataHora(r.quando)} • ${r.autor}'),
                      subtitle: Text(r.observacao ?? (r.ok ? 'Sem ajustes.' : 'Precisa de ajustes.')),
                    ),
                ],
              ),
          ]),
        ),
      ),
    ];
  }
}

// ───── gestao/revisar_telas.dart ─────
class PaginaRevisaoTelas extends StatelessWidget {
  const PaginaRevisaoTelas({super.key});

  @override
  Widget build(BuildContext context) => Obs((c) {
        final revisadas = gestao.telas.where((t) => t.completa && t.revisadaEm != null).length;
        final emRevisao =
            gestao.telas.where((t) => t.marcados.isNotEmpty && !(t.completa && t.revisadaEm != null)).length;
        return Pagina(
          titulo: 'Revisar telas operacionais',
          sub: 'Confira cada tela com a lista de critérios, marque o que está correto e registre a revisão com observações. Serve para validar as telas antes de colocar o sistema em uso e depois de cada mudança.',
          filhos: [
            Wrap(spacing: 16, runSpacing: 16, children: [
              kpi(Icons.fact_check_outlined, 'Telas revisadas', '$revisadas de ${gestao.telas.length}', Colors.green),
              kpi(Icons.pending_actions, 'Em revisão', '$emRevisao', Colors.orange),
            ]),
            const SizedBox(height: 16),
            for (final t in gestao.telas) _CartaoTela(t, key: ValueKey(t.id)),
          ],
        );
      });
}

class _CartaoTela extends StatefulWidget {
  const _CartaoTela(this.t, {super.key});

  final TelaOperacional t;

  @override
  State<_CartaoTela> createState() => _CartaoTelaState();
}

class _CartaoTelaState extends State<_CartaoTela> {
  late final _obs = TextEditingController(text: widget.t.observacao);
  String? _erro;

  @override
  void dispose() {
    _obs.dispose();
    super.dispose();
  }

  void _registrar() {
    final t = widget.t;
    final o = _obs.text.trim();
    if (!t.completa && o.length < 5) {
      setState(() => _erro = 'Há critérios sem marcar: explique o que está pendente na observação.');
      return;
    }
    setState(() => _erro = null);
    t.revisadaEm = DateTime.now();
    t.por = admLogin;
    t.observacao = o.isEmpty ? null : o;
    dados.log('Tela "${t.nome}" revisada (${t.marcados.length}/${t.criterios.length} critérios)${t.observacao == null ? '' : '. ${t.observacao}'}');
    msg(context, 'Revisão da tela "${t.nome}" registrada.');
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final Widget status = t.completa && t.revisadaEm != null
        ? chipRotulo('Revisada em ${formatarData(t.revisadaEm!)}', Colors.green, icone: Icons.check_circle)
        : t.marcados.isNotEmpty
            ? chipRotulo('Em revisão (${t.marcados.length}/${t.criterios.length})', Colors.orange, icone: Icons.pending_actions)
            : chipRotulo('Não revisada', Colors.grey, icone: Icons.help_outline);

    return Card(
      child: ExpansionTile(
        title: Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(t.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
          status,
        ]),
        subtitle: Text('Quem usa: ${t.onde}${t.por == null ? '' : ' • última revisão por ${t.por}'}',
            style: const TextStyle(fontSize: 12)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (var i = 0; i < t.criterios.length; i++)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: t.marcados.contains(i),
              title: Text(t.criterios[i]),
              onChanged: (v) {
                setState(() => v == true ? t.marcados.add(i) : t.marcados.remove(i));
                dados.atualizar();
              },
            ),
          const SizedBox(height: 8),
          TextField(controller: _obs, maxLines: 2, decoration: decoracaoCampo('Observações da revisão')),
          if (_erro != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _registrar,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Registrar revisão'),
            ),
          ),
        ],
      ),
    );
  }
}

// ───── gestao/instrucoes.dart ─────
/// Lista os guias de um público (usada na página do administrador, no painel do auxiliar e na do cliente).
Widget guiaDeUso(BuildContext c, PublicoAlvo p, {bool soPublicadas = true}) {
  final l = gestao.instrucoes.where((i) => i.publico == p && (!soPublicadas || i.publicada)).toList();
  if (l.isEmpty) return const Text('Ainda não há instruções para este público.');
  return Column(children: [
    for (final i in l)
      Card(
        child: ExpansionTile(
          title: Text(i.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var n = 0; n < i.passos.length; n++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 11,
                    child: Text('${n + 1}', style: const TextStyle(fontSize: 11)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(i.passos[n])),
                ]),
              ),
            if (i.dica != null && i.dica!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_outline, size: 18, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(child: Text(i.dica!, style: const TextStyle(fontSize: 13))),
              ]),
            ],
          ],
        ),
      ),
  ]);
}

/// Abre o guia de uso em uma janela (ex.: botão "Como usar" na página do cliente).
void abrirGuiaDeUso(BuildContext c, PublicoAlvo p) {
  showDialog<void>(
    context: c,
    builder: (d) => AlertDialog(
      title: const Text('Como usar'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: guiaDeUso(d, p))),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Fechar'))],
    ),
  );
}

/// Página somente de leitura com o guia de uso (painel do auxiliar).
class PaginaGuiaDeUso extends StatelessWidget {
  const PaginaGuiaDeUso(this.publico, {super.key});

  final PublicoAlvo publico;

  @override
  Widget build(BuildContext context) => Obs((c) => Pagina(
        titulo: 'Instruções de uso',
        sub: 'Passo a passo das principais tarefas. Toque em um título para abrir.',
        filhos: [guiaDeUso(c, publico)],
      ));
}

/// Página do administrador: elaborar, editar, publicar e copiar as instruções de uso.
class PaginaInstrucoes extends StatelessWidget {
  const PaginaInstrucoes({super.key});

  void _editar(BuildContext c, [Instrucao? i]) {
    final titulo = TextEditingController(text: i?.titulo);
    final passos = TextEditingController(text: i?.passos.join('\n'));
    final dica = TextEditingController(text: i?.dica);
    var publico = i?.publico ?? PublicoAlvo.auxiliar;
    var publicada = i?.publicada ?? true;
    String? erro;
    showDialog<void>(
      context: c,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(i == null ? 'Nova instrução' : 'Editar instrução'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: titulo, decoration: decoracaoCampo('Título')),
                const SizedBox(height: 12),
                seletor<PublicoAlvo>('Para quem', publico, PublicoAlvo.values,
                    (v) => set(() => publico = v!), (p) => p.rotulo),
                const SizedBox(height: 12),
                TextField(
                  controller: passos,
                  maxLines: 8,
                  decoration: decoracaoCampo('Passos (um por linha)'),
                ),
                const SizedBox(height: 12),
                TextField(controller: dica, decoration: decoracaoCampo('Dica (opcional)')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Publicar para os usuários'),
                  value: publicada,
                  onChanged: (v) => set(() => publicada = v),
                ),
                if (erro != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(erro!, style: TextStyle(color: Theme.of(d).colorScheme.error)),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final lista = passos.text
                    .split('\n')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
                if (titulo.text.trim().length < 3 || lista.isEmpty) {
                  set(() => erro = 'Informe o título e pelo menos um passo.');
                  return;
                }
                final dc = dica.text.trim();
                if (i == null) {
                  gestao.instrucoes.add(Instrucao(gestao.proximoId(), titulo.text.trim(), publico, lista,
                      dica: dc.isEmpty ? null : dc, publicada: publicada));
                  dados.log('Instrução criada: ${titulo.text.trim()} (${publico.rotulo})');
                } else {
                  i.titulo = titulo.text.trim();
                  i.publico = publico;
                  i.passos = lista;
                  i.dica = dc.isEmpty ? null : dc;
                  i.publicada = publicada;
                  i.atualizadaEm = DateTime.now();
                  dados.log('Instrução editada: ${i.titulo}');
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

  Future<void> _excluir(BuildContext c, Instrucao i) async {
    final ok = await confirmar(c, 'Excluir instrução?', i.titulo, rotulo: 'Excluir');
    if (!ok) return;
    gestao.instrucoes.remove(i);
    dados.log('Instrução excluída: ${i.titulo}');
  }

  @override
  Widget build(BuildContext context) => Obs((c) => Pagina(
        titulo: 'Instruções de uso',
        sub: 'Elabore os guias passo a passo para cada público. Os guias publicados aparecem para auxiliares (menu "Instruções de uso") e para clientes (botão "Como usar"). Já deixei um manual inicial pronto: edite como preferir.',
        acoes: [
          FilledButton.icon(
              onPressed: () => _editar(c), icon: const Icon(Icons.add), label: const Text('Nova instrução')),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: gestao.manualEmTexto()));
              msg(c, 'Manual copiado. Cole em um documento para imprimir ou compartilhar.');
            },
            icon: const Icon(Icons.copy_all),
            label: const Text('Copiar manual'),
          ),
        ],
        filhos: [
          for (final p in PublicoAlvo.values) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(p.rotulo, style: Theme.of(c).textTheme.titleMedium),
            ),
            for (final i in gestao.instrucoes.where((x) => x.publico == p))
              Card(
                child: ExpansionTile(
                  title: Text(i.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Wrap(spacing: 8, children: [
                    i.publicada
                        ? chipRotulo('Publicada', Colors.green, icone: Icons.public)
                        : chipRotulo('Rascunho', Colors.grey, icone: Icons.edit_note),
                    Text('Atualizada em ${formatarData(i.atualizadaEm)}', style: const TextStyle(fontSize: 12)),
                  ]),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var n = 0; n < i.passos.length; n++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text('${n + 1}. ${i.passos[n]}'),
                      ),
                    if (i.dica != null && i.dica!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('Dica: ${i.dica}', style: const TextStyle(fontStyle: FontStyle.italic)),
                    ],
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      TextButton.icon(
                          onPressed: () => _editar(c, i),
                          icon: const Icon(Icons.edit),
                          label: const Text('Editar')),
                      TextButton.icon(
                        onPressed: () {
                          i.publicada = !i.publicada;
                          i.atualizadaEm = DateTime.now();
                          dados.log('Instrução "${i.titulo}" ${i.publicada ? 'publicada' : 'despublicada'}');
                        },
                        icon: Icon(i.publicada ? Icons.visibility_off : Icons.public),
                        label: Text(i.publicada ? 'Despublicar' : 'Publicar'),
                      ),
                      TextButton.icon(
                          onPressed: () => _excluir(c, i),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Excluir')),
                    ]),
                  ],
                ),
              ),
          ],
        ],
      ));
}

// ───── gestao/orientar_usuarios.dart ─────
/// Faixa no topo do painel/página do usuário com as orientações da clínica ainda não lidas.
class FaixaOrientacoes extends StatelessWidget {
  const FaixaOrientacoes({
    super.key,
    required this.publico,
    required this.usuario,
    this.margem = const EdgeInsets.fromLTRB(12, 0, 12, 8),
  });

  final PublicoAlvo publico;
  final Usuario usuario;
  final EdgeInsets margem;

  void _abrir(BuildContext c, List<Orientacao> pend) {
    showDialog<void>(
      context: c,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.campaign_outlined, color: Colors.orange, size: 36),
        title: const Text('Orientações da clínica'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final o in pend) ...[
                Text(o.titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(o.texto),
                const SizedBox(height: 16),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Ver depois')),
          FilledButton(
            onPressed: () {
              for (final o in pend) {
                o.cientes.add(usuario.id);
              }
              dados.log('Orientação lida: ${pend.map((o) => o.titulo).join('; ')}', null, usuario.nome);
              Navigator.pop(d);
            },
            child: const Text('Ciente'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Obs((c) {
        final pend = gestao.pendentesPara(publico, usuario);
        if (pend.isEmpty) return const SizedBox.shrink();
        return Card(
          color: Colors.orange.withAlpha(40),
          margin: margem,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _abrir(c, pend),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(children: [
                const Icon(Icons.campaign_outlined, color: Colors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pend.length == 1
                        ? 'Orientação da clínica: ${pend.first.titulo}'
                        : '${pend.length} orientações da clínica: ${pend.first.titulo} e mais ${pend.length - 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                TextButton(onPressed: () => _abrir(c, pend), child: const Text('Ver')),
              ]),
            ),
          ),
        );
      });
}

class PaginaOrientarUsuarios extends StatefulWidget {
  const PaginaOrientarUsuarios({super.key});

  @override
  State<PaginaOrientarUsuarios> createState() => _PaginaOrientarUsuariosState();
}

class _PaginaOrientarUsuariosState extends State<PaginaOrientarUsuarios> {
  final _titulo = TextEditingController();
  final _texto = TextEditingController();
  final _publicos = <PublicoAlvo>{PublicoAlvo.auxiliar};
  int _validadeDias = 7; // 0 = sem prazo
  String? _erro;

  static const _modelos = [
    ('Check-in na chegada', PublicoAlvo.cliente, 'Faça o check-in ao chegar',
        'Ao chegar, informe o seu nome na recepção para fazer o check-in e receber a sua senha. Quem faz check-in não é marcado como ausente.'),
    ('Regra de 24h', PublicoAlvo.cliente, 'Remarcar e cancelar só até 24h antes',
        'Remarcações e cancelamentos precisam ser feitos com pelo menos 24 horas de antecedência. Depois disso, fale com a clínica.'),
    ('Situação do cliente', PublicoAlvo.auxiliar, 'Confira a situação do cliente',
        'Antes de iniciar um atendimento, confira a situação do cliente (faltas e bloqueio) e a confirmação do agendamento. Em caso de dúvida, chame o Administrador.'),
    ('Antes de fechar o caixa', PublicoAlvo.auxiliar, 'Antes de fechar o caixa',
        'Conclua os atendimentos em andamento, vincule os lançamentos sem vínculo e confira Pix, débito e crédito antes de fechar o caixa do dia.'),
  ];

  @override
  void dispose() {
    _titulo.dispose();
    _texto.dispose();
    super.dispose();
  }

  void _publicar() {
    final t = _titulo.text.trim();
    final x = _texto.text.trim();
    if (t.length < 3 || x.length < 10 || _publicos.isEmpty) {
      setState(() => _erro = 'Informe o título, um texto com pelo menos 10 caracteres e para quem é.');
      return;
    }
    final valida = _validadeDias == 0 ? null : DateTime.now().add(Duration(days: _validadeDias));
    gestao.orientacoes.insert(
      0,
      Orientacao(
          id: gestao.proximoId(),
          titulo: t,
          texto: x,
          publicos: Set.of(_publicos),
          autor: admLogin,
          validaAte: valida),
    );
    dados.log('Orientação publicada para ${_publicos.map((p) => p.rotulo).join(' e ')}: $t');
    _titulo.clear();
    _texto.clear();
    setState(() => _erro = null);
    msg(context, 'Orientação publicada. Ela aparece no painel dos usuários até eles marcarem "Ciente".');
  }

  @override
  Widget build(BuildContext context) => Obs((c) {
        return Pagina(
          titulo: 'Orientar usuários',
          sub: 'Publique orientações curtas para auxiliares e clientes. Elas aparecem numa faixa no topo do painel (ou da página do cliente) até a pessoa marcar "Ciente", e você acompanha quem já leu.',
          filhos: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Nova orientação', style: Theme.of(c).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('Modelos prontos', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    for (final m in _modelos)
                      ActionChip(
                        label: Text(m.$1),
                        onPressed: () => setState(() {
                          _titulo.text = m.$3;
                          _texto.text = m.$4;
                          _publicos
                            ..clear()
                            ..add(m.$2);
                        }),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(controller: _titulo, decoration: decoracaoCampo('Título')),
                  const SizedBox(height: 12),
                  TextField(controller: _texto, maxLines: 3, decoration: decoracaoCampo('Orientação')),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, children: [
                    for (final p in [PublicoAlvo.auxiliar, PublicoAlvo.cliente])
                      FilterChip(
                        label: Text(p.rotulo),
                        selected: _publicos.contains(p),
                        onSelected: (v) => setState(() => v ? _publicos.add(p) : _publicos.remove(p)),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 260,
                    child: seletor<int>('Validade', _validadeDias, const [7, 30, 0],
                        (v) => setState(() => _validadeDias = v!),
                        (d) => d == 0 ? 'Sem prazo' : '$d dias'),
                  ),
                  if (_erro != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_erro!, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _publicar,
                    icon: const Icon(Icons.campaign_outlined),
                    label: const Text('Publicar orientação'),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Text('Orientações publicadas', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (gestao.orientacoes.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Nenhuma orientação publicada.'))),
            for (final o in gestao.orientacoes) _cartaoOrientacao(c, o),
          ],
        );
      });

  Widget _cartaoOrientacao(BuildContext c, Orientacao o) {
    final dest = gestao.destinatarios(o).toList();
    final leram = dest.where((u) => o.cientes.contains(u.id)).length;
    final Widget status = o.encerrada
        ? chipRotulo('Encerrada', Colors.grey, icone: Icons.block)
        : o.vencida
            ? chipRotulo('Vencida', Colors.grey, icone: Icons.schedule)
            : chipRotulo('Vigente', Colors.green, icone: Icons.campaign_outlined);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(o.titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            status,
            for (final p in o.publicos) chipRotulo(p.rotulo, Colors.indigo),
          ]),
          const SizedBox(height: 6),
          Text(o.texto),
          const SizedBox(height: 8),
          Text(
            'Publicada em ${formatarData(o.criadaEm)} por ${o.autor}'
            '${o.validaAte == null ? ' • sem prazo' : ' • válida até ${formatarData(o.validaAte!)}'}'
            ' • Cientes: $leram de ${dest.length}',
            style: const TextStyle(fontSize: 12),
          ),
          if (!o.encerrada && !o.vencida) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () {
                o.encerrada = true;
                dados.log('Orientação encerrada: ${o.titulo}');
              },
              icon: const Icon(Icons.block),
              label: const Text('Encerrar'),
            ),
          ] else if (o.encerrada) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () {
                o.encerrada = false;
                dados.log('Orientação reaberta: ${o.titulo}');
              },
              icon: const Icon(Icons.replay),
              label: const Text('Reabrir'),
            ),
          ],
        ]),
      ),
    );
  }
}