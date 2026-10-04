# Pocket Chat

**A chat interface for talking directly to Apple Intelligence.** Pocket Chat is a simple iPhone app that gives you a normal
messaging-style chat window on top of the language model Apple builds into the phone, so you can ask it questions, draft text,
brainstorm and study with it without going through Siri or any other app.

It is built on Apple's **Foundation Models** framework (`SystemLanguageModel` and `LanguageModelSession`, iOS 26+). The model runs
**entirely on the device**: prompts and replies are never sent to a server, no account or API key is needed, and it works offline.
It needs an Apple Intelligence capable iPhone (iPhone 15 Pro or newer) with Apple Intelligence switched on in Settings; if it isn't,
the app tells you exactly what to enable.

## Features
- Streaming replies with a Stop button, Regenerate, and a typing indicator
- Saved conversations (JSON in Application Support) with a history screen, swipe to delete
- Markdown in replies (bold, italic, code, links), copy / share from a long press
- Settings: persona (assistant, concise, tutor, creative writer, custom instructions), response length, creativity (temperature), haptics
- Clear explanations when the model is unavailable (device not eligible, Apple Intelligence off, model still downloading) with a "Check again" button; rechecks when the app returns to the foreground
- The model has a small context window: long chats are automatically condensed and retried once, and a restored chat is rebuilt from a compact recap
- Friendly messages for guardrail, refusal, unsupported-language, busy and context-size errors
- VoiceOver labels, Dynamic Type, light/dark mode

## Layout
- `Sources/ChatLogic.swift`  pure logic (personas, settings, titles, recap) - tested by `tests/main.swift`
- `Sources/ChatEngine.swift`  FoundationModels wrapper (`SystemLanguageModel.default`, `LanguageModelSession`, `streamResponse`)
- `Sources/ChatViewModel.swift`, `Stores.swift`  state, persistence, settings
- `Sources/ContentView.swift`  all screens;  `PocketChatApp.swift`  entry point
- `Assets.xcassets`  original app icon;  `project.yml`  XcodeGen spec

## Build
    swiftc -O Sources/ChatLogic.swift tests/main.swift -o /tmp/t && /tmp/t          # logic tests
    xcodegen generate
    # simulator (uses the Mac's own Apple Intelligence model)
    xcodebuild -project PocketChat.xcodeproj -scheme PocketChat -sdk iphonesimulator -configuration Release \
      -destination 'platform=iOS Simulator,name=<an iPhone simulator>' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
    # device
    xcodebuild -project PocketChat.xcodeproj -scheme PocketChat -sdk iphoneos -configuration Release \
      -destination 'id=<iPhone UDID>' -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
      DEVELOPMENT_TEAM=<your team id> -derivedDataPath build-dev build
    xcrun devicectl device install app --device <UDID> build-dev/Build/Products/Release-iphoneos/PocketChat.app

Test hook: launch argument `-autoprompt "text"` sends a prompt automatically.
Requires an Apple Intelligence capable device (iPhone 15 Pro or newer) with Apple Intelligence switched on in Settings.
The Apple team ID is intentionally blank in `project.yml`.
