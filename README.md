# Absurd Templates

HTML-first templates for Dart. `abs` is a CLI that compiles a directory of
`.html` files into typed Dart functions.

- [At a glance](#at-a-glance)
- [Simple on purpose](#simple-on-purpose)
- [Install](#install)
- [Templates](#templates)
- [Configure](#configure)
- [Generated API](#generated-api)
- [Example](#example)
- [Agent skill](#agent-skill)
- [Checking templates](#checking-templates)
- [Developing abs](#developing-abs)
- [Vendor instead of installing](#vendor-instead-of-installing)

## At a glance

A layout, `fragments/layout/primary.html`:

```html
<x-props title="String" content="Fragment"></x-props>

<!DOCTYPE html>
<html lang="en">
  <head><title>{{ title }}</title></head>
  <body>{{ content }}</body>
</html>
```

A page that renders inside it, `fragments/pages/users.html`:

```html
<x-props users="List<({String name, bool active})>"></x-props>

<x-fragment template="/layout/primary.html" title="Users">
  <x-slot name="content">
    <ul>
      <x-for in="users" as="user">
        <li ?user.active:class="active">{{ user.name }}</li>
      </x-for>
    </ul>
  </x-slot>
</x-fragment>
```

Run `abs` and call the generated function from Dart:

```dart
import 'generated/html.dart';

final String html = Fragments.pages.users(
  users: [(name: 'Ada', active: true), (name: 'Grace', active: false)],
).toHtml();
```

Dart passes only data; the page picks its own layout.

## Simple on purpose

Absurd Templates is extremely simple and constrained. It does not invent a
pseudo language inside your HTML. Templates are plain HTML plus a handful of
`x-` tags, `{{ }}` and a few attribute forms; anything that needs real logic
is computed in Dart and passed in as a typed prop. Your editor, your
formatter, your browser, and your agent already understand everything else.

The small surface is the point. As Arun puts it in
[The creative power of constraints](https://arun.is/blog/creative-power-constraints/):

> With just the right amount of constraints, creativity becomes almost an
> inevitability.

Every feature a template language adds is another place for complexity to
hide, and [complexity *very*, *very* bad](https://grugbrain.dev/#grug-on-complexity)

So abs says no to expressions, filters, macros and inheritance chains, and
keeps the logic in Dart, where the type checker can see it.

## Install

From [pub.dev](https://pub.dev/packages/abs):

```sh
dart pub global activate abs   # abs on your PATH, for every project
```

or per project, pinned in `pubspec.yaml`:

```sh
dart pub add dev:abs
dart run abs                   # works exactly like abs: check, init, help...
```

From a clone of this repository, as a native binary with the fastest
startup:

```sh
make install                   # ~/.local/bin/abs
make install PREFIX=/usr/local # or anywhere else
```

`make uninstall` removes it again; `make` lists the other commands.

## Templates

Every template starts with `<x-props>` and is plain HTML plus these tags:

- `<x-props name="Type" ...>`: declares the template's parameters, one
  attribute per prop, its value a Dart type. Must come first.
- `<x-for in as [index-from index-as]>`: renders its children once per item
  of the list `in`, named `as`.
- `<x-if case>`: renders its children when `case` is `true`.
- `<x-if-not case>`: renders its children when `case` is `false`.
- `<x-fragment template ...props>`: renders another template, by its path
  from the input directory starting with `/`.
- `<x-slot name>`: inside `<x-fragment>`, passes its children as the `name`
  prop.

Values and attributes:

- `{{ value }}` inserts a declared variable or its fields (`user.name`,
  `pair.$1`), never other Dart code: compute values in Dart.
- `{{ }}` escapes text, inserts `Fragment` values as HTML, renders `null` as
  nothing and lists item by item.
- Escaping does not make URLs safe: check `href`, `src` and `action` values
  in Dart.
- `{{ }}` cannot go inside `<script>` or `<style>`: use a `data-` attribute.
- Nullable props are optional parameters, all others are `required`.
- `<x-fragment>` props: `label="Users"` passes a `String`,
  `count="{{ users.length }}"` passes the value as it is, an omitted
  nullable prop passes `null`.
- `?condition:attribute` renders the attribute only when `condition` is
  `true`, `?!condition:attribute` only when it is `false`.
- `...attributes` writes every entry of a `Map<String, String>` as
  attributes; `?condition:...attributes` only when `condition` is `true`.
- An attribute cannot be both plain and conditional
  (`class="btn" ?isActive:class="active"`): combine it in Dart.
- A directive tag alone on its line is removed with that line; directives
  inside `<!-- -->` are left alone.

A full template, `fragments/pages/users.html`:

```html
<x-props
  title="String"
  users="List<({String name, bool active})>"
  isLoading="bool"
  extraAttributes="Map<String, String>?"
  footer="Fragment?"
></x-props>

<x-fragment template="/layout/primary.html" title="{{ title }}">
  <x-slot name="content">
    <section ...extraAttributes>
      <h1>{{ title }}</h1>
      <x-fragment template="/ui/badge.html" label="Users" count="{{ users.length }}" />

      <x-if case="isLoading">
        <p>Loading…</p>
      </x-if>
      <x-if-not case="isLoading">
        <ol>
          <x-for in="users" as="user" index-from="1" index-as="number">
            <li ?user.active:class="active" ?!user.active:class="idle">
              {{ number }}. {{ user.name }}
            </li>
          </x-for>
        </ol>
      </x-if-not>

      <button ?isLoading:disabled>Refresh</button>
      {{ footer }}
    </section>
  </x-slot>
</x-fragment>
```

## Configure

`abs.yaml` in your project root. `abs init` creates it with comments that
explain every option:

```yaml
input: fragments              # required, scanned recursively for .html
output: lib/generated/html.dart # required
class: Fragments              # optional, defaults to Fragments
```

abs.yaml holds only these top-level keys, with plain or quoted text values
and `#` comments; other YAML features are rejected with the line they are on.

Run `abs` to generate the output file.

## Generated API

All templates become functions under one class, `Fragments` unless `class`
in `abs.yaml` says otherwise, grouped by directory:
`fragments/pages/user-page.html` becomes `Fragments.pages.userPage(...)`.
Each returns a `Fragment`; call `.toHtml()` to render it.

```dart
final String html = Fragments.pages.users(users: users).toHtml();
```

Mark the generated file as generated in `.gitattributes` to collapse it in
pull requests:

```
lib/generated/html.dart linguist-generated=true
```

## Example

[`example/`](example) has fragments, their generated
[`html.dart`](example/generated/html.dart) and a [`main.dart`](example/main.dart)
that renders them:

```sh
cd example && abs && dart main.dart
```

## Agent skill

```sh
npx skills add namzug16/absurd_templates
```

```sh
# Scans immediate dependencies and discovers available skills.
dart run skills@ get
```

## Checking templates

```sh
abs check                              # every template
abs check fragments/pages/users.html  # only these files
```

`abs check` writes nothing. It reports syntax errors and Dart errors mapped
back to the template, warns about unused props, and exits with 1 on errors:

```text
error: The getter 'nmae' isn't defined for the type '({bool active, String name})'.
  --> fragments/pages/users.html:12:16
   |
12 |         <li>{{ user.nmae }}</li>
   |                ^

abs check: 1 error and 0 warnings in 1 template
```

## Developing abs

After changing anything in `lib/src` or the skill, run
`dart run tool/build_vendored_source.dart` to rebuild the guide that
`abs guide` prints and the copy that `abs vendor` writes (a test fails until
you do), and bump `version` in
`pubspec.yaml` together with `absVersion` in `lib/src/cli.dart` before
releasing, so vendored copies can tell they are out of date. `make publish`
rebuilds them, runs `make check` and publishes the package to pub.dev.

## Vendor instead of installing

To use abs without installing it, copy it into your project as one Dart file
that needs only the Dart SDK, no packages:

```sh
abs vendor                 # writes tool/abs.dart; or: abs vendor path/to/file.dart
dart run tool/abs.dart     # works exactly like abs: check, init, help...
```

Commit `tool/abs.dart`. Its header records the abs version and a checksum.
Running `abs vendor` again with a newer abs updates the copy. It never
overwrites a file it did not write, a copy edited by hand, or a copy from a
newer abs. `abs version` (or `dart run tool/abs.dart version`) prints the
version.

## License

[MIT](LICENSE)
