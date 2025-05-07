import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Add Firestore

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  String? _userId;
  String? _userName;
  String? _userEmail;

  AuthService(this._auth) {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  String? get userId => _userId;
  String? get userName => _userName;
  String? get userEmail => _userEmail;

  Future<void> _onAuthStateChanged(User? user) async {
    _user = user;
    if (user != null) {
      _userId = user.uid;
      _userEmail = user.email;

      // Fetch user name from Firestore
      final doc = await _firestore.collection('users').doc(user.uid).get();
      _userName = doc.data()?['name'] ?? user.displayName ?? 'User';

      notifyListeners();
    }
  }

  // Register a user and save their data in Firestore
  Future<UserCredential?> registerWithEmail({
    required String id,
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = userCredential.user;

      if (user != null) {
        await _saveUserData(
          uid: user.uid,
          name: name,
          email: email,
          phone: phone,
        );
      }

      return userCredential;
    } catch (e) {
      debugPrint('Registration error: $e');
      return null;
    }
  }

  // Save user info to Firestore
  Future<void> _saveUserData({
    required String uid,
    required String name,
    required String email,
    required String phone,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'Id':uid,
        'name': name,
        'email': email,
        'phone': phone,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error saving user data: $e');
    }
  }

  // Sign in with email and password
  Future<UserCredential?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      debugPrint('Login error: $e');
      return null;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
