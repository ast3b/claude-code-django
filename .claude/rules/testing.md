---
paths:
  - "**/tests/**"
  - "**/test_*"
  - "**/conftest.py"
---

# Testing

## Test levels

| What changes | Minimum level |
|---|---|
| Function / method with no external calls | Unit |
| Service calling `delay()` | Unit (mock delay) + E2E (delay→apply) |
| Celery task with external API | Integration (`.apply()`, mock provider) |
| Webhook handler | Integration (real handler + DB check) |
| Full business cycle (enqueue → task → DB) | E2E |

## Rules

1. **New service / business logic** → unit test mocking external dependencies.
2. **Celery task with external API** → integration test via `.apply()`, mock the provider.
3. **Changes to `enqueue_*` services** → E2E test intercepting `delay()` (delay→apply).
4. **Webhook handler** → integration test with real handler call and DB state check.

## Running tests

```bash
pytest source/ --tb=short -q              # Full run
pytest source/app/tests/ -v               # Single app
pytest tests/path/test_foo.py::test_bar   # Single test
pytest -m integration -v                  # Integration + E2E only
pytest source/ --cov=source --cov-report=html  # With coverage
```

## Coverage targets

- **Core business logic**: 80%+
- **Calculators / pure functions**: 90%+
- **Models**: 80%+
- **Views**: 70%+
