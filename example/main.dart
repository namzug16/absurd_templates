import 'generated/html.dart';

void main() {
  final users = Fragments.pages.users(
    title: 'Users',
    users: [
      (name: 'Ada', active: true),
      (name: 'Grace', active: false),
      (name: '<script>alert(1)</script>', active: true),
    ],
  );

  final page = Fragments.pages.user(name: 'Ada', surname: 'Lovelace', active: true);

  print(users.toHtml());
  print(page.toHtml());
  print(Fragments.pages.admin.dashboard(visits: 42).toHtml());
}
