# Medical records and reminder work

## User requirements
- Custom nested archive folders; upload reports, images, videos and other files without a per-folder/upload count cap; export.
- Outpatient/hospital visit records, linked archives, export.
- Quick doctor-instruction notes.
- Fix meals not notifying while water notifications work; improve interaction where useful.
- Confirmed: 200 MB per file is sufficient.

## Phases
1. [complete] Trace storage, attachments, export, reminder scheduling and existing UI.
2. [complete] Fix and regression-test reminder scheduling.
3. [complete] Add archive/visit/instruction data and scalable encrypted lazy attachments.
4. [complete] Build medical workspace, folder/file actions, record forms and linked exports.
5. [complete] Validate migrations, sync/error handling, UI, exports and Android build; update docs.

## Completion evidence
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: 25 tests passed, including encrypted chunk integrity/legacy compatibility and 320/390/1440 UI flows.
- Android debug APK and production Flutter Web builds passed.
- Three-page PDF rendered and visually reviewed; ZIP hierarchy, unique paths and original bytes verified.
- Emulator reminder queue/channels inspected. Real-device sound/delivery remains OS-dependent; the new test buttons and channel diagnostics support verification after installing.

## Decisions
- Preserve all previous uncommitted work and user data.
- Reuse encrypted account storage and media preview; avoid a parallel plaintext medical backend.
- New primary Medical workspace with Archives / Visits / Instructions; keep existing daily care and journeys accessible.
- Exports: readable record PDFs and original-file ZIPs retaining folder structure.

## Errors
- Tool output aggregation truncated some file reads; read important files in smaller batches.
- ADB could not bind its local listener in sandbox; retried through required escalation.
- A combined UI patch did not match the existing `widget.store` main navigation line; applied new screen and integration edits separately without overwriting other work.
- First formatter found the new dart:convert import appended at the bottom of store.dart; moved it before declarations before continuing validation.
- Static analysis parsed all feature code; remaining issues were brace/import lints and two async-context flow warnings. Applying targeted automatic fixes and explicit branch returns.
- Second analyzer run had one nested conditional brace lint, so tests had not started yet. Fixing that remaining branch before rerunning.
- First full tests: 21 passed; PDF long text could not paginate because a Padding wrapper prevented Text spanning, and 3 widget cases timed out on an indeterminate background spinner while a modal was open. Use PDF spanning Text directly and reserve upload progress animation for actual uploads.
- PDF/ZIP tests now pass. Widget tests advanced past opening modals but waited on real encrypted database work under the fake test clock; move save taps and queue drainage into tester.runAsync.
- UI tests then reached visit details successfully; Flutter's pageBack helper assumed an English tooltip in this Chinese app. Tap the actual BackButton instead. PDF visual review shows valid pagination; format discharge dates for readers.
