# Qt-for-Python-Web-Browser
Tabbed web browser in Qt for Python (PySide6), based on the official Qt for Python Web Browser example.

### Why?
The original PySide2 Web Browser example in the official tutorial at https://doc.qt.io/qtforpython-5/examples/tabbedbrowser.html is not able to run because of missing files. I replaced the file from other sources (e.g. webengineview.py is only found on pastebin, https://pastebin.com/DPWTWhFa , lol this import is custom file and has nothing to do with apt/pip packages!). I also fixed the [doc] syntax error and updated QWebXXX to QWebEngineXXX as stated at https://doc.qt.io/archives/qt-5.6/qtwebenginewidgets-qtwebkitportingguide.html , etc.

In 2026 it was ported from PySide2 to PySide6, because Qt WebEngine 5.13 shows blank pages on current Linux (glibc 2.34+).

#### Requirement:
    python3 -m venv .venv
    .venv/bin/pip install -r requirements.txt

Uses PySide6 6.12 (Qt WebEngine 6.140, Chromium 140).
Qt 6.5+ needs `libxcb-cursor0` on X11 (`sudo apt install libxcb-cursor0`).
 
#### Usage
    .venv/bin/python main.py

#### Playing MP4 (optional)
This section is only needed for MP4 video; the browser itself runs on any Linux with the steps above.

The Qt WebEngine from pip has no H.264/AAC codecs, so MP4 videos don't play (WebM, MP3, Opus and Vorbis do). A page offering MP4 with an Ogg fallback plays sound only, because Chromium no longer supports Theora video.

`tools/build-webengine-codecs.sh` builds the same Qt WebEngine version as your `.venv` from Qt's official source with the proprietary codecs, and installs it into `.venv`:

    tools/build-webengine-codecs.sh --check      # what the engine in .venv can play
    tools/build-webengine-codecs.sh              # build and install (hours; can be resumed)
    tools/build-webengine-codecs.sh --restore    # back to the pip engine

- The build script is tested on Ubuntu 24.04 only, not on Red Hat-based distributions (Fedora, RHEL). It needs about 60 GB free disk space and at least 8 GB RAM. The script first installs the missing build packages (compiler, cmake, ninja, nodejs and development libraries) with apt and sudo, after asking; packages that are already installed are never upgraded. `--skip-packages` skips only that step and still builds: use it on distributions without apt after installing the equivalent packages with your own package manager (e.g. `dnf`), or on Ubuntu when they are already installed. The build takes several hours; parallel jobs follow your CPU cores and RAM (`--jobs N` to override).
- Work files go to `~/qtwebengine-codecs` (`--work DIR` to change). The finished engine is kept in `~/qtwebengine-codecs/stage`. If you recreate `.venv`, or another PySide6 project uses the same PySide6 version, install that instead of building again (takes seconds):

      tools/build-webengine-codecs.sh --install-only ~/qtwebengine-codecs/stage                       # this .venv
      tools/build-webengine-codecs.sh --venv ../other-project/.venv --install-only ~/qtwebengine-codecs/stage

- `pip install -U PySide6-WebEngine` (or a reinstall) brings back the engine without MP4; run the script again afterwards. With an unchanged version it only reinstalls.
- H.264 and AAC are patented: building for your own use is common practice, but distributing the built engine may need patent licences.

#### Screenshot:

![Web Browser](/screenshot.png?raw=true "Web Browser")  
