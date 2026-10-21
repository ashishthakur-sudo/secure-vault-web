import 'package:flutter/material.dart';
import 'auth/auth_screen.dart';
import 'home/vault_screen.dart';
import 'services/auth_service.dart';
import 'services/vault_service.dart';

class SecureVaultApp extends StatefulWidget {
  const SecureVaultApp({super.key});

  @override
  State<SecureVaultApp> createState() => _SecureVaultAppState();
}

class _SecureVaultAppState extends State<SecureVaultApp> {
  final _authService = AuthService();
  final _vaultService = VaultService();
  bool _loading = true;
  bool _isSetup = false;
  bool? _decoyMode;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    final configured = await _authService.isConfigured();
    if (!mounted) return;
    setState(() {
      _isSetup = !configured;
      _loading = false;
    });
  }

  Future<void> _authenticate(String password, AuthResult result) async {
    if (result == AuthResult.master) {
      await _vaultService.unlock(password);
    }
    if (!mounted) return;
    setState(() => _decoyMode = result == AuthResult.decoy);
  }

  Future<void> _createVault(String password, {String? decoyPin}) async {
    await _vaultService.create(password);
    await _authService.configure(password, decoyPin: decoyPin);
    if (!mounted) return;
    setState(() {
      _isSetup = false;
      _decoyMode = false;
    });
  }

  Future<void> _lock() async {
    await _vaultService.lock();
    if (!mounted) return;
    setState(() => _decoyMode = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Secure Vault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4055A8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _decoyMode != null
              ? VaultScreen(
                  vault: _vaultService,
                  decoyMode: _decoyMode!,
                  onLock: _lock,
                )
              : AuthScreen(
                  isSetup: _isSetup,
                  authService: _authService,
                  onAuthenticate: _authenticate,
                  onCreateVault: _createVault,
                ),
    );
  }
}
