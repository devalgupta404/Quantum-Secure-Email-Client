import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/app.dart';

void main() {
  testWidgets('App boots to Inbox screen', (WidgetTester tester) async {
    await tester.pumpWidget(const QuMailApp());
    expect(find.widgetWithText(AppBar, 'Inbox'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('No messages yet'), findsOneWidget);
  });
}
