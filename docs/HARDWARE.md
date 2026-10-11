# Philips Roku hardware and evidence

Research checked against official Roku documentation on 2026-10-10. The project target is the Philips 40PFL6533/F7, reported Roku model H530X, OS 15.3.4 build 2303, with a 1080p display. The original hardware research was followed by installation and read-only/runtime checks on the actual television. Actual test outcomes belong in `VERIFICATION.md`; documentation, successful compilation, and packaging do not establish playback.

## What the documentation establishes

Roku lists the **Miami / H000X** family as a 2022 platform with ARM quad-core 1 GHz CPU, 512 MB RAM, OpenGL ES 2.0, maximum **720p UI**, maximum **1080p60 playback**, and no HDR. The installed native app confirmed `roDeviceInfo.GetModel()` returns H000X on this H530X television. Roku explains that its TV family identifier can differ from the specific model displayed in Settings. A 1080p panel therefore does not establish a 1080p SceneGraph rendering surface. [Hardware specifications](https://developer.roku.com/dev/docs/hardware)

The native app uses one `Video` node. Roku's current reference limits prebuffering to one stream; a second prebuffer replaces the first. An archived Roku staff response also identifies one concurrent video stream as a hardware limitation. This is enough to avoid promising native multi-view, but it is not a fresh H530X concurrency measurement. No documented decoder-count or simultaneous-Video feature query was found. A server-composited mosaic would be one decoded stream; this project does not provision such a service. [Video reference](https://developer.roku.com/dev/docs/video), [Roku staff discussion](https://forum.developer.roku.com/t/multiple-rovideoplayers-behavior/3253)

For this target, prefer AVC/H.264 with AAC stereo in HLS or DASH. Roku's AVC table describes up to 1920x1080, main/high profiles, levels 4.1/4.2, up to 60 fps, and up to 10 Mbps; device-specific playback still requires testing. HEVC is documented for 4K-capable devices, so do not assume it on this 2K family. Each feed's codec, frame rate, manifest, audio tracks, authentication, and seeking behavior must be exercised. A filename extension alone does not establish compatibility. [Streaming specifications](https://developer.roku.com/dev/docs/media)

## Runtime capabilities to record

Use `GetModel()`, `GetModelDetails()`, `GetOSVersion()`, `GetVideoMode()`, `GetUIResolution()`, `GetSupportedGraphicsResolutions()`, `GetGraphicsPlatform()`, and `GetDisplayProperties()` to establish the actual device and rendering surface. Use `CanDecodeVideo()`/`CanDecodeAudio()` with the intended formats, retaining their `result` flags and suggested supported alternatives. Check `GetDrmInfo()`/`GetDrmInfoEx()` when applicable. The old `HasFeature("1080p_hardware")` and `GetVideoDecodeInfo()` are deprecated. A positive single-format response does not establish simultaneous stream capacity. [ifDeviceInfo](https://developer.roku.com/dev/docs/ifdeviceinfo)

If concurrency is investigated separately, independently record each node's state, errors, and advancing positions, then observe two different changing pictures on the physical screen. Paused images, changing clocks, multiple posters, two objects allocated in memory, or two successful format probes are not proof of two decoders. Do not relabel a UI demonstration as live multi-view.

## Persistent credentials and EPG

Roku's registry is encrypted and persists across launches/reboots. It is scoped to the **developer ID**, so apps signed by the same developer can share it. The limit is **32 KB after zlib compression**. Store short credentials/tokens and settings, explicitly `Flush()` necessary updates, check available space and results, and avoid frequent writes. The registry is not an app-exclusive hardware credential vault. Developer tooling can query app registry data; keep developer access credentials private. Uninstall, factory reset, explicit deletion, and signing-identity changes can remove data. [roRegistry](https://developer.roku.com/dev/docs/roregistry), [ifRegistry](https://developer.roku.com/dev/docs/ifregistry), [ECP registry query](https://developer.roku.com/dev/docs/external-control-api)

`roUrlTransfer.EnableEncodings(true)` enables gzip transfer encoding. This documents an HTTP-compressed XML response path; it does not prove a bare `.xml.gz` body without the appropriate HTTP encoding will be decoded. No general native gunzip method appears in `ifByteArray`, and no built-in XMLTV importer was found. Raw gzip feed handling and large XMLTV memory use remain separate verification items. A service may normalize feeds to bounded XML when necessary. [ifUrlTransfer](https://developer.roku.com/dev/docs/ifurltransfer), [ifByteArray](https://developer.roku.com/dev/docs/ifbytearray)

## Packaging and device tool

Tools require Python 3.9+ and only its standard library. Run commands from the repository root. `npm run build` compiles into `dist/staging`, then `scripts/package.py` produces `dist/apex-after-dark-roku.zip` and `dist/apex-after-dark-roku.zip.sha256`. It includes only `manifest`, BrightScript in `source/`, XML/BrightScript in `components/`, and supported image assets in `images/`. It excludes configuration, credentials, logs, source maps, tests, and hidden files. It rejects runtime symlinks, unsafe ZIP entries, and common embedded-credential patterns. These checks complement source review; they are not a general secret-detection proof. ZIP order, timestamps, and permissions are fixed for reproducible output with the same Python/zlib toolchain. A failed validation removes any unvalidated final ZIP and stale checksum.

```sh
npm test
npm run build
python3 scripts/package.py
```

The last command repackages existing compiler staging; it does not compile changed source. Do not use it as a substitute for `npm run build` after source edits.

Every device command first queries ECP and requires **model-number H530X**. Only explicit private IPv4 addresses are accepted; there is no discovery, DNS lookup, arbitrary ECP endpoint, or alternate-model override. HTTP redirects and environment proxies are disabled. No Fire TV/ADB operations exist.

```sh
python3 scripts/roku.py --host 192.168.0.110 info
python3 scripts/roku.py --host 192.168.0.110 media
python3 scripts/roku.py --host 192.168.0.110 perf
```

These read-only queries output filtered device metadata, player telemetry, or sideloaded-app CPU percentages and memory bytes. Serial numbers, room names, media URLs, provider titles, and process identifiers are omitted. The `info` result includes `developer_enabled` when reported. ECP settings may require **Settings → System → Advanced system settings → Control by mobile apps → Enabled**, and performance queries require Developer Mode. [ECP](https://developer.roku.com/dev/docs/external-control-api)

Enable Developer Mode using Roku's documented remote sequence (Home three times, Up twice, then Right, Left, Right, Left, Right), accept the developer agreement, and set a developer password. This password is for local installation, separate from provider account credentials. The device reboots. A Roku holds **one sideloaded app**; installation replaces the existing one. [Developer setup](https://developer.roku.com/dev/docs/developer-setup)

```sh
python3 scripts/roku.py --host 192.168.0.110 install
python3 scripts/roku.py --host 192.168.0.110 launch
python3 scripts/roku.py --host 192.168.0.110 key Back
python3 scripts/roku.py --host 192.168.0.110 key Home
```

The install command validates the ZIP and checksum, uses HTTP Digest as `rokudev`, and prompts with `getpass` in an interactive terminal. `ROKU_DEV_PASSWORD` from an existing protected environment is also supported. Alternatively, provide `--password-file .private/roku-password`; the file must be owned by the current user, have mode 600, and have no symlinks. No password value is accepted as a command-line argument or printed. Do not put a literal password in a shell command. A successful install response means installation only; confirm launch, UI, account access, and playback separately.

## Capturing evidence without secrets

```sh
python3 scripts/roku.py --host 192.168.0.110 logs --seconds 15 --output evidence/private/runtime.json
python3 scripts/roku.py --host 192.168.0.110 screenshot --output evidence/private/home.jpg
```

Screenshot also prompts for the developer password. Output files are confined to ignored `evidence/private/`, reject symlinks, and use mode 600. Do not screenshot account entry or other sensitive screens. Roku screenshots capture **UI only and exclude content playback**; 1080p screenshots additionally require 4K-capable hardware. Review them for layout, focus, and displayed recovery states. They cannot verify changing frames, audio, or multi-view. [Screenshot utility](https://developer.roku.com/dev/docs/developer-setup)

The logs command reads port 8085 without sending debugger commands, for at most 60 seconds. It does not expose arbitrary console output. It accepts `APEX_EVENT ` followed by JSON and filters enumerated event/screen/state/kind values plus bounded numeric metrics. Fields such as URLs, tokens, account names, titles, and unknown text are omitted. It also extracts BrightScript compile/runtime error codes and source locations, excluding surrounding text. Omitted-line counts are reported; an empty filtered log does not mean an error-free run. For example:

```brightscript
print "APEX_EVENT " + FormatJson({event: "playback", state: "playing", position: 12.5})
```

Open collection before a launch to capture startup diagnostics. BrightScript console output and error traces come from port 8085; additional SceneGraph diagnostics and resource tools are documented for port 8080. Raw console output can include app-provided secrets and is intentionally not an export option here. [Debugging](https://developer.roku.com/dev/docs/debugging)

Record the package SHA-256 and build with each physical run. Pair telemetry with direct observation or a consented camera recording of changing frames; test audible sound separately. Mark untested rows explicitly, including real sign-in, restored credentials, actual movie/episode/live playback, remote controls, stream switching, network recovery, memory pressure, and any concurrency experiment. Finish at Apex Home and stop sending commands.
