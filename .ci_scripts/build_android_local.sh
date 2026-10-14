#!/bin/bash
# Build the Augustus Android APK on a Linux machine, the same way the "Android" CI job does.
# Installs the Android SDK, NDK and CMake into $ANDROID_HOME on first run (~5 GB).
#
# Usage: .ci_scripts/build_android_local.sh
# Optional environment variables:
#   ANDROID_HOME       Android SDK location (default: ~/android-sdk)
#   SDL_VERSION        2.x builds SDL from source; 3.x uses prebuilt AARs (default: 2.32.10, as in CI)
#   SDL_MIXER_VERSION  (default: 2.8.2, or 3.2.2 when SDL_VERSION is 3.x)
#   MAVEN_CENTRAL_MIRROR  Fetch Maven Central artefacts from this URL instead, e.g. if
#                         repo.maven.apache.org answers "429 Too Many Requests":
#                         https://maven-central.storage-download.googleapis.com/maven2/
#
# Output: build/augustus-debug.apk (debug-signed, installable with "adb install")

set -e

cd "$(dirname "$0")/.."

export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export SDL_VERSION="${SDL_VERSION:-2.32.10}"
if [[ "${SDL_VERSION%%.*}" == "3" ]]; then
    export SDL_MIXER_VERSION="${SDL_MIXER_VERSION:-3.2.2}"
else
    export SDL_MIXER_VERSION="${SDL_MIXER_VERSION:-2.8.2}"
fi
export BUILD_TARGET=android

CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip"
NDK_VERSION=$(sed -n 's/.*ndkVersion = "\(.*\)"/\1/p' android/augustus/build.gradle)
CMAKE_VERSION=$(sed -n 's/.*version = "\(.*\)"/\1/p' android/augustus/build.gradle | head -1)

if ! command -v java > /dev/null; then
    echo "Java 17 or newer is required (e.g. sudo apt install openjdk-17-jdk)" >&2
    exit 1
fi

# 1. Android SDK command-line tools
SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
    echo "Installing Android command-line tools to $ANDROID_HOME"
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    curl -sSfL -o /tmp/cmdline-tools.zip "$CMDLINE_TOOLS_URL"
    unzip -q -o /tmp/cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools"
    rm -rf "$ANDROID_HOME/cmdline-tools/latest"
    mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
    rm /tmp/cmdline-tools.zip
fi

# 2. NDK and CMake versions pinned in android/augustus/build.gradle.
# Gradle downloads the SDK platform and build tools itself once the licences are accepted.
echo "Installing SDK packages: ndk;$NDK_VERSION cmake;$CMAKE_VERSION"
yes | "$SDKMANAGER" --licenses > /dev/null || true
"$SDKMANAGER" "platform-tools" "ndk;$NDK_VERSION" "cmake;$CMAKE_VERSION" > /dev/null

# 3. SDL sources or AARs, using the CI script
if [[ "${SDL_VERSION%%.*}" == "3" ]] || ! ls ext/SDL2/SDL2-* > /dev/null 2>&1; then
    ./.ci_scripts/install_dependencies.sh
fi

# 4. Build the debug APK
mkdir -p build
GRADLE_ARGS=()
if [ -n "$MAVEN_CENTRAL_MIRROR" ]; then
    INIT_SCRIPT="$(mktemp --suffix=.gradle)"
    cat > "$INIT_SCRIPT" << GRADLE
def redirect = { RepositoryHandler repos ->
    repos.withType(MavenArtifactRepository).configureEach { repo ->
        if (repo.url.toString().startsWith('https://repo.maven.apache.org/maven2')) {
            repo.url = '$MAVEN_CENTRAL_MIRROR'
        }
    }
}
beforeSettings { settings ->
    redirect(settings.pluginManagement.repositories)
    redirect(settings.buildscript.repositories)
}
allprojects {
    redirect(buildscript.repositories)
    redirect(repositories)
}
GRADLE
    GRADLE_ARGS+=(--init-script "$INIT_SCRIPT")
fi
cd android
TERM=dumb ./gradlew "${GRADLE_ARGS[@]}" assembleDebug
cd ..
cp android/augustus/build/outputs/apk/debug/augustus-debug.apk build/augustus-debug.apk
echo "APK ready: $(pwd)/build/augustus-debug.apk"
