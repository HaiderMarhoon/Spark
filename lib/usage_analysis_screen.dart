import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';

// Data model for usage records
class UsageData {
  final DateTime time;
  final double value;
  final String type; // 'electricity' or 'water' (lowercase)
  final String unit; // e.g., 'kWh', 'L'

  UsageData({
    required this.time,
    required this.value,
    required this.type,
    required this.unit,
  });
}

// Data model to summarize usage and cost for a single day
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
  const UsageAnalysisScreen({Key? key}) : super(key: key);

  @override
  State<UsageAnalysisScreen> createState() => _UsageAnalysisScreenState();
}

// State class for UsageAnalysisScreen
class _UsageAnalysisScreenState extends State<UsageAnalysisScreen> {
  // State variables
  String _selectedTimePeriod = "Daily";
  String _selectedUsageType = "electricity";
  DateTime _selectedDate = DateTime.now(); // Default to current date
  List<UsageData> _allUsageData = []; // Stores raw data fetched for the selected month
  List<DailySummary> _monthlyDailySummaries = []; // Stores daily summaries for the entire selected month
  List<FlSpot> _chartSpots = []; // Processed data points for the chart
  double _displayTotalUsage = 0.0; // Total/Average usage for the current view
  double _displayEstimatedCost = 0.0; // Total/Average estimated cost for the current view
  bool _isLoading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _recommendations = []; // State for dynamic recommendations

  // --- Tariff Configuration (Example for BHD - ADJUST AS NEEDED) ---
  // Note: These rates are examples and likely need adjustment for accuracy.
  // Water rates often vary significantly and might have different structures.
  final double _electricityTier1Rate = 0.003; // BHD per kWh
  final double _electricityTier2Rate = 0.009; // BHD per kWh
  final double _electricityTier3Rate = 0.016; // BHD per kWh
  final double _electricityTier1Limit = 3000.0; // kWh (monthly assumed)
  final double _electricityTier2Limit = 5000.0; // kWh (monthly assumed)

  // Example Water Tariff (Highly simplified - replace with actual rates)
  final double _waterRatePerLiter = 0.0008; // Example: 0.8 fils per Liter (0.0008 BHD/L)
  // --- End Tariff Configuration ---

  // --- Recommendation Thresholds (Example Values - ADJUST AS NEEDED) ---
  final double _highElectricityThresholdDaily = 15.0; // kWh per day
  final double _highWaterThresholdDaily = 200.0; // Liters per day (0.2 m³)
  // ---

  @override
  void initState() {
    super.initState();
    // Load data for the initial month (based on _selectedDate)
    _loadDataForSelectedMonth();
  }

  // --- Data Loading Logic ---

  // Loads usage data from Firestore for the ENTIRE month of _selectedDate
  Future<void> _loadDataForSelectedMonth() async {
    if (_isLoading) return;
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _allUsageData = []; // Clear previous data
      _monthlyDailySummaries = []; // Clear previous summaries
      _chartSpots = []; // Clear previous spots
      _displayTotalUsage = 0.0;
      _displayEstimatedCost = 0.0;
      _recommendations = [];
    });

    try {
      // Calculate the start and end of the month based on _selectedDate
      final int year = _selectedDate.year;
      final int month = _selectedDate.month;
      final DateTime firstDayOfMonth = DateTime(year, month, 1);
      // End date is the first moment of the next month
      final DateTime firstDayOfNextMonth = (month == 12)
          ? DateTime(year + 1, 1, 1) // Handle December -> January transition
          : DateTime(year, month + 1, 1);

      print("Fetching data for month: ${DateFormat('MMMM').format(_selectedDate)}");
      print("Query Range: >= $firstDayOfMonth and < $firstDayOfNextMonth");

      final snapshot = await FirebaseFirestore.instance
          .collection("usage_data")
          .where("type", isEqualTo: _selectedUsageType) // Filter by type server-side
      // Query for the entire selected month
          .where("time", isGreaterThanOrEqualTo: Timestamp.fromDate(firstDayOfMonth))
          .where("time", isLessThan: Timestamp.fromDate(firstDayOfNextMonth))
          .orderBy("time", descending: false) // Order chronologically
          .get();

      print("Firestore query completed. Found ${snapshot.docs.length} documents for the month.");

      final List<UsageData> fetchedData = snapshot.docs.map((doc) {
        final data = doc.data();
        // Robust data parsing with null checks and defaults
        final timestamp = (data["time"] as Timestamp?)?.toDate();
        final value = (data["value"] as num?)?.toDouble();
        final unit = data["unit"] as String? ?? (_selectedUsageType == 'electricity' ? 'kWh' : 'L'); // Default unit based on type
        final type = (data["type"] as String?)?.toLowerCase() ?? _selectedUsageType;

        // Only include valid records
        if (timestamp != null && value != null && value >= 0) { // Ensure value is not null and non-negative
          return UsageData(time: timestamp, value: value, type: type, unit: unit);
        } else {
          print("Skipping invalid record: time=$timestamp, value=$value, type=$type, unit=$unit");
          return null; // Skip invalid records
        }
      }).whereType<UsageData>().toList(); // Filter out nulls

      if (mounted) {
        setState(() {
          _allUsageData = fetchedData; // Store data for the selected month
          _processDataForMonth(); // Process into daily summaries
          _processDataForView(); // Process for the current view
          _isLoading = false;
        });
      }
    } catch (e, s) { // Catch specific exceptions if needed, log stack trace
      print("----------------------------------------");
      print("❌ Error loading data for month: $e");
      print("Stack trace:\n$s");
      print("----------------------------------------");
      if (mounted) {
        setState(() {
          _errorMessage = "Failed to load usage data. Check connection and configuration.";
          _isLoading = false;
          _allUsageData.clear();
          _monthlyDailySummaries.clear();
          _processDataForView(); // Clear dependent state
        });
      }
    }
  }

  // Processes the loaded _allUsageData into daily summaries for the entire month
  void _processDataForMonth() {
    if (_allUsageData.isEmpty) {
      _monthlyDailySummaries = [];
      return;
    }

    // Map: Day of Month (1-31) -> List of usage values for that day
    Map<int, List<UsageData>> dataPerDay = {};
    for (var data in _allUsageData) {
      dataPerDay.putIfAbsent(data.time.day, () => []).add(data);
    }

    List<DailySummary> dailySummaries = [];
    // Calculate the number of days in the selected month
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

    // Sort by date to ensure correct order
    dailySummaries.sort((a, b) => a.date.compareTo(b.date));

    _monthlyDailySummaries = dailySummaries;
    print("Processed ${_monthlyDailySummaries.length} daily summaries for the month.");
  }


  // Processes the daily summaries based on the selected view (_selectedTimePeriod)
  void _processDataForView() {
    if (!mounted) return;

    List<FlSpot> spots = [];
    double totalUsageForPeriod = 0;
    double totalEstimatedCostForPeriod = 0;

    if (_monthlyDailySummaries.isEmpty) {
      print("No daily summaries available for processing view.");
      setState(() { _chartSpots = []; _displayTotalUsage = 0; _displayEstimatedCost = 0; _recommendations = []; });
      return;
    }

    // --- DAILY VIEW ---
    // Shows hourly data points for the specific _selectedDate
    if (_selectedTimePeriod == "Daily") {
      final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 0, 0, 0);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Filter the month's raw data for the selected day
      List<UsageData> dailyData = _allUsageData.where((data) =>
      !data.time.isBefore(startOfDay) && data.time.isBefore(endOfDay)
      ).toList();

      dailyData.sort((a, b) => a.time.compareTo(b.time));

      spots = dailyData.map((data) {
        double hourFraction = data.time.hour + (data.time.minute / 60.0) + (data.time.second / 3600.0);
        double estimatedCost = _calculateEstimatedCostForPeriod(data.value);
        return FlSpot(hourFraction, estimatedCost);
      }).toList();

      totalUsageForPeriod = dailyData.fold(0.0, (sum, item) => sum + item.value);
      totalEstimatedCostForPeriod = dailyData.fold(0.0, (sum, item) => sum + _calculateEstimatedCostForPeriod(item.value));

      print("Daily View Processed: Date=${DateFormat.yMd().format(_selectedDate)}, Spots=${spots.length}, Total Usage=$totalUsageForPeriod, Total Est Cost=$totalEstimatedCostForPeriod");

      // --- WEEKLY VIEW ---
      // Shows the TOTAL daily estimated cost for each day in the 7-day period ending on _selectedDate
    } else if (_selectedTimePeriod == "Weekly") {
      // Calculate the 7-day period ending on _selectedDate
      final DateTime endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day); // End of the day
      final DateTime startDate = endDate.subtract(const Duration(days: 6)); // Start of the day 6 days prior

      // Filter daily summaries for the 7-day period
      List<DailySummary> weeklySummaries = _monthlyDailySummaries.where((summary) =>
      !summary.date.isBefore(startDate) && !summary.date.isAfter(endDate)
      ).toList();

      // Sort by date to ensure correct order for plotting
      weeklySummaries.sort((a, b) => a.date.compareTo(b.date));

      // Map daily summaries to FlSpot, using the day index within the week as X
      spots = weeklySummaries.asMap().entries.map((entry) {
        // X value is the index in the weeklySummaries list (0 to 6)
        // This represents the position within the 7-day period
        return FlSpot(entry.key.toDouble(), entry.value.estimatedCost);
      }).toList();

      // Calculate total usage and estimated cost for the 7-day period
      totalUsageForPeriod = weeklySummaries.fold(0.0, (sum, item) => sum + item.totalUsage);
      totalEstimatedCostForPeriod = weeklySummaries.fold(0.0, (sum, item) => sum + item.estimatedCost);


      print("Weekly View Processed: Start=${DateFormat.yMd().format(startDate)}, End=${DateFormat.yMd().format(endDate)}, Spots=${spots.length}, Total Usage=$totalUsageForPeriod, Total Est Cost=$totalEstimatedCostForPeriod");


      // --- MONTHLY VIEW ---
      // Shows the TOTAL daily estimated cost for each day of the month (1-31)
    } else if (_selectedTimePeriod == "Monthly") {
      // For monthly view, we plot the estimated cost for each day of the month
      spots = _monthlyDailySummaries.map((summary) {
        // X value is the day of the month
        return FlSpot(summary.date.day.toDouble(), summary.estimatedCost);
      }).toList();


      // Summary should show AVERAGE daily usage and AVERAGE daily estimated cost for the MONTH
      int daysWithDataCount = _monthlyDailySummaries.where((s) => s.totalUsage > 0).length;
      double sumOfRawUsage = _monthlyDailySummaries.fold(0.0, (sum, item) => sum + item.totalUsage);
      double sumOfEstimatedCost = _monthlyDailySummaries.fold(0.0, (sum, item) => sum + item.estimatedCost);

      totalUsageForPeriod = (daysWithDataCount > 0) ? sumOfRawUsage / daysWithDataCount : 0.0;
      totalEstimatedCostForPeriod = (daysWithDataCount > 0) ? sumOfEstimatedCost / daysWithDataCount : 0.0;

      print("Monthly View Processed: Spots=${spots.length}, Avg Daily Est Cost=$totalEstimatedCostForPeriod, Avg Daily Usage=$totalUsageForPeriod");
    }

    // Update state & Generate Recommendations
    if (mounted) {
      setState(() {
        _chartSpots = spots;
        _displayTotalUsage = totalUsageForPeriod; // Total/Average raw usage for summary
        _displayEstimatedCost = totalEstimatedCostForPeriod; // Total/Average estimated cost for summary

        // Generate recommendations based on the processed data
        // For Weekly/Monthly, recommendations are based on average daily usage derived from the period's total
        double averageDailyUsageForRecs = _selectedTimePeriod == "Daily" ? totalUsageForPeriod :
        (_selectedTimePeriod == "Weekly" && spots.isNotEmpty ? totalUsageForPeriod / 7.0 : // Average over 7 days
        (_selectedTimePeriod == "Monthly" && spots.isNotEmpty ? totalUsageForPeriod : 0.0)); // Monthly already uses average daily

        _recommendations = _generateRecommendations(spots, averageDailyUsageForRecs);
      });
    }
  }


  // --- Simple "AI" Recommendation Logic ---
  List<Map<String, dynamic>> _generateRecommendations(List<FlSpot> currentSpots, double currentAvgDailyTotal) {
    List<Map<String, dynamic>> recs = [];
    bool isElectricity = _selectedUsageType == 'electricity';
    // Use daily thresholds for recommendations, as currentAvgDailyTotal represents daily usage
    double highThreshold = isElectricity ? _highElectricityThresholdDaily : _highWaterThresholdDaily;

    String periodContext = "";
    String monthYearStr = DateFormat('MMMM').format(_selectedDate);

    if (_selectedTimePeriod == "Daily") {
      periodContext = "for ${DateFormat.yMd().format(_selectedDate)}";
    } else if (_selectedTimePeriod == "Weekly") {
      final DateTime endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final DateTime startDate = endDate.subtract(const Duration(days: 6));
      periodContext = "on average during the week ending ${DateFormat.yMd().format(_selectedDate)}";
    } else if (_selectedTimePeriod == "Monthly") {
      periodContext = "on average for days in $monthYearStr";
    }


    // 1. Check overall average daily usage against threshold
    if (currentAvgDailyTotal > highThreshold) {
      recs.add({
        'icon': isElectricity ? Icons.power_off_rounded : Icons.shower_rounded,
        'text': 'Your usage $periodContext seems high (${currentAvgDailyTotal.toStringAsFixed(1)} ${_getUnit()}/day). Look for ways to conserve ${isElectricity ? 'electricity' : 'water'}.'
      });
    } else if (currentAvgDailyTotal > 0) {
      recs.add({
        'icon': Icons.thumb_up_alt_rounded,
        'text': 'Your usage $periodContext is moderate (${currentAvgDailyTotal.toStringAsFixed(1)} ${_getUnit()}/day). Keep up the good work!'
      });
    }

    // 2. Find Peak Usage Time/Day (if data exists)
    // This makes most sense for Daily view
    if (_selectedTimePeriod == "Daily" && currentSpots.isNotEmpty) {
      // Find the hour(s) with the highest usage (based on cost, as Y is cost)
      double maxCost = currentSpots.map((s) => s.y).fold(0.0, max);
      List<FlSpot> peakCostSpots = currentSpots.where((s) => s.y >= maxCost * 0.8).toList(); // Find spots near the peak cost

      // Only recommend if peak cost is significantly higher than average hourly cost
      // Estimate average hourly cost from average daily cost
      double averageDailyCost = _calculateEstimatedCostForPeriod(currentAvgDailyTotal);
      double averageHourlyCost = averageDailyCost / 24.0;

      if (maxCost > (averageHourlyCost * 2)) { // If peak hourly cost is > 2x average hourly cost
        String peakTimesText = peakCostSpots.map((spot) {
          final hour = spot.x.floor();
          final min = ((spot.x - hour) * 60).round().clamp(0, 59);
          return '${hour.toString().padLeft(2,'0')}:${min.toString().padLeft(2,'0')}';
        }).toSet().join(', '); // Get unique hours

        recs.add({
          'icon': Icons.warning_amber_rounded,
          'text': 'Estimated cost peaks significantly around $peakTimesText. Try to reduce consumption during these times.'
        });
      }
    }
    // Peak analysis for Weekly/Monthly averages might be less actionable for specific times
    // but could highlight peak days (based on average daily cost, as Y is daily cost)
    else if (_selectedTimePeriod != "Daily" && currentSpots.isNotEmpty) {
      FlSpot peakCostSpot = currentSpots.reduce((curr, next) => curr.y > next.y ? curr : next);
      // Estimate average daily cost from average daily usage
      double averageDailyCostForRecs = _calculateEstimatedCostForPeriod(currentAvgDailyTotal);


      // Check if the peak average daily cost is significantly higher than the overall average daily cost
      if (peakCostSpot.y > (averageDailyCostForRecs * 1.5)) { // e.g., > 1.5x average daily cost
        String peakDayText = '';
        if (_selectedTimePeriod == "Weekly") {
          // Find the date for the peak spot's day within the week
          final DateTime endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
          final DateTime startDate = endDate.subtract(const Duration(days: 6));
          final peakDate = startDate.add(Duration(days: peakCostSpot.x.toInt())); // Add index (0-6) to start date
          final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          // Get the weekday name for the peak date
          peakDayText = weekdays.elementAtOrNull(peakDate.weekday - 1) ?? 'a specific day';


        } else if (_selectedTimePeriod == "Monthly") {
          peakDayText = 'around day ${peakCostSpot.x.toInt()}';
        }
        if (peakDayText.isNotEmpty) {
          recs.add({
            'icon': Icons.warning_amber_rounded,
            'text': 'Estimated daily cost tends to be highest $peakDayText in $monthYearStr.'
          });
        }
      }
    }


    // 3. Add generic recommendations
    if (isElectricity) {
      recs.add({'icon': Icons.lightbulb_outline_rounded, 'text': 'Consider switching to energy-efficient LED lighting.'});
      recs.add({'icon': Icons.power_settings_new_rounded, 'text': 'Unplug chargers and appliances when not in use (phantom load).'});
      recs.add({'icon': Icons.thermostat_rounded, 'text': 'Optimize AC usage: set moderate temperatures, use timers, ensure good insulation.'});

    } else { // Water
      recs.add({'icon': Icons.opacity_rounded, 'text': 'Regularly check for dripping taps or running toilets.'});
      recs.add({'icon': Icons.shower_rounded, 'text': 'Consider shorter showers or installing water-saving showerheads.'});
      recs.add({'icon': Icons.local_laundry_service_rounded, 'text': 'Run washing machines and dishwashers only with full loads.'});
      recs.add({'icon': Icons.grass_rounded, 'text': 'Water your garden efficiently, preferably early morning or late evening.'});
    }

    // Limit number of recommendations shown
    return recs.take(4).toList();
  }


  // Calculates the estimated electricity cost based on tiered rates
  // Assumes usageValue is for a specific period (e.g., one hour, one day)
  // Note: For accurate billing, tiered rates apply to TOTAL monthly usage.
  // This function provides an ESTIMATE based on the provided usageValue.
  double _calculateElectricityCost(double usageValue) {
    if (usageValue <= 0) return 0.0;

    // This is a simplified estimation for visualization.
    // A truly accurate tiered cost needs the TOTAL monthly usage to apply tiers sequentially.
    // For a simple estimate based on a single usageValue:
    // Assume this usageValue contributes to the tiers proportionally or falls within one tier.

    double cost = 0.0;
    // Simplified cost calculation based on usage value and rates
    if (usageValue <= _electricityTier1Limit) { // Using monthly limits as a rough guide for rates
      cost = usageValue * _electricityTier1Rate;
    } else if (usageValue <= _electricityTier2Limit) {
      // This part of a simple direct calculation is tricky with tiers.
      // For a simple estimate based on a single usageValue:
      cost = (min(usageValue, _electricityTier1Limit) * _electricityTier1Rate) +
          (max(0.0, usageValue - _electricityTier1Limit) * _electricityTier2Rate);
    } else {
      cost = (_electricityTier1Limit * _electricityTier1Rate) +
          ((_electricityTier2Limit - _electricityTier1Limit) * _electricityTier2Rate) +
          (max(0.0, usageValue - _electricityTier2Limit) * _electricityTier3Rate);
    }

    // IMPORTANT: This tiered cost calculation is a simplification for visualization purposes.
    // For accurate billing, you MUST calculate cost based on the total monthly usage applied to the tiers.

    return cost;
  }

  // Calculates the estimated water cost (simple flat rate example)
  double _calculateWaterCost(double usageValue) {
    if (usageValue <= 0) return 0.0;
    // Replace with actual tiered calculation if needed
    return usageValue * _waterRatePerLiter;
  }


  // Applies cost calculation to the provided usage value
  double _calculateEstimatedCostForPeriod(double usageValue) {
    if (_selectedUsageType == 'electricity') {
      return _calculateElectricityCost(usageValue);
    } else if (_selectedUsageType == 'water') {
      return _calculateWaterCost(usageValue);
    }
    return 0.0; // Default case
  }

  // Gets the unit for the selected type
  String _getUnit() {
    // Find the unit from the first available data point for the selected type
    // Use _allUsageData which contains data for the selected month
    final firstMatchingRecord = _allUsageData.firstWhere(
            (data) => data.type == _selectedUsageType, // Should always find one if _allUsageData is not empty
        orElse: () => UsageData(time: DateTime.now(), value: 0, type: _selectedUsageType, unit: _selectedUsageType == 'electricity' ? 'kWh' : 'L')); // Default based on type
    return firstMatchingRecord.unit;
  }

  // --- Build Methods ---

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usage Analysis'),
        backgroundColor: Colors.green, // Use surface color for AppBar
        elevation: 1, // Add slight elevation
      ),
      // Use a SafeArea to avoid overlaps with system UI
      body: SafeArea(
        child: RefreshIndicator(
          // Trigger loading data for the currently selected month on pull-to-refresh
          onRefresh: _loadDataForSelectedMonth,
          child: ListView( // Use ListView for scrollability
            padding: const EdgeInsets.all(16.0),
            children: [
              // Header
              // Filters
              _buildFilterSection(context, theme, textTheme),
              const SizedBox(height: 20),

              // Content Area (Chart, Summary, Recommendations)
              _buildContentArea(context, theme, textTheme),
            ],
          ),
        ),
      ),
    );
  }

  // Builds the filter dropdowns and date picker section
  Widget _buildFilterSection(BuildContext context, ThemeData theme, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        // Use recommended surface color and alpha for opacity
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(128), // Use alpha instead of withOpacity
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Usage Type Dropdown
          Expanded(
            flex: 2, // Give type dropdown a bit more space
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedUsageType,
                icon: Icon(Icons.arrow_drop_down_rounded, color: theme.colorScheme.primary),
                isExpanded: true, // Allow dropdown to expand
                items: ["electricity", "water"].map((type) =>
                    DropdownMenuItem<String>(
                        value: type,
                        child: Row( children: [
                          Icon(type == 'electricity' ? Icons.electrical_services_rounded : Icons.water_drop_rounded, color: theme.colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          // Capitalize first letter
                          Text(type[0].toUpperCase() + type.substring(1)),
                        ])
                    ),
                ).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null && newValue != _selectedUsageType) {
                    setState(() => _selectedUsageType = newValue);
                    // Reload data for the selected month when type changes
                    _loadDataForSelectedMonth();
                  }
                },
                style: textTheme.titleMedium,
                dropdownColor: theme.colorScheme.surfaceContainerHighest, // Match dropdown background
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Time Period Dropdown & Date Picker
          Expanded(
            flex: 3, // Give time period controls more space
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end, // Align to the right
              children: [
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedTimePeriod,
                    items: ["Daily", "Weekly", "Monthly"].map((period) => DropdownMenuItem<String>(value: period, child: Text(period))).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null && newValue != _selectedTimePeriod) {
                        setState(() => _selectedTimePeriod = newValue);
                        // Re-process existing data for new view (no need to reload)
                        _processDataForView();
                      }
                    },
                    style: textTheme.titleMedium,
                    dropdownColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                // Show Date Picker - allows changing the month context
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.calendar_month_rounded, color: theme.colorScheme.secondary),
                  tooltip: "Select Date / Month", // Updated tooltip
                  onPressed: _selectDate, // Call the date picker method
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Builds the main content area (loading, error, data display)
  Widget _buildContentArea(BuildContext context, ThemeData theme, TextTheme textTheme) {
    // --- Loading State ---
    if (_isLoading) { // Show loading indicator whenever loading is true
      return const Center(heightFactor: 5, child: CircularProgressIndicator());
    }

    // --- Error State ---
    if (_errorMessage != null) {
      return Center(heightFactor: 5, child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.error_outline_rounded, color: theme.colorScheme.error, size: 40),
        const SizedBox(height: 10),
        Text(_errorMessage ?? 'An error occurred', style: textTheme.titleMedium?.copyWith(color: theme.colorScheme.error), textAlign: TextAlign.center),
        const SizedBox(height: 10),
        ElevatedButton(onPressed: _loadDataForSelectedMonth, child: const Text('Retry')), // Retry loading month data
      ]));
    }

    // --- No Data State (after load attempt for the month) ---
    if (_allUsageData.isEmpty && !_isLoading) {
      String monthYearStr = DateFormat('MMMM').format(_selectedDate);
      return Center(heightFactor: 5, child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.signal_cellular_nodata_rounded, color: Colors.grey, size: 40), const SizedBox(height: 10),
        Text("No usage data found for '$_selectedUsageType' in $monthYearStr.", style: textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 10), ElevatedButton(onPressed: _loadDataForSelectedMonth, child: const Text('Retry Fetch')),
      ]));
    }

    // --- No Data For Specific View State (but some data exists for the month) ---
    // This might happen if Daily view is selected for a day with 0 records within the month
    // or if monthlyDailySummaries is empty after processing.
    if (_chartSpots.isEmpty && !_isLoading && (_allUsageData.isNotEmpty || _monthlyDailySummaries.isNotEmpty)) {
      String dateString = _selectedTimePeriod == 'Daily' ? ' on ${DateFormat.yMd().format(_selectedDate)}' : '';
      String message = "No specific usage data available for '$_selectedUsageType' in the selected '$_selectedTimePeriod' view$dateString.";
      // For weekly view, provide a more specific message if the selected date is in a month with no data
      if (_selectedTimePeriod == 'Weekly') {
        message = "No usage data found for '$_selectedUsageType' in the 7-day period ending on ${DateFormat.yMd().format(_selectedDate)}. Please select a date within a month that has data.";
      } else if (_selectedTimePeriod == 'Monthly') {
        message = "No usage data found for '$_selectedUsageType' in ${DateFormat('MMMM').format(_selectedDate)}. Please select a different month.";
      }


      return Center(heightFactor: 5, child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.info_outline_rounded, color: Colors.grey, size: 40), const SizedBox(height: 10),
        Text(message, style: textTheme.titleMedium, textAlign: TextAlign.center),
      ]));
    }


    // --- Main Data Display ---
    final totalUsage = _displayTotalUsage;
    final estimatedCost = _displayEstimatedCost;
    // For weekly view, the date context is the 7-day range
    String dateContextString = "";
    if (_selectedTimePeriod == "Daily") {
      dateContextString = "Showing data for: ${DateFormat('EEE, MMM d, yyyy').format(_selectedDate)}";
    } else if (_selectedTimePeriod == "Weekly") {
      final DateTime endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final DateTime startDate = endDate.subtract(const Duration(days: 6));
      dateContextString = "Showing data for: ${DateFormat.yMd().format(startDate)} - ${DateFormat.yMd().format(endDate)}";
    } else if (_selectedTimePeriod == "Monthly") {
      dateContextString = "Showing data for: ${DateFormat('MMMM yyyy').format(_selectedDate)}";
    }


    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Display selected date/period context
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0, top: 8.0),
          child: Text(
              dateContextString,
              style: textTheme.titleSmall?.copyWith(color: theme.colorScheme.outline)),
        ),

        // Summary Box
        _buildUsageSummary(context, theme, textTheme, totalUsage, estimatedCost),
        const SizedBox(height: 24),

        // Chart Title
        Text(
            _selectedTimePeriod == "Weekly" ? "Estimated Daily Cost for the Week" : // Adjusted title for clarity
            _selectedTimePeriod == "Monthly" ? "Total Daily Estimated Cost by Day of Month" :
            "Estimated Hourly Cost Pattern",
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)
        ),
        Text( // Subtitle indicating context
            _selectedTimePeriod == "Weekly" ? "(Week ending ${DateFormat.yMd().format(_selectedDate)})" :
            _selectedTimePeriod == "Monthly" ? "(Based on data from ${DateFormat('MMMM yyyy').format(_selectedDate)})" : "",
            style: textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)
        ),
        const SizedBox(height: 8),


        // Chart
        _buildChart(context, theme, textTheme, _chartSpots),
        const SizedBox(height: 24),

        // Recommendations
        _buildRecommendations(context, theme, textTheme),
      ],
    );
  }

  // Builds the usage summary box
  Widget _buildUsageSummary(BuildContext context, ThemeData theme, TextTheme textTheme, double totalUsage, double estimatedCost) {
    final unit = _getUnit();
    // Adjust label based on view
    String usageLabel = _selectedTimePeriod == "Daily" ? "Total Usage" :
    _selectedTimePeriod == "Weekly" ? "Total Usage for Week" :
    "Avg. Daily Usage"; // Monthly view shows average daily
    String costLabel = _selectedTimePeriod == "Daily" ? "Est. Cost for Day" :
    _selectedTimePeriod == "Weekly" ? "Est. Cost for Week" :
    "Est. Cost (Avg. Day)"; // Monthly view shows average daily

    final displayType = _selectedUsageType.isNotEmpty ? _selectedUsageType[0].toUpperCase() + _selectedUsageType.substring(1) : '';
    final usageIcon = _selectedUsageType == 'electricity' ? Icons.flash_on_rounded : Icons.opacity_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0), // Adjusted padding
      decoration: BoxDecoration(
          gradient: LinearGradient( colors: [ theme.colorScheme.primaryContainer.withAlpha(153), theme.colorScheme.primaryContainer.withAlpha(77)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(12.0),
          boxShadow: [ BoxShadow( color: Colors.black.withAlpha(13), blurRadius: 8, offset: const Offset(0, 4)) ]
      ),
      child: Column( children: [
        // Usage Row
        _buildSummaryRow(context, theme, textTheme, icon: usageIcon, label: "$usageLabel ($displayType)", value: "${totalUsage.toStringAsFixed(2)} $unit", valueColor: theme.colorScheme.onPrimaryContainer),
        Divider(height: 16, thickness: 0.5, color: theme.colorScheme.outline.withAlpha(128)),
        _buildSummaryRow(context, theme, textTheme, icon: Icons.attach_money_rounded, label: costLabel, value: "${estimatedCost.toStringAsFixed(3)} BHD", valueColor: theme.colorScheme.error), // Use error color for cost
      ]),
    );
  }

  // Helper for summary row
  Widget _buildSummaryRow(BuildContext context, ThemeData theme, TextTheme textTheme, {required IconData icon, required String label, required String value, Color? valueColor}) {
    return Row( children: [
      Icon(icon, color: theme.colorScheme.primary, size: 22), const SizedBox(width: 12),
      Expanded(child: Text(label, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500))),
      Text(value, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: valueColor ?? theme.colorScheme.onSurface)),
    ]);
  }

  // Builds the line chart
  Widget _buildChart(BuildContext context, ThemeData theme, TextTheme textTheme, List<FlSpot> spots) {
    // Handle empty spots case gracefully
    if (spots.isEmpty) return const SizedBox(height: 300, child: Center(child: Text("No chart data available for this view.")));

    // --- Dynamic Axis Configuration ---
    double minXValue = 0, maxXValue = 24, bottomInterval = 4; // Defaults for Daily
    String Function(double) bottomTitleFormatter = (v) => v.toInt().toString().padLeft(2, '0'); // Default: Hour Label

    if (_selectedTimePeriod == "Weekly") {
      minXValue = 0; // Start index for the week
      maxXValue = 6; // End index for the week (7 days total)
      bottomInterval = 1; // Show a label for each day
      final DateTime endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final DateTime startDate = endDate.subtract(const Duration(days: 6));
      final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      bottomTitleFormatter = (v) {
        final dayIndex = v.toInt(); // Index 0-6
        if (dayIndex < 0 || dayIndex > 6) return '';
        // Calculate the actual date for this index and get the weekday
        final dateForSpot = startDate.add(Duration(days: dayIndex));
        return weekdays.elementAtOrNull(dateForSpot.weekday - 1) ?? '';
      };
    } else if (_selectedTimePeriod == "Monthly") {
      minXValue = 1;
      maxXValue = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day.toDouble(); // Max X is days in month
      bottomInterval = 7; // Show labels every 7 days (approximately)
      bottomTitleFormatter = (v) {
        final day = v.toInt();
        if (day < 1 || day > maxXValue) return '';
        return day.toString();
      };
    }

    // --- Calculate Y axis range and interval (based on COST now) ---
    double minYValue = 0.0; // Start at 0, cost cannot be negative
    double maxYValue = 0.1; // Default max Y (a small cost value)
    if (spots.isNotEmpty) {
      // Find the actual maximum Y value (estimated cost) in the data
      maxYValue = spots.map((e) => e.y).fold(0.0, max);
      // Add some padding (e.g., 15%) to the max value for better visualization, ensure minimum padding
      double padding = max(maxYValue * 0.15, 0.01); // Ensure at least a small padding for cost
      maxYValue += padding;
    }
    // Ensure maxY is reasonably larger than minY if data is flat near zero
    if (maxYValue - minYValue < 0.05) { // If range is very small
      maxYValue = minYValue + 0.1; // Ensure a minimum range
    }


    // Calculate interval to aim for approximately 5 labels
    // We want 4 intervals to get 5 labels (min, max, and 3 in between)
    double targetInterval = (maxYValue - minYValue) / 4.0;

    // Find a 'nice' interval close to the target
    // This is a simplified approach; a more robust one would involve logarithms
    List<double> niceIntervals = [0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0]; // Added larger intervals
    double bestInterval = niceIntervals.first;
    double minDiff = (targetInterval - bestInterval).abs();

    for (var interval in niceIntervals) {
      double diff = (targetInterval - interval).abs();
      if (diff < minDiff) {
        minDiff = diff;
        bestInterval = interval;
      }
    }

    // Adjust min/max Y slightly to align with the chosen interval if necessary
    // Use a small tolerance for checking if a value is close to a multiple of the interval
    double tolerance = bestInterval * 0.01;

    // Adjust minYValue to be a multiple of bestInterval, rounded down
    minYValue = (minYValue / bestInterval).floor() * bestInterval;

    // Adjust maxYValue to be a multiple of bestInterval, rounded up
    maxYValue = (maxYValue / bestInterval).ceil() * bestInterval;

    // Ensure there's enough range for at least 4 intervals (5 labels)
    if (maxYValue - minYValue < bestInterval * 4) {
      maxYValue = minYValue + bestInterval * 4;
    }
    // Ensure minYValue is not negative
    minYValue = max(0.0, minYValue);

    // Generate exactly 5 label values
    List<double> yLabelValues = [];
    double step = (maxYValue - minYValue) / 4.0; // 4 intervals for 5 labels
    for (int i = 0; i < 5; i++) {
      yLabelValues.add(minYValue + i * step);
    }
    // Ensure the last label is exactly maxYValue
    if (yLabelValues.isNotEmpty) {
      yLabelValues[4] = maxYValue;
    }


    // Determine line color based on usage type
    Color lineColor = _selectedUsageType == 'electricity' ? Colors.orange.shade700 : Colors.blue.shade600;
    List<Color> gradientColors = [lineColor.withAlpha(204), lineColor]; // Gradient for the line

    // Define alpha value for grid lines
    int gridLineAlpha = 30; // Adjusted alpha for grid lines

    return Container(
      // Adjusted padding for better spacing on all sides
      padding: const EdgeInsets.only(top: 16, bottom: 16, left: 8, right: 16),
      height: 350, // Fixed height for the chart area
      child: LineChart(
        LineChartData(
          clipData: const FlClipData(top: false, bottom: true, left: false, right: false), // Clip only bottom
          backgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(51), // Subtle background
          // --- Grid ---
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true, // Show vertical grid lines
            verticalInterval: bottomInterval, // Match vertical lines to bottom titles
            horizontalInterval: bestInterval, // Use the calculated 'nice' interval for grid lines
            // Use alpha for divider color
            getDrawingHorizontalLine: (value) => FlLine(color: theme.dividerColor.withAlpha(gridLineAlpha), strokeWidth: 1),
            getDrawingVerticalLine: (value) => FlLine(color: theme.dividerColor.withAlpha(gridLineAlpha), strokeWidth: 1),
          ),

          // --- Titles ---
          titlesData: FlTitlesData(
            show: true,
            // Bottom Titles (X-axis: Time/Day)
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, interval: bottomInterval, getTitlesWidget: (value, meta) {
              // Prevent drawing titles outside the min/max range
              if (value < minXValue || value > maxXValue) return const SizedBox.shrink();
              // For weekly/monthly, ensure integer values for labels
              if (_selectedTimePeriod != "Daily" && value != value.toInt().toDouble()) {
                return const SizedBox.shrink();
              }
              // Pass the meta object to the SideTitleWidget
              return SideTitleWidget(meta: meta, space: 8.0, child: Text(bottomTitleFormatter(value), style: textTheme.bodySmall));
            })),
            // Left Titles (Y-axis: Estimated Cost in BHD)
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 55, // Increased reserved size for BHD labels
              getTitlesWidget: (value, meta) {
                // Only show labels at the pre-calculated yLabelValues positions
                double tolerance = bestInterval * 0.01; // Use bestInterval for tolerance here too
                bool isLabelValue = yLabelValues.any((labelValue) => (value - labelValue).abs() < tolerance);

                if (isLabelValue)
                {
                  String labelText = value.toStringAsFixed(3);
                  // Only add BHD to the minimum and maximum value labels for clarity
                  if ((value - minYValue).abs() < tolerance || (value - maxYValue).abs() < tolerance) {
                    labelText += ' BHD';
                  }
                  // Pass the meta object to the SideTitleWidget
                  return SideTitleWidget(meta: meta, space: 8.0, child: Text(labelText, style: textTheme.bodySmall));
                }
                return const SizedBox.shrink(); // Hide other labels

              },
              // Set interval for rendering based on the generated labels (approximate)
              interval: step, // Use the step calculated for labels for rendering interval
            )),
            // Hide Top and Right Titles
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),

          // --- Border ---
          // Use alpha for border color
          borderData: FlBorderData(show: true, border: Border.all(color: theme.dividerColor.withAlpha(51))),

          // --- Axis Limits ---
          minX: minXValue, maxX: maxXValue, minY: minYValue, maxY: maxYValue,

          // --- Line Data ---
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true, // Smooth curve
              gradient: LinearGradient(colors: gradientColors),
              barWidth: 4, // Line thickness
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false), // Hide dots on the line
              belowBarData: BarAreaData( // Add gradient below the line
                  show: true,
                  // Use alpha for gradient colors
                  gradient: LinearGradient(
                      colors: gradientColors.map((color) => color.withAlpha((255 * 0.3).round())).toList(), // Calculate alpha from opacity
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter
                  )
              ),
            )
          ],

          // --- Touch Interaction ---
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true, // Enable tap/hover
            touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (touchedSpot) => theme.colorScheme.secondary, // Use secondary color for tooltip background
                tooltipBorderRadius: BorderRadius.circular(8),
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    String title = ''; // Tooltip title (time/day)
                    String valueText = ''; // Tooltip value text
                    String additionalInfo = ''; // For showing raw usage in weekly/monthly view

                    // The spot.y value now directly represents the estimated cost for the relevant period
                    final estimatedCost = spot.y;

                    if (_selectedTimePeriod == "Daily") {
                      final hr = spot.x.floor();
                      final min = ((spot.x - hr) * 60).round().clamp(0, 59);
                      title = '${hr.toString().padLeft(2,'0')}:${min.toString().padLeft(2,'0')}';
                      valueText = '${estimatedCost.toStringAsFixed(3)} BHD/hr'; // Show estimated cost per hour

                    } else if (_selectedTimePeriod == "Weekly") {
                      // Find the corresponding DailySummary for this spot's index (0-6)
                      final DateTime endDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
                      final DateTime startDate = endDate.subtract(const Duration(days: 6));
                      final dateForSpot = startDate.add(Duration(days: spot.x.toInt()));

                      final dailySummary = _monthlyDailySummaries.firstWhere(
                              (summary) => summary.date.year == dateForSpot.year && summary.date.month == dateForSpot.month && summary.date.day == dateForSpot.day,
                          orElse: () => DailySummary(date: dateForSpot, totalUsage: 0.0, estimatedCost: estimatedCost) // Default if not found
                      );

                      final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                      final dayOfWeek = dailySummary.date.weekday;
                      title = DateFormat.yMd().format(dailySummary.date) + ' (${weekdays.elementAtOrNull(dayOfWeek - 1) ?? ''})'; // Show date and weekday

                      valueText = '${estimatedCost.toStringAsFixed(3)} BHD/day'; // Show estimated cost per day
                      // Display the daily total usage for the specific day
                      additionalInfo = 'Usage: ${dailySummary.totalUsage.toStringAsFixed(2)} ${_getUnit()}/day';


                    } else if (_selectedTimePeriod == "Monthly") {
                      final dayOfMonth = spot.x.toInt();
                      // Find the corresponding DailySummary to get the raw usage
                      final dailySummary = _monthlyDailySummaries.firstWhere(
                              (summary) => summary.date.day == dayOfMonth,
                          orElse: () => DailySummary(date: DateTime(_selectedDate.year, _selectedDate.month, dayOfMonth), totalUsage: 0.0, estimatedCost: estimatedCost) // Default if not found
                      );

                      title = 'Day ${dayOfMonth}';


                      valueText = '${estimatedCost.toStringAsFixed(3)} BHD/day'; // Show estimated cost per day
                      // Display the daily total usage for the specific day
                      additionalInfo = 'Usage: ${dailySummary.totalUsage.toStringAsFixed(2)} ${_getUnit()}/day';

                    }

                    // Tooltip content (Value + Title)
                    return LineTooltipItem(
                        '$valueText\n', // Value text (estimated cost)
                        textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSecondary, fontWeight: FontWeight.bold),
                        children: [
                          if (additionalInfo.isNotEmpty) TextSpan(text: '$additionalInfo\n', style: textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSecondary.withAlpha(204))),
                          TextSpan(text: title, style: textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSecondary.withAlpha(204))) // Time/Day
                        ]
                    );
                  }).toList();
                }
            ),
          ),
        ),
        duration: const Duration(milliseconds: 250), // Animate changes
      ),
    );
  }

  // Builds the dynamic recommendations section
  Widget _buildRecommendations(BuildContext context, ThemeData theme, TextTheme textTheme) {
    final List<Map<String, dynamic>> recommendations = _recommendations;

    if (recommendations.isEmpty) return const SizedBox.shrink(); // Don't show if empty

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Recommendations",
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        // Use ListView.builder for potentially longer lists
        ListView.builder(
          shrinkWrap: true, // Important inside another ListView
          physics: const NeverScrollableScrollPhysics(), // Disable scrolling within outer ListView
          itemCount: recommendations.length,
          itemBuilder: (context, index) {
            final rec = recommendations[index];
            final iconData = rec['icon'] as IconData?;
            final text = rec['text'] as String? ?? '';
            // Use Card for better visual separation
            return Card(
              elevation: 1,
              margin: const EdgeInsets.symmetric(vertical: 4.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              color: theme.colorScheme.surfaceContainerLow, // Use a subtle card color
              child: ListTile(
                leading: iconData != null ? Icon(iconData, color: theme.colorScheme.primary, size: 28) : null,
                title: Text(text, style: textTheme.bodyMedium),
              ),
            );
          },
        ),
      ],
    );
  }

  // --- Helper Methods ---

  // Method to show the date picker
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020), // Allow selecting dates back to 2020
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)), // Allow future dates
    );
    // Check if the widget is still mounted before updating state
    if (mounted && picked != null && picked != _selectedDate) {
      // Check if the month or year changed to trigger a reload
      bool monthChanged = picked.month != _selectedDate.month || picked.year != _selectedDate.year;
      setState(() {
        _selectedDate = picked; // Update the selected date regardless
      });
      if (monthChanged) {
        // If the month changed, reload data for the new month
        _loadDataForSelectedMonth();
      } else {
        // If only the day changed (within the same month), just re-process
        _processDataForView();
      }
    }
  }

} // End of _UsageAnalysisScreenState