import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _pendingEmailVerificationUserKey =
      "pending_email_verification_user";

  static bool _firebaseAvailable = false;
  static bool _lastAppCheckTokenAvailable = false;
  static DateTime? _lastCloudSessionRefreshAt;

  static FirebaseAuth get _auth {
    return FirebaseAuth.instance;
  }

  static void setFirebaseAvailable(bool value) {
    _firebaseAvailable = value;

    if (!value) {
      _lastAppCheckTokenAvailable = false;
    }
  }

  static bool get firebaseAvailable {
    return _firebaseAvailable;
  }

  static bool get lastAppCheckTokenAvailable {
    return _lastAppCheckTokenAvailable;
  }

  static User? get currentUser {
    if (!_firebaseAvailable) {
      return null;
    }

    return _auth.currentUser;
  }

  static Stream<User?> get authStateChanges {
    if (!_firebaseAvailable) {
      return Stream<User?>.value(null);
    }

    return _auth.userChanges();
  }

  static bool get isSignedIn {
    return currentUser != null;
  }

  static bool get isGuest {
    return currentUser?.isAnonymous ?? false;
  }

  static String get userEmail {
    final user = currentUser;

    if (user == null) {
      return "";
    }

    if (user.isAnonymous) {
      return "Guest";
    }

    return user.email ?? "";
  }

  static String get userId {
    return currentUser?.uid ?? "";
  }

  static bool get isEmailVerified {
    final user = currentUser;

    if (user == null || user.isAnonymous) {
      return false;
    }

    return user.emailVerified;
  }

  static Future<void> sendEmailVerification({
    String languageCode = "en",
  }) async {
    _ensureFirebaseAvailable();

    await refreshCloudSession(forceRefresh: true);
    final user = currentUser;

    if (user == null || user.isAnonymous || user.emailVerified) {
      return;
    }

    await _auth.setLanguageCode(languageCode);
    await user.sendEmailVerification();
    await rememberPendingEmailVerification();
  }

  static Future<void> rememberPendingEmailVerification() async {
    final user = currentUser;

    if (user == null || user.isAnonymous || user.emailVerified) {
      await clearPendingEmailVerification();
      return;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_pendingEmailVerificationUserKey, user.uid);
    } catch (_) {
      // Verification itself must still work if local preference storage fails.
    }
  }

  static Future<bool> hasPendingEmailVerification() async {
    final user = currentUser;

    if (user == null || user.isAnonymous || user.emailVerified) {
      return false;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_pendingEmailVerificationUserKey) ==
          user.uid;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearPendingEmailVerification() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_pendingEmailVerificationUserKey);
    } catch (_) {
      // This marker is only a recovery aid and never blocks authentication.
    }
  }

  static Future<void> reloadCurrentUser() async {
    _ensureFirebaseAvailable();
    await _refreshAppCheckToken(forceRefresh: true);

    final user = currentUser;
    await user?.reload();
    await currentUser?.getIdToken(true);

    if (currentUser?.emailVerified ?? false) {
      await clearPendingEmailVerification();
    }

    _lastCloudSessionRefreshAt = DateTime.now();
  }

  static Future<void> refreshCloudSession({bool forceRefresh = false}) async {
    _ensureFirebaseAvailable();

    final now = DateTime.now();
    final lastRefresh = _lastCloudSessionRefreshAt;

    if (!forceRefresh &&
        lastRefresh != null &&
        now.difference(lastRefresh) < const Duration(minutes: 5)) {
      return;
    }

    final user = currentUser;

    if (user == null) {
      throw FirebaseAuthException(
        code: "user-not-found",
        message: "Please sign in again.",
      );
    }

    await _refreshAppCheckToken(forceRefresh: true);
    await user.reload();

    final refreshedUser = currentUser;

    if (refreshedUser == null) {
      throw FirebaseAuthException(
        code: "user-not-found",
        message: "Please sign in again.",
      );
    }

    await refreshedUser.getIdToken(true);

    if (refreshedUser.emailVerified) {
      await clearPendingEmailVerification();
    }

    _lastCloudSessionRefreshAt = now;
  }

  static Future<UserCredential> continueAsGuest() async {
    _ensureFirebaseAvailable();

    return _auth.signInAnonymously();
  }

  static Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) async {
    _ensureFirebaseAvailable();

    final cleanedEmail = email.trim().toLowerCase();

    if (cleanedEmail.isEmpty) {
      throw FirebaseAuthException(
        code: "missing-email",
        message: "Please enter your email address.",
      );
    }

    if (password.length < 6) {
      throw FirebaseAuthException(
        code: "weak-password",
        message: "Password must contain at least 6 characters.",
      );
    }

    final existingUser = currentUser;

    if (existingUser != null && existingUser.isAnonymous) {
      final emailCredential = EmailAuthProvider.credential(
        email: cleanedEmail,
        password: password,
      );

      return existingUser.linkWithCredential(emailCredential);
    }

    return _auth.createUserWithEmailAndPassword(
      email: cleanedEmail,
      password: password,
    );
  }

  static Future<void> updatePreferredName(String name) async {
    _ensureFirebaseAvailable();
    final cleanName = name.trim().replaceAll(RegExp(r"\s+"), " ");

    if (cleanName.isEmpty) {
      throw FirebaseAuthException(
        code: "missing-display-name",
        message: "Please enter the name you would like us to use.",
      );
    }

    await currentUser?.updateDisplayName(cleanName);
    await currentUser?.reload();
  }

  static Future<UserCredential> login({
    required String email,
    required String password,
  }) async {
    _ensureFirebaseAvailable();

    final cleanedEmail = email.trim().toLowerCase();

    if (cleanedEmail.isEmpty) {
      throw FirebaseAuthException(
        code: "missing-email",
        message: "Please enter your email address.",
      );
    }

    if (password.isEmpty) {
      throw FirebaseAuthException(
        code: "missing-password",
        message: "Please enter your password.",
      );
    }

    return _auth.signInWithEmailAndPassword(
      email: cleanedEmail,
      password: password,
    );
  }

  static Future<void> sendPasswordResetEmail({required String email}) async {
    _ensureFirebaseAvailable();

    final cleanedEmail = email.trim().toLowerCase();

    if (cleanedEmail.isEmpty) {
      throw FirebaseAuthException(
        code: "missing-email",
        message: "Please enter your email address.",
      );
    }

    await _auth.sendPasswordResetEmail(email: cleanedEmail);
  }

  static Future<void> logout() async {
    if (!_firebaseAvailable) {
      return;
    }

    await clearPendingEmailVerification();
    await _auth.signOut();
  }

  static Future<void> deleteCurrentUser() async {
    _ensureFirebaseAvailable();

    final user = currentUser;

    if (user == null) {
      return;
    }

    await user.delete();
  }

  static void _ensureFirebaseAvailable() {
    if (_firebaseAvailable) {
      return;
    }

    throw FirebaseAuthException(
      code: "firebase-unavailable",
      message: "Firebase is not available on this device right now.",
    );
  }

  static Future<bool> _refreshAppCheckToken({bool forceRefresh = false}) async {
    try {
      final token = await FirebaseAppCheck.instance.getToken(forceRefresh);
      _lastAppCheckTokenAvailable = token != null && token.trim().isNotEmpty;
      return _lastAppCheckTokenAvailable;
    } catch (_) {
      // Continue with Firebase Auth/Firestore. If App Check enforcement is on,
      // the protected service will return the precise rejection to the UI.
      _lastAppCheckTokenAvailable = false;
      return false;
    }
  }

  static Future<bool> checkAppCheckToken() async {
    if (!_firebaseAvailable) {
      _lastAppCheckTokenAvailable = false;
      return false;
    }

    return _refreshAppCheckToken(forceRefresh: true);
  }

  static String errorMessage(Object error, {required bool vietnamese}) {
    if (error is FirebaseException && error is! FirebaseAuthException) {
      final details = "${error.plugin} ${error.code} ${error.message ?? ""}"
          .toLowerCase();

      if (details.contains("appcheck") ||
          details.contains("app_check") ||
          details.contains("app-check") ||
          details.contains("attestation")) {
        return vietnamese
            ? "Firebase App Check đã từ chối bản ứng dụng này. Hãy chạy bản Debug và đăng ký debug token hiện tại trong Firebase."
            : "Firebase App Check rejected this build. Run the Debug build and register its current debug token in Firebase.";
      }

      if (details.contains("network") ||
          details.contains("unavailable") ||
          details.contains("timeout")) {
        return vietnamese
            ? "Không thể kết nối Firebase. Hãy kiểm tra mạng rồi thử lại."
            : "Could not reach Firebase. Check your connection and try again.";
      }

      return error.message ??
          (vietnamese
              ? "Firebase không thể hoàn tất yêu cầu. Vui lòng thử lại."
              : "Firebase could not complete the request. Please try again.");
    }

    if (error is! FirebaseAuthException) {
      return vietnamese
          ? "Đã xảy ra lỗi. Vui lòng thử lại."
          : "Something went wrong. Please try again.";
    }

    final authDetails = "${error.code} ${error.message ?? ""}".toLowerCase();

    if (authDetails.contains("appcheck") ||
        authDetails.contains("app check") ||
        authDetails.contains("app-check") ||
        authDetails.contains("attestation") ||
        authDetails.contains("403")) {
      return vietnamese
          ? "Firebase App Check đã từ chối bản ứng dụng này. Hãy chạy bản Debug và đăng ký debug token hiện tại trong Firebase."
          : "Firebase App Check rejected this build. Run the Debug build and register its current debug token in Firebase.";
    }

    switch (error.code) {
      case "invalid-email":
        return vietnamese
            ? "Địa chỉ email không hợp lệ."
            : "The email address is invalid.";

      case "user-disabled":
        return vietnamese
            ? "Tài khoản này đã bị vô hiệu hóa."
            : "This account has been disabled.";

      case "user-not-found":
      case "invalid-credential":
        return vietnamese
            ? "Email hoặc mật khẩu không đúng."
            : "The email or password is incorrect.";

      case "wrong-password":
        return vietnamese
            ? "Mật khẩu không đúng."
            : "The password is incorrect.";

      case "email-already-in-use":
        return vietnamese
            ? "Email này đã được sử dụng."
            : "An account already exists for this email.";

      case "weak-password":
        return vietnamese
            ? "Mật khẩu phải có ít nhất 6 ký tự."
            : "Password must contain at least 6 characters.";

      case "operation-not-allowed":
        return vietnamese
            ? "Phương thức đăng nhập này chưa được bật trong Firebase."
            : "This sign-in method is not enabled in Firebase.";

      case "credential-already-in-use":
      case "provider-already-linked":
        return vietnamese
            ? "Thông tin đăng nhập này đã thuộc về một tài khoản khác. Hãy đăng nhập vào tài khoản đó."
            : "These login details already belong to another account. Please sign in to that account.";

      case "network-request-failed":
        return vietnamese
            ? "Không có kết nối mạng. Vui lòng thử lại."
            : "Network error. Please check your connection.";

      case "invalid-app-credential":
      case "app-not-authorized":
        return vietnamese
            ? "Firebase App Check đã từ chối bản ứng dụng này. Hãy kiểm tra debug token."
            : "Firebase App Check rejected this build. Check the current debug token.";

      case "too-many-requests":
        return vietnamese
            ? "Quá nhiều lần thử. Vui lòng đợi rồi thử lại."
            : "Too many attempts. Please wait and try again.";

      case "missing-email":
        return vietnamese
            ? "Vui lòng nhập email."
            : "Please enter your email address.";

      case "missing-password":
        return vietnamese
            ? "Vui lòng nhập mật khẩu."
            : "Please enter your password.";

      case "requires-recent-login":
        return vietnamese
            ? "Vui lòng đăng xuất, đăng nhập lại, rồi thử xóa tài khoản lần nữa."
            : "Please sign out, sign in again, and then try deleting the account.";

      case "firebase-unavailable":
        return vietnamese
            ? "Không thể kết nối Firebase lúc này. Bạn vẫn có thể dùng dữ liệu cục bộ."
            : "Firebase is unavailable right now. You can still use locally stored data.";

      default:
        return error.message ??
            (vietnamese
                ? "Không thể đăng nhập. Vui lòng thử lại."
                : "Authentication failed. Please try again.");
    }
  }
}
