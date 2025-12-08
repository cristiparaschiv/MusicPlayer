# Adding SFBAudioEngine Package Dependency

The code has been updated to use SFBAudioEngine for metadata extraction. You need to add the package dependency to your Xcode project.

## Option 1: Via Xcode UI (Recommended)

1. Open `MusicPlayer.xcodeproj` in Xcode
2. Select the **MusicPlayer** project in the navigator (blue icon at top)
3. Select the **MusicPlayer** target
4. Click on the **Package Dependencies** tab
5. Click the **+** button
6. Enter this URL: `https://github.com/sbooth/SFBAudioEngine`
7. Select **Dependency Rule**: "Up to Next Major Version" with "1.0.0"
8. Click **Add Package**
9. Select **SFBAudioEngine** in the product list
10. Click **Add Package** again

## Option 2: Via Swift Package Manager

If you want to verify the package first, you can check it here:
- Repository: https://github.com/sbooth/SFBAudioEngine
- Documentation: Well-maintained, supports all major audio formats
- License: MIT

## After Adding the Package

Once the package is added, build the project:
```bash
xcodebuild -scheme MusicPlayer -configuration Debug build
```

The updated code will now use SFBAudioEngine for superior metadata extraction with support for:
- Better format support (FLAC, APE, Opus, etc.)
- More complete metadata extraction
- Embedded artwork extraction
- ReplayGain support
- Sort tags
- Lyrics
- And much more!
