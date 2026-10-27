import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    required this.isSetup,
    required this.authService,
    required this.onAuthenticate,
    required this.onCreateVault,
    required this.onResetVault,
    super.key,
  });

  final bool isSetup;
  final AuthService authService;
  final Future<void> Function(String password, AuthResult result)
  onAuthenticate;
  final Future<void> Function(String password, {String? decoyPin})
  onCreateVault;
  final Future<void> Function() onResetVault;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _decoyPin = TextEditingController();
  bool _enableDecoy = false;
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _decoyPin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.isSetup) {
        await widget.onCreateVault(
          _password.text,
          decoyPin: _enableDecoy ? _decoyPin.text : null,
        );
      } else {
        final result = await widget.authService.authenticate(_password.text);
        if (result == AuthResult.rejected) {
          setState(() => _error = 'Incorrect password or PIN.');
        } else {
          await widget.onAuthenticate(_password.text, result);
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Unable to open the vault: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetVault() async {
    final user = Supabase.instance.client.auth.currentUser;
    final phone = user?.phone;
    final email = user?.email;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final phoneAccount = phone != null && phone.isNotEmpty;
    final recipient = phoneAccount ? phone : email;
    if (recipient == null || userId == null) {
      setState(
        () => _error = 'Sign in to your cloud account before resetting.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset vault password or PIN?'),
        content: const Text(
          'We will send a one-time verification code to confirm this reset. Resetting permanently deletes this account’s vault metadata and encrypted files on this device. Your old password cannot be recovered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (phoneAccount) {
        await auth.signInWithOtp(
          phone: phone,
          shouldCreateUser: false,
          channel: OtpChannel.whatsapp,
        );
      } else {
        await auth.signInWithOtp(email: email, shouldCreateUser: false);
      }
      if (!mounted) return;
      final code = await _requestOtp(
        recipient,
        channel: phoneAccount ? 'WhatsApp' : 'email',
      );
      if (code == null || !mounted) return;
      final response = phoneAccount
          ? await auth.verifyOTP(phone: phone, token: code, type: OtpType.sms)
          : await auth.verifyOTP(
              email: email,
              token: code,
              type: OtpType.email,
            );
      if (response.user?.id != userId) {
        throw const AuthException(
          'The verification code did not confirm the signed-in account.',
        );
      }
      await widget.onResetVault();
      _password.clear();
      if (mounted) {
        setState(() => _error = 'Code confirmed. Create a new vault password.');
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Vault reset failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _requestOtp(
    String recipient, {
    required String channel,
  }) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Confirm your $channel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter the one-time code sent to $recipient.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: InputDecoration(labelText: '$channel code'),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.pop(context, value.trim());
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(context, value);
              },
              child: const Text('Verify code'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.lock_outline, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      widget.isSetup
                          ? 'Create your vault'
                          : 'Unlock your vault',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _password,
                      autofocus: true,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: widget.isSetup
                            ? 'Master password'
                            : 'Password or PIN',
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter a password.';
                        }
                        if (widget.isSetup && value.length < 10) {
                          return 'Use at least 10 characters.';
                        }
                        if (utf8.encode(value).length > 72) {
                          return 'Use no more than 72 UTF-8 bytes.';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (widget.isSetup) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirm,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm master password',
                        ),
                        validator: (value) => value != _password.text
                            ? 'Passwords do not match.'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable decoy PIN'),
                        subtitle: const Text(
                          'Opens a separate, empty, read-only vault.',
                        ),
                        value: _enableDecoy,
                        onChanged: (value) =>
                            setState(() => _enableDecoy = value),
                      ),
                      if (_enableDecoy)
                        TextFormField(
                          controller: _decoyPin,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Decoy PIN (4+ digits)',
                          ),
                          validator: (value) {
                            if (!_enableDecoy) return null;
                            if (value == null || value.length < 4) {
                              return 'Use at least 4 characters.';
                            }
                            if (utf8.encode(value).length > 72) {
                              return 'Use no more than 72 UTF-8 bytes.';
                            }
                            if (value == _password.text) {
                              return 'The decoy PIN must differ from the master password.';
                            }
                            return null;
                          },
                        ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(widget.isSetup ? 'Create vault' : 'Unlock'),
                    ),
                    if (!widget.isSetup) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : _resetVault,
                        child: const Text(
                          'Forgot password or PIN? Reset by email',
                        ),
                      ),
                    ],
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
