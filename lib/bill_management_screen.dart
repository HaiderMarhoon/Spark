import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'dart:async'; // For simulating delay
import 'dart:math'; // For random usage simulation
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore
import 'home_screen.dart';
import 'auth_service.dart'; // Assuming this is for user authentication

// Import the new PaymentScreen (assuming it's in payment_screen.dart)
import './payment_screen.dart';


// --- Data Models ---
enum BillStatus { paid, due, overdue }

class Bill {
  final String id;
  final DateTime billDate; // Typically the end date of the billing period
  final double amount;
  final BillStatus status;
  final DateTime? dueDate; // Nullable if already paid or not applicable
  final double? electricityCost; // Added for breakdown
  final double? waterCost; // Added for breakdown

  Bill({
    required this.id,
    required this.billDate,
    required this.amount,
    required this.status,
    this.dueDate,
    this.electricityCost,
    this.waterCost,
  });
}

// --- Bill Management Screen Widget ---
class BillManagementScreen extends StatefulWidget {
  const BillManagementScreen({super.key});

  @override
  State<BillManagementScreen> createState() => _BillManagementScreenState();
}

class _BillManagementScreenState extends State<BillManagementScreen> {
  // --- State Variables ---
  Bill? _currentProjectedBill; // Holds the estimated current bill
  List<Bill> _pastBills = [];
  bool _isLoading = true;
  String? _errorMessage;

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


  // --- Data Fetching & Calculation ---
  @override
  void initState() {
    super.initState();
    _fetchBillData();
  }

  Future<void> _fetchBillData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Simulate fetching past bills (replace with actual Firestore fetch)
      // In a real app, you'd fetch past bills from Firestore, likely from a 'bills' collection
      // associated with the user.
      final fetchedPastBills = [
        Bill(id: 'b3', billDate: DateTime(2025, 4, 30), amount: 35.200, status: BillStatus.paid, dueDate: DateTime(2025, 5, 15), electricityCost: 28.550, waterCost: 6.650),
        Bill(id: 'b2', billDate: DateTime(2025, 3, 31), amount: 31.800, status: BillStatus.paid, dueDate: DateTime(2025, 4, 15), electricityCost: 25.100, waterCost: 6.700),
        Bill(id: 'b1', billDate: DateTime(2025, 2, 28), amount: 29.500, status: BillStatus.paid, dueDate: DateTime(2025, 3, 15), electricityCost: 22.800, waterCost: 6.700),
      ];

      // Determine the start date for fetching current usage data.
      // This should be the day after the latest past bill date.
      DateTime lastBillDate = fetchedPastBills.isNotEmpty
          ? fetchedPastBills.first.billDate
          : DateTime.now().subtract(const Duration(days: 30)); // Default to 30 days ago if no past bills

      final DateTime fetchStartDate = DateTime(lastBillDate.year, lastBillDate.month, lastBillDate.day).add(const Duration(days: 1));
      final DateTime fetchEndDate = DateTime.now(); // Up to the current day and hour

      print("Fetching usage data for current bill period: from ${DateFormat.yMd().format(fetchStartDate)} to ${DateFormat.yMd().format(fetchEndDate)}");

      // Fetch electricity usage data from Firestore
      final electricitySnapshot = await FirebaseFirestore.instance
          .collection("usage_data")
          .where("type", isEqualTo: "electricity")
          .where("time", isGreaterThanOrEqualTo: Timestamp.fromDate(fetchStartDate))
          .where("time", isLessThanOrEqualTo: Timestamp.fromDate(fetchEndDate)) // Include data up to the current time
          .orderBy("time", descending: false)
          .get();

      double totalElectricityUsage = 0.0;
      for (var doc in electricitySnapshot.docs) {
        final data = doc.data();
        final value = (data["value"] as num?)?.toDouble();
        if (value != null && value >= 0) {
          totalElectricityUsage += value;
        }
      }
      print("Fetched ${electricitySnapshot.docs.length} electricity records. Total usage: $totalElectricityUsage kWh");


      // Fetch water usage data from Firestore
      final waterSnapshot = await FirebaseFirestore.instance
          .collection("usage_data")
          .where("type", isEqualTo: "water")
          .where("time", isGreaterThanOrEqualTo: Timestamp.fromDate(fetchStartDate))
          .where("time", isLessThanOrEqualTo: Timestamp.fromDate(fetchEndDate)) // Include data up to the current time
          .orderBy("time", descending: false)
          .get();

      double totalWaterUsage = 0.0;
      for (var doc in waterSnapshot.docs) {
        final data = doc.data();
        final value = (data["value"] as num?)?.toDouble();
        if (value != null && value >= 0) {
          totalWaterUsage += value;
        }
      }
      print("Fetched ${waterSnapshot.docs.length} water records. Total usage: $totalWaterUsage L");


      // Calculate estimated costs
      double estimatedElectricityCost = _calculateElectricityCost(totalElectricityUsage);
      double estimatedWaterCost = _calculateWaterCost(totalWaterUsage);
      double totalProjectedAmount = estimatedElectricityCost + estimatedWaterCost;

      // Estimate the due date (e.g., 15th of the next month relative to the fetch end date)
      final DateTime now = DateTime.now();
      final DateTime estimatedDueDate = DateTime(now.year, now.month + 1, 15);


      final projectedBill = Bill(
        id: 'current_proj',
        billDate: now, // Represents "up to today"
        amount: totalProjectedAmount,
        status: BillStatus.due, // Assuming it's not paid yet
        dueDate: estimatedDueDate,
        electricityCost: estimatedElectricityCost,
        waterCost: estimatedWaterCost,
      );

      if (mounted) {
        setState(() {
          _pastBills = fetchedPastBills;
          _currentProjectedBill = projectedBill;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e, s) { // Catch specific exceptions if needed, log stack trace
      print("----------------------------------------");
      print("❌ Error fetching bill data: $e");
      print("Stack trace:\n$s");
      print("----------------------------------------");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Could not load bill data. Please try again.";
          _pastBills.clear();
          _currentProjectedBill = null;
        });
      }
    }
  }

  // Calculates the estimated electricity cost based on tiered rates
  // Assumes totalMonthlyUsage is the cumulative usage for the current billing cycle.
  double _calculateElectricityCost(double totalMonthlyUsage) {
    if (totalMonthlyUsage <= 0) return 0.0;

    double cost = 0.0;
    double remainingUsage = totalMonthlyUsage;

    // Apply Tier 1
    double tier1Usage = min(remainingUsage, _electricityTier1Limit);
    cost += tier1Usage * _electricityTier1Rate;
    remainingUsage -= tier1Usage;

    // Apply Tier 2
    if (remainingUsage > 0) {
      double tier2Usage = min(remainingUsage, _electricityTier2Limit - _electricityTier1Limit);
      cost += tier2Usage * _electricityTier2Rate;
      remainingUsage -= tier2Usage;
    }

    // Apply Tier 3
    if (remainingUsage > 0) {
      cost += remainingUsage * _electricityTier3Rate;
    }

    return cost;
  }

  // Calculates the estimated water cost (simple flat rate example - replace with tiered if applicable)
  double _calculateWaterCost(double totalMonthlyUsage) {
    if (totalMonthlyUsage <= 0) return 0.0;
    // Replace with actual tiered calculation if needed
    return totalMonthlyUsage * _waterRatePerLiter;
  }


  // --- Navigation ---
  void _navigateToPayment(double amount) {
    if (amount <= 0) return; // Don't navigate if amount is zero or less

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentScreen(amountDue: amount),
      ),
    );

  }


  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing'),
        backgroundColor: Colors.green, // Use surface color for AppBar
        elevation: 1, // Add slight elevation
      ),
      body: RefreshIndicator(
        onRefresh: _fetchBillData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? _buildErrorWidget(context, colorScheme, textTheme)
            : ListView( // Use ListView for overall scrolling
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildCurrentBillCard(context, theme, textTheme, colorScheme),
            const SizedBox(height: 24.0),
            Text("Payment History", style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12.0),
            _buildPastBillsList(context, theme, textTheme, colorScheme),
          ],
        ),
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildErrorWidget(BuildContext context, ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 40),
            const SizedBox(height: 10),
            Text(_errorMessage!, style: textTheme.titleMedium?.copyWith(color: colorScheme.error), textAlign: TextAlign.center),
            const SizedBox(height: 10), ElevatedButton(onPressed: _fetchBillData, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentBillCard(BuildContext context, ThemeData theme, TextTheme textTheme, ColorScheme colorScheme) {
    if (_currentProjectedBill == null) {
      // Show a placeholder or message if current bill isn't calculated yet
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
        child: const Padding(
          padding: EdgeInsets.all(20.0),
          child: Center(child: Text("Calculating current estimated bill...")),
        ),
      );
    }

    final bill = _currentProjectedBill!;
    final bool isPayable = bill.status == BillStatus.due || bill.status == BillStatus.overdue;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      color: colorScheme.surfaceContainerHighest, // Use a distinct background
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Current Estimated Bill", // Clarify it's an estimate
              style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  "${bill.amount.toStringAsFixed(3)} BHD", // Format amount
                  style: textTheme.displayMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                _buildStatusChip(bill.status, colorScheme),
              ],
            ),

            const SizedBox(height: 8.0),
            // Display breakdown if available
            if (bill.electricityCost != null || bill.waterCost != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (bill.electricityCost != null)
                      Text(
                        "Electricity: ${bill.electricityCost!.toStringAsFixed(3)} BHD",
                        style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    if (bill.waterCost != null)
                      Text(
                        "Water: ${bill.waterCost!.toStringAsFixed(3)} BHD",
                        style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12.0),

            if (bill.dueDate != null)
              Text(
                "Due Date: ${DateFormat.yMMMd().format(bill.dueDate!)}", // Format date
                style: textTheme.bodyMedium?.copyWith(color: bill.status == BillStatus.overdue ? colorScheme.error : colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: 20.0),
            Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.payment_rounded),
                label: const Text("Pay Now"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                  textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                ),
                // Disable button if not payable or amount is zero
                onPressed: isPayable && bill.amount > 0 ? () => _navigateToPayment(bill.amount) : null,
              ),
            ),
            const SizedBox(height: 8.0),
            Center(
              child: Text(
                "Based on usage up to ${DateFormat.yMMMd().add_jm().format(DateTime.now())}", // Show date and time
                style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
              ),
            )
          ],
        ),
      ),
    );
  }


  Widget _buildStatusChip(BillStatus status, ColorScheme colorScheme) {
    String text;
    Color bgColor;
    Color fgColor;
    IconData icon;

    switch (status) {
      case BillStatus.paid:
        text = "Paid";
        bgColor = Colors.green.shade100;
        fgColor = Colors.green.shade800;
        icon = Icons.check_circle_rounded;
        break;
      case BillStatus.due:
        text = "Due";
        bgColor = Colors.orange.shade100;
        fgColor = Colors.orange.shade800;
        icon = Icons.hourglass_empty_rounded;
        break;
      case BillStatus.overdue:
        text = "Overdue";
        bgColor = colorScheme.errorContainer;
        fgColor = colorScheme.onErrorContainer;
        icon = Icons.error_rounded;
        break;
    }

    return Chip(
      avatar: Icon(icon, color: fgColor, size: 18),
      label: Text(text),
      labelStyle: TextStyle(color: fgColor, fontWeight: FontWeight.bold),
      backgroundColor: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      visualDensity: VisualDensity.compact, // Make chip smaller
      side: BorderSide.none,
    );
  }

  Widget _buildPastBillsList(BuildContext context, ThemeData theme, TextTheme textTheme, ColorScheme colorScheme) {
    if (_pastBills.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20.0),
        child: Center(child: Text("No past bill history found.")),
      );
    }

    return ListView.builder(
      shrinkWrap: true, // Important inside another ListView
      physics: const NeverScrollableScrollPhysics(), // Disable nested scrolling
      itemCount: _pastBills.length,
      itemBuilder: (context, index) {
        final bill = _pastBills[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12.0),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
          child: ListTile(
            leading: Icon(Icons.receipt_long_rounded, color: colorScheme.secondary),
            title: Text(
              DateFormat('MMMM y').format(bill.billDate), // Format as Month Year
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Column( // Use a Column for multiple lines in subtitle
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${bill.amount.toStringAsFixed(3)} BHD",
                  style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                // Display breakdown in past bills list if available
                if (bill.electricityCost != null)
                  Text(
                    "Electricity: ${bill.electricityCost!.toStringAsFixed(3)} BHD",
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.8)),
                  ),
                if (bill.waterCost != null)
                  Text(
                    "Water: ${bill.waterCost!.toStringAsFixed(3)} BHD",
                    style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.8)),
                  ),
              ],
            ),
            trailing: _buildStatusChip(bill.status, colorScheme),
            onTap: () {
              // TODO: Implement navigation to a detailed bill view or PDF download
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Tapped on ${DateFormat('MMMM y').format(bill.billDate)} bill')),
              );
            },
          ),
        );
      },
    );
  }

}