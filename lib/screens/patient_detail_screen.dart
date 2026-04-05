import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../utils/error_utils.dart';

const _crimson  = Color(0xFFDC143C);
const _darkBg   = Color(0xFF111827);
const _darkCard = Color(0xFF1F2937);
const _darkBdr  = Color(0xFF374151);

class PatientDetailScreen extends StatefulWidget {
  final String patientUid;
  final String patientName;
  final String diagnosis;
  final int lastAdherence;

  const PatientDetailScreen({
    super.key,
    required this.patientUid,
    required this.patientName,
    required this.diagnosis,
    required this.lastAdherence,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  int _selectedDays = 7;
  List<Map<String, dynamic>> _logs = [];
  Map<String, int> _logsByDate = {}; // Date string -> adherence
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 6));
  DateTime _endDate = DateTime.now();
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Fetch patient's account creation date
      final userDoc = await _db.collection('users').doc(widget.patientUid).get();
      final createdAt = userDoc.data()?['createdAt'] as Timestamp?;
      
      // Get all logs first to find the earliest one
      final snap = await _db
          .collection('users')
          .doc(widget.patientUid)
          .collection('daily_logs')
          .orderBy('date', descending: false)
          .get();
      
      // Determine account start date: use createdAt if available, otherwise first log date
      DateTime accountCreatedDate;
      if (createdAt != null) {
        final d = createdAt.toDate();
        accountCreatedDate = DateTime(d.year, d.month, d.day); // normalize to midnight
      } else if (snap.docs.isNotEmpty) {
        // Find the first log that has actual data (adherence > 0)
        final firstRealLog = snap.docs.firstWhere(
          (d) => ((d.data()['adherence'] as num?)?.toInt() ?? 0) > 0,
          orElse: () => snap.docs.first,
        );
        final firstDate = firstRealLog.data()['date'] as String?;
        if (firstDate != null) {
          accountCreatedDate = DateTime.parse(firstDate);
        } else {
          accountCreatedDate = DateTime.now().subtract(const Duration(days: 7));
        }
      } else {
        accountCreatedDate = DateTime.now().subtract(const Duration(days: 7));
      }
      
      // Normalize to midnight so difference.inDays is always an exact integer
      final now = DateTime.now();
      final endDate = DateTime(now.year, now.month, now.day);
      final acct = accountCreatedDate;
      accountCreatedDate = DateTime(acct.year, acct.month, acct.day);
      DateTime startDate;
      
      if (_selectedDays == -1) {
        // All time - start from account creation
        startDate = accountCreatedDate;
      } else {
        startDate = endDate.subtract(Duration(days: _selectedDays - 1));
        // Don't go before account creation
        if (startDate.isBefore(accountCreatedDate)) {
          startDate = accountCreatedDate;
        }
      }

      // Filter client-side based on date range
      // Use account creation date as absolute minimum (ignore any logs before it)
      final accountStartStr = DateFormat('yyyy-MM-dd').format(accountCreatedDate);
      final startStr = DateFormat('yyyy-MM-dd').format(startDate);
      final endStr = DateFormat('yyyy-MM-dd').format(endDate);
      
      final filteredLogs = snap.docs
          .map((d) => d.data())
          .where((log) {
            final date = log['date'] as String? ?? '';
            // Ignore any logs from before the account was created
            if (date.compareTo(accountStartStr) < 0) return false;
            return date.compareTo(startStr) >= 0 && date.compareTo(endStr) <= 0;
          })
          .toList();

      // Build a map of date -> adherence for quick lookup
      final Map<String, int> logsByDate = {};
      for (final log in filteredLogs) {
        final date = log['date'] as String?;
        if (date != null) {
          logsByDate[date] = (log['adherence'] as num?)?.toInt() ?? 0;
        }
      }

      // For "All Time", adjust startDate to earliest log date if we have data
      DateTime effectiveStartDate = startDate;
      if (_selectedDays == -1 && filteredLogs.isNotEmpty) {
        final earliestDate = filteredLogs.first['date'] as String?;
        if (earliestDate != null) {
          effectiveStartDate = DateTime.parse(earliestDate);
        }
      }

      setState(() {
        _logs = filteredLogs;
        _logsByDate = logsByDate;
        _startDate = effectiveStartDate;
        _endDate = endDate;
        _loading = false;
      });
      
    } catch (e) {
      setState(() {
        _loading = false;
        _error = ErrorUtils.getFriendlyMessage(e);
      });
    }
  }

  double _getAverageAdherence() {
    final totalDays = _endDate.difference(_startDate).inDays + 1;
    if (totalDays <= 0) return 0;
    
    // Sum all logged days + 0 for missing days
    final total = _logs.fold<int>(0, (s, l) => s + ((l['adherence'] as num?)?.toInt() ?? 0));
    return total / totalDays;
  }

  Color _riskColor(int adherence) {
    if (adherence >= 80) return Colors.green;
    if (adherence >= 50) return Colors.orange;
    return Colors.red;
  }

  String _riskLabel(int adherence) {
    if (adherence >= 80) return 'Low Risk';
    if (adherence >= 50) return 'Moderate Risk';
    return 'High Risk';
  }

  List<FlSpot> _getSpots() {
    if (_startDate.isAfter(_endDate)) return [];
    
    final spots = <FlSpot>[];
    final totalDays = _endDate.difference(_startDate).inDays + 1;
    
    // Create spots for ALL days in range, using 0 for missing days
    for (int i = 0; i < totalDays; i++) {
      final date = _startDate.add(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      
      // Use logged value if available, otherwise 0
      final adherence = _logsByDate[dateStr]?.toDouble() ?? 0.0;
      spots.add(FlSpot(i.toDouble(), adherence));
    }
    
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final average = _getAverageAdherence();
    final spots = _getSpots();
    final axisColor = isDark ? Colors.white70 : Colors.black54;
    final gridColor = isDark ? Colors.white12 : Colors.black12;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: isDark ? _darkBg : const Color(0xFFF0F4F8),
      appBar: AppBar(
        backgroundColor: _crimson,
        foregroundColor: Colors.white,
        elevation: 2,
        title: Text(widget.patientName, style: const TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Patient Info Card
            _buildPatientInfoCard(isDark),
            const SizedBox(height: 24),

            // Error display
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.security_rounded, color: Colors.red.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Permission Denied',
                            style: TextStyle(color: Colors.red.shade700, fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          color: Colors.red.shade700,
                          onPressed: _loadData,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Update your Firestore Security Rules to allow doctors to read patient data:',
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        '''match /users/{userId}/daily_logs/{logId} {
  allow read: if request.auth != null && 
    get(/databases/\$(database)/documents/users/\$(request.auth.uid)).data.role == 'doctor';
}''',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Error: $_error',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Period Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _periodChip('7 Days', 7),
                const SizedBox(width: 8),
                _periodChip('30 Days', 30),
                const SizedBox(width: 8),
                _periodChip('All Time', -1),
              ],
            ),
            const SizedBox(height: 24),

            // Average Adherence Card
            _buildAverageCard(average, isDark, axisColor),
            const SizedBox(height: 24),

            // Adherence Graph
            _buildGraphSection(isDark, axisColor, gridColor, spots),
            const SizedBox(height: 24),

            // Daily Logs List
            _buildDailyLogsList(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientInfoCard(bool isDark) {
    final initials = widget.patientName
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();
    // Use calculated average from loaded logs, not passed lastAdherence
    final displayAdherence = _logs.isNotEmpty ? _getAverageAdherence().round() : widget.lastAdherence;
    final riskColor = _riskColor(displayAdherence);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? _darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? _darkBdr : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: riskColor.withOpacity(isDark ? 0.2 : 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: riskColor.withOpacity(0.15),
            child: Text(initials, style: TextStyle(color: riskColor, fontWeight: FontWeight.w800, fontSize: 20)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.patientName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    )),
                const SizedBox(height: 4),
                Text('Diagnosis: ${widget.diagnosis}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 95),
            child: Column(
              children: [
                // Adherence ring - uses calculated average
                SizedBox(
                  width: 70,
                  height: 70,
                  child: CustomPaint(
                    painter: _RingPainter(
                      percentage: displayAdherence / 100,
                      color: riskColor,
                      trackColor: isDark ? Colors.white10 : Colors.grey.shade200,
                    ),
                    child: Center(
                      child: Text('$displayAdherence%',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: riskColor)),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: riskColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: riskColor.withOpacity(0.3)),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_riskLabel(displayAdherence),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: riskColor)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodChip(String label, int days) {
    final isSelected = _selectedDays == days;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: _crimson.withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected ? _crimson : Colors.grey,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      onSelected: (on) {
        if (on) {
          setState(() => _selectedDays = days);
          _loadData();
        }
      },
    );
  }

  Widget _buildAverageCard(double average, bool isDark, Color axisColor) {
    final riskColor = _riskColor(average.round());
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: riskColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: riskColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text('Average Adherence', style: TextStyle(fontSize: 14, color: axisColor)),
          const SizedBox(height: 8),
          Text('${average.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: riskColor)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: riskColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_riskLabel(average.round()),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          ),
          if (_logs.isNotEmpty || _selectedDays != -1) ...[
            const SizedBox(height: 12),
            Text(
              _selectedDays == -1
                  ? '${_logs.length} days with data'
                  : '${_logs.length} of ${_endDate.difference(_startDate).inDays + 1} days logged',
              style: TextStyle(fontSize: 12, color: axisColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGraphSection(bool isDark, Color axisColor, Color gridColor, List<FlSpot> spots) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? _darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? _darkBdr : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Daily Adherence',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              )),
          const SizedBox(height: 4),
          Text(
            _selectedDays == -1
                ? 'All time data'
                : 'Last $_selectedDays days',
            style: TextStyle(fontSize: 12, color: axisColor),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 280,
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _crimson))
                : spots.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bar_chart_rounded, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            const Text('No adherence data yet'),
                          ],
                        ),
                      )
                    : LineChart(
                        LineChartData(
                          minX: 0,
                          maxX: (_endDate.difference(_startDate).inDays).toDouble().clamp(1, double.infinity),
                          minY: 0,
                          maxY: 100,
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: true,
                              curveSmoothness: 0.35,
                              color: _crimson,
                              barWidth: 2.5,
                              isStrokeCapRound: true,
                              dotData: FlDotData(
                                show: spots.length <= 31,
                                getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                                  radius: 5,
                                  color: _riskColor(spot.y.round()),
                                  strokeWidth: 2,
                                  strokeColor: Colors.white,
                                ),
                              ),
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  colors: [_crimson.withOpacity(0.3), _crimson.withOpacity(0)],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ],
                          extraLinesData: ExtraLinesData(horizontalLines: [
                            HorizontalLine(
                              y: 80,
                              color: Colors.green.withOpacity(0.5),
                              strokeWidth: 1,
                              dashArray: [6, 4],
                              label: HorizontalLineLabel(
                                show: true,
                                alignment: Alignment.topRight,
                                style: const TextStyle(fontSize: 10, color: Colors.green),
                                labelResolver: (_) => '80%',
                              ),
                            ),
                            HorizontalLine(
                              y: 50,
                              color: Colors.orange.withOpacity(0.5),
                              strokeWidth: 1,
                              dashArray: [6, 4],
                              label: HorizontalLineLabel(
                                show: true,
                                alignment: Alignment.topRight,
                                style: const TextStyle(fontSize: 10, color: Colors.orange),
                                labelResolver: (_) => '50%',
                              ),
                            ),
                          ]),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 40,
                                interval: 25,
                                getTitlesWidget: (value, _) => Text(
                                  '${value.toInt()}%',
                                  style: TextStyle(fontSize: 11, color: axisColor),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 28,
                                interval: () {
                                  final totalDays = _endDate.difference(_startDate).inDays + 1;
                                  return totalDays <= 7 ? 1.0 : (totalDays / 7).ceilToDouble();
                                }(),
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  final totalDays = _endDate.difference(_startDate).inDays + 1;
                                  if (idx < 0 || idx >= totalDays) return const SizedBox.shrink();
                                  final date = _startDate.add(Duration(days: idx));
                                  return SideTitleWidget(
                                    axisSide: meta.axisSide,
                                    child: Text(
                                      DateFormat(totalDays <= 7 ? 'E' : 'M/d').format(date),
                                      style: TextStyle(fontSize: 10, color: axisColor),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: 25,
                            getDrawingHorizontalLine: (_) => FlLine(color: gridColor, strokeWidth: 1),
                          ),
                          borderData: FlBorderData(
                            show: true,
                            border: Border(
                              bottom: BorderSide(color: gridColor, width: 1),
                              left: BorderSide(color: gridColor, width: 1),
                            ),
                          ),
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              // tooltipBgColor for older fl_chart versions
                              tooltipBgColor: Colors.black87,
                              getTooltipItems: (spots) => spots.map((s) {
                                final idx = s.x.toInt();
                                final totalDays = _endDate.difference(_startDate).inDays + 1;
                                if (idx < 0 || idx >= totalDays) return null;
                                final date = _startDate.add(Duration(days: idx));
                                final formattedDate = DateFormat('MMM d').format(date);
                                return LineTooltipItem(
                                  '$formattedDate\n',
                                  const TextStyle(color: Colors.white70, fontSize: 11),
                                  children: [
                                    TextSpan(
                                      text: '${s.y.toInt()}%',
                                      style: TextStyle(
                                        color: _riskColor(s.y.round()),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
          ),
          const SizedBox(height: 20),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _legendItem('Low Risk (>80%)', Colors.green),
              _legendItem('Moderate Risk (50-79%)', Colors.orange),
              _legendItem('High Risk (<50%)', Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildDailyLogsList(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? _darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? _darkBdr : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Daily Logs (Past 7 Days)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              )),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: _crimson))
          else
            ..._buildAllDaysLogs(isDark),
        ],
      ),
    );
  }

  List<Widget> _buildAllDaysLogs(bool isDark) {
    final widgets = <Widget>[];
    final today = DateTime.now();
    
    // Show only last 7 days (most recent first)
    for (int i = 0; i < 7; i++) {
      final date = today.subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      
      // Check if we have a log for this day
      final hasLog = _logsByDate.containsKey(dateStr);
      final adherence = _logsByDate[dateStr] ?? 0;
      
      // Find full log data if exists
      final log = _logs.firstWhere(
        (l) => l['date'] == dateStr,
        orElse: () => {},
      );
      final takenCount = (log['takenCount'] as num?)?.toInt() ?? 0;
      final totalMeds = (log['totalMeds'] as num?)?.toInt() ?? 0;
      
      final riskColor = _riskColor(adherence);
      final formattedDate = DateFormat('MMM d, yyyy').format(date);

      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: riskColor.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: riskColor.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 40,
                decoration: BoxDecoration(
                  color: riskColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formattedDate,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      hasLog 
                        ? '$takenCount / $totalMeds medicines taken'
                        : 'No medicines logged',
                      style: TextStyle(
                        fontSize: 12, 
                        color: Colors.grey.shade600,
                        fontStyle: hasLog ? FontStyle.normal : FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: riskColor.withOpacity(0.4)),
                ),
                child: Text('$adherence%',
                    style: TextStyle(fontWeight: FontWeight.w700, color: riskColor)),
              ),
            ],
          ),
        ),
      );
    }
    
    return widgets;
  }
}

// Ring Painter (same as in dashboard_screen.dart)
class _RingPainter extends CustomPainter {
  final double percentage;
  final Color color, trackColor;
  _RingPainter({required this.percentage, required this.color, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    const w = 6.0;
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
