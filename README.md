# SurviveNet – Disaster Connectivity Platform

SurviveNet is a **real-time disaster management and emergency response mobile application** designed for India.  
It helps citizens stay informed about disasters, locate safe zones, send SOS alerts, and enables authorities to manage disaster data in real time.

---

## Key Features

### 🔔 Real-Time Disaster Alerts
- Live weather & disaster alerts using **OpenWeather Weather Alerts API**
- Displays **active and recent disasters**
- India-specific alerts (floods, cyclones, heatwaves, storms)

### 🗺️ Interactive Disaster Map
- Shows:
  - Danger zones
  - Safe zones
  - Rescue shelters

### 🆘 SOS Emergency System
- One-tap SOS call to emergency services (**100 / 112**)
- Sends emergency SMS with:
  - Live GPS location
  - Google Maps link
  - Emergency note

### 👥 Role-Based Access
- **Victim / Public User**
  - View disasters
  - Contact vonlunteers and emergency teams
  - Navigate to shelters
  - Send SOS alerts
- **Volunteer**
  - Contact victims
  - Coordinate rescue efforts

### 🔐 Secure Authentication
- Firebase Authentication
- Role-based Firestore access

---
## 🛠 Tech Stack

### Frontend
- Flutter (Dart)
- Material UI
- flutter_map

### Backend & Services
- Firebase Authentication
- Firebase Firestore
- OpenWeather API
- OpenStreetMap
- Device SMS & Call Intents
---

##  APIs Used

| API | Purpose |
|----|--------|
| OpenWeather | Weather alerts & disaster warnings |
| OpenStreetMap | Map rendering & navigation |
| Firebase | Auth & real-time database |

---
##  Firebase Setup

1. Create a Firebase project
2. Enable:
   - Authentication → Email/Password
   - Firestore Database
3. Add Android app
4. Download `google-services.json`
5. Place it inside: android/app/google-services.json
---

## 🛠️ Installation
Follow these steps to set up and run the SurviveNet application locally.
Make sure you have the following installed:
   - Flutter SDK (Channel Stable, minimum version 3.0.0+)
   - Dart SDK
   - A connected mobile device or a running emulator/simulator.
   - A Firebase Project set up with Firestore enabled.
---

## Getting started 

Clone the repository:
git clone [https://github.com/yourusername/survivenet.git](https://github.com/yourusername/survivenet.git)
cd survivenet


Install Flutter dependencies:

flutter pub get


Configure Firebase:

Follow the official Flutter documentation to add the Firebase configuration files (google-services.json for Android and GoogleService-Info.plist for iOS) to their respective directories.

Run the application:

flutter run

