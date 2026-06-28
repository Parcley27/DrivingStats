# Switchback

An iOS app for recording and analyzing driving dynamics using your iPhone's built-in sensors.

## What it does

Switchback captures motion and GPS data while you drive, then gives you a detailed breakdown of how smooth (or not) your driving was. It's useful for anyone who wants to quantify their driving style, whether for performance driving, driver training, or just curiosity.

## Features

- **Live recording:** Real-time readouts of speed, g-forces, and hard event counts while you drive
- **Smoothness Score:** A 0-100 score computed from hard braking, cornering, acceleration, and peak jerk
- **Route map:** Colour-coded by speed, with an interactive scrubber for speed and elevation at any point
- **Session history:** All drives are saved locally with full stats, charts, and a trend line over your last 12 sessions
- **Session merging:** Automatically combine consecutive drives taken within a configurable time window
- **Named locations:** Reverse-geocodes start/end points and lets you save custom location names
- **G-g diagram:** Lateral vs. longitudinal acceleration envelope for performance analysis

## Technical

- SwiftUI + SwiftData
- CoreMotion (IMU at 10 Hz) + CoreLocation (GPS)
- MapKit for route rendering and geocoding
- Swift Charts for real-time and historical visualization
- Fully on-device — no network dependency

## Privacy
Everything is entirely local and run completely on your device, with the exception of GPS (of course) and automatic route names (these can be disabled). None of your data is transmitted, saved, or otherwise accessed by us or another third party.

## Requirements

iOS 26.1+, iPhone with working GPS and motion sensors.

## A note on how this was built
Switchback was written almost entirely by AI coding tools
