import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

/// Áreas disponíveis no app.
enum Area { estetica, psicologia }

extension AreaInfo on Area {
  String get nome => this == Area.estetica ? 'Estética' : 'Psicologia';

  IconData get icone => this == Area.estetica ? Icons.spa : Icons.psychology;

  Color get cor => this == Area.estetica
      ? const Color(0xFFD81B7A) // rosa
      : const Color(0xFF3F7CAC); // azul

  Color get corClara => this == Area.estetica
      ? const Color(0xFFFFE3F0)
      : const Color(0xFFE0EEF8);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Estética & Psicologia',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6C5CE7),
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  Area? _areaSelecionada;

  @override
  Widget build(BuildContext context) {
    final area = _areaSelecionada;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: area == null
                ? [const Color(0xFFFFE3F0), const Color(0xFFE0EEF8)]
                : [area.corClara, Colors.white],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo da faculdade centralizada
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Image.asset(
                      'assets/logo_unipora.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 32),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: area == null
                        ? _EscolhaArea(
                            key: const ValueKey('escolha'),
                            onSelecionar: (a) =>
                                setState(() => _areaSelecionada = a),
                          )
                        : _FormularioLogin(
                            key: ValueKey(area),
                            area: area,
                            onVoltar: () =>
                                setState(() => _areaSelecionada = null),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tela inicial com os dois emblemas.
class _EscolhaArea extends StatelessWidget {
  const _EscolhaArea({super.key, required this.onSelecionar});

  final ValueChanged<Area> onSelecionar;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Bem-vindo(a)',
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Escolha sua área para entrar',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 40),
        Wrap(
          spacing: 40,
          runSpacing: 32,
          alignment: WrapAlignment.center,
          children: [
            _Emblema(area: Area.estetica, onTap: () => onSelecionar(Area.estetica)),
            _Emblema(
                area: Area.psicologia, onTap: () => onSelecionar(Area.psicologia)),
          ],
        ),
      ],
    );
  }
}

/// Emblema clicável (círculo com ícone + nome).
class _Emblema extends StatefulWidget {
  const _Emblema({required this.area, required this.onTap});

  final Area area;
  final VoidCallback onTap;

  @override
  State<_Emblema> createState() => _EmblemaState();
}

class _EmblemaState extends State<_Emblema> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final area = widget.area;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [area.cor.withOpacity(0.75), area.cor],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: area.cor.withOpacity(_hover ? 0.5 : 0.3),
                      blurRadius: _hover ? 28 : 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(area.icone, size: 72, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(
                area.nome,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: area.cor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Qual tela do fluxo de autenticação está aberta.
enum _Tela { login, cadastro, recuperar }

String? _validaEmail(String? v) {
  if (v == null || v.trim().isEmpty) return 'Informe seu e-mail';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) {
    return 'E-mail inválido';
  }
  return null;
}

InputDecoration _decoracao(String label, IconData icone, {Widget? sufixo}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icone),
    suffixIcon: sufixo,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );
}

class _BotaoPrincipal extends StatelessWidget {
  const _BotaoPrincipal({
    required this.texto,
    required this.cor,
    required this.carregando,
    required this.onPressed,
  });

  final String texto;
  final Color cor;
  final bool carregando;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: carregando ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: cor,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: carregando
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : Text(texto, style: const TextStyle(fontSize: 16)),
    );
  }
}

/// Cartão que alterna entre login, cadastro de cliente e recuperação de senha.
class _FormularioLogin extends StatefulWidget {
  const _FormularioLogin({super.key, required this.area, required this.onVoltar});

  final Area area;
  final VoidCallback onVoltar;

  @override
  State<_FormularioLogin> createState() => _FormularioLoginState();
}

class _FormularioLoginState extends State<_FormularioLogin> {
  _Tela _tela = _Tela.login;

  void _ir(_Tela t) => setState(() => _tela = t);

  String get _titulo {
    switch (_tela) {
      case _Tela.login:
        return 'Login ${widget.area.nome}';
      case _Tela.cadastro:
        return 'Cadastro de cliente';
      case _Tela.recuperar:
        return 'Recuperar senha';
    }
  }

  Widget get _conteudo {
    switch (_tela) {
      case _Tela.login:
        return _LoginForm(
          key: const ValueKey('login'),
          area: widget.area,
          onCadastro: () => _ir(_Tela.cadastro),
          onEsqueci: () => _ir(_Tela.recuperar),
        );
      case _Tela.cadastro:
        return _CadastroForm(
          key: const ValueKey('cadastro'),
          area: widget.area,
          onConcluido: () => _ir(_Tela.login),
        );
      case _Tela.recuperar:
        return _RecuperarSenhaForm(
          key: const ValueKey('recuperar'),
          area: widget.area,
          onVoltarLogin: () => _ir(_Tela.login),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final area = widget.area;
    final noLogin = _tela == _Tela.login;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Card(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: noLogin ? widget.onVoltar : () => _ir(_Tela.login),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(noLogin ? 'Voltar' : 'Voltar ao login'),
                ),
              ),
              const SizedBox(height: 8),
              CircleAvatar(
                radius: 36,
                backgroundColor: area.cor,
                child: Icon(area.icone, size: 38, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(
                _titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: area.cor),
              ),
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _conteudo,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Login (administrador e clientes).
class _LoginForm extends StatefulWidget {
  const _LoginForm({
    super.key,
    required this.area,
    required this.onCadastro,
    required this.onEsqueci,
  });

  final Area area;
  final VoidCallback onCadastro;
  final VoidCallback onEsqueci;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  bool _ocultarSenha = true;
  bool _carregando = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _senhaCtrl.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _carregando = true);

    // TODO: autenticação real (Firebase, API própria etc.).
    // O backend deve devolver o perfil (administrador ou cliente)
    // para você direcionar à tela certa.
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;
    setState(() => _carregando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Login de ${widget.area.nome} realizado!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cor = widget.area.cor;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: _decoracao('E-mail', Icons.email_outlined),
            validator: _validaEmail,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _senhaCtrl,
            obscureText: _ocultarSenha,
            decoration: _decoracao(
              'Senha',
              Icons.lock_outline,
              sufixo: IconButton(
                icon: Icon(
                    _ocultarSenha ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _ocultarSenha = !_ocultarSenha),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Informe sua senha';
              if (v.length < 6) return 'Mínimo de 6 caracteres';
              return null;
            },
            onFieldSubmitted: (_) => _entrar(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.onEsqueci,
              child: Text('Esqueci minha senha', style: TextStyle(color: cor)),
            ),
          ),
          const SizedBox(height: 8),
          _BotaoPrincipal(
            texto: 'Entrar',
            cor: cor,
            carregando: _carregando,
            onPressed: _entrar,
          ),
          const SizedBox(height: 16),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('É cliente e ainda não tem conta?'),
              TextButton(
                onPressed: widget.onCadastro,
                child: Text('Cadastre-se',
                    style: TextStyle(color: cor, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cadastro de cliente.
class _CadastroForm extends StatefulWidget {
  const _CadastroForm({
    super.key,
    required this.area,
    required this.onConcluido,
  });

  final Area area;
  final VoidCallback onConcluido;

  @override
  State<_CadastroForm> createState() => _CadastroFormState();
}

class _CadastroFormState extends State<_CadastroForm> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefoneCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  final _confirmaCtrl = TextEditingController();
  bool _ocultarSenha = true;
  bool _carregando = false;

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _emailCtrl.dispose();
    _telefoneCtrl.dispose();
    _senhaCtrl.dispose();
    _confirmaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cadastrar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _carregando = true);

    // TODO: criar a conta no backend sempre com perfil "cliente".
    // Contas de administrador devem ser criadas somente por você.
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;
    setState(() => _carregando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cadastro realizado! Faça seu login.')),
    );
    widget.onConcluido();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nomeCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _decoracao('Nome completo', Icons.person_outline),
            validator: (v) => (v == null || v.trim().length < 3)
                ? 'Informe seu nome completo'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: _decoracao('E-mail', Icons.email_outlined),
            validator: _validaEmail,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _telefoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: _decoracao('Telefone / WhatsApp', Icons.phone_outlined),
            validator: (v) {
              final digitos = (v ?? '').replaceAll(RegExp(r'\D'), '');
              return digitos.length < 10 ? 'Informe um telefone válido' : null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _senhaCtrl,
            obscureText: _ocultarSenha,
            decoration: _decoracao(
              'Senha',
              Icons.lock_outline,
              sufixo: IconButton(
                icon: Icon(
                    _ocultarSenha ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _ocultarSenha = !_ocultarSenha),
              ),
            ),
            validator: (v) =>
                (v == null || v.length < 6) ? 'Mínimo de 6 caracteres' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmaCtrl,
            obscureText: _ocultarSenha,
            decoration: _decoracao('Confirmar senha', Icons.lock_reset),
            validator: (v) =>
                v != _senhaCtrl.text ? 'As senhas não conferem' : null,
            onFieldSubmitted: (_) => _cadastrar(),
          ),
          const SizedBox(height: 24),
          _BotaoPrincipal(
            texto: 'Criar conta',
            cor: widget.area.cor,
            carregando: _carregando,
            onPressed: _cadastrar,
          ),
        ],
      ),
    );
  }
}

/// Recuperação de senha por e-mail.
class _RecuperarSenhaForm extends StatefulWidget {
  const _RecuperarSenhaForm({
    super.key,
    required this.area,
    required this.onVoltarLogin,
  });

  final Area area;
  final VoidCallback onVoltarLogin;

  @override
  State<_RecuperarSenhaForm> createState() => _RecuperarSenhaFormState();
}

class _RecuperarSenhaFormState extends State<_RecuperarSenhaForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _carregando = false;
  bool _enviado = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _carregando = true);

    // TODO: dispare o e-mail de redefinição no backend.
    // Ex. com Firebase Auth:
    // await FirebaseAuth.instance.sendPasswordResetEmail(email: _emailCtrl.text.trim());
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;
    setState(() {
      _carregando = false;
      _enviado = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cor = widget.area.cor;

    if (_enviado) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.mark_email_read_outlined, size: 56, color: cor),
          const SizedBox(height: 16),
          Text(
            'Se o e-mail ${_emailCtrl.text.trim()} estiver cadastrado, '
            'você receberá em instantes um link para criar uma nova senha. '
            'Confira também a caixa de spam.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _BotaoPrincipal(
            texto: 'Voltar ao login',
            cor: cor,
            carregando: false,
            onPressed: widget.onVoltarLogin,
          ),
        ],
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Informe o e-mail da sua conta e enviaremos um link para '
            'redefinir sua senha.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: _decoracao('E-mail', Icons.email_outlined),
            validator: _validaEmail,
            onFieldSubmitted: (_) => _enviar(),
          ),
          const SizedBox(height: 24),
          _BotaoPrincipal(
            texto: 'Enviar link de recuperação',
            cor: cor,
            carregando: _carregando,
            onPressed: _enviar,
          ),
        ],
      ),
    );
  }
}