import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carer_record_app/domains/auth/presentation/auth_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('renders the sign-in screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SignInScreen())),
    );
    expect(find.text('Acceder a Carer Record'), findsOneWidget);
  });
}
