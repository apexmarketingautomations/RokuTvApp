# Apex After Dark for Roku

Native BrightScript and SceneGraph application for the Philips H530X Roku TV. This is a separate repository and app from [the Fire TV implementation](https://github.com/apexmarketingautomations/fire-tv-app-). It shares existing Apollo and Railway contracts and the user-authorized Apex branding assets. It does not modify or deploy the Fire TV project.

**Status:** the native source compiles and an installable development ZIP is available. Installation and physical playback verification are pending Developer Mode and account pairing. This is not a verified production release. See [the test record](docs/VERIFICATION.md) and [hardware limitations](docs/HARDWARE.md).

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
- Search: movies, loaded series and live channels, preserving query and page when navigating back.
- Settings: Apollo username/password, phone setup, reconnect, sign-out, build and capability information.

Left returns to the navigation rail at the content boundary; Right returns to content. OK opens details or selects an action. Play starts a focused title. Options opens categories, search and pagination. Outside playback, Fast Forward advances a page and Replay/Rewind returns a page. During playback the native Roku Video UI owns play/pause, fast-forward, rewind and supported seeking. Up/Down switches through channels in the current live page when those keys reach the app. These native focus/control behaviors still require physical verification.

Back dismisses overlays first, then closes playback or nested browsing, then returns to Home. At Home, Back opens an explicit exit dialog. Fullscreen playback releases its Video content on exit. Failed startup does not overwrite a saved resume position. Position is saved every 30 seconds during playback and when leaving; a sudden power cut can lose the most recent unsaved interval.

## Connection and privacy

Use an **Apollo username**, not an email address. The existing HTTPS Railway relay supports one-time phone pairing without backend changes. The setup link contains a short-lived claim token: do not capture or share that screen. Direct TV password entry is masked.

The user has authorized reuse of the account already connected to Fire TV. That permission does not make the private credential values available to this checkout. The Railway connector exposes variable names only; no account was copied or embedded. Finish pairing using that authorized account once the TV is available. Do not obtain it by interrupting or accessing the separately tested Fire Stick.

Credentials are stored in Roku's encrypted, developer-ID-scoped registry. Apps with the same signing identity can share that registry; it is not an app-exclusive hardware vault. Sign-out clears account data, favorites and viewing history. Registry failures are reported. The history retains 12 bounded metadata snapshots with no stream URL or request headers; favorites are capped at 100. Catalogs stay in task memory and reload after restart. Uninstall/factory reset/signing-identity changes may remove persisted state.

## Provider behavior and limits

Apollo playlists are the playable inventory. The provider's JSON metadata service enriches matching IMDb IDs on displayed pages. No streams, titles, artwork, episode numbers or listings are fabricated. Missing artwork uses the Apex logo.

TV inventory is loaded lazily from the documented existing integration's pages 1–20. **Load more provider catalog** expands it; the UI reports loaded scope and loaded match counts. Search can find playlist titles and canonical metadata already obtained from browsing; it is not a complete canonical metadata search service. Categories are actual M3U groups. Canonical metadata genres are not a complete category index.

Extensionless VOD is probed using HEAD Content-Type, with a deadline. Feeds rejecting HEAD or omitting a useful type require further provider-specific work; they are not falsely treated as HLS. Actual codec support and stream availability require TV tests. A better error message does not repair an upstream stream.

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

Menus and screenshots cannot prove video playback; Roku screenshots omit the video plane. Advancing player telemetry is supporting evidence, not proof of changing pictures or audible sound. Complete every row in the physical test record, leave Apex Home, and stop remote commands when finished.
