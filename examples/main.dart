import 'generated/html.dart';

void main() {
  final users = Html.pages.users(
    title: 'Users',
    users: [
      (name: 'Ada', active: true),
      (name: 'Grace', active: false),
      (name: '<script>alert(1)</script>', active: true),
    ],
  );

  final page = Html.pages.user(name: 'Ada', surname: 'Lovelace', active: true);

  print(users.toHtml());
  print(page.toHtml());
  print(Html.pages.admin.dashboard(visits: 42).toHtml());
}
