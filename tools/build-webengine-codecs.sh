#!/usr/bin/env bash
# Build Qt WebEngine with the proprietary codecs (H.264 and AAC: MP4/M4A/MOV files, and MKV files using them)
# and install it into a PySide6 virtual environment, replacing the pip engine, which lacks them.
# (The pip engine already plays MP3, WebM VP8/VP9/AV1, Opus, Vorbis and FLAC.)
#
#   tools/build-webengine-codecs.sh [--venv DIR] [--work DIR] [--jobs N] [--skip-packages]
#                                                                         build and install (resumable)
#   tools/build-webengine-codecs.sh --check   [--venv DIR]                 show what the engine can play
#   tools/build-webengine-codecs.sh --restore [--venv DIR]                 put the original pip files back
#   tools/build-webengine-codecs.sh --install-only STAGE [--venv DIR]      install an already built stage dir
#
# Needs Linux x86_64, ~60 GB free disk and >= 8 GB RAM. Building Chromium takes several hours
# (roughly 3-6 h on 8 cores). Rerunning continues where it stopped.
# Tested on Ubuntu 24.04; not tested on Red Hat-based distributions (Fedora, RHEL).
# Step 1 installs the build packages (compiler, cmake, ninja, nodejs and -dev libraries) with apt and
# sudo. --skip-packages skips only that step; everything else still runs. Use it on distributions
# without apt after installing the equivalent packages with your own package manager (e.g. dnf),
# or on Ubuntu when they are already installed. A missing package makes the configure or build
# step stop with an error naming it.
# H.264/AAC are patented: fine for your own use; distributing the built binaries may need licences.
set -euo pipefail

VENV=.venv
WORK="$HOME/qtwebengine-codecs"
JOBS=""
PACKAGES=1
ACTION=build
STAGE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --venv) VENV=$2; shift 2 ;;
    --work) WORK=$2; shift 2 ;;
    --jobs) JOBS=$2; shift 2 ;;
    --skip-packages) PACKAGES=0; shift ;;
    --check) ACTION=check; shift ;;
    --restore) ACTION=restore; shift ;;
    --install-only) ACTION=install; STAGE=$2; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

PY="$VENV/bin/python"
[ -x "$PY" ] || die "no Python at $PY (use --venv DIR)"
QTDIR=$("$PY" -c 'import os, PySide6; print(os.path.join(os.path.dirname(PySide6.__file__), "Qt"))') \
  || die "PySide6 is not installed in $VENV"
[ -f "$QTDIR/lib/libQt6WebEngineCore.so.6" ] || die "PySide6-WebEngine is not installed in $VENV"
BACKUP="$QTDIR/.webengine-original"
WE_LIBS="libQt6WebEngineCore libQt6WebEngineWidgets libQt6WebEngineQuick libQt6WebEngineQuickDelegatesQml"

# What the engine in the venv can play. Runs a page in an offscreen QWebEnginePage.
check() {
  QT_QPA_PLATFORM=offscreen "$PY" - <<'PYEOF'
import json, sys
from PySide6.QtCore import QCoreApplication, QTimer
from PySide6.QtWidgets import QApplication
from PySide6.QtWebEngineCore import QWebEnginePage, qWebEngineVersion, qWebEngineChromiumVersion
app = QApplication(sys.argv)
types = {'MP4 H.264 + AAC': 'video/mp4; codecs="avc1.42E01E, mp4a.40.2"', 'MP3': 'audio/mpeg',
         'AAC': 'audio/mp4; codecs="mp4a.40.2"', 'WebM VP9 + Opus': 'video/webm; codecs="vp9, opus"',
         'WebM AV1': 'video/webm; codecs="av01.0.05M.08"', 'Ogg Vorbis': 'audio/ogg; codecs="vorbis"'}
page = QWebEnginePage()
def done(result):
    print('Qt WebEngine {} (Chromium {})'.format(qWebEngineVersion(), qWebEngineChromiumVersion()))
    # canPlayType answers "probably" (supported), "maybe" (container known, codec not stated) or "" (no)
    words = {'probably': 'yes', 'maybe': 'maybe (codec not stated)', '': 'no'}
    for name, answer in json.loads(result).items():
        print('  {:16} {}'.format(name, words.get(answer, answer)))
    app.exit(0 if json.loads(result)['MP4 H.264 + AAC'] else 3)
def run(ok):
    page.runJavaScript('JSON.stringify(Object.fromEntries(Object.entries({}).map(([k, t]) => '
                       '[k, document.createElement("video").canPlayType(t)])))'.format(json.dumps(types)), 0, done)
page.loadFinished.connect(run)
page.setHtml('<p>codec check</p>')
QTimer.singleShot(30000, lambda: (print('timeout'), app.exit(4)))
sys.exit(app.exec())
PYEOF
}

# Copy the built engine over the pip one; the originals are kept once in $BACKUP.
install_stage() {
  local stage=$1 f real
  for f in $WE_LIBS; do
    [ -e "$stage/lib/$f.so.6" ] || die "$stage/lib/$f.so.6 is missing: not a Qt WebEngine install"
  done
  [ -x "$stage/libexec/QtWebEngineProcess" ] || die "$stage/libexec/QtWebEngineProcess is missing"
  if [ ! -d "$BACKUP" ]; then
    say "Backing up the original engine to $BACKUP"
    mkdir -p "$BACKUP/lib" "$BACKUP/libexec"
    for f in $WE_LIBS; do cp -a "$QTDIR/lib/$f.so.6" "$BACKUP/lib/"; done
    cp -a "$QTDIR/libexec/QtWebEngineProcess" "$BACKUP/libexec/"
    cp -a "$QTDIR/resources" "$BACKUP/resources"
    cp -a "$QTDIR/translations/qtwebengine_locales" "$BACKUP/qtwebengine_locales"
    [ -d "$QTDIR/qml/QtWebEngine" ] && cp -a "$QTDIR/qml/QtWebEngine" "$BACKUP/qml-QtWebEngine"
  fi
  say "Installing the codec-enabled engine into $QTDIR"
  for f in $WE_LIBS; do
    real=$(readlink -f "$stage/lib/$f.so.6")       # the versioned file, installed under the SONAME pip uses
    install -m 755 "$real" "$QTDIR/lib/$f.so.6"
  done
  install -m 755 "$stage/libexec/QtWebEngineProcess" "$QTDIR/libexec/QtWebEngineProcess"
  for f in "$stage"/resources/*; do
    [ -f "$f" ] && install -m 644 "$f" "$QTDIR/resources/"
  done
  for f in "$stage"/translations/qtwebengine_locales/*.pak; do
    [ -f "$f" ] && install -m 644 "$f" "$QTDIR/translations/qtwebengine_locales/"
  done
  if [ -d "$stage/qml/QtWebEngine" ]; then
    cp -a "$stage/qml/QtWebEngine/." "$QTDIR/qml/QtWebEngine/"
  fi
  date '+built engine installed %F %T' > "$BACKUP/INSTALLED"
  say "Checking the installed engine"
  check || die "the installed engine still cannot play MP4 (or failed to start); undo with --restore"
  echo
  echo "Done. Note: 'pip install --upgrade/--force-reinstall PySide6-WebEngine' replaces it with the pip"
  echo "engine again; then rerun this script (the build is kept in $WORK, so it only reinstalls)."
}

restore() {
  [ -d "$BACKUP" ] || die "no backup in $BACKUP: the pip engine is still in place"
  local f
  for f in $WE_LIBS; do cp -a "$BACKUP/lib/$f.so.6" "$QTDIR/lib/"; done
  cp -a "$BACKUP/libexec/QtWebEngineProcess" "$QTDIR/libexec/"
  rm -rf "$QTDIR/resources" && cp -a "$BACKUP/resources" "$QTDIR/resources"
  rm -rf "$QTDIR/translations/qtwebengine_locales" && cp -a "$BACKUP/qtwebengine_locales" "$QTDIR/translations/qtwebengine_locales"
  if [ -d "$BACKUP/qml-QtWebEngine" ]; then
    rm -rf "$QTDIR/qml/QtWebEngine" && cp -a "$BACKUP/qml-QtWebEngine" "$QTDIR/qml/QtWebEngine"
  fi
  rm -rf "$BACKUP"
  say "Original pip engine restored"
}

case $ACTION in
  check) check; exit $? ;;
  restore) restore; exit 0 ;;
  install) install_stage "$(readlink -f "$STAGE")"; exit 0 ;;
esac

# ---------------------------------------------------------------- build
# Build exactly the versions the venv uses: Qt (e.g. 6.12.0) and Qt WebEngine (e.g. 6.140.0, released
# separately since Qt 6.12, numbered after its Chromium version).
read -r QT_VERSION WE_VERSION < <("$PY" -c '
from PySide6.QtCore import qVersion
from PySide6.QtWebEngineCore import qWebEngineVersion
print(qVersion(), qWebEngineVersion())')
WE_SERIES=${WE_VERSION%.*}
say "Building Qt WebEngine $WE_VERSION with proprietary codecs for Qt $QT_VERSION"
echo "Work directory: $WORK"

if [ "$PACKAGES" = 1 ] && ! command -v apt-get >/dev/null; then
  die "no apt: install the build packages with your package manager, then rerun with --skip-packages"
fi
mkdir -p "$WORK"
free_gb=$(df -BG --output=avail "$WORK" | tail -1 | tr -dc 0-9)
mem_gb=$(awk '/MemTotal/ {print int($2 / 1048576)}' /proc/meminfo)
[ "$free_gb" -ge 60 ] || [ -f "$WORK/build/build.ninja" ] || die "need ~60 GB free in $WORK, have ${free_gb} GB (use --work DIR)"
[ "$mem_gb" -ge 7 ] || die "need at least 8 GB RAM, have ${mem_gb} GB"
if [ -z "$JOBS" ]; then
  # Chromium compile/link jobs need ~2-3 GB each; too many jobs end in the OOM killer.
  JOBS=$(( mem_gb / 3 )); [ "$JOBS" -ge 1 ] || JOBS=1
  [ "$JOBS" -le "$(nproc)" ] || JOBS=$(nproc)
fi
echo "Parallel jobs: $JOBS (RAM ${mem_gb} GB, $(nproc) cores; override with --jobs N)"

if [ "$PACKAGES" = 1 ]; then
say "Installing build packages (sudo)"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
  build-essential cmake ninja-build pkg-config python3 python3-html5lib python3-venv nodejs gperf bison flex \
  curl xz-utils libnss3-dev libdbus-1-dev libfontconfig-dev libfreetype-dev libxkbcommon-dev \
  libxkbcommon-x11-dev libxkbfile-dev libx11-dev libx11-xcb-dev libxcomposite-dev libxdamage-dev libxext-dev \
  libxfixes-dev libxrandr-dev libxtst-dev libxshmfence-dev libxcb1-dev libxcb-dri3-dev libdrm-dev libgbm-dev \
  libegl-dev libgl-dev libgl1-mesa-dev libvulkan-dev libasound2-dev libpulse-dev libudev-dev libexpat1-dev \
  zlib1g-dev libva-dev libpci-dev libkrb5-dev libcups2-dev libxml2-dev libxslt1-dev
fi

# Qt itself (headers and CMake files) in the same version as PySide6's, from the Qt Company's binaries.
QTDEV="$WORK/qt/$QT_VERSION/gcc_64"
if [ ! -x "$QTDEV/bin/qt-configure-module" ]; then
  say "Downloading Qt $QT_VERSION development files (aqtinstall)"
  [ -x "$WORK/aqt/bin/aqt" ] || { python3 -m venv "$WORK/aqt" && "$WORK/aqt/bin/pip" install -q -U aqtinstall; }
  "$WORK/aqt/bin/aqt" install-qt linux desktop "$QT_VERSION" linux_gcc_64 \
      -m qtwebchannel qtpositioning --outputdir "$WORK/qt" \
    || die "aqt failed; list the modules with: $WORK/aqt/bin/aqt list-qt linux desktop --modules $QT_VERSION linux_gcc_64"
fi
[ -d "$QTDEV/lib/cmake/Qt6Quick" ] || die "Qt Quick is missing in $QTDEV"

# Qt WebEngine source (official release, checked against Qt's md5sums.txt when present).
SRCURL="https://download.qt.io/official_releases/qtwebengine/$WE_SERIES/$WE_VERSION/src"
TARBALL="qtwebengine-everywhere-src-$WE_VERSION.tar.xz"
SRC="$WORK/qtwebengine-everywhere-src-$WE_VERSION"
if [ ! -d "$SRC" ]; then
  if [ ! -f "$WORK/$TARBALL.done" ]; then
    say "Downloading $TARBALL (~600 MB)"
    curl -fL -C - -o "$WORK/$TARBALL" "$SRCURL/$TARBALL" || die "download failed: $SRCURL/$TARBALL"
    if curl -fsL -o "$WORK/md5sums.txt" "$SRCURL/md5sums.txt"; then
      (cd "$WORK" && grep " $TARBALL\$" md5sums.txt | md5sum -c -) || die "checksum mismatch; delete $WORK/$TARBALL"
    fi
    touch "$WORK/$TARBALL.done"
  fi
  say "Unpacking"
  tar -xf "$WORK/$TARBALL" -C "$WORK"
fi

BUILD="$WORK/build"
mkdir -p "$BUILD"
if [ ! -f "$BUILD/build.ninja" ]; then
  say "Configuring"
  (cd "$BUILD" && "$QTDEV/bin/qt-configure-module" "$SRC" -webengine-proprietary-codecs -- \
      -DCMAKE_BUILD_TYPE=Release -DFEATURE_webengine_system_ffmpeg=OFF \
      -DFEATURE_qtpdf_build=OFF -DPython3_EXECUTABLE=/usr/bin/python3) \
    | tee "$WORK/configure.log"
  # The summary goes to build/config.summary, not to the console.
  grep -iE 'Proprietary Codecs.*yes' "$BUILD/config.summary" "$WORK/configure.log" >/dev/null 2>&1 \
    || echo "warning: the configure summary does not show 'Proprietary Codecs ... yes'; see $BUILD/config.summary"
fi

say "Building (several hours; safe to interrupt and rerun)"
export NINJAJOBS="-j$JOBS"         # Qt WebEngine passes this to Chromium's own ninja
(cd "$BUILD" && cmake --build . --parallel "$JOBS")

say "Staging the build"
STAGE="$WORK/stage"
rm -rf "$STAGE"
(cd "$BUILD" && cmake --install . --prefix "$STAGE" >/dev/null)

install_stage "$STAGE"
