import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async'; // Import async library for StreamSubscription
import 'dart:math';
//verify
String? _getSafeString(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  if (value is num) { // Handles int, double, etc.
    return value.toString();
  }
  // Fallback for other unexpected types, with a warning.
  print('Warning: Field "$key" in Firestore had unexpected type ${value.runtimeType}. Converting to string.');
  return value.toString();
}

// Data model for usage records
class UsageData {
  final DateTime time;
  final double value;
  final String type; // 'electricity', 'water', or 'sensor1'
  final String unit; // e.g., 'kWh', 'L', 'mA'
  final String? deviceId; // Optional: To identify specific sensors
  final String? userId; // Optional: To associate data with a user

  UsageData({
    required this.time,
    required this.value,
    required this.type,
    required this.unit,
    this.deviceId,
    this.userId,
  });

  factory UsageData.fromFirestore(DocumentSnapshot doc, String defaultType, String defaultUnit) {
    final data = doc.data() as Map<String, dynamic>? ?? {}; // Handle null data

    final timestamp = (data["time"] as Timestamp?)?.toDate() ?? DateTime.now(); // Default to now if missing
    final value = (data["value"] as num?)?.toDouble() ?? 0.0; // Default to 0.0 if missing/invalid

    final String? deviceIdFromData = _getSafeString(data, "DeviceId");
    final String? userId = _getSafeString(data, "userId");
    final String? rawTypeFromData = _getSafeString(data, "type");
    final String? rawUnitFromData = _getSafeString(data, "unit");

    String determinedType;
    String determinedUnit;

    // Determine type and unit.
    if (deviceIdFromData == _UsageAnalysisScreenState.SENSOR_DEVICE_ID) {
      determinedType = 'sensor1';
      determinedUnit = 'mA'; // Sensor unit is always mA
    } else {
      determinedType = rawTypeFromData?.toLowerCase() ?? defaultType.toLowerCase();
      determinedUnit = rawUnitFromData ?? defaultUnit;
    }

    return UsageData(
      time: timestamp,
      value: value,
      type: determinedType,
      unit: determinedUnit,
      deviceId: deviceIdFromData, // Store the deviceId obtained
      userId: userId,
    );
  }
}

// Data model to summarize usage and cost for a single day (for historical data)
class DailySummary {
  final DateTime date;
  final double totalUsage;
  final double estimatedCost;

  DailySummary({
    required this.date,
    required this.totalUsage,
    required this.estimatedCost,
  });
}


// StatefulWidget for the Usage Analysis Screen
class UsageAnalysisScreen extends StatefulWidget {
  final String? userId; // Pass userId if needed for filtering sensor data

  const UsageAnalysisScreen({Key? key, this.userId}) : super(key: key);

  @override
  State<UsageAnalysisScreen> createState() => _UsageAnalysisScreenState();
}

// State class for UsageAnalysisScreen
class _UsageAnalysisScreenState extends State<UsageAnalysisScreen> {
  // State variables
  String _selectedTimePeriod = "Daily";
  String _selectedUsageType = "electricity";
  DateTime _selectedDate = DateTime.now();

  // Data Stores
  List<UsageData> _historicalUsageData = [];
  List<DailySummary> _monthlyDailySummaries = [];
  List<UsageData> _realtimeSensorData = [];

  // Chart and Display
  List<FlSpot> _chartSpots = [];
  double _displayTotalUsage = 0.0;
  double _displayEstimatedCost = 0.0;
  String _displayUnit = 'kWh';

  // State Management
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription? _sensorStreamSubscription;
  DateTime? _sensorStreamStartTime;

  List<Map<String, dynamic>> _recommendations = [];

  static const String SENSOR_DEVICE_ID = 'IoT Sensor1';

  // --- Tariff Configuration (Example for BHD - ADJUST AS NEEDED) ---
  final double _electricityTier1Rate = 0.003;
  final double _electricityTier2Rate = 0.009;
  final double _electricityTier3Rate = 0.016;
  final double _electricityTier1Limit = 3000.0;
  final double _electricityTier2Limit = 5000.0;
  final double _waterRatePerLiter = 0.0008;

  // --- Recommendation Thresholds (Example Values - ADJUST AS NEEDED) ---
  final double _highElectricityThresholdDaily = 15.0;
  final double _highWaterThresholdDaily = 200.0; // This is 200L, if aiming for 1000L/day, this might be too low
  final double _highSensorThreshold = 1000.0;

  @override
  void initState() {
    super.initState();
    _handleDataSourceChange();
  }

  @override
  void dispose() {
    _cancelSensorStream();
    super.dispose();
  }

  // --- Data Handling Logic ---
  Future<void> _handleDataSourceChange() async {
    await _cancelSensorStream();
    _clearDataState();

    if (_selectedUsageType == 'sensor1') {
      await _listenToSensorData();
    } else {
      await _loadHistoricalDataForMonth();
    }
  }

  void _clearDataState() {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _historicalUsageData = [];
      _monthlyDailySummaries = [];
      _realtimeSensorData = [];
      _chartSpots = [];
      _displayTotalUsage = 0.0;
      _displayEstimatedCost = 0.0;
      _displayUnit = _getUnit();
      _recommendations = [];
    });
  }

  Future<void> _cancelSensorStream() async {
    await _sensorStreamSubscription?.cancel();
    _sensorStreamSubscription = null;
    _sensorStreamStartTime = null;
    print("Sensor stream cancelled.");
  }

  Future<void> _listenToSensorData() async {
    if (!mounted) return;
    print("Attempting to listen to Sensor 1 stream (Device ID: $SENSOR_DEVICE_ID)...");

    final completer = Completer<void>();

    setState(() {
      _isLoading = true;
      _realtimeSensorData = [];
      _selectedTimePeriod = "Daily";
      _displayUnit = 'mA';
    });

    _sensorStreamStartTime = DateTime.now();

    try {
      Query query = FirebaseFirestore.instance
          .collection("records")
          .where("DeviceId", isEqualTo: SENSOR_DEVICE_ID)
          .where("time", isGreaterThanOrEqualTo: Timestamp.fromDate(_sensorStreamStartTime!))
          .orderBy("time", descending: false);

      _sensorStreamSubscription = query.snapshots().listen((snapshot) {
        print("Received ${snapshot.docs.length} sensor readings from stream.");
        if (!mounted) return;

        final List<UsageData> newReadings = snapshot.docs.map((doc) {
          return UsageData.fromFirestore(doc, 'sensor1', 'mA');
        }).where((data) => data.value >= 0).toList();


        setState(() {
          _realtimeSensorData = newReadings;
          if (_isLoading) _isLoading = false;
          _errorMessage = null;
          _processDataForView();
        });
        if (!completer.isCompleted) {
          completer.complete();
        }

      }, onError: (error, stackTrace) {
        print("----------------------------------------");
        print("❌ Error in Sensor 1 stream: $error");
        print("Stack trace:\n$stackTrace");
        print("----------------------------------------");
        if (mounted) {
          setState(() {
            _errorMessage = "Failed to get real-time sensor data. Check Firestore index and permissions.";
            _isLoading = false;
            _realtimeSensorData.clear();
            _processDataForView();
          });
        }
        _cancelSensorStream();
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }, onDone: () {
        print("Sensor 1 stream was closed.");
        if (mounted) {
          if (_isLoading) setState(() { _isLoading = false; });
        }
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

    } catch (e, s) {
      print("----------------------------------------");
      print("❌ Error setting up sensor listener: $e");
      print("Stack trace:\n$s");
      print("----------------------------------------");
      if (mounted) {
        setState(() {
          _errorMessage = "Error starting sensor listener.";
          _isLoading = false;
        });
      }
      if (!completer.isCompleted) {
        completer.completeError(e, s);
      }
    }
    return completer.future;
  }

  Future<void> _loadHistoricalDataForMonth() async {
    if (!mounted) return;
    print("----------------------------------------------------");
    print("LOAD HISTORICAL DATA FOR MONTH - START");
    print("Selected Usage Type: $_selectedUsageType");
    print("Selected Date for Query: $_selectedDate (Year: ${_selectedDate.year}, Month: ${_selectedDate.month})");

    if (!_isLoading) {
      setState(() { _isLoading = true; });
    }
    print("Is Loading (before fetch): $_isLoading");

    try {
      final int year = _selectedDate.year;
      final int month = _selectedDate.month;
      final DateTime firstDayOfMonth = DateTime(year, month, 1);
      final DateTime firstDayOfNextMonth = (month == 12)
          ? DateTime(year + 1, 1, 1)
          : DateTime(year, month + 1, 1);

      print("Querying for type: '$_selectedUsageType'");
      print("Querying time >= $firstDayOfMonth (Timestamp: ${firstDayOfMonth.millisecondsSinceEpoch ~/ 1000})");
      print("Querying time < $firstDayOfNextMonth (Timestamp: ${firstDayOfNextMonth.millisecondsSinceEpoch ~/ 1000})");

      final querySnapshot = await FirebaseFirestore.instance
          .collection("usage_data")
          .where("type", isEqualTo: _selectedUsageType)
          .where("time", isGreaterThanOrEqualTo: Timestamp.fromDate(firstDayOfMonth))
          .where("time", isLessThan: Timestamp.fromDate(firstDayOfNextMonth))
          .orderBy("time", descending: false)
          .get();

      print("Firestore query completed. Documents fetched: ${querySnapshot.docs.length}");
      if (querySnapshot.docs.isNotEmpty) {
        print("First fetched document data: ${querySnapshot.docs.first.data()}");
      }

      final String defaultUnit = _selectedUsageType == 'electricity' ? 'kWh' : 'L';
      final List<UsageData> fetchedData = querySnapshot.docs.map((doc) {
        return UsageData.fromFirestore(doc, _selectedUsageType, defaultUnit);
      }).where((data) => data.value >= 0).toList();

      double totalFetchedUsage = fetchedData.fold(0.0, (sum, item) => sum + item.value);
      print("Fetched ${fetchedData.length} $_selectedUsageType records. Total usage: $totalFetchedUsage ${fetchedData.isNotEmpty ? fetchedData.first.unit : defaultUnit}");

      if (mounted) {
        setState(() {
          _historicalUsageData = fetchedData;
          _processDataForMonth();
          _processDataForView();
          _isLoading = false;
          print("Is Loading (after successful fetch & process): $_isLoading");
        });
      }
    } catch (e, s) {
      print("❌ Error loading historical data for month: $e");
      print("Stack trace:\n$s");
      if (mounted) {
        setState(() {
          _errorMessage = "Failed to load usage data. Check connection, Firestore rules, and data format.";
          _isLoading = false;
          _historicalUsageData.clear();
          _monthlyDailySummaries.clear();
          _processDataForView();
          print("Is Loading (after error): $_isLoading");
        });
      }
    }
    print("LOAD HISTORICAL DATA FOR MONTH - END");
    print("----------------------------------------------------");
  }

  void _processDataForMonth() {
    if (_selectedUsageType == 'sensor1' || _historicalUsageData.isEmpty) {
      _monthlyDailySummaries = [];
      return;
    }

    Map<int, List<UsageData>> dataPerDay = {};
    for (var data in _historicalUsageData) {
      dataPerDay.putIfAbsent(data.time.day, () => []).add(data);
    }

    List<DailySummary> dailySummaries = [];
    final int daysInMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;

    for (int i = 1; i <= daysInMonth; i++) {
      final dayData = dataPerDay[i] ?? [];
      double totalUsageForDay = dayData.fold(0.0, (sum, item) => sum + item.value);
      double estimatedCostForDay = _calculateEstimatedCostForPeriod(totalUsageForDay);

      dailySummaries.add(DailySummary(
        date: DateTime(_selectedDate.year, _selectedDate.month, i),
        totalUsage: totalUsageForDay,
        estimatedCost: estimatedCostForDay,
      ));
    }

    dailySummaries.sort((a, b) => a.date.compareTo(b.date));
    _monthlyDailySummaries = dailySummaries;
    print("Processed ${_monthlyDailySummaries.length} daily summaries for the month.");
  }

  void _processDataForView() {
    if (!mounted) return;

    List<FlSpot> spots = [];
    double totalUsageForView = 0;
    double totalEstimatedCostForView = 0;
    double latestValue = 0;

    if (_selectedUsageType == 'sensor1') {
      if (_realtimeSensorData.isEmpty) {
        print("No real-time sensor data available for processing view.");
        if(mounted) {
          setState(() { _chartSpots = []; _displayTotalUsage = 0; _displayEstimatedCost = 0; _recommendations = []; _displayUnit = 'mA'; });
        }
        return;
      }

      _realtimeSensorData.sort((a, b) => a.time.compareTo(b.time));
      spots = _realtimeSensorData.map((data) {
        return FlSpot(data.time.millisecondsSinceEpoch.toDouble(), data.value);
      }).toList();

      if (_realtimeSensorData.isNotEmpty) {
        latestValue = _realtimeSensorData.last.value;
      }
      totalUsageForView = latestValue;
      totalEstimatedCostForView = 0.0;

      print("Sensor 1 View Processed: Readings=${spots.length}, Latest Value=$latestValue mA");

    } else {
      if (_monthlyDailySummaries.isEmpty && _historicalUsageData.isEmpty) {
        print("No historical data available for processing view in _processDataForView.");
        if(mounted) {
          setState(() { _chartSpots = []; _displayTotalUsage = 0; _displayEstimatedCost = 0; _recommendations = []; _displayUnit = _getUnit(); });
        }
        return;
      }

      if (_selectedTimePeriod == "Daily") {
        final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 0, 0, 0);
        final endOfDay = startOfDay.add(const Duration(days: 1));
        List<UsageData> dailyData = _historicalUsageData.where((data) =>
        !data.time.isBefore(startOfDay) && data.time.isBefore(endOfDay)
        ).toList();
        dailyData.sort((a, b) => a.time.compareTo(b.time));
        spots = dailyData.map((data) {
          double hourFraction = data.time.hour + (data.time.minute / 60.0) + (data.time.second / 3600.0);
          double estimatedCost = _calculateEstimatedCostForPeriod(data.value);
          return FlSpot(hourFraction, estimatedCost);
        }).toList();
        totalUsageForView = dailyData.fold(0.0, (sum, item) => sum + item.value);
        totalEstimatedCostForView = dailyData.fold(0.0, (sum, item) => sum + _calculateEstimatedCostForPeriod(item.value));
        print("Daily View (Historical) Processed: Date=${DateFormat.yMd().format(_selectedDate)}, Spots=${spots.length}, Total Usage=$totalUsageForView, Total Est Cost=$totalEstimatedCostForView");

      } else if (_selectedTimePeriod == "Weekly") {
        final DateTime endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
        final DateTime startDate = endDate.subtract(const Duration(days: 6));
        List<DailySummary> weeklySummaries = _monthlyDailySummaries.where((summary) =>
        !summary.date.isBefore(startDate) && !summary.date.isAfter(endDate)
        ).toList();
        weeklySummaries.sort((a, b) => a.date.compareTo(b.date));
        spots = weeklySummaries.asMap().entries.map((entry) {
          return FlSpot(entry.key.toDouble(), entry.value.estimatedCost);
        }).toList();
        totalUsageForView = weeklySummaries.fold(0.0, (sum, item) => sum + item.totalUsage);
        totalEstimatedCostForView = weeklySummaries.fold(0.0, (sum, item) => sum + item.estimatedCost);
        print("Weekly View (Historical) Processed: Start=${DateFormat.yMd().format(startDate)}, End=${DateFormat.yMd().format(endDate)}, Spots=${spots.length}, Total Usage=$totalUsageForView, Total Est Cost=$totalEstimatedCostForView");

      } else if (_selectedTimePeriod == "Monthly") {
        spots = _monthlyDailySummaries.map((summary) {
          return FlSpot(summary.date.day.toDouble(), summary.estimatedCost);
        }).toList();
        int daysWithDataCount = _monthlyDailySummaries.where((s) => s.totalUsage > 0).length;
        double sumOfRawUsage = _monthlyDailySummaries.fold(0.0, (sum, item) => sum + item.totalUsage);
        double sumOfEstimatedCost = _monthlyDailySummaries.fold(0.0, (sum, item) => sum + item.estimatedCost);
        totalUsageForView = (daysWithDataCount > 0) ? sumOfRawUsage / daysWithDataCount : 0.0;
        totalEstimatedCostForView = (daysWithDataCount > 0) ? sumOfEstimatedCost / daysWithDataCount : 0.0;
        print("Monthly View (Historical) Processed: Spots=${spots.length}, Avg Daily Est Cost=$totalEstimatedCostForView, Avg Daily Usage=$totalUsageForView");
      }
    }

    if (mounted) {
      setState(() {
        _chartSpots = spots;
        _displayTotalUsage = totalUsageForView;
        _displayEstimatedCost = totalEstimatedCostForView;
        _displayUnit = _getUnit();
        double valueForRecs = 0;
        if (_selectedUsageType == 'sensor1') {
          valueForRecs = latestValue;
        } else if (_selectedTimePeriod == "Daily") {
          valueForRecs = totalUsageForView;
        } else if (_selectedTimePeriod == "Weekly") {
          valueForRecs = spots.isNotEmpty && totalUsageForView != 0 ? totalUsageForView / 7.0 : 0.0;
        } else if (_selectedTimePeriod == "Monthly") {
          valueForRecs = totalUsageForView;
        }
        _recommendations = _generateRecommendations(
            currentSpots: _chartSpots,
            valueForComparison: valueForRecs,
            averageCostForPeriod: totalEstimatedCostForView,
            totalUsageForPeriod: totalUsageForView
        );
      });
    }
  }

  List<Map<String, dynamic>> _generateRecommendations({
    required List<FlSpot> currentSpots,
    required double valueForComparison,
    required double averageCostForPeriod,
    required double totalUsageForPeriod,
  }) {
    List<Map<String, dynamic>> recs = [];
    String currentUnit = _getUnit();

    if (_selectedUsageType == 'sensor1') {
      recs.add({
        'icon': Icons.sensors_rounded,
        'text': 'Latest Sensor 1 reading: ${valueForComparison.toStringAsFixed(1)} $currentUnit.'
      });
      if (valueForComparison > _highSensorThreshold) {
        recs.add({
          'icon': Icons.warning_amber_rounded,
          'text': 'Sensor reading is currently high (>${_highSensorThreshold.toStringAsFixed(0)} $currentUnit). Check the connected device.'
        });
      }
      recs.add({'icon': Icons.info_outline_rounded, 'text': 'This sensor monitors real-time values in $currentUnit.'});

    } else {
      bool isElectricity = _selectedUsageType == 'electricity';
      double highThreshold = isElectricity ? _highElectricityThresholdDaily : _highWaterThresholdDaily;
      String periodContext = "";
      // Use yMMMMd for month and year string for recommendations to be consistent.
      String monthYearStr = DateFormat('MMMM yyyy').format(_selectedDate);


      if (_selectedTimePeriod == "Daily") {
        // Use 'EEE, MMM d, yyyy' for daily context to match the corrected date display
        periodContext = "for ${DateFormat('EEE, MMM d, yyyy').format(_selectedDate)}";
      } else if (_selectedTimePeriod == "Weekly") {
        // Use 'EEE, MMM d, yyyy' for weekly context
        final DateTime endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
        final DateTime startDate = endDate.subtract(const Duration(days: 6));
        periodContext = "on average per day during the week ending ${DateFormat('EEE, MMM d, yyyy').format(_selectedDate)}";
      } else if (_selectedTimePeriod == "Monthly") {
        periodContext = "on average per day in $monthYearStr";
      }

      if (valueForComparison > highThreshold) {
        recs.add({
          'icon': isElectricity ? Icons.power_off_rounded : Icons.shower_rounded,
          'text': 'Usage $periodContext seems high (${valueForComparison.toStringAsFixed(1)} $currentUnit/day). Look for ways to conserve ${isElectricity ? 'electricity' : 'water'}.'
        });
      } else if (valueForComparison > 0) { // Only show "good work" if there's some usage
        recs.add({
          'icon': Icons.thumb_up_alt_rounded,
          'text': 'Usage $periodContext is moderate (${valueForComparison.toStringAsFixed(1)} $currentUnit/day). Keep up the good work!'
        });
      }


      if (currentSpots.isNotEmpty) {
        double maxCost = currentSpots.map((s) => s.y).fold(0.0, max);
        double averageCostPerUnitTime = 0;
        if (_selectedTimePeriod == "Daily" && totalUsageForPeriod > 0) {
          averageCostPerUnitTime = averageCostForPeriod / 24.0;
        } else if (_selectedTimePeriod == "Weekly" && totalUsageForPeriod > 0) {
          averageCostPerUnitTime = averageCostForPeriod / 7.0; // average daily cost in the week
        } else if (_selectedTimePeriod == "Monthly" && totalUsageForPeriod > 0) {
          // averageCostForPeriod is already the average daily cost for the month in this view
          averageCostPerUnitTime = averageCostForPeriod;
        }


        if (maxCost > (averageCostPerUnitTime * 1.5) && averageCostPerUnitTime > 0) {
          String peakTimeText = '';
          if (_selectedTimePeriod == "Daily") {
            List<FlSpot> peakCostSpots = currentSpots.where((s) => s.y >= maxCost * 0.8).toList();
            peakTimeText = peakCostSpots.map((spot) {
              final hour = spot.x.floor();
              final min = ((spot.x - hour) * 60).round().clamp(0, 59);
              return '${hour.toString().padLeft(2,'0')}:${min.toString().padLeft(2,'0')}';
            }).toSet().join(', ');
            if (peakTimeText.isNotEmpty) peakTimeText = 'around $peakTimeText';

          } else { // Weekly or Monthly
            FlSpot peakCostSpot = currentSpots.reduce((curr, next) => curr.y > next.y ? curr : next);
            if (_selectedTimePeriod == "Weekly") {
              final DateTime endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
              final DateTime startDate = endDate.subtract(const Duration(days: 6));
              final peakDate = startDate.add(Duration(days: peakCostSpot.x.toInt()));
              final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
              // Using 'EEE, MMM d' for a more descriptive peak day
              peakTimeText = DateFormat('EEE, MMM d').format(peakDate);
              peakTimeText = 'on $peakTimeText';
            } else if (_selectedTimePeriod == "Monthly") {
              // For monthly, peakCostSpot.x is the day of the month.
              // We can format this with the month name for clarity.
              final peakDate = DateTime(_selectedDate.year, _selectedDate.month, peakCostSpot.x.toInt());
              peakTimeText = DateFormat('MMM d').format(peakDate); // e.g., "May 15"
              peakTimeText = 'around $peakTimeText';
            }
          }

          if (peakTimeText.isNotEmpty) {
            recs.add({
              'icon': Icons.warning_amber_rounded,
              'text': 'Estimated cost peaks significantly $peakTimeText. Try to reduce consumption during these times/days.'
            });
          }
        }
      }

      if (isElectricity) {
        recs.add({'icon': Icons.lightbulb_outline_rounded, 'text': 'Consider switching to energy-efficient LED lighting.'});
        recs.add({'icon': Icons.power_settings_new_rounded, 'text': 'Unplug chargers and appliances when not in use (phantom load).'});
        recs.add({'icon': Icons.thermostat_rounded, 'text': 'Optimize AC usage: set moderate temperatures, use timers, ensure good insulation.'});
      } else {
        recs.add({'icon': Icons.opacity_rounded, 'text': 'Regularly check for dripping taps or running toilets.'});
        recs.add({'icon': Icons.shower_rounded, 'text': 'Consider shorter showers or installing water-saving showerheads.'});
        recs.add({'icon': Icons.local_laundry_service_rounded, 'text': 'Run washing machines and dishwashers only with full loads.'});
        recs.add({'icon': Icons.grass_rounded, 'text': 'Water your garden efficiently, preferably early morning or late evening.'});
      }
    }
    return recs.take(4).toList();
  }

  // --- Cost Calculation ---
  double _calculateElectricityCost(double usageValue) {
    if (usageValue <= 0) return 0.0;
    double cost = 0.0;
    if (usageValue <= _electricityTier1Limit) {
      cost = usageValue * _electricityTier1Rate;
    } else if (usageValue <= _electricityTier2Limit) {
      cost = (min(usageValue, _electricityTier1Limit) * _electricityTier1Rate) +
          (max(0.0, usageValue - _electricityTier1Limit) * _electricityTier2Rate);
    } else {
      cost = (_electricityTier1Limit * _electricityTier1Rate) +
          ((_electricityTier2Limit - _electricityTier1Limit) * _electricityTier2Rate) +
          (max(0.0, usageValue - _electricityTier2Limit) * _electricityTier3Rate);
    }
    return cost;
  }

  double _calculateWaterCost(double usageValue) {
    if (usageValue <= 0) return 0.0;
    return usageValue * _waterRatePerLiter;
  }

  double _calculateEstimatedCostForPeriod(double usageValue) {
    if (_selectedUsageType == 'sensor1') {
      return 0.0;
    } else if (_selectedUsageType == 'electricity') {
      return _calculateElectricityCost(usageValue);
    } else if (_selectedUsageType == 'water') {
      return _calculateWaterCost(usageValue);
    }
    return 0.0;
  }

  String _getUnit() {
    switch (_selectedUsageType) {
      case 'electricity':
        return 'kWh';
      case 'water':
        return 'L';
      case 'sensor1':
        return 'mA';
      default:
        if(_realtimeSensorData.isNotEmpty) return _realtimeSensorData.first.unit;
        if(_historicalUsageData.isNotEmpty) return _historicalUsageData.first.unit;
        return '';
    }
  }

  // --- Build Methods ---
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usage Analysis'),
        backgroundColor: Colors.green,
        elevation: 1,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handleDataSourceChange,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildFilterSection(context, theme, textTheme),
              const SizedBox(height: 20),
              _buildContentArea(context, theme, textTheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection(BuildContext context, ThemeData theme, TextTheme textTheme) {
    bool isSensorSelected = _selectedUsageType == 'sensor1';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedUsageType,
                icon: Icon(Icons.arrow_drop_down_rounded, color: theme.colorScheme.primary),
                isExpanded: true,
                items: ["electricity", "water", "sensor1"].map((type) {
                  IconData icon;
                  String label;
                  switch(type) {
                    case 'electricity': icon = Icons.electrical_services_rounded; label = 'Electricity'; break;
                    case 'water': icon = Icons.water_drop_rounded; label = 'Water'; break;
                    case 'sensor1': icon = Icons.sensors_rounded; label = 'Sensor 1'; break;
                    default: icon = Icons.help_outline; label = 'Unknown';
                  }
                  return DropdownMenuItem<String>(
                      value: type,
                      child: Row( children: [
                        Icon(icon, color: theme.colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(label),
                      ])
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null && newValue != _selectedUsageType) {
                    setState(() {
                      _selectedUsageType = newValue;
                      if (newValue == 'sensor1') {
                        _selectedTimePeriod = "Daily";
                      }
                    });
                    _handleDataSourceChange();
                  }
                },
                style: textTheme.titleMedium,
                dropdownColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedTimePeriod,
                    onChanged: isSensorSelected ? null : (String? newValue) {
                      if (newValue != null && newValue != _selectedTimePeriod) {
                        setState(() => _selectedTimePeriod = newValue);
                        _processDataForView();
                      }
                    },
                    items: ["Daily", "Weekly", "Monthly"].map((period) =>
                        DropdownMenuItem<String>(
                            value: period,
                            enabled: !isSensorSelected || period == "Daily",
                            child: Text(
                              period,
                              style: TextStyle(
                                color: (!isSensorSelected || period == "Daily")
                                    ? theme.textTheme.titleMedium?.color
                                    : theme.disabledColor,
                              ),
                            )
                        )
                    ).toList(),
                    style: textTheme.titleMedium,
                    dropdownColor: theme.colorScheme.surfaceContainerHighest,
                    disabledHint: isSensorSelected ? Text("Daily", style: textTheme.titleMedium?.copyWith(color: theme.disabledColor)) : null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.calendar_month_rounded, color: isSensorSelected ? theme.disabledColor : theme.colorScheme.secondary),
                  tooltip: isSensorSelected ? "Date selection disabled for real-time sensor" : "Select Date / Month",
                  onPressed: isSensorSelected ? null : _selectDate,
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentArea(BuildContext context, ThemeData theme, TextTheme textTheme) {
    if (_isLoading) {
      return const Center(heightFactor: 5, child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(heightFactor: 5, child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.error_outline_rounded, color: theme.colorScheme.error, size: 40),
        const SizedBox(height: 10),
        Text(_errorMessage!, style: textTheme.titleMedium?.copyWith(color: theme.colorScheme.error), textAlign: TextAlign.center),
        const SizedBox(height: 10),
        ElevatedButton(onPressed: _handleDataSourceChange, child: const Text('Retry')),
      ]));
    }

    bool noDataAvailable = (_selectedUsageType == 'sensor1' && _realtimeSensorData.isEmpty) ||
        (_selectedUsageType != 'sensor1' && _historicalUsageData.isEmpty && _monthlyDailySummaries.isEmpty);

    if (noDataAvailable && !_isLoading) {
      String dataTypeMessage = _selectedUsageType == 'sensor1'
          ? "real-time data for 'Sensor 1' (ID: $SENSOR_DEVICE_ID)"
      // Corrected DateFormat for no data message
          : "historical data for '$_selectedUsageType' in ${DateFormat('MMMM yyyy').format(_selectedDate)}";
      return Center(heightFactor: 5, child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.signal_cellular_nodata_rounded, color: Colors.grey, size: 40), const SizedBox(height: 10),
        Text("No $dataTypeMessage found.", style: textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        ElevatedButton(onPressed: _handleDataSourceChange, child: const Text('Retry Fetch')),
      ]));
    }

    if (_chartSpots.isEmpty && !noDataAvailable && !_isLoading) {
      String message = "No specific data points available for the selected '$_selectedTimePeriod' view of '$_selectedUsageType'.";
      if (_selectedUsageType != 'sensor1') {
        if (_selectedTimePeriod == 'Daily') {
          // Corrected DateFormat for no chart data message (Daily)
          message = "No '$_selectedUsageType' data found for ${DateFormat('EEE, MMM d, yyyy').format(_selectedDate)}.";
        } else if (_selectedTimePeriod == 'Weekly') {
          // Corrected DateFormat for no chart data message (Weekly)
          final DateTime endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
          final DateTime startDate = endDate.subtract(const Duration(days: 6));
          message = "No '$_selectedUsageType' data found for the week ${DateFormat('MMM d').format(startDate)} - ${DateFormat('MMM d, yyyy').format(endDate)}.";
        }
      } else {
        message = "Waiting for initial Sensor 1 readings or no readings in the current view window.";
      }
      return Center(heightFactor: 5, child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.info_outline_rounded, color: Colors.grey, size: 40), const SizedBox(height: 10),
        Text(message, style: textTheme.titleMedium, textAlign: TextAlign.center),
      ]));
    }

    final totalUsage = _displayTotalUsage;
    final estimatedCost = _displayEstimatedCost;
    final currentUnit = _displayUnit;

    String dateContextString = "";
    if (_selectedUsageType == 'sensor1') {
      dateContextString = "Showing real-time data for: Sensor 1";
      if (_sensorStreamStartTime != null) {
        dateContextString += " (since ${DateFormat.jm().format(_sensorStreamStartTime!)})";
      }
    } else if (_selectedTimePeriod == "Daily") {
      // Corrected DateFormat: Removed _bin_46 by using 'EEE, MMM d, yyyy'
      dateContextString = "Showing data for: ${DateFormat('EEE, MMM d, yyyy').format(_selectedDate)}";
    } else if (_selectedTimePeriod == "Weekly") {
      final DateTime endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final DateTime startDate = endDate.subtract(const Duration(days: 6));
      // Corrected DateFormat for weekly view for consistency
      dateContextString = "Showing data for: ${DateFormat('MMM d').format(startDate)} - ${DateFormat('MMM d, yyyy').format(endDate)}";
    } else if (_selectedTimePeriod == "Monthly") {
      // Corrected DateFormat for monthly view
      dateContextString = "Showing data for: ${DateFormat('MMMM yyyy').format(_selectedDate)}";
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0, top: 8.0),
          child: Text(dateContextString, style: textTheme.titleSmall?.copyWith(color: theme.colorScheme.outline)),
        ),
        _buildUsageSummary(context, theme, textTheme, totalUsage, estimatedCost, currentUnit),
        const SizedBox(height: 24),
        _buildChartTitle(context, theme, textTheme),
        const SizedBox(height: 8),
        _buildChart(context, theme, textTheme, _chartSpots),
        const SizedBox(height: 24),
        _buildRecommendations(context, theme, textTheme),
      ],
    );
  }

  Widget _buildChartTitle(BuildContext context, ThemeData theme, TextTheme textTheme) {
    String title = "";
    String subTitle = "";

    if (_selectedUsageType == 'sensor1') {
      title = "Real-time Sensor Readings";
      subTitle = "(Device ID: $SENSOR_DEVICE_ID)";
    } else {
      if (_selectedTimePeriod == "Daily") {
        title = "Estimated Hourly Cost Pattern";
        // Corrected DateFormat for daily chart subtitle
        subTitle = "(Day: ${DateFormat('MMM d, yyyy').format(_selectedDate)})";
      } else if (_selectedTimePeriod == "Weekly") {
        title = "Estimated Daily Cost for the Week";
        final DateTime endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
        final DateTime startDate = endDate.subtract(const Duration(days: 6));
        // Corrected DateFormat for weekly chart subtitle
        subTitle = "(Week: ${DateFormat('MMM d').format(startDate)} - ${DateFormat('MMM d, yyyy').format(endDate)})";
      } else if (_selectedTimePeriod == "Monthly") {
        title = "Total Daily Estimated Cost by Day";
        // Corrected DateFormat for monthly chart subtitle
        subTitle = "(Month: ${DateFormat('MMMM yyyy').format(_selectedDate)})";
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        if (subTitle.isNotEmpty)
          Text(subTitle, style: textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
      ],
    );
  }

  Widget _buildUsageSummary(BuildContext context, ThemeData theme, TextTheme textTheme, double usageValue, double costValue, String unit) {
    String usageLabel = "";
    String costLabel = "Est. Cost";
    IconData usageIcon;
    String displayType = '';

    switch (_selectedUsageType) {
      case 'electricity':
        usageIcon = Icons.flash_on_rounded;
        displayType = 'Electricity';
        if (_selectedTimePeriod == "Daily") usageLabel = "Total Usage";
        else if (_selectedTimePeriod == "Weekly") usageLabel = "Total Usage for Week";
        else usageLabel = "Avg. Daily Usage";
        if (_selectedTimePeriod == "Daily") costLabel = "Est. Cost for Day";
        else if (_selectedTimePeriod == "Weekly") costLabel = "Est. Cost for Week";
        else costLabel = "Est. Cost (Avg. Day)";
        break;
      case 'water':
        usageIcon = Icons.opacity_rounded;
        displayType = 'Water';
        if (_selectedTimePeriod == "Daily") usageLabel = "Total Usage";
        else if (_selectedTimePeriod == "Weekly") usageLabel = "Total Usage for Week";
        else usageLabel = "Avg. Daily Usage";
        if (_selectedTimePeriod == "Daily") costLabel = "Est. Cost for Day";
        else if (_selectedTimePeriod == "Weekly") costLabel = "Est. Cost for Week";
        else costLabel = "Est. Cost (Avg. Day)";
        break;
      case 'sensor1':
        usageIcon = Icons.sensors_rounded;
        displayType = 'Sensor 1';
        usageLabel = "Latest Reading";
        costLabel = "Est. Cost";
        break;
      default:
        usageIcon = Icons.help_outline;
        usageLabel = "Usage";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
          gradient: LinearGradient( colors: [ theme.colorScheme.primaryContainer.withAlpha(153), theme.colorScheme.primaryContainer.withAlpha(77)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(12.0),
          boxShadow: [ BoxShadow( color: Colors.black.withAlpha(13), blurRadius: 8, offset: const Offset(0, 4)) ]
      ),
      child: Column( children: [
        _buildSummaryRow(
            context, theme, textTheme,
            icon: usageIcon,
            label: "$usageLabel ($displayType)",
            value: "${usageValue.toStringAsFixed(_selectedUsageType == 'sensor1' ? 1 : 2)} $unit",
            valueColor: theme.colorScheme.onPrimaryContainer
        ),
        if (_selectedUsageType != 'sensor1') ...[
          Divider(height: 16, thickness: 0.5, color: theme.colorScheme.outline.withAlpha(128)),
          _buildSummaryRow(
              context, theme, textTheme,
              icon: Icons.attach_money_rounded,
              label: costLabel,
              value: "${costValue.toStringAsFixed(3)} BHD",
              valueColor: theme.colorScheme.error
          ),
        ] else ... [
          Divider(height: 16, thickness: 0.5, color: theme.colorScheme.outline.withAlpha(128)),
          _buildSummaryRow(
              context, theme, textTheme,
              icon: Icons.money_off_csred_rounded,
              label: costLabel,
              value: "N/A",
              valueColor: theme.colorScheme.outline
          ),
        ]
      ]),
    );
  }

  Widget _buildSummaryRow(BuildContext context, ThemeData theme, TextTheme textTheme, {required IconData icon, required String label, required String value, Color? valueColor}) {
    return Row( children: [
      Icon(icon, color: theme.colorScheme.primary, size: 22), const SizedBox(width: 12),
      Expanded(child: Text(label, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500))),
      Text(value, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: valueColor ?? theme.colorScheme.onSurface)),
    ]);
  }

  Widget _buildChart(BuildContext context, ThemeData theme, TextTheme textTheme, List<FlSpot> spots) {
    if (spots.isEmpty && !_isLoading) {
      return const SizedBox(height: 300, child: Center(child: Text("Chart data is being processed or is unavailable.")));
    }
    if (spots.isEmpty && _isLoading) {
      return const SizedBox(height: 300);
    }

    double minXValue = spots.isNotEmpty ? spots.first.x : 0;
    double maxXValue = spots.isNotEmpty ? spots.last.x : 1;
    double minYValue = 0.0, maxYValue = 0.1;
    double bottomInterval = 1;
    String Function(double) bottomTitleFormatter = (v) => '';
    String Function(double) leftTitleFormatter = (v) => v.toStringAsFixed(1);
    String yAxisLabel = "Value";
    final String currentUnit = _displayUnit;

    if (_selectedUsageType == 'sensor1') {
      yAxisLabel = "Reading ($currentUnit)";
      if (spots.isNotEmpty) {
        minXValue = spots.first.x;
        maxXValue = spots.last.x + (spots.length > 1 ? (spots.last.x - spots.first.x) * 0.05 : 1000);
        minYValue = spots.map((e) => e.y).fold(double.infinity, min);
        maxYValue = spots.map((e) => e.y).fold(double.negativeInfinity, max);
        double yRange = maxYValue - minYValue;
        double yPadding = max(yRange * 0.1, 1.0);
        minYValue = max(0.0, minYValue - yPadding);
        maxYValue = maxYValue + yPadding;
        if (maxYValue - minYValue < 5) maxYValue = minYValue + 5;
      } else {
        minXValue = DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch.toDouble();
        maxXValue = DateTime.now().millisecondsSinceEpoch.toDouble();
        minYValue = 0; maxYValue = 10;
      }

      bottomTitleFormatter = (timestampMillis) {
        final dateTime = DateTime.fromMillisecondsSinceEpoch(timestampMillis.toInt());
        return DateFormat.Hms().format(dateTime);
      };
      double timeRangeSeconds = (maxXValue - minXValue) / 1000.0;
      bottomInterval = max(1000.0, timeRangeSeconds > 0 ? (timeRangeSeconds / 5.0).ceil() * 1000.0 : 1000.0);
      leftTitleFormatter = (v) => v.toStringAsFixed(1);

    } else {
      yAxisLabel = "Est. Cost (BHD)";
      leftTitleFormatter = (v) => v.toStringAsFixed(3);
      minYValue = 0.0;
      maxYValue = 0.01;
      if (spots.isNotEmpty) {
        maxYValue = spots.map((e) => e.y).fold(0.0, max);
        double yPadding = max(maxYValue * 0.15, 0.001);
        maxYValue += yPadding;
      }
      if (maxYValue - minYValue < 0.005) maxYValue = minYValue + 0.01;

      if (_selectedTimePeriod == "Daily") {
        minXValue = 0; maxXValue = 24; bottomInterval = 4;
        bottomTitleFormatter = (v) => v.toInt().toString().padLeft(2, '0');
      } else if (_selectedTimePeriod == "Weekly") {
        minXValue = 0; maxXValue = 6; bottomInterval = 1;
        final DateTime endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
        final DateTime startDate = endDate.subtract(const Duration(days: 6));
        final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        bottomTitleFormatter = (v) {
          final dayIndex = v.toInt();
          if (dayIndex < 0 || dayIndex > 6) return '';
          final dateForSpot = startDate.add(Duration(days: dayIndex));
          return weekdays.elementAtOrNull(dateForSpot.weekday - 1) ?? '';
        };
      } else if (_selectedTimePeriod == "Monthly") {
        minXValue = 1;
        maxXValue = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day.toDouble();
        bottomInterval = max(1.0, (maxXValue / 5.0).floorToDouble());
        bottomTitleFormatter = (v) {
          final day = v.toInt();
          if (day < 1 || day > maxXValue) return '';
          if (day == 1 || day == maxXValue.toInt() || ((day - 1) % bottomInterval == 0)) {
            return day.toString();
          }
          return '';
        };
      }
    }

    double yAxisInterval = 0.1;
    if (maxYValue > minYValue) {
      double targetInterval = (maxYValue - minYValue) / 4.0;
      List<double> niceIntervals = [0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0];
      yAxisInterval = niceIntervals.firstWhere((i) => i >= targetInterval, orElse: () => niceIntervals.last);
      if (maxYValue - minYValue < yAxisInterval * 3 && minYValue + yAxisInterval * 4 > maxYValue) {
        maxYValue = minYValue + yAxisInterval * 4;
      }
    }
    minYValue = max(0.0, minYValue);

    Color lineColor;
    switch(_selectedUsageType) {
      case 'electricity': lineColor = Colors.orange.shade700; break;
      case 'water': lineColor = Colors.blue.shade600; break;
      case 'sensor1': lineColor = Colors.purple.shade600; break;
      default: lineColor = Colors.grey;
    }
    List<Color> gradientColors = [lineColor.withAlpha(204), lineColor];
    int gridLineAlpha = 30;

    return Container(
      padding: const EdgeInsets.only(top: 16, bottom: 16, left: 8, right: 16),
      height: 350,
      child: LineChart(
        LineChartData(
          clipData: const FlClipData.all(),
          backgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(51),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            verticalInterval: bottomInterval,
            horizontalInterval: yAxisInterval,
            getDrawingHorizontalLine: (value) => FlLine(color: theme.dividerColor.withAlpha(gridLineAlpha), strokeWidth: 1),
            getDrawingVerticalLine: (value) => FlLine(color: theme.dividerColor.withAlpha(gridLineAlpha), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: bottomInterval,
                getTitlesWidget: (double value, TitleMeta meta) {
                  if (value < minXValue - bottomInterval*0.1 || value > maxXValue + bottomInterval*0.1) return const SizedBox.shrink();
                  if (_selectedUsageType != 'sensor1' && _selectedTimePeriod != "Daily" && value != value.toInt().toDouble()) {
                    if (_selectedTimePeriod != "Monthly") return const SizedBox.shrink();
                  }
                  return SideTitleWidget(meta: meta, space: 8.0, child: Text(bottomTitleFormatter(value), style: textTheme.bodySmall));
                }
            )),
            leftTitles: AxisTitles(
                axisNameWidget: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(yAxisLabel, style: textTheme.bodySmall),
                ),
                axisNameSize: 22,
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 55,
                  interval: yAxisInterval,
                  getTitlesWidget: (double value, TitleMeta meta) {
                    final tolerance = yAxisInterval * 0.01;
                    if (value < minYValue - tolerance || value > maxYValue + tolerance) return const SizedBox.shrink();

                    bool isMinY = (value - minYValue).abs() < tolerance;
                    bool isMaxY = (value - maxYValue).abs() < tolerance;
                    bool isOnInterval = ((value - minYValue) % yAxisInterval).abs() < tolerance || (yAxisInterval - ((value - minYValue) % yAxisInterval)).abs() < tolerance;

                    if (!(isMinY || isMaxY || isOnInterval)) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(meta: meta, space: 8.0, child: Text(leftTitleFormatter(value), style: textTheme.bodySmall));
                  },
                )),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: true, border: Border.all(color: theme.dividerColor.withAlpha(51))),
          minX: minXValue, maxX: maxXValue, minY: minYValue, maxY: maxYValue,
          lineBarsData: spots.isEmpty ? [] : [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              gradient: LinearGradient(colors: gradientColors),
              barWidth: _selectedUsageType == 'sensor1' ? 3 : 4,
              isStrokeCapRound: true,
              dotData: FlDotData(show: _selectedUsageType == 'sensor1'),
              belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                      colors: gradientColors.map((color) => color.withAlpha((255 * 0.2).round())).toList(),
                      begin: Alignment.topCenter, end: Alignment.bottomCenter
                  )
              ),
            )
          ],
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (touchedSpot) => theme.colorScheme.secondary,
                tooltipBorderRadius: BorderRadius.circular(8),
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    String title = '';
                    String valueText = '';
                    String additionalInfo = '';

                    if (_selectedUsageType == 'sensor1') {
                      final dateTime = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                      title = DateFormat.Hms().format(dateTime);
                      valueText = '${spot.y.toStringAsFixed(1)} $currentUnit';

                    } else {
                      final estimatedCost = spot.y;
                      valueText = '${estimatedCost.toStringAsFixed(3)} BHD';

                      if (_selectedTimePeriod == "Daily") {
                        final hr = spot.x.floor();
                        final min = ((spot.x - hr) * 60).round().clamp(0, 59);
                        title = '${hr.toString().padLeft(2,'0')}:${min.toString().padLeft(2,'0')}';

                      } else if (_selectedTimePeriod == "Weekly") {
                        final DateTime endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
                        final DateTime startDate = endDate.subtract(const Duration(days: 6));
                        final dateForSpot = startDate.add(Duration(days: spot.x.toInt()));
                        final dailySummary = _monthlyDailySummaries.firstWhere(
                                (s) => s.date.year == dateForSpot.year && s.date.month == dateForSpot.month && s.date.day == dateForSpot.day,
                            orElse: () => DailySummary(date: dateForSpot, totalUsage: 0.0, estimatedCost: estimatedCost)
                        );
                        final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                        title = DateFormat.yMd().format(dailySummary.date) + ' (${weekdays.elementAtOrNull(dailySummary.date.weekday - 1) ?? ''})';
                        additionalInfo = 'Usage: ${dailySummary.totalUsage.toStringAsFixed(2)} $currentUnit/day';
                        valueText += '/day';

                      } else if (_selectedTimePeriod == "Monthly") {
                        final dayOfMonth = spot.x.toInt();
                        final dailySummary = _monthlyDailySummaries.firstWhere(
                                (s) => s.date.day == dayOfMonth,
                            orElse: () => DailySummary(date: DateTime(_selectedDate.year, _selectedDate.month, dayOfMonth), totalUsage: 0.0, estimatedCost: estimatedCost)
                        );
                        title = 'Day $dayOfMonth (${DateFormat('MMM d').format(dailySummary.date)})';
                        additionalInfo = 'Usage: ${dailySummary.totalUsage.toStringAsFixed(2)} $currentUnit/day';
                        valueText += '/day';
                      }
                    }
                    return LineTooltipItem(
                        '$valueText\n',
                        textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSecondary, fontWeight: FontWeight.bold),
                        children: [
                          if (additionalInfo.isNotEmpty) TextSpan(text: '$additionalInfo\n', style: textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSecondary.withAlpha(204))),
                          TextSpan(text: title, style: textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSecondary.withAlpha(204)))
                        ]
                    );
                  }).toList();
                }
            ),
          ),
        ),
        duration: const Duration(milliseconds: 150),
      ),
    );
  }

  Widget _buildRecommendations(BuildContext context, ThemeData theme, TextTheme textTheme) {
    if (_recommendations.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Insights & Recommendations",
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _recommendations.length,
          itemBuilder: (context, index) {
            final rec = _recommendations[index];
            final iconData = rec['icon'] as IconData?;
            final text = rec['text'] as String? ?? '';
            return Card(
              elevation: 1,
              margin: const EdgeInsets.symmetric(vertical: 4.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              color: theme.colorScheme.surfaceContainerLow,
              child: ListTile(
                leading: iconData != null ? Icon(iconData, color: theme.colorScheme.primary, size: 28) : null,
                title: Text(text, style: textTheme.bodyMedium ?? const TextStyle()),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _selectDate() async {
    if (_selectedUsageType == 'sensor1') return;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      // Allow selecting dates up to 5 years in the future, or adjust as needed
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (mounted && picked != null && picked != _selectedDate) {
      bool monthChanged = picked.month != _selectedDate.month || picked.year != _selectedDate.year;
      setState(() {
        _selectedDate = picked;
      });
      if (monthChanged) {
        _handleDataSourceChange();
      } else {
        _processDataForView();
      }
    }
  }

} // End of _UsageAnalysisScreenState
