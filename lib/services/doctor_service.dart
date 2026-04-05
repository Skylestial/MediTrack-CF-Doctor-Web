import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DoctorService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Current signed-in doctor UID
  String? get doctorId => _auth.currentUser?.uid;

  // ─── Patients ────────────────────────────────────────────────────────────

  /// Stream of all patients (role == 'patient') — live updates
  /// Uses server-side filtering for efficiency
  Stream<QuerySnapshot> getPatientsStream() {
    return _db
        .collection('users')
        .where('role', isEqualTo: 'patient')
        .snapshots();
  }

  // ─── Alerts ──────────────────────────────────────────────────────────────

  /// Send a custom alert to a specific patient (max 255 chars).
  /// Writes to users/{uid}/notifications — single source of truth for patient.
  /// Also writes a copy to doctors/{doctorId}/sent_alerts for easy querying.
  Future<void> sendAlert(String patientUid, String patientName, String message) async {
    final did = doctorId;
    if (did == null) throw Exception('Not signed in');

    final trimmed = message.trim();
    final capped = trimmed.length > 255 ? trimmed.substring(0, 255) : trimmed;
    final timestamp = FieldValue.serverTimestamp();

    // Create the alert document
    final alertData = {
      'type':        'consultation_request',
      'doctorId':    did,
      'patientUid':  patientUid,
      'patientName': patientName,
      'message':     capped,
      'timestamp':   timestamp,
      'read':        false,
    };

    // Write to patient's notifications
    final patientNotifRef = await _db
        .collection('users')
        .doc(patientUid)
        .collection('notifications')
        .add(alertData);

    // Also write to doctor's sent_alerts collection for easy querying
    await _db
        .collection('doctors')
        .doc(did)
        .collection('sent_alerts')
        .doc(patientNotifRef.id)
        .set({
      ...alertData,
      'notificationId': patientNotifRef.id,
    });
  }

  /// Stream of all alerts sent by this doctor.
  /// Uses doctor's sent_alerts collection (simpler, no index needed)
  Stream<QuerySnapshot> getSentAlertsStream() {
    final did = doctorId;
    if (did == null) return const Stream.empty();

    // Use doctor's sent_alerts collection - simpler and doesn't require composite index
    return _db
        .collection('doctors')
        .doc(did)
        .collection('sent_alerts')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// Alternative: Stream using collectionGroup (requires Firestore index)
  /// Shows real-time read status from patient notifications
  Stream<QuerySnapshot> getSentAlertsStreamViaCollectionGroup() {
    final did = doctorId;
    if (did == null) return const Stream.empty();
    return _db
        .collectionGroup('notifications')
        .where('doctorId', isEqualTo: did)
        .snapshots();
  }

  /// Sync read status from patient's notification to doctor's sent_alerts copy
  Future<void> syncReadStatus(String patientUid, String notificationId, bool read) async {
    final did = doctorId;
    if (did == null) return;

    await _db
        .collection('doctors')
        .doc(did)
        .collection('sent_alerts')
        .doc(notificationId)
        .update({'read': read});
  }

  // ─── Low Adherence Alerts ─────────────────────────────────────────────────

  /// Stream of low adherence alerts from all patients
  Stream<QuerySnapshot> getLowAdherenceAlertsStream() {
    return _db
        .collection('low_adherence_alerts')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }

  /// Mark a low adherence alert as read
  Future<void> markLowAdherenceAlertRead(String alertId) async {
    await _db.collection('low_adherence_alerts').doc(alertId).update({'read': true});
  }

  /// Delete a low adherence alert
  Future<void> deleteLowAdherenceAlert(String alertId) async {
    await _db.collection('low_adherence_alerts').doc(alertId).delete();
  }

  /// Delete a sent alert (soft delete for doctor, permanent if both deleted)
  Future<void> deleteSentAlert(String alertId, String patientUid) async {
    final did = doctorId;
    if (did == null) return;

    // Get the current state of the alert
    final alertDoc = await _db
        .collection('doctors')
        .doc(did)
        .collection('sent_alerts')
        .doc(alertId)
        .get();

    if (!alertDoc.exists) return;

    final data = alertDoc.data();
    final deletedByPatient = data?['deletedByPatient'] ?? false;

    if (deletedByPatient) {
      // Patient already deleted, so permanently delete from both
      await _db
          .collection('doctors')
          .doc(did)
          .collection('sent_alerts')
          .doc(alertId)
          .delete();

      try {
        await _db
            .collection('users')
            .doc(patientUid)
            .collection('notifications')
            .doc(alertId)
            .delete();
      } catch (e) {}
    } else {
      // Soft delete - mark as deleted by doctor
      await _db
          .collection('doctors')
          .doc(did)
          .collection('sent_alerts')
          .doc(alertId)
          .update({'deletedByDoctor': true});

      // Sync to patient's copy
      try {
        await _db
            .collection('users')
            .doc(patientUid)
            .collection('notifications')
            .doc(alertId)
            .update({'deletedByDoctor': true});
      } catch (e) {}
    }
  }

  /// Create a low adherence alert for a specific patient
  /// This is a system-generated alert triggered when patient's 7-day adherence < 50%
  Future<void> createLowAdherenceAlert(String patientUid, String patientName, int adherencePercent) async {
    final did = doctorId;
    if (did == null) throw Exception('Not signed in');

    await _db
        .collection('users')
        .doc(patientUid)
        .collection('notifications')
        .add({
      'type':        'low_adherence_alert',
      'doctorId':    did,
      'patientUid':  patientUid,
      'patientName': patientName,
      'message':     'System Alert: Your adherence in the last 7 days is only $adherencePercent%. Please contact your doctor.',
      'timestamp':   FieldValue.serverTimestamp(),
      'read':        false,
      'isSystemAlert': true,
    });
  }

  // ─── Deprecated ─────────────────────────────────────────────────────────
  /// @deprecated Use sendAlert() instead
  Future<void> requestConsultation(String patientUid, String doctorId) async {
    await sendAlert(patientUid, 'Patient', 'Your doctor is requesting a consultation.');
  }
}
