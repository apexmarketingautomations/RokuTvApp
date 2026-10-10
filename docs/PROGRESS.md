# Roku implementation continuation

User requests native app, separate private GitHub repository apexmarketingautomations/apex-after-dark-roku, physical installation/test, untouched Fire TV. User has explicitly authorized using the same Apollo account as Fire TV. No public publishing or spending.

2026-10-10: native source, assets, worker, playback UI, executable tests, tooling, package, independent review and regression repairs prepared in local branch roku/native-app. No remote commands or installation attempted because Developer Mode remains disabled. User supplied existing private repository apexmarketingautomations/RokuTvApp; write/admin access confirmed; use this target and retain its name. A single concise Developer Mode handoff was already sent after the ZIP was prepared. Await user's completion; do not repeat approval questions.

Remaining: push source/branch to RokuTvApp using connector Git objects or authenticated Git; install current rebuilt ZIP via digest installer after Developer Mode; pair same authorized Apollo account; test every physical row in VERIFICATION.md; fix reproduced runtime bugs; record installed build and exact checksum; finish at Apex Home and stop input. Sideloading is already authorized. Never touch separate Fire Stick or Fire TV checkout.

Source modules: ApexScene owns screens and single Video lifecycle. ApiTask owns TLS HTTP, catalogs, pairing, registry and progress. Core owns pure parsing, identity, paging and history. Navigation owns Back and category-choice behavior. scripts/roku.py guards H530X and filters evidence. scripts/package.py produces deterministic runtime-only ZIP. Tests run without hardware and do not prove focus/playback.

Design decisions: use native Roku Video controls for seeking; no redundant custom seek implementation. UI is authored at FHD and Roku scales to reported 720p UI. Persist at most12 genuine history snapshots and100favorites under registry budget. Metadata enriches displayed items; search scope remains explicit. No provider credentials were read, copied or committed; Railway values are redacted and current Fire TV build has empty provisioning token. Need authorized account pairing after installation.

Review repairs verified with red/green regressions: credential retention in retry state; invalidated pending navigation/playback; signout view references; pair cancellation; favorites access; season-first flow; persistence error feedback; same-title series identity and episode deduplication across pages; genuine episode history after restart; failed-start resume bookmark preservation; telemetry filter mismatch.

Outstanding uncertainties: raw gzip XMLTV without Content-Encoding, VOD providers rejecting HEAD, full metadata canonical search/category coverage, native renderer/focus/performance, codec compatibility, audible sound and all three actual playback classes. These are explicit limitations, not declared provider failures.
