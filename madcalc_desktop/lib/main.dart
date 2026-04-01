import 'package:flutter/widgets.dart';

import 'app.dart';
import 'controllers/madcalc_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await MadCalcController.create();
  runApp(MadCalcApp(controller: controller));
}
