import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'dart:async'; // For simulating delay
import 'dart:math'; // For random usage simulation

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

  Bill({
    required this.id,
    required this.billDate,
    required this.amount,
    required this.status,
    this.dueDate,
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

  // --- Simulate Data Fetching & Calculation ---
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

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    try {
      // --- Simulate fetching past bills ---
      final fetchedPastBills = [
        Bill(id: 'b3', billDate: DateTime(2025, 4, 30), amount: 28.550, status: BillStatus.paid, dueDate: DateTime(2025, 5, 15)),
        Bill(id: 'b2', billDate: DateTime(2025, 3, 31), amount: 25.100, status: BillStatus.paid, dueDate: DateTime(2025, 4, 15)),
        Bill(id: 'b1', billDate: DateTime(2025, 2, 28), amount: 22.800, status: BillStatus.paid, dueDate: DateTime(2025, 3, 15)),
      ];

      // --- Simulate calculating projected current bill ---
      // In a real app:
      // 1. Find the date of the last bill (e.g., April 30th from fetchedPastBills).
      // 2. Fetch usage data from that date until today (May 4th).
      // 3. Apply tariff calculations (like in UsageAnalysisScreen) to the fetched usage.
      // 4. Estimate the due date (e.g., 15th of next month).

      // Simulation for May 1st - May 4th (today)
      final random = Random();
      double simulatedUsageSoFar = 0;
      // Simulate usage for ~4 days (adjust as needed)
      for (int i = 0; i < 4 * 24; i++) {
        // Use realistic hourly ranges (example)
        if (i % 24 < 6) simulatedUsageSoFar += 0.5 + random.nextDouble() * 1.5; // Night
        else if (i % 24 < 18) simulatedUsageSoFar += 1.5 + random.nextDouble() * 4.5; // Day
        else simulatedUsageSoFar += 2.0 + random.nextDouble() * 6.0; // Evening
      }
      // Apply a simplified cost calculation (example: 0.012 BHD per kWh)
      double projectedAmount = simulatedUsageSoFar * 0.012;
      DateTime estimatedDueDate = DateTime(2025, 6, 15); // Estimated due date for May bill

      final projectedBill = Bill(
        id: 'current_proj',
        billDate: DateTime.now(), // Represents "up to today"
        amount: projectedAmount,
        status: BillStatus.due, // Assuming it's not paid yet
        dueDate: estimatedDueDate,
      );
      // --- End Simulation ---


      if (mounted) {
        setState(() {
          _pastBills = fetchedPastBills;
          _currentProjectedBill = projectedBill;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      print("Error fetching bill data: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Could not load bill data. Please try again.";
        });
      }
    }
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
        backgroundColor: colorScheme.surface, // Use surface color for AppBar
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
                "Based on usage up to ${DateFormat.yMMMd().format(DateTime.now())}",
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
              DateFormat('MMMM yyyy').format(bill.billDate), // Format as Month Year
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              "${bill.amount.toStringAsFixed(3)} BHD",
              style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            trailing: _buildStatusChip(bill.status, colorScheme),
            onTap: () {
              // TODO: Implement navigation to a detailed bill view or PDF download
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Tapped on ${DateFormat('MMMM yyyy').format(bill.billDate)} bill')),
              );
            },
          ),
        );
      },
    );
  }
}
