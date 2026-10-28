import 'package:flutter_test/flutter_test.dart';
import 'package:tasklet/main.dart';

void main() {
  testWidgets('app boots', (tester) async {
    await tester.pumpWidget(const TaskletApp());
    expect(find.text('Tasklet'), findsOneWidget);
  });
}
