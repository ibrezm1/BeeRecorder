# Voice Transcribe & Chat App

This is a Flutter application that allows users to record audio, transcribe it using the Gemini API, and then chat with the AI about the transcription. It utilizes local storage for saving recordings and chat history.

## Features

* 🎤 **Audio Recording:** Record, pause, resume, and stop audio.
* ⏱️ **Auto-Stop Timer:** Set a duration for the recording to stop automatically.
* 💾 **Local Storage:** Save recordings and chat history locally using `sqflite`.
* 🤖 **Gemini Transcription:** Transcribe recorded audio using the `gemini-2.5-flash-lite` model.
* 💬 **AI Chat:** Chat with the Gemini model about the transcription content.
* ⚙️ **Settings:** Configure your Gemini API key.

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
flutter pub get
```

### 3\. Configure the Gemini API Key

The app requires a **Gemini API Key** to function. You will need to enter this key in the app's settings screen once you run it.

1.  Launch the app on a device or emulator.
2.  Navigate to the **Settings** screen (usually via an icon in the AppBar).
3.  Enter your Gemini API Key and save it.

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