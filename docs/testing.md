# Test Coverage — FixingNation

Coverage reports are generated on every CI run and uploaded to **Codecov**.

---

## View Coverage

[![Codecov](https://codecov.io/gh/RohanExploit/FixingNation/branch/main/graph/badge.svg)](https://codecov.io/gh/RohanExploit/FixingNation)

---

## Run Coverage Locally

```bash
cd flutter_app
flutter test --coverage
```

Report is written to `flutter_app/coverage/lcov.info`.

To view as HTML (requires lcov installed):

```bash
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

---

## Coverage Targets (Guidelines)

| File | Target |
|---|---|
| `post_model.dart` | ≥ 80% |
| `auth_notifier.dart` | ≥ 70% |
| `feed_notifier.dart` | ≥ 70% |
| `post_repository.dart` | ≥ 60% |
| UI pages (`*_page.dart`) | best effort |

---

## Adding Tests

Unit tests live in `flutter_app/test/`. Use the following conventions:

```
test/
  unit/
    post_model_test.dart
    auth_notifier_test.dart
    feed_notifier_test.dart
  widget/
    feed_page_test.dart
```

Example unit test for `PostModel`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/domain/post_model.dart';

void main() {
  group('PostModel', () {
    test('formattedCategory converts snake_case correctly', () {
      final post = PostModel(/* ... */ category: 'road_damage');
      expect(post.formattedCategory, 'Road Damage');
    });

    test('isUnderReview true for status under_review', () {
      final post = PostModel(/* ... */ status: 'under_review');
      expect(post.isUnderReview, isTrue);
    });
  });
}
```

---

## CI Setup

Coverage is uploaded automatically by `.github/workflows/ci.yml`.
You need to add the Codecov token as a GitHub secret:

**Repo → Settings → Secrets → Actions → New repository secret**

```
Name:  CODECOV_TOKEN
Value: (from codecov.io → your project → Settings)
```
