import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math'; // Import for min/max functions

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
  List<FlSpot> _chartSpots = []; // Processed data points for the chart
  double _displayTotalUsage = 0.0; // Total/Average usage for the current view
  double _displayEstimatedCost = 0.0; // Estimated cost for the current view
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
    });

    try {
      // Calculate the start and end of the month based on _selectedDate
      final int year = _selectedDate.year;
      final int month = _selectedDate.month;
      final DateTime firstDayOfMonth = DateTime(year, month, 1);
      // End date is the first moment of the *next* month
      final DateTime firstDayOfNextMonth = (month == 12)
          ? DateTime(year + 1, 1, 1) // Handle December -> January transition
          : DateTime(year, month + 1, 1);

      print("Fetching data for month: ${DateFormat('MMMM yyyy').format(_selectedDate)}");
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
          _isLoading = false;
          _processDataForView(); // Process the newly loaded data
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
          _processDataForView(); // Clear dependent state
        });
      }
    }
  }

  // Processes the loaded _allUsageData based on the selected view (_selectedTimePeriod)
  void _processDataForView() {
    if (!mounted) return;

    List<FlSpot> spots = [];
    double totalForPeriod = 0;

    // Use the already loaded data for the selected month (_allUsageData)
    // No need to filter by type again, as _loadDataForSelectedMonth already did it.
    if (_allUsageData.isEmpty) {
      print("No data available in _allUsageData for processing.");
      setState(() { _chartSpots = []; _displayTotalUsage = 0; _displayEstimatedCost = 0; _recommendations = []; });
      return;
    }

    // --- DAILY VIEW ---
    // Shows hourly data points for the specific _selectedDate
    if (_selectedTimePeriod == "Daily") {
      final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 0, 0, 0);
      final endOfDay = startOfDay.add(const Duration(days: 1)); // Up to the start of the next day

      // Filter the month's data for the selected day
      List<UsageData> dailyData = _allUsageData.where((data) =>
      !data.time.isBefore(startOfDay) && data.time.isBefore(endOfDay)
      ).toList();

      // Sort data by time (already sorted from Firestore, but good practice)
      dailyData.sort((a, b) => a.time.compareTo(b.time));

      spots = dailyData.map((data) {
        // X value represents the hour of the day (0.0 to 23.99...)
        double hourFraction = data.time.hour + (data.time.minute / 60.0) + (data.time.second / 3600.0);
        return FlSpot(hourFraction, data.value);
      }).toList();

      totalForPeriod = dailyData.fold(0.0, (sum, item) => sum + item.value);

      print("Daily View Processed: Date=$startOfDay, Spots=${spots.length}, Total=$totalForPeriod");

      // --- WEEKLY VIEW ---
      // Shows the AVERAGE *hourly* usage for each day of the week (Mon-Sun)
      // calculated using data from the ENTIRE loaded month (_allUsageData).
    } else if (_selectedTimePeriod == "Weekly") {
      // Map: Weekday (1=Mon, 7=Sun) -> List of usage values for that weekday within the loaded month
      Map<int, List<double>> valuesPerWeekday = {};
      for (var data in _allUsageData) {
        valuesPerWeekday.putIfAbsent(data.time.weekday, () => []).add(data.value);
      }

      List<MapEntry<int, double>> dailyAverages = [];
      double sumOfAverages = 0;
      int daysWithDataCount = 0;

      for (int i = 1; i <= 7; i++) { // Iterate Mon (1) to Sun (7)
        double dayAverage = 0;
        if (valuesPerWeekday.containsKey(i) && valuesPerWeekday[i]!.isNotEmpty) {
          double sum = valuesPerWeekday[i]!.fold(0.0, (a, b) => a + b);
          // Calculate the average hourly usage for this weekday
          dayAverage = sum / valuesPerWeekday[i]!.length;
          sumOfAverages += dayAverage;
          daysWithDataCount++;
        }
        // Add spot: X=weekday (1-7), Y=average *hourly* usage for that weekday
        dailyAverages.add(MapEntry(i, dayAverage));
      }

      dailyAverages.sort((a, b) => a.key.compareTo(b.key));
      spots = dailyAverages.map((entry) => FlSpot(entry.key.toDouble(), entry.value)).toList();

      // Average *hourly* usage across the week days that had data in the month
      totalForPeriod = (daysWithDataCount > 0) ? sumOfAverages / daysWithDataCount : 0.0;

      print("Weekly View Processed: Spots=${spots.length}, Avg Hourly Usage (for month)=$totalForPeriod");


      // --- MONTHLY VIEW ---
      // Shows the AVERAGE *hourly* usage for each day of the month (1-31)
      // calculated using data from the ENTIRE loaded month (_allUsageData).
    } else if (_selectedTimePeriod == "Monthly") {
      // Map: Day of Month (1-31) -> List of usage values for that day within the loaded month
      Map<int, List<double>> valuesPerDayOfMonth = {};
      for (var data in _allUsageData) {
        valuesPerDayOfMonth.putIfAbsent(data.time.day, () => []).add(data.value);
      }

      List<MapEntry<int, double>> dayAverages = [];
      double sumOfAverages = 0;
      int daysWithDataCount = 0;
      // Use the number of days in the actual month being displayed
      int daysInMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;

      for (int i = 1; i <= daysInMonth; i++) { // Iterate 1 to last day of the loaded month
        double dayAverage = 0;
        if (valuesPerDayOfMonth.containsKey(i) && valuesPerDayOfMonth[i]!.isNotEmpty) {
          double sum = valuesPerDayOfMonth[i]!.fold(0.0, (a, b) => a + b);
          // Calculate the average hourly usage for this day of the month
          dayAverage = sum / valuesPerDayOfMonth[i]!.length;
          sumOfAverages += dayAverage;
          daysWithDataCount++;
        }
        // Add spot: X=day of month (1-daysInMonth), Y=average *hourly* usage for that day
        dayAverages.add(MapEntry(i, dayAverage));
      }

      dayAverages.sort((a, b) => a.key.compareTo(b.key));
      spots = dayAverages.map((entry) => FlSpot(entry.key.toDouble(), entry.value)).toList();

      // Average *hourly* usage across the month days that had data
      totalForPeriod = (daysWithDataCount > 0) ? sumOfAverages / daysWithDataCount : 0.0;

      print("Monthly View Processed: Spots=${spots.length}, Avg Hourly Usage (for month)=$totalForPeriod");
    }

    // Update state & Generate Recommendations
    if (mounted) {
      setState(() {
        _chartSpots = spots;
        // Adjust displayed total based on view type
        if (_selectedTimePeriod == "Daily") {
          _displayTotalUsage = totalForPeriod; // Sum for the specific day
        } else {
          // For Weekly/Monthly, display average *daily* usage for better context
          // Multiply average hourly usage by 24
          _displayTotalUsage = totalForPeriod * 24.0;
        }

        _displayEstimatedCost = _calculateEstimatedCostForPeriod(_displayTotalUsage);
        // Generate recommendations based on the processed data
        _recommendations = _generateRecommendations(spots, _displayTotalUsage); // Use display total for recs
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
    String monthYearStr = DateFormat('MMMM yyyy').format(_selectedDate); // Month context for recs

    if (_selectedTimePeriod == "Daily") {
      periodContext = "for ${DateFormat.yMd().format(_selectedDate)}";
    } else if (_selectedTimePeriod == "Weekly") {
      periodContext = "on average for weekdays in $monthYearStr";
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
      // Find the hour(s) with the highest usage
      double maxUsage = currentSpots.map((s) => s.y).fold(0.0, max);
      List<FlSpot> peakSpots = currentSpots.where((s) => s.y >= maxUsage * 0.8).toList(); // Find spots near the peak

      // Only recommend if peak is significantly higher than average hourly usage
      if (maxUsage > (currentAvgDailyTotal / 24 * 2)) { // If peak hourly usage is > 2x average hourly
        String peakTimesText = peakSpots.map((spot) {
          final hour = spot.x.floor();
          return '${hour.toString().padLeft(2,'0')}:00';
        }).toSet().join(', '); // Get unique hours

        recs.add({
          'icon': Icons.warning_amber_rounded,
          'text': 'Usage peaks significantly around $peakTimesText. Try to reduce consumption during these times.'
        });
      }
    }
    // Peak analysis for Weekly/Monthly averages might be less actionable for specific times
    // but could highlight peak days.
    else if (_selectedTimePeriod != "Daily" && currentSpots.isNotEmpty) {
      FlSpot peakSpot = currentSpots.reduce((curr, next) => curr.y > next.y ? curr : next);
      // Check if the peak average is significantly higher than the overall average
      if (peakSpot.y > (currentAvgDailyTotal / 24 * 1.5)) { // e.g., > 1.5x average hourly
        String peakDayText = '';
        if (_selectedTimePeriod == "Weekly") {
          final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
          peakDayText = weekdays.elementAtOrNull(peakSpot.x.toInt() - 1) ?? 'a specific day';
        } else if (_selectedTimePeriod == "Monthly") {
          peakDayText = 'around day ${peakSpot.x.toInt()}';
        }
        if (peakDayText.isNotEmpty) {
          recs.add({
            'icon': Icons.warning_amber_rounded,
            'text': 'Average usage tends to be highest $peakDayText in $monthYearStr.'
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
  // Assumes totalUsage is for a specific period (e.g., one day)
  // Note: Tier limits are often monthly, so daily cost is a rough estimate.
  double _calculateElectricityCost(double dailyKwh) {
    if (dailyKwh <= 0) return 0.0;
    // Estimate daily limits based on monthly limits (crude approximation)
    double dailyTier1Limit = _electricityTier1Limit / 30.0;
    double dailyTier2Limit = _electricityTier2Limit / 30.0;

    double cost = 0.0;
    if (dailyKwh <= dailyTier1Limit) {
      cost = dailyKwh * _electricityTier1Rate;
    } else if (dailyKwh <= dailyTier2Limit) {
      cost = (dailyTier1Limit * _electricityTier1Rate) +
          ((dailyKwh - dailyTier1Limit) * _electricityTier2Rate);
    } else {
      cost = (dailyTier1Limit * _electricityTier1Rate) +
          ((dailyTier2Limit - dailyTier1Limit) * _electricityTier2Rate) +
          ((dailyKwh - dailyTier2Limit) * _electricityTier3Rate);
    }
    return cost;
  }

  // Calculates the estimated water cost (simple flat rate example)
  double _calculateWaterCost(double dailyLiters) {
    if (dailyLiters <= 0) return 0.0;
    // Replace with actual tiered calculation if needed
    return dailyLiters * _waterRatePerLiter;
  }


  // Applies cost calculation to the period's displayed usage value
  double _calculateEstimatedCostForPeriod(double usageForPeriod) {
    if (_selectedUsageType == 'electricity') {
      return _calculateElectricityCost(usageForPeriod);
    } else if (_selectedUsageType == 'water') {
      return _calculateWaterCost(usageForPeriod);
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
      // Use a SafeArea to avoid overlaps with system UI
      body: SafeArea(
        child: RefreshIndicator(
          // Trigger loading data for the currently selected month on pull-to-refresh
          onRefresh: _loadDataForSelectedMonth,
          child: ListView( // Use ListView for scrollability
            padding: const EdgeInsets.all(16.0),
            children: [
              // Header
              Text("Usage Analysis", style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
              const SizedBox(height: 20),

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
        // FIX: Use recommended surface color and alpha for opacity
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
                // Always show date picker now as it defines the month context
                // if (_selectedTimePeriod == "Daily") ...[ // Remove this condition
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.calendar_month_rounded, color: theme.colorScheme.secondary),
                  tooltip: "Select Date / Month", // Updated tooltip
                  onPressed: _selectDate, // Call the date picker method
                )
                // ] // Remove this condition
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
      String monthYearStr = DateFormat('MMMM yyyy').format(_selectedDate);
      return Center(heightFactor: 5, child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.signal_cellular_nodata_rounded, color: Colors.grey, size: 40), const SizedBox(height: 10),
        Text("No usage data found for '$_selectedUsageType' in $monthYearStr.", style: textTheme.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 10), ElevatedButton(onPressed: _loadDataForSelectedMonth, child: const Text('Retry Fetch')),
      ]));
    }

    // --- No Data For Specific View State (but some data exists for the month) ---
    // This might happen if Daily view is selected for a day with 0 records within the month
    if (_chartSpots.isEmpty && !_isLoading && _allUsageData.isNotEmpty) {
      String dateString = _selectedTimePeriod == 'Daily' ? ' on ${DateFormat.yMd().format(_selectedDate)}' : '';
      String message = "No specific usage data available for '$_selectedUsageType' in the selected '$_selectedTimePeriod' view$dateString.";
      return Center(heightFactor: 5, child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.info_outline_rounded, color: Colors.grey, size: 40), const SizedBox(height: 10),
        Text(message, style: textTheme.titleMedium, textAlign: TextAlign.center),
      ]));
    }

    // --- Main Data Display ---
    final totalUsage = _displayTotalUsage;
    final estimatedCost = _displayEstimatedCost;
    String monthYearStr = DateFormat('MMMM yyyy').format(_selectedDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Display selected month context
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0, top: 8.0),
          child: Text(
              "Showing data for: $monthYearStr" +
                  (_selectedTimePeriod == "Daily" ? " (${DateFormat('EEE, MMM d').format(_selectedDate)})" : ""),
              style: textTheme.titleSmall?.copyWith(color: theme.colorScheme.outline)),
        ),

        // Summary Box
        _buildUsageSummary(context, theme, textTheme, totalUsage, estimatedCost),
        const SizedBox(height: 24),

        // Chart Title
        Text(
            _selectedTimePeriod == "Weekly" ? "Average Hourly Usage by Weekday" :
            _selectedTimePeriod == "Monthly" ? "Average Hourly Usage by Day of Month" :
            "Hourly Usage Pattern", // Daily view title
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)
        ),
        Text( // Subtitle indicating context
            _selectedTimePeriod != "Daily" ? "(Based on data from $monthYearStr)" : "",
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
    String usageLabel = _selectedTimePeriod == "Daily" ? "Total Usage" : "Avg. Daily Usage";
    String costLabel = _selectedTimePeriod == "Daily" ? "Est. Cost for Day" : "Est. Cost (Avg. Day)";

    final displayType = _selectedUsageType.isNotEmpty ? _selectedUsageType[0].toUpperCase() + _selectedUsageType.substring(1) : '';
    final usageIcon = _selectedUsageType == 'electricity' ? Icons.flash_on_rounded : Icons.opacity_rounded;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
          gradient: LinearGradient( colors: [ theme.colorScheme.primaryContainer.withAlpha(153), theme.colorScheme.primaryContainer.withAlpha(77)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(12.0),
          boxShadow: [ BoxShadow( color: Colors.black.withAlpha(13), blurRadius: 8, offset: const Offset(0, 4)) ]
      ),
      child: Column( children: [
        // Usage Row
        _buildSummaryRow(context, theme, textTheme, icon: usageIcon, label: "$usageLabel ($displayType)", value: "${totalUsage.toStringAsFixed(2)} $unit", valueColor: theme.colorScheme.onPrimaryContainer),
        // Conditionally show Cost Row (e.g., if cost is calculated)
        // Always show cost row, but value might be 0 if not applicable
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

    final unit = _getUnit();

    // --- Dynamic Axis Configuration ---
    double minXValue = 0, maxXValue = 24, bottomInterval = 4; // Defaults for Daily
    String Function(double) bottomTitleFormatter = (v) => v.toInt().toString().padLeft(2, '0'); // Default: Hour

    if (_selectedTimePeriod == "Weekly") {
      minXValue = 1; maxXValue = 7; bottomInterval = 1; // Mon=1, Sun=7
      final wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      bottomTitleFormatter = (v) => wd.elementAtOrNull(v.toInt() - 1) ?? '';
    } else if (_selectedTimePeriod == "Monthly") {
      minXValue = 1;
      // Adjust maxX based on the actual days in the month being viewed
      maxXValue = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day.toDouble();
      bottomInterval = 5; // Show labels every 5 days
      bottomTitleFormatter = (v) => v.toInt().toString(); // Day number
    }

    // --- Calculate Y axis range ---
    double minYValue = 0.0; // Start at 0, usage cannot be negative
    double maxYValue = 10.0; // Default max Y
    if (spots.isNotEmpty) {
      // Find the actual maximum Y value in the data
      maxYValue = spots.map((e) => e.y).fold(0.0, max);
      // Add some padding (e.g., 15%) to the max value for better visualization, ensure minimum padding
      double padding = max(maxYValue * 0.15, 2.0); // Ensure at least 2 units padding
      maxYValue += padding;
    }
    // Ensure maxY is reasonably larger than minY if data is flat near zero
    if (maxYValue <= minYValue + 1) { maxYValue = minYValue + 10;}


    // Determine line color based on usage type
    Color lineColor = _selectedUsageType == 'electricity' ? Colors.orange.shade700 : Colors.blue.shade600;
    List<Color> gradientColors = [lineColor.withAlpha(204), lineColor]; // Gradient for the line

    // FIX: Define alpha value for grid lines
    int gridLineAlpha = 30; // Adjusted alpha for grid lines

    return Container(
      padding: const EdgeInsets.only(top: 16, right: 8), // Add padding
      height: 350, // Fixed height for the chart area
      child: LineChart(
        LineChartData(
          // FIX: Move clipData here and use FlClipData() constructor
          clipData: FlClipData(top: false, bottom: true, left: false, right: false), // Clip only bottom
          backgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(51), // Subtle background
          // --- Grid ---
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true, // Show vertical grid lines
            verticalInterval: bottomInterval, // Match vertical lines to bottom titles
            horizontalInterval: (maxYValue > minYValue) ? ((maxYValue - minYValue) / 5).ceilToDouble().clamp(1.0, 1000.0) : 1, // Aim for ~5 horizontal lines
            // FIX: Use alpha for divider color
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
              if ((_selectedTimePeriod == "Weekly" || _selectedTimePeriod == "Monthly") && value != value.toInt().toDouble()) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(axisSide: meta.axisSide, space: 8.0, child: Text(bottomTitleFormatter(value), style: textTheme.bodySmall));
            })),
            // Left Titles (Y-axis: Usage Value)
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 45, // Increased reserved size
              getTitlesWidget: (value, meta) {
                // Only show labels at reasonable intervals if they fall on the calculated interval lines
                // Ensure meta.appliedInterval is positive before using modulo
                if (value == minYValue || value == maxYValue || (meta.appliedInterval > 0 && value % meta.appliedInterval == 0)) {
                  return SideTitleWidget(axisSide: meta.axisSide, space: 8.0, child: Text(value.toStringAsFixed(1), style: textTheme.bodySmall)); // Show 1 decimal place
                }
                return const SizedBox.shrink();
              },
              // Let the chart calculate a reasonable interval, but provide hints
              interval: (maxYValue > minYValue) ? ((maxYValue - minYValue) / 5).clamp(1.0, 1000.0) : 1, // Aim for ~5-6 intervals
            )),
            // Hide Top and Right Titles
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),

          // --- Border ---
          // FIX: Use alpha for border color
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
                  // FIX: Use alpha for gradient colors
                  gradient: LinearGradient(
                      colors: gradientColors.map((color) => color.withAlpha((255 * 0.3).round())).toList(), // Calculate alpha from opacity
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter
                  )
              ),
              // clipData removed from here
            )
          ],

          // --- Touch Interaction ---
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true, // Enable tap/hover
            touchTooltipData: LineTouchTooltipData(
                tooltipBgColor: theme.colorScheme.secondary, // Tooltip background
                tooltipRoundedRadius: 8,
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((spot) {
                    String title = ''; // Tooltip title (time/day)
                    if (_selectedTimePeriod == "Daily") { final hr = spot.x.floor(); final min = ((spot.x - hr) * 60).round().clamp(0, 59); title = '${hr.toString().padLeft(2,'0')}:${min.toString().padLeft(2,'0')}'; }
                    else if (_selectedTimePeriod == "Weekly") { final wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']; title = wd.elementAtOrNull(spot.x.toInt() - 1) ?? ''; }
                    else if (_selectedTimePeriod == "Monthly") { title = 'Day ${spot.x.toInt()}'; }

                    // Tooltip content (Value and Title)
                    return LineTooltipItem(
                        '${spot.y.toStringAsFixed(2)} $unit\n', // Value + Unit
                        textTheme.bodyMedium!.copyWith(color: theme.colorScheme.onSecondary, fontWeight: FontWeight.bold),
                        // FIX: Use alpha for tooltip text color
                        children: [TextSpan(text: title, style: textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSecondary.withAlpha(204)))] // Time/Day
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
          // separatorBuilder: (context, index) => const SizedBox(height: 4), // Not needed with Card margins
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
