import 'package:absurd_templates_benchmark/scenarios.dart';
import 'package:test/test.dart';

void main() {
  for (final scenario in loadScenarios()) {
    test('${scenario.name}: every engine renders the same HTML', () {
      final expectedHtml = withoutWhitespaceBetweenTags(
        scenario.renderByEngine['abs']!(),
      );
      expect(expectedHtml, contains('User 1 &lt;Ada &amp; Grace&gt;'));
      for (final engineName in engineNames.skip(1)) {
        expect(
          withoutWhitespaceBetweenTags(scenario.renderByEngine[engineName]!()),
          expectedHtml,
          reason: engineName,
        );
      }
    });
  }
}
