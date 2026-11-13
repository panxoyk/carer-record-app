import 'package:flutter/material.dart';

import '../../../core/design_system/clinical_design_system.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_providers.dart';
import '../../../core/design_system/clinical_toast.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _passwordVisible = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
    title: 'Carer-Record',
    subtitle: 'Sistema de trazabilidad clínica',
    footer: const Padding(
      padding: EdgeInsets.fromLTRB(24, ClinicalSpacing.section, 24, 0),
      child: Column(
        children: [
          Text(
            '¿No tienes acceso? Contacta al administrador de tu institución.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: ClinicalColors.secondary),
          ),
          SizedBox(height: ClinicalSpacing.section),
          Text(
            'Uso exclusivo personal clínico autorizado',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: ClinicalColors.tertiary),
          ),
        ],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Iniciar sesión', style: ClinicalTextStyles.pageTitle),
        const SizedBox(height: ClinicalSpacing.compact),
        const Text(
          'Accede con tus credenciales institucionales',
          style: TextStyle(fontSize: 15, color: ClinicalColors.secondary),
        ),
        const SizedBox(height: 20),
        const ExcludeSemantics(child: _AuthFieldLabel('Correo institucional')),
        Semantics(
          label: 'Correo electrónico',
          child: TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username],
            decoration: clinicalInputDecoration(
              prefixIcon: const Icon(
                Icons.person_outline_rounded,
                color: ClinicalColors.tertiary,
              ),
            ),
          ),
        ),
        const SizedBox(height: ClinicalSpacing.card),
        const ExcludeSemantics(child: _AuthFieldLabel('Contraseña')),
        Semantics(
          label: 'Contraseña',
          child: TextField(
            controller: _password,
            obscureText: !_passwordVisible,
            autofillHints: const [AutofillHints.password],
            decoration: clinicalInputDecoration(
              prefixIcon: const Icon(
                Icons.lock_outline_rounded,
                color: ClinicalColors.tertiary,
              ),
              suffixIcon: IconButton(
                tooltip: _passwordVisible
                    ? 'Ocultar contraseña'
                    : 'Mostrar contraseña',
                onPressed: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
                icon: Icon(
                  _passwordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: ClinicalColors.tertiary,
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            onPressed: () => context.go('/recover'),
            child: const Text('¿Olvidaste tu contraseña?'),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: ClinicalSpacing.item),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: ClinicalSpacing.compact),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
            onPressed: _busy
                ? null
                : () async {
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    try {
                      await ref
                          .read(authRepositoryProvider)
                          .signIn(email: _email.text, password: _password.text);
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => _error = 'No fue posible acceder. Revisa tus credenciales.',
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            child: Text(_busy ? 'Accediendo…' : 'Iniciar sesión'),
          ),
        ),
      ],
    ),
  );
}

class _AuthFieldLabel extends StatelessWidget {
  const _AuthFieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: ClinicalSpacing.compact),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: .6,
        fontWeight: FontWeight.w600,
        color: ClinicalColors.secondary,
      ),
    ),
  );
}

class RecoverPasswordScreen extends ConsumerStatefulWidget {
  const RecoverPasswordScreen({super.key});
  @override
  ConsumerState<RecoverPasswordScreen> createState() =>
      _RecoverPasswordScreenState();
}

class _RecoverPasswordScreenState extends ConsumerState<RecoverPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _message;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
    title: 'Recuperar contraseña',
    child: Column(
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: clinicalInputDecoration(labelText: 'Correo electrónico'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() {
                    _busy = true;
                    _error = null;
                    _message = null;
                  });
                  try {
                    await ref
                        .read(authRepositoryProvider)
                        .sendPasswordRecovery(_email.text);
                    if (mounted) {
                      setState(
                        () => _message = 'Si el correo existe, recibirás las instrucciones de recuperación.',
                      );
                    }
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () => _error = 'No fue posible enviar las instrucciones. Inténtalo nuevamente.',
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: Text(_busy ? 'Enviando…' : 'Enviar instrucciones'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_message!),
          ),
        TextButton(
          onPressed: () => context.go('/login'),
          child: const Text('Volver a acceso'),
        ),
      ],
    ),
  );
}

class UpdatePasswordScreen extends ConsumerStatefulWidget {
  const UpdatePasswordScreen({super.key});
  @override
  ConsumerState<UpdatePasswordScreen> createState() =>
      _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends ConsumerState<UpdatePasswordScreen> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
    title: 'Definir nueva contraseña',
    child: Column(
      children: [
        TextField(
          controller: _password,
          obscureText: true,
          decoration: clinicalInputDecoration(
            labelText: 'Nueva contraseña (mínimo 6 caracteres)',
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  if (_password.text.length < 6) {
                    setState(
                      () => _error =
                          'La contraseña debe tener al menos 6 caracteres.',
                    );
                    return;
                  }
                  setState(() {
                    _busy = true;
                    _error = null;
                  });
                  final messengerContext = context;
                  try {
                    await ref
                        .read(authRepositoryProvider)
                        .updatePassword(_password.text);
                    if (!mounted) return;
                    ref.read(authGateProvider).finishPasswordRecovery();
                    if (messengerContext.mounted) {
                      ClinicalToast.success(
                        messengerContext,
                        message: 'Contraseña actualizada.',
                      );
                      messengerContext.go('/');
                    }
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () =>
                            _error = 'No fue posible actualizar la contraseña.',
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          child: Text(_busy ? 'Guardando…' : 'Guardar contraseña'),
        ),
      ],
    ),
  );
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
  });
  final String title;
  final Widget child;
  final String? subtitle;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: ClinicalBrandMark(size: 64)),
                      const SizedBox(height: ClinicalSpacing.card),
                      Text(
                        subtitle == null ? 'Carer-Record' : title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: ClinicalColors.ink,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: ClinicalColors.secondary,
                          ),
                        ),
                      ],
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 20, 24, 20),
                        child: Divider(height: 1),
                      ),
                      if (subtitle == null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            title,
                            style: ClinicalTextStyles.pageTitle,
                          ),
                        ),
                        const SizedBox(height: ClinicalSpacing.section),
                      ],
                      ClinicalCard(
                        elevated: false,
                        padding: const EdgeInsets.symmetric(
                          horizontal: ClinicalSpacing.section,
                        ),
                        child: child,
                      ),
                      ?footer,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Símbolo de Carer-Record: cuadrado mint redondeado con un check.
class ClinicalBrandMark extends StatelessWidget {
  const ClinicalBrandMark({this.size = 72, super.key});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ClinicalColors.mint,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        Icons.check_rounded,
        size: size * 0.55,
        color: ClinicalColors.ink.withValues(alpha: .9),
      ),
    ),
  );
}
