import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'community_contribution_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Current Firebase user (null if not signed in)
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes for AuthWrapper
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Register with email/password and create Firestore profile
  Future<User?> registerWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      await user.updateDisplayName(name);
      await _createUserProfile(user, name: name);
      await CommunityContributionService.instance.processPendingQueue();
    }
    return user;
  }

  /// Sign in with email/password
  Future<User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await CommunityContributionService.instance.processPendingQueue();
    return credential.user;
  }

  /// Sign in with Google OAuth
  Future<User?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // User cancelled

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;

    // Create profile if first sign-in
    if (user != null && userCredential.additionalUserInfo?.isNewUser == true) {
      await _createUserProfile(
        user,
        name: googleUser.displayName ?? '',
        photoUrl: googleUser.photoUrl,
      );
    }
    await CommunityContributionService.instance.processPendingQueue();
    return user;
  }

  /// Send password reset email
  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// Sign out from both Firebase and Google
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Create user profile document in Firestore
  Future<void> _createUserProfile(
    User user, {
    required String name,
    String? photoUrl,
  }) async {
    await _firestore.collection('users').doc(user.uid).set({
      'name': name,
      'email': user.email ?? '',
      'profilePhotoUrl': photoUrl ?? user.photoURL,
      'registrationDate': FieldValue.serverTimestamp(),
      'locationPreference': null,
      'contributionOptOut': false,
    });
  }
}
