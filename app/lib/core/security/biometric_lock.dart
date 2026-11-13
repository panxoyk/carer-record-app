import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../domains/auth/presentation/auth_providers.dart';
import '../../domains/auth/presentation/sign_out_action.dart';
import '../design_system/clinical_design_system.dart';

/// Device biometrics (Face ID, Touch ID or fingerprint) through `local_auth`.
abstract interface class BiometricAuthenticator {
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason);
}

class LocalBiometricAuthenticator implements BiometricAuthenticator {
  LocalBiometricAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (ref) => LocalBiometricAuthenticator(),
);

/// Optional biometric lock of an already signed-in session. The preference
/// lives in the device keystore; no password or token is stored by the app.
class BiometricLockController extends ChangeNotifier {
  BiometricLockController(this._authenticator, {FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'carer_record.biometric_lock';
  final BiometricAuthenticator _authenticator;
  final FlutterSecureStorage _storage;
  bool _enabled = false;
  bool _locked = false;
  bool _loaded = false;

  bool get enabled => _enabled;
  bool get locked => _enabled && _locked;
  bool get loaded => _loaded;

  /// Reads the preference once; a cold start with the lock enabled starts
  /// locked.
  Future<void> load() async {
    if (_loaded) return;
    try {
      _enabled = await _storage.read(key: _key) == 'true';
    } catch (_) {
      _enabled = false;
    }
    _locked = _enabled;
    _loaded = true;
    notifyListeners();
  }

  /// Enabling requires a successful biometric check first.
  Future<bool> setEnabled(bool value) async {
    if (value) {
      if (!await _authenticator.isAvailable()) return false;
      if (!await _authenticator.authenticate(
        'Confirma tu identidad para activar el acceso biométrico',
      )) {
        return false;
      }
    }
    try {
      await _storage.write(key: _key, value: value.toString());
    } catch (_) {
      return false;
    }
    _enabled = value;
    _locked = false;
    notifyListeners();
    return true;
  }

  void lock() {
    if (!_enabled || _locked) return;
    _locked = true;
    notifyListeners();
  }

  Future<bool> unlock() async {
    final ok = await _authenticator.authenticate(
      'Accede a Carer-Record con tu biometría',
    );
    if (ok) {
      _locked = false;
      notifyListeners();
    }
    return ok;
  }

  /// Used when the user signs out from the lock screen.
  void release() {
    _locked = false;
    notifyListeners();
  }
}

final biometricLockProvider = ChangeNotifierProvider<BiometricLockController>(
  (ref) =>
      BiometricLockController(ref.watch(biometricAuthenticatorProvider))
        ..load(),
);

/// Shows the lock screen over the app while a restored session is locked.
/// The app locks again whenever it goes to the background.
class BiometricLockGate extends ConsumerStatefulWidget {
  const BiometricLockGate({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<BiometricLockGate> createState() => _BiometricLockGateState();
}

class _BiometricLockGateState extends ConsumerState<BiometricLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ref.read(biometricLockProvider).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(biometricLockProvider);
    final session = ref.watch(sessionProvider);
    final locked = session != null && lock.locked;
    return Stack(
      children: [
        widget.child,
        if (locked) const Positioned.fill(child: BiometricLockScreen()),
      ],
    );
  }
}

class BiometricLockScreen extends ConsumerStatefulWidget {
  const BiometricLockScreen({super.key});

  @override
  ConsumerState<BiometricLockScreen> createState() =>
      _BiometricLockScreenState();
}

class _BiometricLockScreenState extends ConsumerState<BiometricLockScreen> {
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await ref.read(biometricLockProvider).unlock();
    if (mounted) {
      setState(() {
        _busy = false;
        _failed = !ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: ClinicalColors.mint,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 40,
                  color: ClinicalColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Carer-Record',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Sesión protegida',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: ClinicalColors.secondary),
            ),
            const SizedBox(height: 40),
            Center(
              child: Icon(
                Icons.fingerprint_rounded,
                size: 56,
                color: _failed
                    ? ClinicalColors.destructive
                    : ClinicalColors.mintDark,
              ),
            ),
            if (_failed)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'No se pudo verificar tu identidad. Inténtalo de nuevo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ClinicalColors.destructive),
                ),
              ),
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
              onPressed: _busy ? null : _unlock,
              icon: const Icon(Icons.face_retouching_natural),
              label: const Text('Acceder con Face ID / huella'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      ref.read(biometricLockProvider).release();
                      await signOutAction(context, ref);
                    },
              child: const Text('Usar contraseña'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Uso exclusivo personal clínico autorizado',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: ClinicalColors.tertiary),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}
