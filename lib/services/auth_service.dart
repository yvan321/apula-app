import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keyUserEmail = 'user_email';
  static const String _keyLoginTimestamp = 'login_timestamp';

  /// Save login session when user successfully logs in
  static Future<void> saveLoginSession(String email) async {
    await _storage.write(key: _keyIsLoggedIn, value: 'true');
    await _storage.write(key: _keyUserEmail, value: email);
    await _storage.write(key: _keyLoginTimestamp, value: DateTime.now().toIso8601String());
    print('✅ Login session saved for: $email');
  }

  /// Check if user has a valid login session
  static Future<bool> hasValidSession() async {
    try {
      final isLoggedIn = await _storage.read(key: _keyIsLoggedIn);
      final email = await _storage.read(key: _keyUserEmail);
      
      // Check if Firebase user is still authenticated
      final currentUser = FirebaseAuth.instance.currentUser;
      
      if (isLoggedIn == 'true' && email != null && currentUser != null) {
        print('✅ Valid session found for: $email');
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ Error checking session: $e');
      return false;
    }
  }

  /// Get stored user email
  static Future<String?> getStoredEmail() async {
    return await _storage.read(key: _keyUserEmail);
  }

  /// Validate user role and verification status
  static Future<Map<String, dynamic>?> validateUser(String email) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase())
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        return null;
      }

      final userData = query.docs.first.data();
      final role = (userData['role'] ?? 'User').toString().toLowerCase();
      final verified = userData['verified'] == true;

      return {
        'userData': userData,
        'role': role,
        'verified': verified,
        'isValidUser': role == 'user' && verified,
      };
    } catch (e) {
      print('❌ Error validating user: $e');
      return null;
    }
  }

  /// Clear login session (logout)
  static Future<void> clearLoginSession() async {
    await _storage.delete(key: _keyIsLoggedIn);
    await _storage.delete(key: _keyUserEmail);
    await _storage.delete(key: _keyLoginTimestamp);
    await FirebaseAuth.instance.signOut();
    print('✅ Login session cleared');
  }

  /// Auto-login with stored session
  static Future<bool> autoLogin() async {
    try {
      final hasSession = await hasValidSession();
      if (!hasSession) return false;

      final email = await getStoredEmail();
      if (email == null) return false;

      // Validate user is still a verified regular user
      final validation = await validateUser(email);
      if (validation == null || !validation['isValidUser']) {
        // User is no longer valid, clear session
        await clearLoginSession();
        return false;
      }

      print('✅ Auto-login successful for: $email');
      return true;
    } catch (e) {
      print('❌ Auto-login error: $e');
      return false;
    }
  }

  /// Get session info for debugging
  static Future<Map<String, String?>> getSessionInfo() async {
    return {
      'isLoggedIn': await _storage.read(key: _keyIsLoggedIn),
      'email': await _storage.read(key: _keyUserEmail),
      'timestamp': await _storage.read(key: _keyLoginTimestamp),
    };
  }
}
