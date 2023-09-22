# Qt-for-Python-Web-Browser
Web Browser Code in Qt for Python (PySide2) tutorial.

### Why?
The first Web Browser example code in the official tutorial at https://doc-snapshots.qt.io/qtforpython/tutorials/examples/tabbedbrowser.html is not able to run because of missing files. I replaced the file from other sources (e.g. webengineview.py is only found on pastebin, https://pastebin.com/DPWTWhFa , lol this import is custom file and has nothing to do with apt/pip packages!). I also fixed the [doc] syntax error and updated QWebXXX to QWebEngineXXX as stated at https://doc.qt.io/archives/qt-5.6/qtwebenginewidgets-qtwebkitportingguide.html , etc.

#### Requirement:
    python3 -m pip install -r requirements.txt
 
#### Usage
    python3 main.py

#### Screenshot:

![Pyside2 Web Browser](/screenshot.png?raw=true "Pyside2 Web Browser")  
