# Apex After Dark for Roku

Native BrightScript and SceneGraph application for the Philips H530X Roku TV. This is a separate repository and app from [the Fire TV implementation](https://github.com/apexmarketingautomations/fire-tv-app-). It shares existing Apollo and Railway contracts and the user-authorized Apex branding assets. It does not modify or deploy the Fire TV project.

**Status:** native build **1.0.00006** is installed on the Philips H530X Roku TV. Local tests and compilation pass; the saved Apollo account restores, real catalog and Continue Watching load, and an on-device Details crash has been fixed. Build 1.0.6 episode and live-channel samples showed advancing native playback state; earlier controls were sampled on build 4. **Movie playback is not reliable:** I Swear stops near 175 seconds with media error -5, while Wake Up Dead Man and Bugonia failed during startup with -3. The EPG request failed with a DNS error; the unresolved target has not yet been isolated. Roku screenshots do not show the video plane; the user directly confirmed moving picture and audible sound for Man vs Baby and A&E. Movie playback remains failed. See [the verification record](docs/VERIFICATION.md) and [hardware limitations](docs/HARDWARE.md).

## Build 6 fixes and checks

A missing provider synopsis no longer crashes the string-only Details dialog. The same saved episode opened its Details with a safe fallback on the TV. Native numeric segment telemetry shows downloaded audio/video segments preceding the I Swear error but does not establish its cause. Current local checks passed **31 Python tests**, **52 scene assertions**, **9 navigation assertions**, the core suite, compiler and package build. The installed ZIP's SHA-256 is `f4dcff305feaf7c0bb7d3f039a51d1ed1f2b24ee95057330cd6c0e9a0231daf9`.

## Build 4 audit fixes

Movie year categories now start with the newest real provider year, with All first and exact filter values preserved. Switching sections clears stale cards; selection is blocked during loading. Opening a child list starts at its first item, and returning restores the parent query, category, page and focus. Status and provider-page scope are shorter, and playback hints/build labels avoid clipped or unsupported glyphs.

Resolve and history preserve safe same-ID artwork when the authoritative catalog has none, while playback URLs and headers still come from the current catalog. Final checks passed: **31 Python tests**, **44 scene assertions**, **9 navigation assertions**, core, compilation and packaging. [Build 4 installation evidence](evidence/2026-10-10-build4-installed.json) identifies the exact archive; native startup, catalog, category/filter and search checks are recorded. The final movie run failed after initially advancing, so playback is not a pass.

## Earlier fixes retained from build 3

The local build 1.0.00003 source improves M3U delimiter parsing while preserving quoted/escaped fields and stable catalog IDs. A 500-entry synthetic playlist took 5,001 ms before and 3,035 ms after in the development computer’s `brs` interpreter (39.3% less time). This is not a native TV startup measurement. Connected catalog loading now says the account is saved. Episode search filters the selected season and page, and Back restores the parent query. Settings ignores playback/paging shortcuts for hidden catalog content; dismissing an ordinary dialog keeps its pending catalog request alive.

Refresh now fetches the movie or live playlist again. TV browsing refreshes provider page 1; an episode view refreshes the selected show's earliest loaded provider page and states that scope. Other loaded TV pages remain available. Failed or empty refreshes retain usable cache and saved account data; successful replacements update stream URLs and remove obsolete playback entries. A successful TV refresh reopens discovery beyond a previously learned catalog end. Replacement inventories reapply cached artwork ordering without resetting the metadata request budget. Poster loads have explicit dimensions and card titles wrap to two lines.

Build 3 checks covered these fixes with 29 Python tests, 28 scene assertions, navigation/core tests and the BrightScript compiler. Build 3 native catalogs, example artwork and movie/episode/live playback telemetry were confirmed. Episode/live picture and sound were later directly confirmed by the user; performance, broader artwork coverage and repeated-exit verification remain separate from local tests. See [the verification record](docs/VERIFICATION.md).

## Build

Node.js 20+ and Python 3.9+ are required on the development computer. The TV runs only the packaged native source and assets; it does not require Node, Python, a browser, or a Fire Stick.

```sh
npm ci
npm test
npm run check
npm run build
```

Output: `dist/apex-after-dark-roku.zip` and its `.sha256` sidecar. The build prints the checksum, size and runtime file count. Runtime package inputs are explicitly allowlisted. Packages contain no provisioned account, device password or environment file. Build output is reproducible with the same source and Python/zlib toolchain.

## Screens and remote

- Home: a feature panel plus real library, Continue Watching and Recently Watched rows.
- Movies: provider titles, optional matched metadata, categories and paged browsing.
- TV Shows: series, season selection, ordered episodes and explicit partial-catalog status.
- Live TV and Favorites: real channels, provider categories, favorites and channel switching.
- Guide: upcoming XMLTV listings per selected channel, with watch/retry/back controls.
- Search: movies, loaded series and live channels; episode search also filters the selected season. Query and page are preserved when navigating back.
- Settings: Apollo username/password, phone setup, reconnect, sign-out, build and capability information.

Left returns to the navigation rail at the content boundary; Right returns to content. OK opens details or selects an action. Play starts a focused title. Options opens categories, search and pagination. Outside playback, Fast Forward advances a page and Replay/Rewind returns a page. During playback the native Roku Video UI owns play/pause, fast-forward, rewind and supported seeking. Up/Down switches through channels in the current live page when those keys reach the app. Several native focus/control behaviors were sampled on the TV; broader physical verification remains open.

Back dismisses overlays first, then closes playback or nested browsing, then returns to Home. At Home, Back opens an explicit exit dialog. Fullscreen playback releases its Video content on exit. Failed startup does not overwrite a saved resume position. Position is saved every 30 seconds during playback and when leaving; a sudden power cut can lose the most recent unsaved interval.

## Connection and privacy

Use an **Apollo username**, not an email address. The existing HTTPS Railway relay supports one-time phone pairing without backend changes. The setup link contains a short-lived claim token: do not capture or share that screen. Direct TV password entry is masked.

The authorized Apollo account already used by Fire TV was paired on October 10 using the existing authenticated Railway dashboard and the one-time HTTPS setup flow. Credentials were kept out of source, packages, logs, and evidence. The Railway connector itself exposes variable names only. One exit/relaunch of build 1.0.00001 restored sign-in, but the user subsequently reported recurring reconnect prompts. Build 1.0.00002 restores valid saved credentials immediately and loads catalogs separately; a provider outage no longer changes the saved account into a signed-out state. Immediate saved-account restoration was observed at build 2 and build 3 launch. One build 3 exit/relaunch also restored the account without credential entry. Repeated cycles and full-reboot checks remain pending. No Fire Stick playback was interrupted.

Credentials are stored in Roku's encrypted, developer-ID-scoped registry. Apps with the same signing identity can share that registry; it is not an app-exclusive hardware vault. Sign-out clears account data, favorites and viewing history. Registry failures are reported. The history retains 12 bounded metadata snapshots with no stream URL or request headers; favorites are capped at 100. Catalogs stay in task memory and reload after restart. Uninstall/factory reset/signing-identity changes may remove persisted state.

## Provider behavior and limits

Apollo playlists are the playable inventory. The provider's JSON metadata service enriches matching IMDb IDs on displayed pages. Initial movie/series browsing can also fetch at most two category pages of up to 250 metadata records per attempt, with at most two attempts, matching only existing playlist entries and prioritizing titles with artwork while keeping pagination stable. Incomplete artwork metadata remains retryable within a bounded budget. No streams, titles, artwork, episode numbers or listings are fabricated. Missing artwork uses the Apex logo.

October 10 computer-side provider probes returned 19,592 movies and 5,000 episodes on the first TV page. The first 30 movies had no playlist artwork, and metadata matched only one of those 30; a known-title control also matched. A sampled metadata image returned HTTP 403, with a separate probe identifying Cloudflare error 1010. Two sampled new movies and two episodes returned HLS types to HEAD but closed GET requests without a response; “I Swear (2025)” returned an HLS master playlist. These samples identify provider-side availability problems, not a verified diagnosis of every TV failure. Build 3 subsequently loaded some artwork on Roku, so the computer-side image 403 does not establish a universal Roku image block. No access-control bypass was attempted.

TV inventory is loaded lazily from the documented existing integration's pages 1–20. **Load more provider catalog** expands it; the UI reports loaded scope and loaded match counts. Search can find playlist titles and canonical metadata already obtained from browsing; it is not a complete canonical metadata search service. Categories are actual M3U groups. Canonical metadata genres are not a complete category index.

Extensionless VOD is probed using HEAD Content-Type, with a deadline. Supported MIME mapping includes HLS, MP4/QuickTime, DASH and Matroska; a recognized container does not guarantee supported codecs or a successful GET. Feeds rejecting HEAD or omitting a useful type require further provider-specific work; they are not falsely treated as HLS. Playback diagnostics export only allowlisted error categories and numeric codes, without stream URLs or raw errors. Native build 3 reports advancing H264/AAC playback for sampled movie, episode and live streams. The user has directly confirmed moving picture and audible sound for the sampled episode and live channel; movie output is unresolved.

XMLTV uses HTTP gzip decoding when correctly signaled. A raw `.gz` file body without suitable HTTP encoding may not decode; the app explains the failure while leaving live channels usable. Large real catalogs and guide memory usage need device profiling.

Independent Multi-View is not enabled. Official Roku documentation describes one prebuffered Video stream, and no current H530X exception has been verified. A server-composited feed is an alternative to investigate separately; no infrastructure was provisioned and no paid service was purchased.

## Install and verify

Prepare the ZIP first, then follow [Roku Developer Mode setup](https://developer.roku.com/dev/docs/developer-setup). The installer username is `rokudev`; keep its password out of chat and command arguments.

```sh
python3 scripts/roku.py --host 192.168.0.110 info
python3 scripts/roku.py --host 192.168.0.110 install
python3 scripts/roku.py --host 192.168.0.110 launch
```

Installation prompts securely for the developer password. Commands check that the target reports H530X before sending input. The installer replaces the one sideloaded Roku app. See [hardware/tooling notes](docs/HARDWARE.md) for the private-password-file option, UI screenshots, filtered logs, resource queries and evidence limitations.

Menus and screenshots cannot prove video playback; Roku screenshots omit the video plane. Advancing player telemetry is supporting evidence, not proof of changing pictures or audible sound. Complete every row in the physical test record and record observed results before declaring the app verified.
