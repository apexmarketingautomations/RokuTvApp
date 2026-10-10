# Apex After Dark native Roku design

The user authorizes implementation, installation and physical testing; no public publication or paid infrastructure. Their full brief is the implementation scope. Create a separate private `apexmarketingautomations/apex-after-dark-roku` repository, isolated branch and directory. The Fire TV source is read-only reference; never operate its device or change its deployment.

Target verified 2026-10-10: Philips 40PFL6533/F7, H530X, OS 15.3.4 build 2303, 192.168.0.110. Developer Mode disabled. Prepare an installable ZIP before requesting remote steps.

## Architecture

Native BrightScript / SceneGraph only. Reuse existing Apex source-derived holographic backdrop, logo and splash. Layout at 1920x1080 with safe margins, left rail, center feature panel and bounded landscape artwork rows. One background worker owns HTTP, credentials, caches and registry. UI receives only bounded results; credentials never reach labels, diagnostics or package assets. Keep account separate until user pairs explicitly or authorizes reuse. Existing Railway relay is compatible and unchanged. Direct Apollo username/password entry is also available.

The registry stores provider credentials privately under this developer ID, never hardcoded. Saved credentials restore across restart; reconnect tests the saved account; sign-out deletes credentials, caches, favorites and watch history. HTTP uses certificate validation, fixed deadlines and sanitized errors.

Provider truth: Apollo M3U lists supply playable URLs and IDs. Provider metadata may enrich matching IDs only. Missing artwork gets a branded fallback; unknown titles retain provider names. TV series group only explicit provider series identities/season/episode numbers. Guide reads real XMLTV and reports absence honestly. Optional metadata/guide failures do not block catalogs.

## Screens and behavior

Home offers featured actual content, continue watching and recent history. Movies, TV Shows and Live TV support categories and paged bounded results. Series opens seasons then ordered episodes. Search reports loaded scope and known counts with pagination. Live favorites and channel switching use the current ordered live list. Settings shows connection/build/hardware status and account controls.

Back closes keyboard/dialog first, player next, detail stack next, then screen to Home. Root Back opens explicit exit confirmation. Playback uses a single Video node with native controls, resume position, state/error observers, startup timeout, and cleanup before replacing a title. Resume/history persist without stream URLs. Keep browsing state across player transitions.

Multi-View must follow official capabilities plus device evidence. No static tiles labeled concurrent playback. Server composition is documented as an alternative only; provision nothing.

## Verification

BrightScript compilation and executable pure-logic tests exercise parsing, pagination, episode grouping, seek/resume and secret exclusion. Deterministic ZIP with checksum. Physical matrix separately records launch, sign-in/relaunch, all screens, three real playback classes with changing frames, controls, recovery, focus, retained state and resource logs. Never infer audible sound from video or playback from menu screenshots. If installation/account access is blocked, record exact untested rows and continue all independent work. Finish physical testing at Apex Home, then stop commands.
