# Voice Notes AI : Your Smart Recording Companion!

This is a Flutter application that allows users to record audio, transcribe it using the Gemini API, and then chat with the AI about the transcription. It utilizes local storage for saving recordings and chat history.

## Key Features:

1. **Voice Recording**
    - Record audio with microphone permission handling
    - Auto-stop timer (5, 10, 15, 20 minutes) with slider selection
    - Option to extend recording by 5 minutes when time is running out
    - Import external audio files

2. **Transcription**
    - Automatic transcription using Gemini AI
    - Save with default name or custom name
    - AI-powered title generation for recordings

3. **AI Chat**
    - Chat with your transcriptions
    - Default suggestion chips on first chat: "Create a MOM", "Summarize key points", "List action items", "Extract dates and deadlines"
    - Context-aware conversations

4. **Storage**
    - Local SQLite database for recordings and chat history
    - Audio files stored locally
    - Persistent chat conversations

5. **Settings**
    - Google API Key configuration
    - Model selection (default: gemini-2.5-flash-lite)
    - Dark mode toggle

6. **Recordings Library**
    - View all recordings
    - Play audio files
    - Delete recordings
    - Navigate to chat

## Support the Creator

If you found the Bee AI Recorder app helpful, consider buying me a coffee!  
[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/ibrezm)


## File Structure:
- `main.dart` - App entry point
- `screens/home_screen.dart` - Navigation hub
- `screens/recording_screen.dart` - Recording interface
- `screens/transcription_screen.dart` - Transcription & naming
- `screens/chat_screen.dart` - Chat with recordings
- `screens/recordings_list_screen.dart` - Recordings library
- `screens/settings_screen.dart` - App settings
- `utils/database_helper.dart` - SQLite operations
- `utils/gemini_service.dart` - Gemini API integration

Make sure to add your Gemini API key in the Settings before using the app!


## Prerequisites

Before running or building the app, ensure you have the following installed:

* **Flutter SDK:** Make sure Flutter is installed and configured correctly.
* **Dart SDK:** Included with the Flutter SDK.
* **Android Studio / VS Code:** With Flutter and Dart plugins installed.
* **Android Development Environment:** Required for building Android APKs (Java/JDK, Android SDK).
* **Gemini API Key:** You'll need a Google Gemini API key to use the transcription and chat features. You can get one from Google AI Studio.

-----

## Getting Started

### 1\. Clone the Repository

Assuming you have the source code, navigate to the project root directory.

### 2\. Install Dependencies

You need to fetch all the necessary packages defined in the `pubspec.yaml` file. This is done using the `flutter pub get` command.

```bash
dart run flutter_launcher_icons:main
flutter clean
flutter pub get
flutter build apk --release
```

### 3\. Configure the Gemini API Key

The app requires a **Gemini API Key** to function. You will need to enter this key in the app's settings screen once you run it.

1.  Launch the app on a device or emulator.
2.  Navigate to the **Settings** screen (usually via an icon in the AppBar).
3.  Enter your Gemini API Key and save it.

-----

## Icon Creation
- To remove the background from icons, use: https://remove-white-background.imageonline.co/#google_vignette
- To check if the icon background is transparent, use: https://onlinepngtools.com/check-if-png-is-transparent

-----

## TODO
- [ ] Implement a foreground service for persistent recording even when the app is in the background.
- [ ] Increase the maximum auto-stop duration to 2 hours (120 minutes).
- [ ] Add home screen to say that autostop any time is possible 
- [ ] Push to Android store and ask reddit to help in approving 10 users
- [ ] Implement Ideation site with Google auth and AI to what user wants
-----

## Running the App

### Running on a Device/Emulator

To run the app in development mode:

```bash
flutter run
```

-----

## Building a Release APK (Android)

To create a production-ready Android APK file, you'll need to run the `flutter build apk` command with the `--release` flag.

### 1\. Preparation (Signing Key)

Before building a release APK, you must set up a signing key. This is a standard requirement for all Android apps published to the Google Play Store or distributed outside of it.

* **Generate a Key:** Follow the official Flutter documentation to [generate a key and set up keystore properties](https://www.google.com/search?q=https://docs.flutter.dev/deployment/android%23signing-the-app). This involves creating a `.jks` file and adding a `key.properties` file to your project's `android` directory.

### 2\. Execute Build Command

Once your signing key is set up, run the following command in the terminal from the root directory of your Flutter project:

```bash
flutter build apk --release
```

### 3\. Locating the APK

After the build process completes successfully, the final release APK file will be located at:

```
build/app/outputs/flutter-apk/app-release.apk
```

This file is now ready for distribution or submission to an app store.
