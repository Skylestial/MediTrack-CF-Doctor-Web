import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> get user => _auth.authStateChanges();

  Future<User?> signIn(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email, 
        password: password
      );

      // Role check — only doctors allowed
      final uid = credential.user!.uid;
      final doc = await _firestore.collection('users').doc(uid).get();

      if (!doc.exists || doc['role'] != 'doctor') {
        await _auth.signOut();
        throw Exception('Doctors only');
      }

      return credential.user;
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  Future<User?> signUp(String email, String password) async {
    try {
      // Create Firebase Auth user
      final UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email, 
        password: password
      );

      // Write Firestore document with role: doctor
      if (cred.user != null) {
        await _firestore
            .collection('users')
            .doc(cred.user!.uid)
            .set({
          'email': email,
          'role': 'doctor',
          'createdAt': Timestamp.now(),
        });
      }

      return cred.user;
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
