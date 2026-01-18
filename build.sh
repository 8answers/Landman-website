#!/bin/bash
set -e

echo "Installing Flutter..."
cd /tmp
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="/tmp/flutter/bin:$PATH"

echo "Flutter version:"
flutter --version

echo "Getting Flutter dependencies..."
cd /opt/build/repo
flutter pub get

echo "Enabling web support..."
flutter create . --platforms web

echo "Building web..."
flutter build web --release

echo "Build complete!"
