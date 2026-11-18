import os, shutil, sqlite3, sys
from PySide6.QtCore import QByteArray, QDateTime, QStandardPaths, QUrl
from PySide6.QtNetwork import QNetworkCookie
from PySide6.QtWebEngineCore import QWebEnginePage, QWebEngineProfile
from PySide6.QtWebEngineWidgets import QWebEngineView
from PySide6.QtWidgets import QApplication

from PySide6 import QtCore

_web_actions = [QWebEnginePage.WebAction.Back, QWebEnginePage.WebAction.Forward,
               QWebEnginePage.WebAction.Reload,
               QWebEnginePage.WebAction.Undo, QWebEnginePage.WebAction.Redo,
               QWebEnginePage.WebAction.Cut, QWebEnginePage.WebAction.Copy,
               QWebEnginePage.WebAction.Paste, QWebEnginePage.WebAction.SelectAll]

# Qt 6 made QWebEngineProfile.defaultProfile() off-the-record. Qt 5's default
# profile was the persistent profile named "Default", so use that name
# explicitly to keep the existing cookies, cache and site data in
# <AppDataLocation>/QtWebEngine/Default and <CacheLocation>/QtWebEngine/Default.
_profile = None

def browser_profile():
    global _profile
    if _profile is None:
        old_cookies = _read_qt5_cookies()
        _profile = QWebEngineProfile('Default', QApplication.instance())
        if old_cookies:
            _restore_cookies(_profile, old_cookies)
    return _profile

# Chromium in Qt WebEngine 6 erases a Cookies database written by Qt 5's
# Chromium (schema version < 13) instead of migrating it. Once, before the
# profile opens it, keep a copy as "Cookies.qt5" and read its cookies so
# they can be added back through the cookie store.
_QT5_COOKIE_SCHEMA_LIMIT = 13

def _read_qt5_cookies():
    try:
        db = os.path.join(QStandardPaths.writableLocation(
            QStandardPaths.StandardLocation.AppDataLocation),
            'QtWebEngine', 'Default', 'Cookies')
        backup = db + '.qt5'
        if not os.path.isfile(db) or os.path.exists(backup):
            return []
        con = sqlite3.connect('file:{}?mode=ro'.format(db), uri=True)
        try:
            version = int(con.execute(
                "SELECT value FROM meta WHERE key='version'").fetchone()[0])
        finally:
            con.close()
        if version >= _QT5_COOKIE_SCHEMA_LIMIT:
            return []
        shutil.copy2(db, backup)
        if os.path.isfile(db + '-journal'):
            shutil.copy2(db + '-journal', backup + '-journal')
        con = sqlite3.connect('file:{}?mode=ro'.format(backup), uri=True)
        con.row_factory = sqlite3.Row
        try:
            rows = [dict(r) for r in con.execute('SELECT * FROM cookies')]
        finally:
            con.close()
        print('[WebEngine] Found {} cookies in Qt 5 profile (schema {}); '
              'backup kept as {}'.format(len(rows), version, backup), flush=True)
        return rows
    except Exception as e:  # never block startup on migration
        print('[WebEngine] WARNING: could not read Qt 5 cookies: {}'.format(
            type(e).__name__), file=sys.stderr, flush=True)
        return []

def _restore_cookies(profile, rows):
    now_ms = QDateTime.currentMSecsSinceEpoch()
    restored = skipped = 0
    for row in rows:
        try:
            value = row.get('value') or ''
            host = row['host_key']
            expires_us = int(row.get('expires_utc') or 0)  # since 1601-01-01
            expires_ms = expires_us // 1000 - 11644473600000 if expires_us else 0
            if not value or (expires_ms and expires_ms <= now_ms):
                skipped += 1  # encrypted or expired
                continue
            secure = bool(row.get('is_secure', row.get('secure', 0)))
            cookie = QNetworkCookie(QByteArray(row['name'].encode()),
                                    QByteArray(value.encode()))
            cookie.setPath(row.get('path') or '/')
            cookie.setSecure(secure)
            cookie.setHttpOnly(bool(row.get('is_httponly', row.get('httponly', 0))))
            samesite = row.get('samesite', -1)
            if samesite == 1:
                cookie.setSameSitePolicy(QNetworkCookie.SameSite.Lax)
            elif samesite == 2:
                cookie.setSameSitePolicy(QNetworkCookie.SameSite.Strict)
            if expires_ms:
                cookie.setExpirationDate(QDateTime.fromMSecsSinceEpoch(expires_ms))
            if host.startswith('.'):
                cookie.setDomain(host)  # domain cookie; otherwise host-only
            origin = QUrl('{}://{}/'.format('https' if secure else 'http',
                                            host.lstrip('.')))
            profile.cookieStore().setCookie(cookie, origin)
            restored += 1
        except Exception:
            skipped += 1
    print('[WebEngine] Restored {} Qt 5 cookies ({} expired/encrypted/invalid '
          'skipped)'.format(restored, skipped), flush=True)

class WebEngineView(QWebEngineView):

    enabled_changed = QtCore.Signal(QWebEnginePage.WebAction, bool)

    @staticmethod
    def web_actions():
        return _web_actions

    @staticmethod
    def minimum_zoom_factor():
        return 0.25

    @staticmethod
    def maximum_zoom_factor():
        return 5

    def __init__(self, tab_factory_func, window_factory_func):
        super(WebEngineView, self).__init__(browser_profile())
        self._tab_factory_func = tab_factory_func
        self._window_factory_func = window_factory_func
        page = self.page()
        self._actions = {}
        for web_action in WebEngineView.web_actions():
            action = page.action(web_action)
            action.changed.connect(self._enabled_changed)
            self._actions[action] = web_action

    def is_web_action_enabled(self, web_action):
        return self.page().action(web_action).isEnabled()

    def createWindow(self, window_type):
        if window_type == QWebEnginePage.WebWindowType.WebBrowserTab or window_type == QWebEnginePage.WebWindowType.WebBrowserBackgroundTab:
            return self._tab_factory_func()
        return self._window_factory_func()

    def _enabled_changed(self):
        action = self.sender()
        web_action = self._actions[action]
        self.enabled_changed.emit(web_action, action.isEnabled())