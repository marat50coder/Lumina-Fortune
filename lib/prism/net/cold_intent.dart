import 'local_vault.dart';

// ─────────────────────────────────────────────────────────────
// COLD INTENT — cold-boot deep-link consumption
// ─────────────────────────────────────────────────────────────
// A cold-boot push tap on Android delivers the URL through the
// launch intent, which Firebase Messaging surfaces via
// `getInitialMessage()`. [PushGate] writes it into the vault's
// pending slot. This class is a thin one-shot reader so the
// dispatcher has a single entry point for cold-launch URLs,
// symmetric with the returning-launch path.
// ─────────────────────────────────────────────────────────────

class ColdIntent {
  ColdIntent._();

  /// Reads and clears the pending URL. Returns `null` when there
  /// was no cold-boot push tap.
  static Future<String?> tap(LocalVault vault) => vault.takePending();
}
