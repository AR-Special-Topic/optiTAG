# EventPipeSDExport snapshot

Source: https://github.com/CrocoFishing/DetectPipeDemo/tree/codex/event1-project-upload-20261111/clients/ios

VAD and progress updates synced from reference commit `65c230c54b944872a66808ccccd8b4b38b3b96bf`. Local integration changes:

- Explicit `SDExportManifestParser.init(sessionID:)` to make construction compile despite private stored fields.
- Coordinator accepts an async `joinNetwork` callback; the App provides manual Wi-Fi instructions. NetworkExtension calls are removed so Personal Teams can sign the App without Hotspot Configuration.
- Export request IDs reserve 0x40000000...0x7fffffff; App captures use the lower range.

App owns CoreBluetooth delegates and forwards callbacks. App target owns entitlements and permission strings. Reference SDK contract tests are preserved in Tests.

Deletion supports `nextBatch` within one management session and an awaited `onConfirmed` callback for durable per-file checkpoints and live progress. A heartbeat keeps the session alive until the entire cleanup round ends.
