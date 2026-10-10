# Verification record — 2026-10-10

## Current status

**Not installed; physical verification incomplete.** Build identifier: `1.0.00001`. The validated ZIP is 5,605,891 bytes with SHA-256 `a9af5df2b83fe1dbb58419e9b69e290dee3924800da5f0b338a17f01147a4a12`, also recorded in `dist/apex-after-dark-roku.zip.sha256`. No installed build identifier can be reported until the installer and launch are verified.

Verified through read-only ECP: Philips TV reports Roku H530X, OS 15.3.4 build 2303, UI resolution 720p, address 192.168.0.110. Developer Mode is **disabled**. The panel model is 40PFL6533/F7 and the supplied display resolution is 1920x1080. No remote keypress or playback replacement has been sent.

Railway `/health` returned HTTP 200 and `ok:true`. This establishes relay health only; it does not establish Apollo authentication or stream availability. No authenticated Apollo provider call has been made by this Roku project.

The GitHub connector verified the reference repository is private and uses `main`. The supplied Fire TV working directory has no `.git` metadata. It was read as a source reference only. Its source, builds, device connection and deployment were not changed.

The separate local repository is `/Users/tay/Documents/ChatGPT/developer/apex-after-dark-roku`, branch `roku/native-app`. The user supplied the separate private repository `apexmarketingautomations/RokuTvApp`. Connector access was verified with write/admin permissions. The Roku branch is being uploaded there; its existing name is retained.

## Automated verification

- BrightScript/SceneGraph source compiles with BrighterScript 0.73.6, with no reported errors.
- Executable BRS core tests cover M3U quoting, titles, stream-format classification, identity stability across credential changes and provider pages, distinct same-named series, numeric season/episode ordering, category/search pagination, XMLTV offsets, pairing cancellation, bounded responses, registry failures, and restored episode history.
- Nine navigation assertions cover Back ordering and bounded category selection.
- Eleven scene assertions exercise credential-free retry state, stale response invalidation, account-view cleanup, background persistence-error reporting, and preserving bookmarks when startup fails.
- Twenty Python tests cover deterministic ZIPs, unsafe/secret-bearing package inputs, device identity guards, private credential files, installer status parsing and evidence redaction, including the actual app's telemetry names.
- A fresh independent code review identified application defects. Regression tests were written and run red before the corresponding fixes. The reviewer confirmed documented keyboard password masking, Video metadata fields and synchronous stop behavior. Static review cannot confirm native focus or playback.

## Physical matrix

| Check | Actual result | Evidence required |
|---|---|---|
| Device identity / OS / UI resolution | PASS, read-only query | H530X / 15.3.4-2303 / 720p UI |
| Developer Mode | BLOCKED: disabled | User enables it with physical remote |
| Install / launch / build identity | NOT RUN | Successful ZIP installer response and app launch |
| Apollo account connection | NOT RUN | Pair authorized Fire TV account without copying secrets into package |
| Saved sign-in after exit and TV restart | NOT RUN | Relaunch/reboot without credential entry |
| Home / Continue Watching / recent history | NOT RUN | Focused UI and resume title after restart |
| Movies: titles, artwork, categories, details | NOT RUN | Real catalog displayed on TV |
| TV Shows: seasons, ordered/titled episodes | NOT RUN | Real provider series and partial-page controls |
| Live TV, favorites and switching | NOT RUN | Real channels and decoder transition |
| Search: query, scope, count and pages | NOT RUN | Search and Back with retained state |
| Guide: real listings and failure recovery | NOT RUN | XMLTV data; live playback remains usable after guide failure |
| Settings: reconnect / sign-out | NOT RUN | Actual registry/session behavior |
| Live changing video frames | NOT RUN | Physical observation or recording plus telemetry |
| Movie changing video frames | NOT RUN | Physical observation or recording plus telemetry |
| Episode changing video frames | NOT RUN | Physical observation or recording plus telemetry |
| Audible sound | NOT RUN | Direct audible verification; screenshots are insufficient |
| Play/pause / FF / rewind / supported seek | NOT RUN | Physical remote and actual seekable media |
| Back / browsing-state retention / exit dialog | NOT RUN | Native remote interaction |
| Unavailable stream / timeout / failed request | NOT RUN | Controlled physical failure and recovery |
| Crash logs / decoder cleanup / memory | NOT RUN | Filtered 8085 logs, resource measurements and repeated playback changes |
| Independent Multi-View | NOT IMPLEMENTED; model-specific test pending | Official documentation does not establish support; no fake preview claim |
| Finish at stable Apex Home | NOT RUN | App must first be installed; no remote commands currently active |

## Open limitations

Developer Mode is pending user action. GitHub write access is available through the connector. The authorized account's credentials are not readable through the Railway connector, and there is no local provisioning token in the inspected current Fire TV bundle. Provider pairing will still be needed; permission to reuse that account is already recorded and must not be requested again.

Canonical title search covers metadata already loaded by browsing, not the entire remote metadata index. TV search is explicitly scoped to loaded provider pages. HTTP gzip guide handling and extensionless-stream HEAD responses require real-account tests. The H530X's exact SoC family, decoding support, catalog memory use and concurrency have not been measured from an installed channel.

There is no evidence here of an upstream stream failure or repair. All playback rows remain unverified.
