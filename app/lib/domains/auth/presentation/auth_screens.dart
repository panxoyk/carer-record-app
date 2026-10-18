import 'package:flutter/material.dart';

import '../../../core/design_system/clinical_design_system.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_providers.dart';

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
    title: 'Carer Record',
    subtitle: 'Contexto para el cuidado clínico',
    footer: const Column(
      children: [
        SizedBox(height: ClinicalSpacing.section),
        Text('¿No tienes acceso?'),
        SizedBox(height: ClinicalSpacing.compact),
        Text('Contacta al administrador de tu institución.'),
      ],
    ),
    child: ClinicalCard(
      padding: const EdgeInsets.all(ClinicalSpacing.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Iniciar sesión', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: ClinicalSpacing.compact),
          Text(
            'Ingresa con tu cuenta institucional.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: ClinicalSpacing.section),
          const ExcludeSemantics(child: _AuthFieldLabel('Correo electrónico')),
          Semantics(
            label: 'Correo electrónico',
            child: TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username],
              decoration: clinicalInputDecoration(),
            ),
          ),
          const SizedBox(height: ClinicalSpacing.item),
          const ExcludeSemantics(child: _AuthFieldLabel('Contraseña')),
          Semantics(
            label: 'Contraseña',
            child: TextField(
              controller: _password,
              obscureText: !_passwordVisible,
              autofillHints: const [AutofillHints.password],
              decoration: clinicalInputDecoration(
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
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
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
                            .signIn(
                              email: _email.text,
                              password: _password.text,
                            );
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
    ),
  );
}

class _AuthFieldLabel extends StatelessWidget {
  const _AuthFieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: ClinicalSpacing.compact),
    child: Text(label, style: Theme.of(context).textTheme.labelLarge),
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
          onPressed: () async {
            if (_password.text.length < 6) {
              setState(
                () =>
                    _error = 'La contraseña debe tener al menos 6 caracteres.',
              );
              return;
            }
            try {
              await ref
                  .read(authRepositoryProvider)
                  .updatePassword(_password.text);
              ref.read(authGateProvider).finishPasswordRecovery();
              if (context.mounted) context.go('/');
            } catch (_) {
              setState(
                () => _error = 'No fue posible actualizar la contraseña.',
              );
            }
          },
          child: const Text('Guardar contraseña'),
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
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(ClinicalSpacing.page),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: subtitle == null ? null : TextAlign.center,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: ClinicalSpacing.compact),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: ClinicalSpacing.section),
                      child,
                      if (footer != null) footer!,
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
