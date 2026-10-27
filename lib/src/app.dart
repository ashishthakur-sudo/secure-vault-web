import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/cloud_auth_screen.dart';
import 'auth/auth_screen.dart';
import 'home/vault_screen.dart';
import 'services/auth_service.dart';
import 'services/vault_service.dart';

class SecureVaultApp extends StatefulWidget {
  const SecureVaultApp({required this.supabaseConfigured, super.key});

  final bool supabaseConfigured;

  @override
  State<SecureVaultApp> createState() => _SecureVaultAppState();
}

class _SecureVaultAppState extends State<SecureVaultApp> {
  AuthService? _authService;
  final _vaultService = VaultService();
  bool _loading = true;
  bool _isSetup = false;
  bool _cloudAuthenticated = false;
  bool? _decoyMode;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    if (!widget.supabaseConfigured) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _cloudAuthenticated = false;
          _loading = false;
        });
      }
      return;
    }
    final authService = AuthService(userId: userId);
    final configured = await authService.isConfigured();
    if (!mounted) return;
    setState(() {
      _authService = authService;
      _cloudAuthenticated = true;
      _isSetup = !configured;
      _loading = false;
    });
  }

  Future<void> _onCloudAuthenticated() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError(
        'Cloud sign-in completed without an authenticated user.',
      );
    }
    final authService = AuthService(userId: userId);
    final configured = await authService.isConfigured();
    if (!mounted) return;
    setState(() {
      _authService = authService;
      _cloudAuthenticated = true;
      _isSetup = !configured;
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
    final authService = _authService;
    if (authService == null) {
      throw StateError(
        'Sign in to your cloud account before creating a vault.',
      );
    }
    await authService.configure(password, decoyPin: decoyPin);
    if (!mounted) return;
    setState(() {
      _isSetup = false;
      _decoyMode = false;
    });
  }

  Future<void> _resetVault() async {
    final authService = _authService;
    if (authService == null) {
      throw StateError(
        'Sign in to your cloud account before resetting the vault.',
      );
    }
    await _vaultService.reset();
    await authService.clearCredentials();
    if (!mounted) return;
    setState(() {
      _isSetup = true;
      _decoyMode = null;
    });
  }

  Future<void> _lock() async {
    await _vaultService.lock();
    if (!mounted) return;
    setState(() => _decoyMode = null);
  }

  Future<void> _signOut() async {
    await _vaultService.lock();
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    setState(() {
      _authService = null;
      _cloudAuthenticated = false;
      _decoyMode = null;
    });
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
          : !widget.supabaseConfigured
          ? const _CloudConfigurationRequired()
          : !_cloudAuthenticated
          ? CloudAuthScreen(onAuthenticated: _onCloudAuthenticated)
          : _decoyMode != null
          ? VaultScreen(
              vault: _vaultService,
              decoyMode: _decoyMode!,
              onLock: _lock,
              onSignOut: _signOut,
            )
          : AuthScreen(
              isSetup: _isSetup,
              authService: _authService!,
              onAuthenticate: _authenticate,
              onCreateVault: _createVault,
              onResetVault: _resetVault,
            ),
    );
  }
}

class _CloudConfigurationRequired extends StatelessWidget {
  const _CloudConfigurationRequired();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: const Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 56),
              SizedBox(height: 16),
              Text(
                'Configure your Supabase project',
                style: TextStyle(fontSize: 22),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                'Add SUPABASE_URL and SUPABASE_ANON_KEY to your local .env file, apply the database migrations with `supabase db push`, then restart the app. Never use a service-role key in the client.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
