# Smart Emergency Response System

An AI-powered emergency response application designed to detect potential emergencies, recognize distress signals and initiate automated emergency response workflows.

The system combines machine learning, offline speech recognition, mobile application development and cloud-based services to improve the speed and reliability of emergency assistance.

## Overview

Traditional emergency response systems often depend on individuals manually triggering an SOS alert. This project aims to reduce that dependency by introducing automated emergency detection through multiple AI-based mechanisms.

The application integrates fall detection, voice-based distress recognition and scream detection with location-based emergency notifications and a centralized emergency management workflow.

## Key Features

- **AI-Based Fall Detection:** Detects potential human falls using a TensorFlow Lite model and smartphone sensor data.
- **Voice Distress Recognition:** Uses offline speech recognition with Vosk to identify distress-related voice commands.
- **Scream Detection:** Uses a custom-trained CNN model to identify potential screaming sounds.
- **Background Monitoring:** Supports continuous monitoring through Flutter background services.
- **Emergency Countdown:** Initiates a cancellation countdown before processing an emergency alert.
- **Secure Cancellation:** Supports password-based cancellation and biometric authentication.
- **Location Tracking:** Retrieves the user's location during emergency situations.
- **Nearby User Notifications:** Facilitates location-based emergency notifications to nearby users.
- **Trusted Contacts:** Supports emergency contact management.
- **Cloud Integration:** Uses Firebase services for authentication and emergency record management.
- **Emergency Dispatch Interface:** Provides a centralized interface for monitoring and managing emergency alerts.

## Technology Stack

| Category | Technologies |
|---|---|
| Mobile Application | Flutter, Dart |
| Machine Learning | TensorFlow Lite, CNN |
| Fall Detection | 1D CNN, Accelerometer Sensors |
| Voice Recognition | Vosk, Offline Speech Recognition |
| Audio Processing | Dart, FFT-based Processing |
| Backend | Python, Firebase Cloud Functions |
| Database | Cloud Firestore |
| Authentication | Firebase Authentication |
| Location Services | Geolocator |
| Background Processing | Flutter Foreground Task |

## AI Model Implementation

### 1. Fall Detection

- Model: `best_mobile_fall_model.tflite`
- Framework: TensorFlow Lite
- Integration: Flutter
- Sensor input: Smartphone accelerometer data

The fall detection component uses a trained 1D CNN model to identify potential fall events using sensor measurements.

### 2. Scream Detection

- Model: `scream_detection_model.tflite`
- Framework: TensorFlow Lite
- Integration: Flutter
- Input: Processed audio features

The scream detection component analyzes audio input to identify potential screaming events using a CNN-based classification model.

### 3. Voice Distress Recognition

- Technology: Vosk
- Package: `vosk_flutter_service`
- Recognition: Offline English speech recognition

Vosk enables speech recognition without depending on an internet connection for the recognition process. The recognized speech is evaluated by the emergency detection workflow.

## Emergency Response Workflow

1. The application monitors relevant sensor and audio inputs.
2. AI-based detection components identify potential emergency situations.
3. An emergency cancellation countdown is initiated.
4. The user can cancel a false alert using the configured security mechanism.
5. If the alert is not cancelled, the emergency workflow proceeds.
6. The application retrieves available location information.
7. Emergency information is processed through the backend and Firebase services.
8. Notifications and emergency records are handled by the configured response components.

## Project Structure

```text
Smart-Emergency-Response-System/
│
├── android/
├── assets/
│   └── models/
│       ├── best_mobile_fall_model.tflite
│       ├── scream_detection_model.tflite
│       └── vosk-model-small-en-us-0.15.zip
│
├── functions/
│   ├── main.py
│   ├── emergency_worker.py
│   ├── render_app.py
│   └── requirements.txt
│
├── ios/
├── lib/
│   ├── models/
│   ├── screens/
│   ├── services/
│   ├── utils/
│   ├── widgets/
│   └── main.dart
│
├── test/
├── web/
├── windows/
│
├── firebase.json
├── firestore.rules
├── pubspec.yaml
├── pubspec.lock
└── README.md
```

## Installation and Setup

### Prerequisites

- Flutter SDK
- Dart SDK
- Android Studio or VS Code
- Firebase project
- Python 3.11 for the Python backend

### 1. Clone the repository

```bash
git clone https://github.com/souravsct1028723/Smart-Emergency-Response-System.git

cd Smart-Emergency-Response-System
```

### 2. Install Flutter dependencies

```bash
flutter pub get
```

### 3. Configure Firebase

Configure your own Firebase project and update the required Firebase configuration files.

Ensure that Firebase Authentication, Cloud Firestore and other required services are configured.

Never commit private credentials or service-account keys.

### 4. Configure the Python backend

```bash
cd functions

python -m venv venv
```

Activate the environment and install dependencies:

```bash
pip install -r requirements.txt
```

### 5. Run the application

Return to the project root:

```bash
cd ..
flutter run
```

## Results and Evaluation

The project incorporates multiple AI-based emergency detection components.

Quantitative model evaluation results, including confusion matrices and classification metrics, will be documented here as validated experimental results.

## Future Improvements

- Improve emergency detection accuracy.
- Reduce false-positive emergency alerts.
- Enhance offline emergency communication capabilities.
- Improve multi-device emergency coordination.
- Expand the centralized emergency dispatch functionality.
- Optimize background monitoring and battery consumption.

## Disclaimer

This project is an academic software prototype developed for emergency detection and response research. It is not a certified emergency service and should not be relied upon as the sole means of obtaining emergency assistance.

## Author

**Sourav Krishna**

Computer Science and Engineering (Artificial Intelligence)

GitHub: [@souravsct1028723](https://github.com/souravsct1028723)

---

If you find this project interesting, consider giving the repository a star!
