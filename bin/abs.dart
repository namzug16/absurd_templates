import 'package:abs/src/cli.dart';
import 'package:abs/src/vendor.dart';

Future<void> main(List<String> arguments) =>
    runAbs(arguments, vendor: vendorAbs);
