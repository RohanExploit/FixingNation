/// Cloudflare Worker connection configuration.
///
/// Values are read from compile-time --dart-define flags so they stay out of
/// source code in production builds.  The defaultValue fields contain working
/// development defaults and must be overridden for any public release:
///
///   flutter build apk --release \
///     --dart-define=WORKER_URL=https://... \
///     --dart-define=WORKER_SECRET=<secret>
library worker_config;

/// Base URL of the deployed Cloudflare Worker (no trailing slash).
const String kWorkerBaseUrl = String.fromEnvironment(
  'WORKER_URL',
  defaultValue: 'https://fixingnation-ai-worker.itzrohan007.workers.dev',
);

/// Value sent in the `x-api-secret` request header.
/// Must match the API_SHARED_SECRET Cloudflare Worker secret.
const String kWorkerSharedSecret = String.fromEnvironment(
  'WORKER_SECRET',
  defaultValue: 'fixingnation-secret-2026',
);
