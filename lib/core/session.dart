import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/models.dart';
import 'backend/api_client.dart';
import 'hotel_store.dart';

/// Keeps the signed-in user across app restarts.
class SessionStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _userIdKey = 'user_id';
  static const String _accessKey = 'access_token';
  static const String _refreshKey = 'refresh_token';

  static Future<void> save(AppUser user) async {
    try {
      await _storage.write(key: _userIdKey, value: user.id.toString());
    } catch (_) {
      // Storage may be unavailable (tests, some web browsers): the session simply won't persist.
    }
  }

  /// Persists the backend tokens every time they change (sign-in, refresh, sign-out).
  static void watch(ApiClient api) {
    api.onSessionChanged = (session) async {
      try {
        if (session == null) {
          await _storage.delete(key: _accessKey);
          await _storage.delete(key: _refreshKey);
        } else {
          await _storage.write(key: _accessKey, value: session.accessToken);
          await _storage.write(key: _refreshKey, value: session.refreshToken);
        }
      } catch (_) {}
    };
  }

  /// Restores the user only while the account still exists and is active (US-03).
  static Future<AppUser?> restore(HotelStore store) async {
    final remote = store.remote;
    if (remote != null) {
      watch(remote.api);
      String? access;
      String? refresh;
      try {
        access = await _storage.read(key: _accessKey);
        refresh = await _storage.read(key: _refreshKey);
      } catch (_) {
        return null;
      }
      if (access == null) return null;
      return remote.restore(ApiSession(access, refresh));
    }

    String? raw;
    try {
      raw = await _storage.read(key: _userIdKey);
    } catch (_) {
      return null;
    }
    final user = store.userById(int.tryParse(raw ?? ''));
    if (user == null || !user.active) {
      await clear();
      return null;
    }
    store.currentUser = user;
    return user;
  }

  static Future<void> clear() async {
    try {
      await _storage.delete(key: _userIdKey);
      await _storage.delete(key: _accessKey);
      await _storage.delete(key: _refreshKey);
    } catch (_) {}
  }
}
