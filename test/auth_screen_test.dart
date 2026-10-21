import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/src/auth/auth_screen.dart';
import 'package:secure_vault/src/services/auth_service.dart';

void main() {
  testWidgets('password visibility can be toggled on the unlock screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          isSetup: false,
          authService: AuthService(),
          onAuthenticate: (password, result) async {},
          onCreateVault: (password, {String? decoyPin}) async {},
        ),
      ),
    );

    final passwordFinder = find.descendant(
      of: find.byType(TextFormField).first,
      matching: find.byType(EditableText),
    );
    var passwordField = tester.widget<EditableText>(passwordFinder);
    expect(passwordField.obscureText, isTrue);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();

    passwordField = tester.widget<EditableText>(passwordFinder);
    expect(passwordField.obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });
}
