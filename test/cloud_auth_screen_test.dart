import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_vault/src/auth/cloud_auth_screen.dart';

Finder _fieldWithLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is InputDecorator && widget.decoration.labelText == label,
);

void main() {
  testWidgets('email sign-in is the default and phone OTP is not shown', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CloudAuthScreen(onAuthenticated: () async {})),
    );

    expect(_fieldWithLabel('Email'), findsOneWidget);
    expect(_fieldWithLabel('Account password'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Mobile number'), findsNothing);
    expect(find.text('Send WhatsApp code'), findsNothing);
  });

  testWidgets('new accounts use email and password without confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: CloudAuthScreen(onAuthenticated: () async {})),
    );

    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Create account'), findsOneWidget);
    expect(
      find.text(
        'Create an account with your email and password. '
        'Email confirmation is not required.',
      ),
      findsOneWidget,
    );
    expect(find.text('Already have an account? Sign in'), findsOneWidget);
    expect(find.text('Send WhatsApp code'), findsNothing);
  });
}
