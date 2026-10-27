import 'package:absurd_templates/src/cli.dart';
import 'package:absurd_templates/src/vendor.dart';

Future<void> main(List<String> arguments) =>
    runAbs(arguments, vendor: vendorAbs);
