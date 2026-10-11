# Roku verification record — 2026-10-11

## Current build and scope

Build **1.0.00006** is installed on the Philips H530X Roku TV (Roku OS 15.3.4, build 2303). The exact native package is `dist/apex-after-dark-roku.zip`: **5,608,930 bytes**, **15 runtime files**, SHA-256 `f4dcff305feaf7c0bb7d3f039a51d1ed1f2b24ee95057330cd6c0e9a0231daf9`. The installer accepted this ZIP; the active app reports **1.0.6**. See the [sanitized build 6 record](../evidence/2026-10-11-build6-verification.json). `npm test` passed the core suite, **9 navigation assertions**, **52 scene assertions**, and **31 Python tests**; `npm run check`, `npm run build`, and `git diff --check` passed. These local tests use synthetic inputs and do not prove video output.

The app is a native BrightScript/SceneGraph project in a separate repository. It uses the existing Apollo playlists and the user-authorized Railway pairing contract. No Fire TV source, deployment, or Fire Stick was modified. The paired Apollo account survives sideloaded updates and repeated observed app launches without re-entering credentials; a full TV power-cycle remains untested.

## Actual Roku observations

| Area | Observation | Result |
|---|---|---|
| Launch/account | Build 1.0.6 opened Home with the saved account and no login prompt after installation. It loaded **19,594** movie-library results. | Pass for observed launch; full reboot untested |
| Home/history | A private UI screenshot of build 1.0.5 showed **Continue Watching** with the saved Man vs Baby episode and I Swear movie. The Roku registry contained their saved positions (episode 194 s, movie 173 s). Build 1.0.6's episode Details dialog offered **Resume playback**. | Pass for saved state and visible resume option; exact resumed seek still sampled separately |
| Details crash | Build 1.0.5 raised BrightScript runtime `&h18` when a title lacked a description. Build 1.0.6 opened that same episode's Details on the TV with “Details are not provided for this title.” | Pass after fix |
| Movies/browsing | Build 1.0.6 loaded Movies with 19,594 results. Wake Up Dead Man and Bugonia had titles, synopses and artwork metadata. Build 1.0.4 showed actual movie-year categories newest first; selecting 2025 returned 903 matches and searching I Swear returned one. | Partial; other categories/pages/artwork remain sampled only |
| TV shows/episode | Build 1.0.6 listed 503 series on the first provider TV page. The saved Man vs Baby S1E1 resumed with native H264/AAC HLS telemetry advancing **200.381 → 223.781 s** without an observed error. Build 1.0.4 had additionally exercised pause and seek. | Native playback state pass for that sample; picture and sound unconfirmed |
| Live/Favorites | Build 1.0.4 listed 5,766 channels, saved A&E to Favorites, and showed one favorite; Up/Down switched to ActionMax East. Build 1.0.6 A&E native H264/AAC HLS state advanced **24.623 → 50.699 s** with no observed error. | Native playback state and controls pass for samples; picture and sound unconfirmed |
| Guide | A&E guide displayed a clear failure and still offered Watch channel; that action started live A&E. A computer-side request for the configured default EPG host `tvnow.best` failed DNS resolution (`gaierror` errno 8). | Listings unavailable in this network/provider state; live fallback pass |
| I Swear movie | Build 1.0.4 and 1.0.5 each resumed near 144–168 s, advanced, then stopped near **174–175 s** with `mediaerror -5`, internal code 9, DRM code 0. Build 1.0.5 logged successful `downloadedSegment` status 0 for sampled audio/video segments 21–29 before error. Its dialog offered retry/settings/library; Back returned to the library. | **Fail** for sustained movie playback. Cause is not established. Successful sampled downloads do not prove correct demux/decode. |
| Other movies | Build 1.0.6 Wake Up Dead Man and Bugonia stopped during startup with native error **-3** and displayed the recovery dialog. Prior computer-side authenticated GET samples for two movies closed without response. | **Fail** for these two samples; provider/network/decoder cause not established |
| Visual/audio | Roku UI screenshots omit the video plane, and player telemetry cannot prove changing pictures or audible sound. The user's direct viewing/sound confirmation is still pending. | **Unverified** |

Some artwork loads on Roku while other images fail. First-page image-node counts include retained SceneGraph nodes, so they are not a visible-card coverage percentage. The first 30 Apollo movie playlist entries had no playlist artwork; metadata matching was sparse, and one sampled metadata image returned HTTP 403/Cloudflare 1010 from the development computer. Neither observation proves that all artwork is unavailable.

## Reproducibility and evidence handling

The installed build's package checksum is reproducible with `npm run build`; the package includes only allowlisted native source and assets. Private on-device state, screenshots, debugger output, stream samples, account values and URLs remain in ignored `evidence/private/` or `.private/`. Public `evidence/` records contain only sanitized status, counts and hashes. Native `downloadedSegment` telemetry exports numeric fields only, and runtime logs omit unknown raw lines. Passwords, tokens, full stream URLs and request headers are excluded from source, package and public evidence.

The unresolved movie errors should not be presented as a working E2E movie pass. An all-green physical acceptance requires sustained playback for representative movies, shows and live channels with visible changing pictures and audible sound; guide listings where the provider supplies an accessible feed; repeated exit/relaunch and full-reboot persistence; error recovery; and resource checks. The present work establishes a functioning native app shell, real catalog and selected native playback, while recording movie and guide failures honestly. No independent Multi-View capability has been established or enabled on this hardware.

Earlier exact installation records remain under `evidence/2026-10-10-build{2,3,4}-installed.json`, with sanitized provider diagnostics in `evidence/2026-10-10-provider-diagnostics.json`. The build 3 samples showed I Swear, Man vs Baby and A&E media positions advancing, but they are historical results; the later I Swear failures supersede any conclusion that its sustained playback works.
