import 'package:darkroom/features/camera/presentation/swipe_tuning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(SwipeTuning.reset);

  test('a fast phone keeps the live viewfinder in swipes', () {
    for (final fps in <double>[20, 58, 55, 60, 52, 57]) {
      SwipeTuning.judgeForTest(fps); // (the first, slow, is the warm-up)
    }
    expect(SwipeTuning.auto, isFalse);
  });

  test('two slow swipes of the last three freeze it', () {
    SwipeTuning.judgeForTest(25); // warm-up, ignored
    SwipeTuning.judgeForTest(30);
    expect(SwipeTuning.auto, isFalse);
    SwipeTuning.judgeForTest(60);
    SwipeTuning.judgeForTest(28);
    expect(SwipeTuning.auto, isTrue);
    expect(SwipeTuning.freeze, isTrue);
  });
}
