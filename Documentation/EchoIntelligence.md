# Echo Intelligence

Echo Intelligence extends the current `Widget` app; Home, navigation, playback, library and podcasts remain owned by their existing managers. Open it with the sparkle button in Home. Configuration lives under Settings → Echo Intelligence. Music continues while the full-screen assistant is open or dismissed.

## Included

- Procedural **3D Metal** amber line sphere: nested organic tangent walks, five crossing orbital rings, dense core and sparse particles. One static geometry buffer and one instanced draw, perspective camera, quaternion rotation, pinch zoom, two-finger pan/roll, inertial movement and double-tap reset.
- Idle/listening/thinking/speaking/action/success/error render states. Microphone and synthesized speech amplitudes drive gentle deformation. Rotation/shimmer respect Reduce Motion; rendering pauses behind sheets, on dismissal and in inactive scenes. Low Power Mode and thermal pressure reduce resolution/frame rate. 60 FPS is a target, not a measured physical-device result.
- Minimal input surface, expandable transcript, current music control, per-action confirmation, provider settings, credential storage and conversation/action history.
- Streaming conversations, cancellation, bounded context, up to eight provider rounds and sixteen tool calls per request. Mutations are deduplicated within a turn. Unknown tools/arguments, invalid numeric values and unsupported enums are rejected.
- English and Dutch localization through the existing string catalog. Other app languages currently fall back to English for these new strings.
- Speech recognition with explicit microphone/speech permissions. Recognized phrases are sent automatically after at least two seconds without new words or detected voice activity; punctuation-only changes do not restart this pause. Early final results open another recognition segment so resumed speech is retained. Final recognition may add up to 600 ms before a single send. Empty recordings and cancelled/dismissed sessions do not send. Offline Only requires on-device recognition for the selected language. Optional system voices synthesize actual PCM audio; music can continue, duck or pause/resume. Closing/backgrounding releases speech resources.

## Providers

| Provider | Implementation | Requirements / limits |
| --- | --- | --- |
| Automatic | Prefers Apple, then installed Qwen; OpenAI only if online requests are explicitly allowed and a key exists | No fallback after a request fails; never silently changes from offline to cloud |
| Apple Foundation Models | `SystemLanguageModel`, `LanguageModelSession.streamResponse`, separate typed native tools for current playback, search, play, transport and favorites; advanced actions feed the same registry | iOS 26+, supported hardware, enabled/downloaded Apple Intelligence, supported language; Apple's context/safety/availability limits still apply. Its local model prewarms when Intelligence opens; compact context, intent-specific tools and greedy sampling reduce planning overhead. Replies are bounded to 768 generated tokens |
| Qwen Local | MLX Qwen3 0.6B 4-bit, token streaming, bounded KV cache, directory-only model/tokenizer loading | Physical Metal device, at least 4 GB RAM, ~500 MB download and 1.5 GB available storage. The model itself is chat-only; common Dutch/English music commands run through the shared deterministic app-command path without model inference. Structured chat roles and `enable_thinking: false`; hardware inference needs device validation |
| OpenAI | HTTPS Chat Completions SSE and function tools | User key and a compatible model; default `gpt-4.1-mini` |
| Gemini | Google's documented OpenAI-compatible `/v1beta/openai/chat/completions` endpoint | User Gemini API key; default `gemini-2.5-flash`; model must support streaming/function calls |
| Custom | Same adapter with configurable HTTPS base URL/model and optional bearer key | Include `/v1` if the server requires it. No plain HTTP, embedded URL credentials or redirects; compatible streaming/tool contract required |

Online integrations require **Offline Only off** and **Allow AI requests to leave this device on**. API credentials use a separate Keychain service with `WhenUnlockedThisDeviceOnly`; keys are not placed in history, defaults or repository files. Connection Test sends a small real prompt using the entered credential; Save Key persists it for conversations. OpenAI uses `max_completion_tokens`, and HTTP diagnostics distinguish rejected credentials, quota/billing, rate limits, unavailable models and unsupported parameters without echoing secret-bearing provider messages. No provider credentials were available in the implementation environment, so real cloud responses were not tested here.

### Qwen dependencies and model lifecycle

Both `project.yml` and the Swift Playgrounds package pin `mlx-swift-examples` **2.25.6**, using its `MLXLLM` and `MLXLMCommon` products. That historical tag must come from **mlx-swift-examples**: the subsequently split `mlx-swift-lm` repository has an incomplete package layout at that tag. MLX and swift-transformers are transitive dependencies. No API keys or model weights are bundled.

Download is explicitly initiated in Settings, retrieves the model repository's immutable revision, and downloads only `config.json`, `tokenizer.json`, `tokenizer_config.json` and `model.safetensors`. A staging directory becomes installed only after all files succeed. Progress, cancellation, deletion and disk-space checks are implemented. A failed/cancelled download is removed. Inference loads only the installed directory; missing assets raise an error rather than triggering an online fallback. The local model preloads when Intelligence opens and keeps its model container between turns. Stop, dismissal, backgrounding, provider changes and model deletion unload it; starting voice input retains the warm model. The first generated token is streamed immediately. Qwen responses are bounded to 512 generated tokens. The MLX cache is limited to 32 MB and cleared after generation. Verify real peak/resident-memory behavior on target hardware.

## Supported app actions

All actions use existing Echo managers, not a second music engine. Read-only queries are available in Chat Only. Ask Before Actions asks before mutations. Full App Control executes registered mutations directly, but playlist deletion always asks. The assistant cannot change its own permission mode, consent, credentials or account/security settings.

- **Library:** focused title/artist/album/genre search, favorites, release-year range, explicit exclusions, recent additions, most/least played and least recently played ordering. Returns up to 40 real IDs and limited metadata, not the whole library or audio.
- **Playback:** ordered/shuffled song selection, artist/album selection via search, pause/resume/next/previous, seek, shuffle/repeat, queue add/remove/clear/replace while retaining the current occurrence. Playback reports success only after engine playback is observed; seek reports a request, not a falsely synchronous completion.
- **Playlists:** list/create/rename/add/remove/reorder/play/shuffle/delete. Smart playlists resolve with the existing library evaluator; direct edits of their rules are not exposed. Reordering validates complete membership. No music-file deletion tool exists.
- **DJ:** persistent request/exclusion/selection context, learning-based real-library ranking, upcoming-queue refinement without restarting the current song, and continuous filtered Echo Flow. Subsequent refills honor the allowed candidate IDs and use existing skip/completion learning. Normal Echo Flow can be explicitly started/stopped. A fresh app launch retains DJ preferences, but intentionally does not start playback automatically.
- **Podcasts:** query saved/cached episodes and playback progress, play/resume, download/cancel download, subscribe/unsubscribe a known episode's show. Download results distinguish scheduled from complete.
- **Settings:** system/light/dark/custom appearance, existing EQ presets, crossfade 0 or 1–12 seconds, mono.
- **Navigation:** Home, library, podcasts, fetch, search, settings, playlists, favorites and songs. Uses `AppRouter`; hidden tabs open as a sheet rather than rewriting tab preferences.

Example: “Find my 30 most played rock songs, create Rock Favorites, shuffle it and start playing.” The provider searches locally, receives IDs, creates the playlist and starts existing playback. Each step returns its actual outcome; failures are not rolled back automatically. “Make it calmer” can search metadata and refine the same DJ session; it cannot measure tempo/energy that Echo does not have.

## Privacy and persistence

Prompt/tool-result context is minimal and bounded by whole turns. Song and podcast metadata is treated as untrusted data, never permission or executable instructions. AI-only offline mode does not disable Echo's existing podcast, artwork or music networking. With offline mode disabled, Apple's speech service may process microphone audio remotely; the voice setting explains this.

Conversation history is local, protected and excluded from backup, with a maximum of 50 conversations. The action audit keeps 200 records. Turning off conversation saving does not delete previous history; Clear History removes conversations and audit records. A cancelled operation may already have affected the player: cancellation stops further work, not playback the user requested. Incomplete tool results are marked cancelled/unconfirmed and must not be retried automatically.

## Files

Foundation Models returns structured tool validation/permission errors to the model instead of opaque `echo_action` invocation failures. Common Apple intents have distinct typed tools instead of requiring a JSON string. Favoriting the current song pins its ID before confirmation and never calls transport. Registered advanced action names are constrained during generation. Reasoning blocks and incomplete `<think>` tags are withheld from streaming, stored assistant answers and speech, including existing-history display.

New implementation is in `Echo.swiftpm/Echo/Intelligence/`:

- `AIModels.swift`, `EchoToolRegistry.swift`: portable types, privacy/permission policies, SSE framing and strict schemas.
- `AISettingsStore.swift`: preferences, Keychain credentials, protected local history.
- `AIQuickCommands.swift`: conservative complete-command matching for Dutch/English status, pause/resume, next/previous, current-track favorites and playing a real local song. These use the existing validation, confirmation, favorite-target pinning and action history, then return a local result without an extra model round. Named-song favorite requests restrict the model to search/status/favorite tools; unadvertised tools are rejected. Negations, quotations and compound commands remain with the model. Complex model-generated actions cannot be guaranteed correct; ambiguous targets must be clarified.
- `AIProviders.swift`, `AppleAITools.swift`, `QwenAIProvider.swift`: provider protocol, dispatch, streaming and model lifecycle.
- `AIConversationController.swift`, `EchoActionEngine.swift`: conversation orchestration, approvals, deduplication and real Echo integration.
- `AIResponseSafety.swift`: reasoning-block filtering before display/storage/speech, provider request/error compatibility and voice endpoint policy.
- `AISpeechController.swift`: recognition, PCM synthesis, levels and audio-session restoration.
- `UniverseRenderer.swift`, `EchoIntelligenceView.swift`, `AISettingsView.swift`: renderer bridge, camera interaction and user interface.

Shader: `Echo.swiftpm/Echo/Resources/EchoUniverse.metal`.
Integration changes: `AppRouter.swift`, `ContentView.swift`, `HomeView.swift`, `SettingsView.swift`, `AudioPlayerManager.swift`, `EqualizedAudioPlayer.swift`, `Localizable.xcstrings`, both app plist files, both package/project definitions, `WidgetBuild.yml`. Manual test sources: `Tests/EchoIntelligenceTests.swift` and `UITests/HomeInteractionTests.swift`. These are no longer executed by the automatic IPA/Home workflows.

## Build and physical iPhone test

1. Check out `codex/echo-intelligence` on a Mac with Xcode 26 or later and XcodeGen 2.45.4+.
2. Run `xcodegen generate --spec project.yml`, open `Echo.xcodeproj`, select your signing team for Echo and EchoWidget, and use the existing matching App Group entitlements/provisioning. Existing Python/LAME dependencies and their repository build instructions still apply. No new paid AI entitlement is introduced.
3. Confirm `EchoUniverse.metal` is in the Echo compile sources. XcodeGen discovers it under the app source tree. Swift Playgrounds processes the Resources directory. Microphone/speech usage descriptions are present in both plist paths.
4. Build/run the Echo scheme on an iPhone with iOS 26+. Import several real local songs with different artists/genres, create a test playlist and subscribe to a podcast.
5. Start a song, open the Home sparkle button, rotate/pinch/two-finger pan/roll/reset the universe, type a question, expand history, then close. Confirm music never restarts merely because the assistant opens/closes. Repeat with Reduce Motion and Low Power Mode.
6. On supported hardware, select Apple and ask a general question offline. On unsupported hardware verify the availability error. Download Qwen with internet, enable airplane mode and ask a question; cancel generation and watch memory after dismissal. Remove the model and verify offline failure rather than a network fallback.
7. For OpenAI/Gemini/custom, disable Offline Only, explicitly allow cloud requests, enter/save your key and model, then Test Connection. Ask follow-up questions and cancel mid-stream. Re-enable Offline Only and verify that cloud providers are blocked.
8. Exercise pause, seek, playlist creation and a multi-step request in all permission modes. Deny an action; it must not execute. In Full App Control try playlist deletion; it must still ask. Check action history and verify results in the original Echo screens.
9. Start a DJ mix excluding an artist/genre, skip beyond the initial queue and inspect refills. Refine the mix while a song is playing; the current position must continue. Start normal Echo Flow and verify the previous DJ filter is cleared.
10. Enable voice input, grant permissions, dictate, then pause and verify one automatic send without tapping Send. Test denied permission, unsupported offline language, phone interruptions and Bluetooth routes. For spoken replies test mix/duck/pause and verify restoration after completion, cancellation and dismissal.
11. Automatic unit/UI test execution is removed from the IPA build. Home previews are manual (`workflow_dispatch`) and capture screenshots without UI tests. Existing test sources can still be run manually in Xcode when wanted. Qwen and Apple on-device models cannot be validated by these simulator tests; use physical hardware for model availability, offline recognition, thermal/GPU/60 FPS and memory checks.
12. Inspect Quick Access and For You in light, dark and custom themes: card shadows should fade below the horizontal rails. Open Now Playing from the MiniPlayer and quickly tap pause, queue, seek or close during the opening spring. Controls must respond; Home, tabs and the hidden MiniPlayer must stay inactive until the player closes. Repeat with a partial opening drag and Reduce Motion. The UI suite checks that underlying controls are unavailable while Now Playing is open; rapid taps during the spring still need device verification.

## Explicit limits

This is implemented source code, not a claim that every device/provider has been exercised. Qwen model inference is chat-only; the shared direct-command path handles supported common music commands for every provider. There is no live web search, arbitrary iOS access, external sharing, account modification, song-file deletion, arbitrary script execution or automatic import/download of missing songs. Mood matching uses existing metadata and listening preferences, not acoustic analysis; exact-duration mixes, professional beatmatching, gradual artist morphs and guaranteed tempo synchronization are not implemented. Navigation to individual album/artist-detail pages and editing smart playlist rules are not exposed yet. No general transactional undo is provided; playlist deletion retains explicit confirmation. Some provider-generated/system error text follows the provider/OS language.
