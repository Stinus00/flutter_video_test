// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_video_test/main.dart' as app;

void main() {
  test('next playlist index cycles through the available lists', () {
    expect(app.getNextListIndex(0, 2), 1);
    expect(app.getNextListIndex(1, 2), 0);
    expect(app.getNextListIndex(2, 3), 0);
  });
}
