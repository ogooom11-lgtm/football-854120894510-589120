import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:new_football/src/app/bomban_futbol_app.dart';

void main() {
  testWidgets('Bomban Futbol starts on setup screen', (tester) async {
    await tester.pumpWidget(const BombanFutbolApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
