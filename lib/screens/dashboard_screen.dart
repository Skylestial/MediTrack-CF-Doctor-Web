import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/doctor_service.dart';
import '../services/auth_service.dart';
import 'patient_detail_screen.dart';
import 'settings_screen.dart';
import '../providers/theme_provider.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────
const _crimson  = Color(0xFFDC143C);
const _darkBg   = Color(0xFF111827); // slate-900
const _darkCard = Color(0xFF1F2937); // slate-800
const _darkBdr  = Color(0xFF374151); // slate-700

enum _RiskFilter { all, low, moderate, high }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final DoctorService _service = DoctorService();
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _listenForLowAdherenceAlerts();
  }

  void _listenForLowAdherenceAlerts() {
    _service.getLowAdherenceAlertsStream().listen((snap) {
      if (!mounted) return;
      
      // Check for unread alerts
      final unreadAlerts = snap.docs.where((d) {
        final data = d.data() as Map<String, dynamic>;
        return data['read'] != true;
      }).toList();

      // Show a snackbar for new unread alerts (only the first one)
      if (unreadAlerts.isNotEmpty) {
        final alert = unreadAlerts.first.data() as Map<String, dynamic>;
        final patientName = alert['patientName'] as String? ?? 'A patient';
        final adherence = alert['adherencePercent'] as int? ?? 0;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                // Navigate to the patient
                final patientUid = alert['patientUid'] as String? ?? '';
                if (patientUid.isNotEmpty) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PatientDetailScreen(
                        patientUid: patientUid,
                        patientName: patientName,
                        diagnosis: 'CF',
                        lastAdherence: adherence,
                      ),
                    ),
                  );
                }
              },
            ),
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Low Adherence Alert',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$patientName\'s 7-day adherence is <50%',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

        // Mark as read to avoid showing again
        _service.markLowAdherenceAlertRead(unreadAlerts.first.id);
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ─── Alert Dialog ─────────────────────────────────────────────────────────
  Future<void> _showAlertDialog(BuildContext ctx, String uid, String name) async {
    final ctrl = TextEditingController();
    final key  = GlobalKey<FormState>();
    bool loading = false;

    await showDialog(
      context: ctx,
      builder: (_) => StatefulBuilder(
        builder: (_, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _crimson.withOpacity(0.15),
              child: const Icon(Icons.send_rounded, color: _crimson, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Send Alert', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text(name, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.normal)),
              ]),
            ),
          ]),
          content: Form(
            key: key,
            child: TextFormField(
              controller: ctrl,
              maxLength: 255,
              maxLines: 4,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Type your message to the patient…',
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a message' : null,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _crimson, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: loading ? null : () async {
                if (!key.currentState!.validate()) return;
                ss(() => loading = true);
                try {
                  await _service.sendAlert(uid, name, ctrl.text);
                  if (_.mounted) Navigator.pop(_);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      backgroundColor: Colors.green.shade700,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      content: Row(children: [
                        const Icon(Icons.check_circle, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text('Alert sent to $name'),
                      ]),
                    ));
                  }
                } catch (_) { ss(() => loading = false); }
              },
              child: loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Send Alert'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Sign out ─────────────────────────────────────────────────────────────
  Future<void> _signOut(BuildContext ctx) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _crimson),
            onPressed: () => Navigator.pop(_, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (ok == true) await AuthService().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user   = FirebaseAuth.instance.currentUser;
    final screenWidth = MediaQuery.of(context).size.width;
    // Responsive breakpoints: < 480 = phone, 480-768 = tablet portrait, 768-1024 = tablet landscape, > 1024 = desktop
    final isCompact = screenWidth < 480; // Fold phones, small screens
    final isMobile = screenWidth < 768; // Tablets in portrait, phones

    return Scaffold(
      backgroundColor: isDark ? _darkBg : const Color(0xFFF0F4F8),
      endDrawer: _ProfileDrawer(user: user, onSignOut: () => _signOut(context)),
      appBar: _buildAppBar(context, isDark, isMobile, isCompact),
      body: Stack(
        children: [
          // Main content area
          TabBarView(
            controller: _tabs,
            children: [
              _PatientsTab(service: _service, onAlert: _showAlertDialog, isCompact: isCompact),
              _AlertsTab(service: _service),
            ],
          ),

          // Floating sidebar (only on larger screens)
          if (!isMobile)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _buildFloatingSidebar(context, isDark),
            ),
        ],
      ),
    );
  }

  Widget _buildFloatingSidebar(BuildContext context, bool isDark) {
    return Container(
      width: 72,
      margin: const EdgeInsets.only(top: 16, left: 16, bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? _darkCard.withOpacity(0.95) : Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isDark ? _darkBdr : Colors.grey.shade200, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          _buildSidebarTab(
            icon: Icons.people_alt_rounded,
            label: 'Patients',
            isSelected: _tabs.index == 0,
            onTap: () => setState(() => _tabs.animateTo(0)),
          ),
          const SizedBox(height: 8),
          _buildSidebarTab(
            icon: Icons.send_rounded,
            label: 'Messages',
            isSelected: _tabs.index == 1,
            onTap: () => setState(() => _tabs.animateTo(1)),
          ),
          const Spacer(),
          _buildSidebarTab(
            icon: Icons.settings_rounded,
            label: 'Settings',
            isSelected: false,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSidebarTab({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      preferBelow: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isSelected ? _crimson.withOpacity(0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? _crimson : Colors.transparent,
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              color: isSelected ? _crimson : Colors.grey,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isDark, bool isMobile, bool isCompact) {
    return AppBar(
      backgroundColor: _crimson, // Always crimson, even in dark mode
      foregroundColor: Colors.white,
      elevation: 2,
      titleSpacing: isCompact ? 8 : 20,
      title: Row(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/logo.png',
            height: isCompact ? 28 : 34,
            width: isCompact ? 28 : 34,
            fit: BoxFit.contain,
          ),
        ),
        SizedBox(width: isCompact ? 6 : 10),
        Text('MediTrack CF', style: TextStyle(fontWeight: FontWeight.w800, fontSize: isCompact ? 14 : 18, letterSpacing: 0.5)),
      ]),
      bottom: isMobile ? TabBar(
        controller: _tabs,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        tabs: const [
          Tab(icon: Icon(Icons.people_alt_rounded, size: 18), text: 'Patients'),
          Tab(icon: Icon(Icons.send_rounded, size: 18), text: 'Messages'),
        ],
      ) : null,
      actions: [
        Consumer<ThemeProvider>(
          builder: (_, theme, __) => IconButton(
            icon: Icon(theme.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            tooltip: 'Toggle Theme',
            onPressed: theme.toggleTheme,
          ),
        ),
        Builder(builder: (ctx) => IconButton(
          icon: CircleAvatar(
            radius: 15,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Text(
              (FirebaseAuth.instance.currentUser?.email ?? 'D')[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          tooltip: 'Profile',
          onPressed: () => Scaffold.of(ctx).openEndDrawer(),
        )),
        const SizedBox(width: 8),
      ],
    );
  }
}

// ─── Profile End-Drawer ───────────────────────────────────────────────────────
class _ProfileDrawer extends StatefulWidget {
  final User? user;
  final VoidCallback onSignOut;

  const _ProfileDrawer({required this.user, required this.onSignOut});

  @override
  State<_ProfileDrawer> createState() => _ProfileDrawerState();
}

class _ProfileDrawerState extends State<_ProfileDrawer> {
  String _name = '';
  String _specialization = '';
  String _hospital = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDoctorData();
  }

  Future<void> _loadDoctorData() async {
    final uid = widget.user?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data() ?? {};
        setState(() {
          _name = data['name'] as String? ?? '';
          _specialization = data['specialization'] as String? ?? '';
          _hospital = data['hospital'] as String? ?? '';
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final email  = widget.user?.email ?? 'doctor@meditrack.com';
    final displayName = _name.isNotEmpty ? _name : email;
    final initial = displayName[0].toUpperCase();

    return Drawer(
      width: 300,
      backgroundColor: isDark ? _darkCard : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_crimson, Color(0xFF9B0E2B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: Text(initial,
                        style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  if (_name.isNotEmpty) ...[
                    Text(_name,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                  ],
                  Text(email,
                      style: TextStyle(color: Colors.white.withOpacity(_name.isNotEmpty ? 0.8 : 1), fontSize: 14, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Doctor', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Info tiles
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: _crimson),
              )
            else ...[
              _DrawerTile(
                icon: Icons.email_outlined,
                label: 'Email',
                value: email,
              ),
              if (_specialization.isNotEmpty)
                _DrawerTile(
                  icon: Icons.medical_services_outlined,
                  label: 'Specialization',
                  value: _specialization,
                ),
              if (_hospital.isNotEmpty)
                _DrawerTile(
                  icon: Icons.local_hospital_outlined,
                  label: 'Hospital',
                  value: _hospital,
                ),
              _DrawerTile(
                icon: Icons.verified_user_outlined,
                label: 'Status',
                value: 'Active',
                valueColor: Colors.green,
              ),
            ],

            const Spacer(),
            const Divider(),

            ListTile(
              leading: const Icon(Icons.logout, color: _crimson),
              title: const Text('Sign Out', style: TextStyle(color: _crimson, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context); // close drawer first
                widget.onSignOut();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _DrawerTile({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey),
      title: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      subtitle: Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: valueColor)),
    );
  }
}

// ─── Patients Tab ─────────────────────────────────────────────────────────────
class _PatientsTab extends StatefulWidget {
  final DoctorService service;
  final Future<void> Function(BuildContext, String, String) onAlert;
  final bool isCompact;

  const _PatientsTab({required this.service, required this.onAlert, this.isCompact = false});

  @override
  State<_PatientsTab> createState() => _PatientsTabState();
}

class _PatientsTabState extends State<_PatientsTab> {
  _RiskFilter _selectedFilter = _RiskFilter.all;
  String _docsSignature = '';
  Future<Map<String, int>>? _riskFuture;

  String _buildDocsSignature(List<DocumentSnapshot> docs) =>
      docs.map((d) => d.id).join('|');

  void _ensureRiskFuture(List<DocumentSnapshot> docs) {
    final signature = _buildDocsSignature(docs);
    if (_riskFuture == null || signature != _docsSignature) {
      _docsSignature = signature;
      _riskFuture = _computeSevenDayRiskMap(docs);
    }
  }

  Future<Map<String, int>> _computeSevenDayRiskMap(List<DocumentSnapshot> docs) async {
    final Map<String, int> map = {};
    final nowRaw = DateTime.now();
    final now = DateTime(nowRaw.year, nowRaw.month, nowRaw.day);
    final startDate = now.subtract(const Duration(days: 6));
    final startStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(now);

    for (final doc in docs) {
      try {
        final userData = doc.data() as Map<String, dynamic>;
        final createdAt = userData['createdAt'] as Timestamp?;

        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(doc.id)
            .collection('daily_logs')
            .orderBy('date', descending: false)
            .get();

        DateTime accountCreatedDate;
        if (createdAt != null) {
          final d = createdAt.toDate();
          accountCreatedDate = DateTime(d.year, d.month, d.day);
        } else if (snap.docs.isNotEmpty) {
          final firstRealLog = snap.docs.firstWhere(
            (d) => ((d.data()['adherence'] as num?)?.toInt() ?? 0) > 0,
            orElse: () => snap.docs.first,
          );
          final firstDate = firstRealLog.data()['date'] as String?;
          accountCreatedDate = firstDate != null
              ? DateTime.parse(firstDate)
              : now.subtract(const Duration(days: 6));
        } else {
          accountCreatedDate = now.subtract(const Duration(days: 6));
        }

        final accountStartStr = DateFormat('yyyy-MM-dd').format(accountCreatedDate);

        final logs = snap.docs
            .map((d) => d.data())
            .where((log) {
              final date = log['date'] as String? ?? '';
              if (date.compareTo(accountStartStr) < 0) return false;
              return date.compareTo(startStr) >= 0 && date.compareTo(endStr) <= 0;
            })
            .toList();

        final effectiveStart = accountCreatedDate.isAfter(startDate)
            ? accountCreatedDate
            : startDate;
        final totalDays = now.difference(effectiveStart).inDays + 1;

        if (totalDays > 0) {
          final total = logs.fold<int>(0, (s, l) => s + ((l['adherence'] as num?)?.toInt() ?? 0));
          map[doc.id] = (total / totalDays).round().clamp(0, 100);
        } else {
          map[doc.id] = 0;
        }
      } catch (_) {
        final data = doc.data() as Map<String, dynamic>;
        map[doc.id] = ((data['lastAdherence'] as num?)?.toInt() ?? 0).clamp(0, 100);
      }
    }

    return map;
  }

  bool _matchesRisk(int adherence, _RiskFilter filter) {
    if (filter == _RiskFilter.all) return true;
    switch (filter) {
      case _RiskFilter.low:
        return adherence >= 80;
      case _RiskFilter.moderate:
        return adherence >= 50 && adherence < 80;
      case _RiskFilter.high:
        return adherence < 50;
      case _RiskFilter.all:
        return true;
    }
  }

  Widget _filterChip(String label, _RiskFilter value) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: _crimson.withOpacity(0.18),
      labelStyle: TextStyle(
        color: isSelected ? _crimson : Colors.grey,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(color: isSelected ? _crimson.withOpacity(0.4) : Colors.grey.withOpacity(0.25)),
      onSelected: (_) => setState(() => _selectedFilter = value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: widget.service.getPatientsStream(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _crimson));
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return _EmptyState(
            icon: Icons.people_outline_rounded,
            title: 'No Patients Yet',
            subtitle: 'Patients will appear here once they register.',
          );
        }

        // Query already filtered server-side for patients only
        final docs = snap.data!.docs;
        _ensureRiskFuture(docs);
        
        if (docs.isEmpty) {
          return _EmptyState(
            icon: Icons.people_outline_rounded,
            title: 'No Patients Yet',
            subtitle: 'Patients will appear here once they register.',
          );
        }

        return FutureBuilder<Map<String, int>>(
          future: _riskFuture,
          builder: (context, riskSnap) {
            final riskMap = riskSnap.data ?? const <String, int>{};
            final filteredDocs = docs.where((d) {
              final adherence = riskMap[d.id] ?? 0;
              return _matchesRisk(adherence, _selectedFilter);
            }).toList();

            return Column(
              children: [
                // ── Stats bar ──────────────────────────────────────────────
                _StatsBar(docs: filteredDocs, isCompact: widget.isCompact),

                Padding(
                  padding: EdgeInsets.fromLTRB(widget.isCompact ? 12 : 16, 12, widget.isCompact ? 12 : 16, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip('All', _RiskFilter.all),
                        const SizedBox(width: 8),
                        _filterChip('Low Risk', _RiskFilter.low),
                        const SizedBox(width: 8),
                        _filterChip('Moderate Risk', _RiskFilter.moderate),
                        const SizedBox(width: 8),
                        _filterChip('High Risk', _RiskFilter.high),
                      ],
                    ),
                  ),
                ),

                if (riskSnap.connectionState == ConnectionState.waiting)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator(color: _crimson)),
                  )
                else if (filteredDocs.isEmpty)
                  Expanded(
                    child: _EmptyState(
                      icon: Icons.filter_alt_off_rounded,
                      title: 'No Patients In This Filter',
                      subtitle: 'Try a different risk filter.',
                    ),
                  )
                else

                // ── Patient grid ──────────────────────────────────────────
                Expanded(
                  child: LayoutBuilder(builder: (_, constraints) {
                    final width = constraints.maxWidth;
                    final isMobile = width < 600;
                    final isNarrow = width < 400; // Fold phones
                    
                    // Calculate best card width based on screen size
                    double maxExtent;
                    double aspectRatio;
                    double spacing;
                    
                    if (isNarrow) {
                      maxExtent = width - 32; // Full width minus padding
                      aspectRatio = 0.72; // More height for compact
                      spacing = 12;
                    } else if (isMobile) {
                      maxExtent = 360;
                      aspectRatio = 0.72;
                      spacing = 14;
                    } else {
                      maxExtent = 340;
                      aspectRatio = 0.75;
                      spacing = 16;
                    }
                    
                    return GridView.builder(
                      padding: EdgeInsets.only(
                        left: isMobile ? (isNarrow ? 12 : 16) : 104,
                        right: isMobile ? (isNarrow ? 12 : 16) : 24,
                        top: 16,
                        bottom: 24,
                      ),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: maxExtent,
                        childAspectRatio: aspectRatio,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                      ),
                      itemCount: filteredDocs.length,
                      itemBuilder: (_, i) => _PatientCard(
                        key: ValueKey(filteredDocs[i].id),
                        doc: filteredDocs[i],
                        onAlert: widget.onAlert,
                        isCompact: isNarrow,
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ─── Stats Bar ────────────────────────────────────────────────────────────────
class _StatsBar extends StatefulWidget {
  final List<DocumentSnapshot> docs;
  final bool isCompact;
  const _StatsBar({required this.docs, this.isCompact = false});

  @override
  State<_StatsBar> createState() => _StatsBarState();
}

class _StatsBarState extends State<_StatsBar> {
  int _avgAdherence = 0;
  int _highRisk = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _calculateStats();
  }

  @override
  void didUpdateWidget(_StatsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recompute whenever the incoming docs list instance changes.
    if (oldWidget.docs != widget.docs) {
      _calculateStats();
    }
  }

  Future<void> _calculateStats() async {
    if (widget.docs.isEmpty) {
      setState(() {
        _avgAdherence = 0;
        _highRisk = 0;
        _loading = false;
      });
      return;
    }

    int totalAdherence = 0;
    int patientCount = 0;
    int highRiskCount = 0;

    // Calculate adherence from last 7 days of daily_logs for each patient
    // using date-only values to avoid time-of-day truncation bugs.
    final nowRaw = DateTime.now();
    final now = DateTime(nowRaw.year, nowRaw.month, nowRaw.day);
    final startDate = now.subtract(const Duration(days: 6));
    final startStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(now);

    for (final doc in widget.docs) {
      try {
        final userData = doc.data() as Map<String, dynamic>;
        final createdAt = userData['createdAt'] as Timestamp?;
        
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(doc.id)
            .collection('daily_logs')
            .orderBy('date', descending: false)
            .get();

        // Determine account start: use createdAt or first real log
        DateTime accountCreatedDate;
        if (createdAt != null) {
          final d = createdAt.toDate();
          accountCreatedDate = DateTime(d.year, d.month, d.day);
        } else if (snap.docs.isNotEmpty) {
          final firstRealLog = snap.docs.firstWhere(
            (d) => ((d.data()['adherence'] as num?)?.toInt() ?? 0) > 0,
            orElse: () => snap.docs.first,
          );
          final firstDate = firstRealLog.data()['date'] as String?;
          accountCreatedDate = firstDate != null
              ? DateTime.parse(firstDate)
              : now.subtract(const Duration(days: 6));
        } else {
          accountCreatedDate = now.subtract(const Duration(days: 6));
        }
        final accountStartStr = DateFormat('yyyy-MM-dd').format(accountCreatedDate);

        final logs = snap.docs
            .map((d) => d.data())
            .where((log) {
              final date = log['date'] as String? ?? '';
              // Ignore logs from before account was created
              if (date.compareTo(accountStartStr) < 0) return false;
              return date.compareTo(startStr) >= 0 && date.compareTo(endStr) <= 0;
            })
            .toList();

        // Calculate total days from account creation (capped at 7)
        final effectiveStart = accountCreatedDate.isAfter(startDate)
          ? accountCreatedDate
          : startDate;
        final totalDays = now.difference(effectiveStart).inDays + 1;
        
        if (totalDays > 0) {
          final total = logs.fold<int>(0, (s, l) => s + ((l['adherence'] as num?)?.toInt() ?? 0));
          final avg = (total / totalDays).round().clamp(0, 100);
          totalAdherence += avg;
          patientCount++;
          if (avg < 50) highRiskCount++;
        } else {
          // No valid days
          patientCount++;
          highRiskCount++;
        }
      } catch (e) {
        // Fallback to lastAdherence
        final data = doc.data() as Map<String, dynamic>;
        final adherence = (data['lastAdherence'] as num?)?.toInt() ?? 0;
        totalAdherence += adherence;
        patientCount++;
        if (adherence < 50) highRiskCount++;
      }
    }

    if (mounted) {
      setState(() {
        _avgAdherence = patientCount > 0 ? (totalAdherence / patientCount).round() : 0;
        _highRisk = highRiskCount;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = screenWidth < 400;
    final total = widget.docs.length;

    return Padding(
      padding: EdgeInsets.only(
        top: isNarrow ? 10 : 14,
        bottom: isNarrow ? 10 : 14,
      ),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? 12 : 16,
            vertical: isNarrow ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: isDark ? _darkCard : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? _darkBdr : Colors.grey.shade200),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatChip(label: 'Total Patients', value: '$total', color: Colors.indigo, isCompact: isNarrow),
                SizedBox(width: isNarrow ? 8 : 12),
                _loading
                    ? _StatChip(label: 'High Risk', value: '...', color: Colors.red, isCompact: isNarrow)
                    : _StatChip(label: 'High Risk', value: '$_highRisk', color: Colors.red, isCompact: isNarrow),
                SizedBox(width: isNarrow ? 8 : 12),
                _loading
                    ? _StatChip(label: 'Avg Adherence', value: '...', color: Colors.grey, isCompact: isNarrow)
                    : _StatChip(label: 'Avg Adherence', value: '$_avgAdherence%',
                        color: _avgAdherence >= 80 ? Colors.green : _avgAdherence >= 50 ? Colors.orange : Colors.red, isCompact: isNarrow),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool isCompact;
  const _StatChip({required this.label, required this.value, required this.color, this.isCompact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 16, vertical: isCompact ? 6 : 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: isCompact ? 16 : 20, color: color)),
        Text(label, style: TextStyle(fontSize: isCompact ? 9 : 11, color: color.withOpacity(0.8))),
      ]),
    );
  }
}

// ─── Patient Card ─────────────────────────────────────────────────────────────
class _PatientCard extends StatefulWidget {
  final DocumentSnapshot doc;
  final Future<void> Function(BuildContext, String, String) onAlert;
  final bool isCompact;

  const _PatientCard({super.key, required this.doc, required this.onAlert, this.isCompact = false});

  @override
  State<_PatientCard> createState() => _PatientCardState();
}

class _PatientCardState extends State<_PatientCard> {
  int? _calculatedAdherence;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAdherence();
  }

  @override
  void didUpdateWidget(_PatientCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doc.id != widget.doc.id) {
      _calculatedAdherence = null;
      _loading = true;
      _fetchAdherence();
    }
  }

  Future<void> _fetchAdherence() async {
    try {
      final uid = widget.doc.id;
      
      final nowRaw = DateTime.now();
      final now = DateTime(nowRaw.year, nowRaw.month, nowRaw.day);
      final startDate = now.subtract(const Duration(days: 6));
      final startStr = DateFormat('yyyy-MM-dd').format(startDate);
      final endStr = DateFormat('yyyy-MM-dd').format(now);

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('daily_logs')
          .orderBy('date', descending: false)
          .get();

      // Determine account start: use createdAt or first real log
      final userData = widget.doc.data() as Map<String, dynamic>;
      final createdAt = userData['createdAt'] as Timestamp?;
      DateTime accountCreatedDate;
      if (createdAt != null) {
        final d = createdAt.toDate();
        accountCreatedDate = DateTime(d.year, d.month, d.day);
      } else if (snap.docs.isNotEmpty) {
        final firstRealLog = snap.docs.firstWhere(
          (d) => ((d.data()['adherence'] as num?)?.toInt() ?? 0) > 0,
          orElse: () => snap.docs.first,
        );
        final firstDate = firstRealLog.data()['date'] as String?;
        accountCreatedDate = firstDate != null
            ? DateTime.parse(firstDate)
            : now.subtract(const Duration(days: 6));
      } else {
        accountCreatedDate = now.subtract(const Duration(days: 6));
      }
      final accountStartStr = DateFormat('yyyy-MM-dd').format(accountCreatedDate);

      final filteredLogs = snap.docs
          .map((d) => d.data())
          .where((log) {
            final date = log['date'] as String? ?? '';
            // Ignore logs from before account was created
            if (date.compareTo(accountStartStr) < 0) return false;
            return date.compareTo(startStr) >= 0 && date.compareTo(endStr) <= 0;
          })
          .toList();

      // Build date -> adherence (clamped 0-100)
      final Map<String, int> logsByDate = {};
      for (final log in filteredLogs) {
        final date = log['date'] as String?;
        if (date != null) {
          final val = ((log['adherence'] as num?)?.toInt() ?? 0).clamp(0, 100);
          logsByDate[date] = val;
        }
      }

      // Calculate total days from account creation (capped at 7)
      final effectiveStart = accountCreatedDate.isAfter(startDate) ? accountCreatedDate : startDate;
      final totalDays = now.difference(effectiveStart).inDays + 1;

      if (totalDays > 0) {
        int sum = 0;
        for (int i = 0; i < totalDays; i++) {
          final date = effectiveStart.add(Duration(days: i));
          final dateStr = DateFormat('yyyy-MM-dd').format(date);
          sum += logsByDate[dateStr] ?? 0; // missing days count as 0
        }

        final avg = (sum / totalDays).round().clamp(0, 100);
        if (mounted) setState(() {
          _calculatedAdherence = avg;
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data      = widget.doc.data() as Map<String, dynamic>;
    final uid       = widget.doc.id;
    final name      = data['name']      as String? ?? 'Unknown';
    final diagnosis = data['diagnosis'] as String? ?? 'CF';
    // Use calculated adherence if available, otherwise fall back to stored value
    final storedAdherence = ((data['lastAdherence'] as num?)?.toInt() ?? 0).clamp(0, 100);
    final adherence = (_calculatedAdherence ?? storedAdherence).clamp(0, 100);
    final isDark    = Theme.of(context).brightness == Brightness.dark;

    final Color riskColor;
    final String riskLabel;
    if (adherence >= 80) { riskColor = Colors.green; riskLabel = 'Low Risk'; }
    else if (adherence >= 50) { riskColor = Colors.orange; riskLabel = 'Moderate Risk'; }
    else { riskColor = Colors.red; riskLabel = 'High Risk'; }

    final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();

    // Responsive sizes
    final avatarRadius = widget.isCompact ? 22.0 : 28.0;
    final ringSize = widget.isCompact ? 90.0 : 110.0;
    final nameSize = widget.isCompact ? 15.0 : 17.0;
    final percentSize = widget.isCompact ? 22.0 : 28.0;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PatientDetailScreen(
              patientUid: uid,
              patientName: name,
              diagnosis: diagnosis,
              lastAdherence: adherence,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? _darkCard : Colors.white,
          borderRadius: BorderRadius.circular(widget.isCompact ? 20 : 24),
          border: Border.all(color: isDark ? _darkBdr : Colors.grey.shade100, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: riskColor.withOpacity(isDark ? 0.2 : 0.1),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar
            CircleAvatar(
              radius: avatarRadius,
              backgroundColor: riskColor.withOpacity(0.15),
              child: Text(initials, style: TextStyle(color: riskColor, fontWeight: FontWeight.w800, fontSize: widget.isCompact ? 14 : 18)),
            ),
            SizedBox(height: widget.isCompact ? 6 : 10),

            // Name + diagnosis
            Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.isCompact ? 8 : 12),
              child: Text(name,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: nameSize,
                      color: isDark ? Colors.white : Colors.black87),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 2),
            Text(diagnosis,
                style: TextStyle(color: Colors.grey, fontSize: widget.isCompact ? 10 : 12)),
            SizedBox(height: widget.isCompact ? 10 : 16),

            // Ring
            SizedBox(
              width: ringSize, height: ringSize,
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _crimson, strokeWidth: 2))
                  : CustomPaint(
                      painter: _RingPainter(
                        percentage: adherence / 100,
                        color: riskColor,
                        trackColor: isDark ? Colors.white10 : Colors.grey.shade100,
                      ),
                      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('$adherence%',
                            style: TextStyle(fontSize: percentSize, fontWeight: FontWeight.w900, color: riskColor)),
                        Text('adherence', style: TextStyle(fontSize: widget.isCompact ? 8 : 10, color: Colors.grey)),
                      ])),
                    ),
            ),
            SizedBox(height: widget.isCompact ? 10 : 14),

            // Risk badge
            Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.isCompact ? 8 : 12),
              child: Container(
                constraints: BoxConstraints(maxWidth: widget.isCompact ? 90 : 110),
                padding: EdgeInsets.symmetric(horizontal: widget.isCompact ? 8 : 12, vertical: widget.isCompact ? 3 : 5),
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: riskColor.withOpacity(0.4)),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(riskLabel,
                      style: TextStyle(color: riskColor, fontWeight: FontWeight.w700, fontSize: widget.isCompact ? 10 : 12)),
                ),
              ),
            ),
            SizedBox(height: widget.isCompact ? 10 : 14),

            // Alert button
            Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.isCompact ? 12 : 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => widget.onAlert(context, uid, name),
                  icon: Icon(Icons.send_rounded, size: widget.isCompact ? 12 : 14),
                  label: Text('Send Message', style: TextStyle(fontWeight: FontWeight.w700, fontSize: widget.isCompact ? 11 : 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _crimson,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(vertical: widget.isCompact ? 8 : 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(widget.isCompact ? 10 : 14)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Alerts Tab ───────────────────────────────────────────────────────────────
class _AlertsTab extends StatelessWidget {
  final DoctorService service;
  const _AlertsTab({required this.service});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;
    final isCompact = screenWidth < 400;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: EdgeInsets.only(
        left: isMobile ? (isCompact ? 12 : 20) : 104,
        right: isCompact ? 12 : 20,
        top: isCompact ? 12 : 20,
        bottom: 20,
      ),
      children: [
        // ─── Received Alerts (Low Adherence) ─────────────────────────────
        _buildSectionHeader(context, 'Received Alerts', Icons.warning_amber_rounded, Colors.red),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: service.getLowAdherenceAlertsStream(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator(color: _crimson)),
              );
            }
            
            if (!snap.hasData || snap.data!.docs.isEmpty) {
              return _buildEmptySection('No low adherence alerts', Icons.check_circle_outline, Colors.green);
            }

            final docs = snap.data!.docs.toList();
            docs.sort((a, b) {
              final at = (a.data() as Map)['timestamp'] as Timestamp?;
              final bt = (b.data() as Map)['timestamp'] as Timestamp?;
              return (bt?.seconds ?? 0).compareTo(at?.seconds ?? 0);
            });

            return Column(
              children: docs.take(10).map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = data['patientName'] as String? ?? 'Patient';
                final msg = data['message'] as String? ?? '';
                final adherence = data['adherencePercent'] as int? ?? 0;
                final ts = (data['timestamp'] as Timestamp?)?.toDate();
                final read = data['read'] == true;
                final patientUid = data['patientUid'] as String? ?? '';
                final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();

                return Container(
                  margin: EdgeInsets.only(bottom: isCompact ? 8 : 12),
                  padding: EdgeInsets.all(isCompact ? 12 : 16),
                  decoration: BoxDecoration(
                    color: isDark ? _darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(isCompact ? 14 : 18),
                    border: Border.all(
                      color: read
                          ? (isDark ? _darkBdr : Colors.grey.shade200)
                          : Colors.red.withOpacity(0.5),
                      width: read ? 1 : 1.5,
                    ),
                    boxShadow: [
                      if (!read) BoxShadow(color: Colors.red.withOpacity(0.1), blurRadius: 12),
                    ],
                  ),
                  child: Row(children: [
                    // Tappable area for navigation
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (!read) {
                            service.markLowAdherenceAlertRead(doc.id);
                          }
                          if (patientUid.isNotEmpty) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PatientDetailScreen(
                                  patientUid: patientUid,
                                  patientName: name,
                                  diagnosis: 'CF',
                                  lastAdherence: adherence,
                                ),
                              ),
                            );
                          }
                        },
                        child: Row(children: [
                          CircleAvatar(
                            radius: isCompact ? 18 : 22,
                            backgroundColor: Colors.red.withOpacity(0.12),
                            child: const Icon(Icons.warning_rounded, color: Colors.red, size: 20),
                          ),
                          SizedBox(width: isCompact ? 10 : 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(
                                child: Text('From: $name',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: isCompact ? 13 : 14)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  '<50%',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red),
                                ),
                              ),
                            ]),
                            SizedBox(height: isCompact ? 3 : 4),
                            Text('7-day adherence dropped below 50%',
                                style: TextStyle(fontSize: isCompact ? 12 : 13, color: Colors.grey),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            SizedBox(height: isCompact ? 3 : 4),
                            Row(children: [
                              Text(
                                ts != null ? DateFormat(isCompact ? 'MMM d · h:mm a' : 'MMM d, yyyy · h:mm a').format(ts) : '—',
                                style: TextStyle(fontSize: isCompact ? 10 : 11, color: Colors.grey),
                              ),
                              if (!read) ...[
                                const SizedBox(width: 8),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                ),
                              ],
                            ]),
                          ])),
                        ]),
                      ),
                    ),
                    // Delete button (outside GestureDetector)
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: isCompact ? 18 : 20, color: Colors.red),
                      tooltip: 'Delete alert',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: ctx,
                          builder: (c) => AlertDialog(
                            title: const Text('Delete Alert'),
                            content: const Text('Delete this low adherence alert?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                              TextButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Delete', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          service.deleteLowAdherenceAlert(doc.id);
                        }
                      },
                    ),
                  ]),
                );
              }).toList(),
            );
          },
        ),
        
        const SizedBox(height: 24),
        
        // ─── Sent Messages ───────────────────────────────────────────────
        _buildSectionHeader(context, 'Sent Messages', Icons.send_rounded, _crimson),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: service.getSentAlertsStream(),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator(color: _crimson)),
              );
            }
            
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade400),
                    const SizedBox(height: 12),
                    Text('Error loading alerts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
                  ],
                ),
              );
            }
            
            final docs = (snap.data?.docs ?? [])
                .where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['deletedByDoctor'] != true;
                })
                .toList();
            docs.sort((a, b) {
              final at = (a.data() as Map)['timestamp'] as Timestamp?;
              final bt = (b.data() as Map)['timestamp'] as Timestamp?;
              return (bt?.seconds ?? 0).compareTo(at?.seconds ?? 0);
            });

            if (docs.isEmpty) {
              return _buildEmptySection('No messages sent yet', Icons.send_rounded, Colors.grey);
            }

            return Column(
              children: docs.map((docSnap) {
                final docId = docSnap.id;
                final data  = docSnap.data() as Map<String, dynamic>;
                final name  = data['patientName'] as String? ?? 'Patient';
                final patientUid = data['patientUid'] as String? ?? '';
                final msg   = data['message']     as String? ?? '';
                final ts    = (data['timestamp']  as Timestamp?)?.toDate();
                final read  = data['read'] == true;
                final deletedByPatient = data['deletedByPatient'] == true;
                final initials = name.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();

                return Container(
                  margin: EdgeInsets.only(bottom: isCompact ? 8 : 12),
                  padding: EdgeInsets.all(isCompact ? 12 : 16),
                  decoration: BoxDecoration(
                    color: isDark ? _darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(isCompact ? 14 : 18),
                    border: Border.all(
                      color: read
                          ? (isDark ? _darkBdr : Colors.grey.shade200)
                          : Colors.orange.withOpacity(0.5),
                      width: read ? 1 : 1.5,
                    ),
                    boxShadow: [
                      if (!read) BoxShadow(color: Colors.orange.withOpacity(0.1), blurRadius: 12),
                    ],
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      radius: isCompact ? 18 : 22,
                      backgroundColor: _crimson.withOpacity(0.12),
                      child: Text(initials, style: TextStyle(color: _crimson, fontWeight: FontWeight.w700, fontSize: isCompact ? 11 : 13)),
                    ),
                    SizedBox(width: isCompact ? 10 : 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('To: $name',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: isCompact ? 13 : 14)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: read ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: read ? Colors.green.withOpacity(0.4) : Colors.orange.withOpacity(0.5),
                            ),
                          ),
                          child: Text(
                            read ? '✓ Read' : '• Unread',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: read ? Colors.green : Colors.orange,
                            ),
                          ),
                        ),
                      ]),
                      SizedBox(height: isCompact ? 3 : 4),
                      Text(msg,
                          style: TextStyle(fontSize: isCompact ? 12 : 13, color: Colors.grey),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      SizedBox(height: isCompact ? 3 : 4),
                      Text(
                        ts != null ? DateFormat(isCompact ? 'MMM d · h:mm a' : 'MMM d, yyyy · h:mm a').format(ts) : '—',
                        style: TextStyle(fontSize: isCompact ? 10 : 11, color: Colors.grey),
                      ),
                      if (deletedByPatient)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '(Deleted by patient)',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                          ),
                        ),
                    ])),
                    // Delete button
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: isCompact ? 18 : 20, color: Colors.red),
                      tooltip: 'Delete message',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: ctx,
                          builder: (c) => AlertDialog(
                            title: const Text('Delete Message'),
                            content: Text(deletedByPatient
                                ? 'This message was already deleted by the patient. Delete permanently?'
                                : 'Delete this message from your sent list?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                              TextButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Delete', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && patientUid.isNotEmpty) {
                          service.deleteSentAlert(docId, patientUid);
                        }
                      },
                    ),
                  ]),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87)),
      ],
    );
  }

  Widget _buildEmptySection(String message, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color.withOpacity(0.5), size: 24),
          const SizedBox(width: 12),
          Text(message, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
        ],
      ),
    );
  }
}

// ─── Empty State ─────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _EmptyState({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 72, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.grey)),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
      ]),
    );
  }
}

// ─── Ring Painter ─────────────────────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  final double percentage;
  final Color color, trackColor;
  _RingPainter({required this.percentage, required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    const w = 10.0;
    final c = Offset(size.width / 2, size.height / 2);
    final r = (size.width - w) / 2;

    canvas.drawCircle(c, r, Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round);

    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-3.14159 / 2);
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r),
      0, 2 * 3.14159 * percentage, false,
      Paint()
        ..shader = SweepGradient(
          colors: [color.withOpacity(0.3), color],
          stops: const [0.0, 1.0],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_) => true;
}
