// Host side of `flutter drive` for integration_test/: saves the tests' report data (frame summaries) to
// build/integration_response_data.json.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
