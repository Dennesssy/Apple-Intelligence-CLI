# Xcode Integration Setup Guide

## Overview

Your app now has **two-way communication** between the chat UI and Xcode:
- ✅ Read code from Xcode into chat
- ✅ Insert AI-generated code back into Xcode
- ✅ App Store compliant (no private APIs)

## Required Setup Steps

### 1. Create App Group

Both your main app and Xcode extension need to share an App Group to communicate.

#### For Main App Target (`AppleiChat`):
1. Select your main app target in Xcode
2. Go to **Signing & Capabilities**
3. Click **+ Capability**
4. Add **App Groups**
5. Click **+** and create: `group.com.yourcompany.appleicode`
   - Replace `com.yourcompany` with your actual team identifier

#### For Extension Target (`AppleiCode`):
1. Select your extension target
2. Repeat steps 2-5 above
3. **Use the exact same App Group identifier**

### 2. Update App Group Identifier in Code

Replace `group.com.yourcompany.appleicode` in these files:

**SourceEditorCommand.swift** (line 15):
```swift
private let appGroupIdentifier = "group.YOUR_ACTUAL_GROUP_ID"
```

**ChatManager.swift** (line 56):
```swift
private let appGroupIdentifier = "group.YOUR_ACTUAL_GROUP_ID"
```

### 3. Configure Extension Commands

Add commands to your extension's `Info.plist`:

1. Open `AppleiCode/Info.plist`
2. Find `NSExtension` > `NSExtensionAttributes` > `XCSourceEditorCommandDefinitions`
3. Add these command definitions:

```xml
<key>XCSourceEditorCommandDefinitions</key>
<array>
    <dict>
        <key>XCSourceEditorCommandClassName</key>
        <string>SourceEditorCommand</string>
        <key>XCSourceEditorCommandIdentifier</key>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER).SendToChat</string>
        <key>XCSourceEditorCommandName</key>
        <string>Send to AI Chat</string>
    </dict>
    <dict>
        <key>XCSourceEditorCommandClassName</key>
        <string>SourceEditorCommand</string>
        <key>XCSourceEditorCommandIdentifier</key>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER).InsertFromChat</string>
        <key>XCSourceEditorCommandName</key>
        <string>Insert from AI Chat</string>
    </dict>
    <dict>
        <key>XCSourceEditorCommandClassName</key>
        <string>SourceEditorCommand</string>
        <key>XCSourceEditorCommandIdentifier</key>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER).ReplaceWithAI</string>
        <key>XCSourceEditorCommandName</key>
        <string>Refactor with AI</string>
    </dict>
</array>
```

### 4. Enable Extension in Xcode

After building and running:

1. Open **System Settings** (macOS)
2. Go to **Privacy & Security** > **Extensions** > **Xcode Source Editor**
3. Enable your extension: `AppleiCode`

## How It Works

### Sending Code to Chat

1. In Xcode, select some code
2. Go to **Editor** menu > **AppleiCode** > **Send to AI Chat**
3. Your chat window automatically receives the code with context
4. AI analyzes it and responds

### Inserting Code from Chat

1. Chat with AI and get code suggestions
2. Click **"Insert in Xcode"** button on any AI response
3. In Xcode, position cursor where you want the code
4. Go to **Editor** > **AppleiCode** > **Insert from AI Chat**
5. Code appears at cursor position

### Refactoring Code

1. Select code in Xcode
2. **Editor** > **AppleiCode** > **Refactor with AI**
3. AI suggests improvements in chat
4. Click **"Insert in Xcode"** to replace

## Architecture

```
┌─────────────────────┐         App Group          ┌──────────────────┐
│   Main macOS App    │◄─────Shared Container─────►│ Xcode Extension  │
│   (ChatManager)     │                             │ (SourceEditor)   │
└─────────────────────┘                             └──────────────────┘
         │                                                    │
         │ Monitors:                                         │ Writes:
         │ - xcode-context.json                              │ - xcode-context.json
         │                                                   │
         │ Writes:                                           │ Reads:
         │ - ai-generated-code.txt                           │ - ai-generated-code.txt
         └───────────────────────────────────────────────────┘
```

## App Store Compliance

✅ **Uses only official APIs:**
- XcodeKit framework (public)
- App Groups (standard)
- FileManager shared containers

✅ **No private APIs or hacks:**
- No AppleScript required
- No Accessibility API abuse
- Fully sandboxed

✅ **User-initiated actions only:**
- Extension commands require manual menu selection
- No automatic code injection

## Troubleshooting

### Extension doesn't appear in Xcode menu
- Check that extension is enabled in System Settings
- Rebuild the extension target
- Restart Xcode

### Code not appearing in chat
- Verify App Group identifier matches in both targets
- Check App Group is enabled in Capabilities
- Look for "Failed to access App Group container" in Console.app

### "Insert from AI Chat" doesn't work
- Ensure you clicked "Insert in Xcode" button first
- Check cursor is positioned in a valid text file
- Verify file is editable (not read-only)

## Next Steps

### Optional Enhancements

1. **Add keyboard shortcuts** for commands in Info.plist
2. **Show notification** when code is ready to insert
3. **Smart code formatting** based on file type
4. **Multi-file context** for larger refactorings
5. **Undo/redo support** for inserted code

## Testing

1. Build and run your main app
2. Build the extension target (Product > Build For > Running)
3. Enable extension in System Settings
4. Open a Swift file in Xcode
5. Select some code
6. Try "Send to AI Chat" command
7. Verify code appears in your chat window

---

**Note:** Remember to replace `group.com.yourcompany.appleicode` with your actual App Group ID!
