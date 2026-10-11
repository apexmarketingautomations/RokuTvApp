# Fire TV playback comparison — 2026-10-11

This review used the current `main` source and audit in the separate [Fire TV repository](https://github.com/apexmarketingautomations/fire-tv-app-). It was read-only. The Roku app remains in its own repository and uses the existing Apollo/Railway contracts.

## Same provider source, different playback engine

| Path | Fire TV | Roku | Finding |
| --- | --- | --- | --- |
| Catalog | [`ApolloProvider`](https://github.com/apexmarketingautomations/fire-tv-app-/blob/main/src/providers/apollo/ApolloProvider.ts) requests Apollo `/api/list/{encoded credentials}/m3u8/{livetv,movies,tvshows/N}` and parses its M3U entries. | `ApiTask.brs` requests the same Apollo paths and `Core.brs` parses the M3U entries. | No separate Roku movie service or URL substitution was found. |
| Playable source | Fire TV `resolveStream()` returns the catalog item's `streamUrl`, `streamHeaders`, and format; `sourceFromItem()` also preserves them. | Roku `ApiResolve()` reselects the item from its current catalog, preserves its URL/headers, resolves unknown format with HEAD, then sets native Video `url`, `streamFormat`, and `httpHeaders`. | Both apps use provider-supplied stream URLs. Roku does not rewrite movie URLs. |
| HLS playback | Fire TV routes adaptive streams through Shaka. On a correlated critical video-segment network failure, [`ShakaPlayer`](https://github.com/apexmarketingautomations/fire-tv-app-/blob/main/src/shakaplayer/ShakaPlayer.ts) can select an unfailed compatible rendition, up to two switches per load. | Roku uses SceneGraph's native Video node. It reports aggregate playback errors but does not expose Shaka's variant tracks or `selectVariantTrack()` operation. | Fire TV's rendition-specific workaround cannot be copied directly into the native Roku player. A blind replay of the same URL may encounter the same failed segment. |
| Unknown extensionless format | Fire TV's `streamProbe.ts` tries HEAD, then a bounded Range GET when HEAD cannot identify the format. | Roku currently uses HEAD only and rejects an unidentified VOD format. | This is a Roku compatibility gap for HEAD-rejected/GET-supported streams. It does not explain the sampled Roku movies that were already identified as HLS and then failed during playback. |

## What the Fire TV evidence establishes

The [October Fire TV audit](https://github.com/apexmarketingautomations/fire-tv-app-/blob/main/docs/USER_EXPERIENCE_AUDIT_2026-10-10.md) recorded a master playlist with empty child playlists for **Jackass: The Movie**, a disconnected GET after a successful HEAD for **Frankie Go Boom**, and an empty redirect reply for **The Ballad of a Small Player**. Those are provider-path failures seen outside Roku. It found an I Swear master, first video playlist and one ranged segment response, but did **not** test sustained physical playback for that title. The same audit found that the guide's redirect destination failed DNS lookup, while the entry host resolved.

The [September Fire TV audit](https://github.com/apexmarketingautomations/fire-tv-app-/blob/main/docs/APEX_AFTER_DARK_AUDIT_2026-09-27.md) isolated a different movie's stall near 42:08 to one failed video rendition; two alternates worked. Fire TV's Shaka failover then carried that movie past 43 minutes. That proves a provider rendition failure can coexist with an app recovery defect. It does not identify the exact cause of Roku's I Swear failure near 175 seconds.

On Roku build 1.0.6, **I Swear** repeatedly stops near 175 seconds with native `mediaerror -5`; **Wake Up Dead Man** and **Bugonia** stop during startup with native error `-3`. Numeric downloaded-segment events and successful Mac probes for selected high-rendition segments do not establish full stream integrity or a decoder root cause. The user reports the sampled Apollo movies fail on another app/device as well. These combined observations make provider availability a serious concern, but they do not prove every movie is unavailable or that no Roku-specific issue remains.

Representative movie playback through a sustained interval with visible picture and audible sound remains the acceptance gap. Do not count the Fire TV source audit, a successful manifest/segment request, or the Roku's short playback clock advance as a movie E2E pass.

The strongest named comparison for a future physical run is **Jackass: Best and Last (2026)**, because Fire TV's September audit observed playback beyond its prior 42-minute failure after rendition recovery. Its present provider availability and Roku behavior still need a fresh test. The Roku TV was showing its PlayStation HDMI input during this read-only review, so no new TV playback result was recorded.
