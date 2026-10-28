import 'dart:io';

import 'package:jinja/jinja.dart' show Environment, MapLoader;
import 'package:mustache_template/mustache_template.dart';

import 'absurd.dart';

typedef User = ({String name, String email, String bio, bool admin});

typedef Scenario = ({
  String name,
  String description,
  Map<String, String Function()> renderByEngine,
});

const engineNames = ['abs', 'jinja', 'mustache'];

/// The same pages written for each engine, with the data already in the
/// shape each engine takes: records for abs, maps for Jinja and Mustache.
///
/// Reads the Jinja and Mustache templates from [templateDirectory].
List<Scenario> loadScenarios({String templateDirectory = 'templates'}) {
  // Every value needs escaping, but no quotes or slashes: the engines escape
  // those with different entities, which would make outputs differ.
  final users = <User>[
    for (var index = 1; index <= 1000; index++)
      (
        name: 'User $index <Ada & Grace>',
        email: 'user$index@example.com',
        bio: 'Writes <code> & ships it, day $index.',
        admin: index % 10 == 0,
      ),
  ];
  final pageUsers = users.take(100).toList();
  final userMaps = [
    for (final (index, user) in users.indexed)
      {
        'name': user.name,
        'email': user.email,
        'bio': user.bio,
        'admin': user.admin,
        // Mustache has no loop index, so the data carries it.
        'number': index + 1,
      },
  ];
  final pageUserMaps = userMaps.take(100).toList();

  String readTemplate(String path) =>
      File('$templateDirectory/$path').readAsStringSync();

  final jinja = Environment(
    leftStripBlocks: true,
    trimBlocks: true,
    loader: MapLoader({
      for (final name in ['card.html', 'table.html', 'page.html'])
        name: readTemplate('jinja/$name'),
    }),
  );
  final jinjaCard = jinja.getTemplate('card.html');
  final jinjaTable = jinja.getTemplate('table.html');
  final jinjaPage = jinja.getTemplate('page.html');

  final mustacheTemplateByName = <String, Template>{};
  Template mustache(String name) => mustacheTemplateByName[name] ??= Template(
    readTemplate('mustache/$name.mustache'),
    name: name,
    partialResolver: mustache,
  );
  final mustacheCard = mustache('card');
  final mustacheTable = mustache('table');
  final mustachePage = mustache('page');

  return [
    (
      name: 'card',
      description: 'one small fragment',
      renderByEngine: {
        'abs': () => Bench.card(user: users.first).toHtml(),
        'jinja': () => jinjaCard.render({'user': userMaps.first}),
        'mustache': () => mustacheCard.renderString(userMaps.first),
      },
    ),
    (
      name: 'table',
      description: '1000 rows with a loop, an index and a condition',
      renderByEngine: {
        'abs': () => Bench.table(users: users).toHtml(),
        'jinja': () => jinjaTable.render({'users': userMaps}),
        'mustache': () => mustacheTable.renderString({'users': userMaps}),
      },
    ),
    (
      name: 'page',
      description: 'a layout composing 100 card fragments',
      renderByEngine: {
        'abs': () => Bench.page(
          title: 'Team <dev & ops>',
          cards: [for (final user in pageUsers) Bench.card(user: user)],
        ).toHtml(),
        'jinja': () =>
            jinjaPage.render({'title': 'Team <dev & ops>', 'users': pageUserMaps}),
        'mustache': () => mustachePage.renderString({
          'title': 'Team <dev & ops>',
          'users': pageUserMaps,
        }),
      },
    ),
  ];
}

final _whitespaceBetweenTagsPattern = RegExp(r'>\s+<');

/// [html] without the indentation and blank lines that engines place
/// differently, so outputs of different engines can be compared.
String withoutWhitespaceBetweenTags(String html) =>
    html.replaceAll(_whitespaceBetweenTagsPattern, '><').trim();
