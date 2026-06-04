import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_profile.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Map simple usernames to secure emails for Firebase Auth
  String _mapUsernameToEmail(String username) {
    username = username.trim().toLowerCase();
    if (username.contains('@')) {
      return username; // Already an email
    }
    return "$username@fivasolo.com";
  }

  // Get current user profile
  Future<UserProfile?> getCurrentUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final doc = await _db.collection('users').doc(user.uid).get();
    if (doc.exists) {
      return UserProfile.fromMap(doc.data()!, user.uid);
    }
    return null;
  }

  // Sign In using mapped email/password
  Future<UserProfile> signIn(String username, String password) async {
    final email = _mapUsernameToEmail(username);
    final credentials = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credentials.user;
    if (user == null) {
      throw Exception("Gagal melakukan login. User null.");
    }

    // Retrieve or create UserProfile in Firestore
    final docRef = _db.collection('users').doc(user.uid);
    final doc = await docRef.get();

    if (doc.exists) {
      return UserProfile.fromMap(doc.data()!, user.uid);
    } else {
      // Setup default fallback profiles if not pre-seeded
      String role = 'cashier';
      String displayName = 'Kasir';
      final cleanUsername = username.trim().toLowerCase();

      if (cleanUsername == 'admin') {
        role = 'developer';
        displayName = 'Administrator';
      } else if (cleanUsername == 'manager') {
        role = 'manager';
        displayName = 'Manager';
      } else if (cleanUsername == 'setiawan') {
        role = 'cashier';
        displayName = 'Setiawan';
      }

      final profile = UserProfile(
        uid: user.uid,
        username: cleanUsername,
        name: displayName,
        role: role,
      );

      await docRef.set(profile.toMap());
      return profile;
    }
  }

  // Seed default users in Firebase (useful for initial run/deployment)
  Future<void> seedDefaultUsers() async {
    final defaultUsers = [
      {'user': 'admin', 'pass': 'cabangjateng', 'role': 'developer', 'name': 'Developer'},
      {'user': 'setiawan', 'pass': 'jateng', 'role': 'cashier', 'name': 'Setiawan'},
      {'user': 'manager', 'pass': 'pfs2025', 'role': 'manager', 'name': 'Manager'},
    ];

    List<String> errors = [];
    for (var u in defaultUsers) {
      try {
        final email = _mapUsernameToEmail(u['user']!);
        // Try creating user in Auth
        UserCredential creds;
        try {
          creds = await _auth.createUserWithEmailAndPassword(
            email: email,
            password: u['pass']!,
          );
        } catch (e) {
          // If already exists, login to get UID
          creds = await _auth.signInWithEmailAndPassword(
            email: email,
            password: u['pass']!,
          );
        }

        final user = creds.user;
        if (user != null) {
          // Save profile in Firestore
          await _db.collection('users').doc(user.uid).set({
            'username': u['user'],
            'name': u['name'],
            'role': u['role'],
          });
        }
      } catch (e) {
        debugPrint("Error seeding user ${u['user']}: $e");
        errors.add("${u['user']}: $e");
      }
    }
    if (errors.isNotEmpty) {
      throw Exception("Gagal membuat beberapa akun default: ${errors.join('; ')}");
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Stream current Auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();
}
