import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  String? _userId;
  String? _userName;
  String? _userEmail;
  String? _selectedHomeId;

  AuthService(this._auth) {
    _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  // Getters
  User? get user => _user;
  bool get isLoggedIn => _user != null;
  String? get userId => _userId;
  String? get userName => _userName;
  String? get userEmail => _userEmail;
  String? get selectedHomeId => _selectedHomeId;

  // Auth state listener
  Future<void> _onAuthStateChanged(User? user) async {
    _user = user;
    if (user != null) {
      _userId = user.uid;
      _userEmail = user.email;

      // Fetch user data from Firestore
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data();
      _userName = data?['name'] ?? user.displayName ?? 'User';
      _selectedHomeId = data?['selectedHomeId'];

      notifyListeners();
    }
  }

  // Register and save user
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

  // Save user data
  Future<void> _saveUserData({
    required String uid,
    required String name,
    required String email,
    required String phone,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'Id': uid,
        'name': name,
        'email': email,
        'phone': phone,
        'selectedHomeId': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error saving user data: $e');
    }
  }

  // Set selected home
  Future<void> setSelectedHome(String homeId) async {
    if (_userId == null) return;

    try {
      await _firestore.collection('users').doc(_userId).update({
        'selectedHomeId': homeId,
      });

      _selectedHomeId = homeId;
      notifyListeners();
    } catch (e) {
      debugPrint('Error setting selected home: $e');
    }
  }

  // Add a new home
  Future<void> addHomeForUser({
    required String userId,
    required String name,
    required String home,
    required String road,
    required String block,
    required String city,
  }) async {
    try {
      await _firestore.collection('homes').add({
        'userId': userId,
        'name': name,
        'home': home,
        'road': road,
        'block': block,
        'city': city,
        'address': 'Home: $home, Road: $road, Block: $block, City: $city',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error adding home: $e');
    }
  }


  // Sign in
  Future<UserCredential?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      debugPrint('Login error: $e');
      return null;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    _user = null;
    _userId = null;
    _userName = null;
    _userEmail = null;
    _selectedHomeId = null;
    notifyListeners();
  }
}
