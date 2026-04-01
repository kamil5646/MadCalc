import 'package:flutter_test/flutter_test.dart';

import 'package:madcalc_desktop/app.dart';
import 'package:madcalc_desktop/controllers/madcalc_controller.dart';

void main() {
  testWidgets('MadCalc renders main title', (WidgetTester tester) async {
    final controller = MadCalcController();

    await tester.pumpWidget(MadCalcApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('MadCalc'), findsWidgets);
    expect(find.text('Dodaj element'), findsWidgets);
  });
}
