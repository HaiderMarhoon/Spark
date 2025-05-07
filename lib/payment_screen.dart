import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For currency formatting

class PaymentScreen extends StatefulWidget {
  final double amountDue;

  const PaymentScreen({required this.amountDue, super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

// Simple class for payment methods
class PaymentMethodOption {
  final String name;
  final String logoAsset; // Path to local asset or use IconData
  final IconData? icon; // Use IconData as placeholder

  PaymentMethodOption({required this.name, this.logoAsset = '', this.icon});
}


class _PaymentScreenState extends State<PaymentScreen> {
  PaymentMethodOption? _selectedMethod;

  // Define payment methods (use Icons as placeholders for logos)
  final List<PaymentMethodOption> _paymentMethods = [
    PaymentMethodOption(name: 'BenefitPay', icon: Icons.phone_android_rounded), // Placeholder
    PaymentMethodOption(name: 'MasterCard', icon: Icons.credit_card_rounded), // Placeholder
    PaymentMethodOption(name: 'Visa', icon: Icons.credit_card), // Placeholder
    PaymentMethodOption(name: 'Apple Pay', icon: Icons.apple_rounded), // Placeholder
  ];

  void _processPayment() {
    if (_selectedMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a payment method.')),
      );
      return;
    }

    // --- Simulate Payment Processing ---
    showDialog(
      context: context,
      barrierDismissible: false, // User must tap button
      builder: (BuildContext dialogContext) {
        return const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("Processing Payment..."),
            ],
          ),
        );
      },
    );

    // Simulate delay
    Future.delayed(const Duration(seconds: 3), () {
      Navigator.of(context).pop(); // Close processing dialog

      // Show success dialog
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Payment Successful'),
            content: Text('Your payment of ${widget.amountDue.toStringAsFixed(3)} BHD via ${_selectedMethod!.name} was successful.'),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(dialogContext).pop(); // Close success dialog
                  Navigator.of(context).pop(); // Go back from PaymentScreen
                  // TODO: Update bill status in the backend/previous screen state
                },
              ),
            ],
          );
        },
      );
    });
    // --- End Simulation ---

    // In a real app:
    // 1. Integrate with the selected payment gateway SDK (BenefitPay, Stripe etc.)
    // 2. Handle success/failure callbacks from the gateway.
    // 3. Update bill status in Firestore/backend upon successful payment.
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    // Format currency
    final currencyFormat = NumberFormat.currency(locale: 'en_BH', symbol: 'BHD ', decimalDigits: 3);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Payment'),
        backgroundColor: colorScheme.surface,
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Amount Display Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
              color: colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 25.0),
                child: Center(
                  child: Column(
                    children: [
                      Text(
                        "Amount Due",
                        style: textTheme.titleMedium?.copyWith(color: colorScheme.onPrimaryContainer),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        currencyFormat.format(widget.amountDue),
                        style: textTheme.displayMedium?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30.0),

            // Payment Method Selection
            Text("Select Payment Method", style: textTheme.titleLarge),
            const SizedBox(height: 15.0),
            Expanded(
              child: ListView.builder(
                itemCount: _paymentMethods.length,
                itemBuilder: (context, index) {
                  final method = _paymentMethods[index];
                  final bool isSelected = _selectedMethod == method;

                  return Card(
                    elevation: isSelected ? 4 : 1, // Highlight selected
                    margin: const EdgeInsets.only(bottom: 10.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                      side: isSelected
                          ? BorderSide(color: colorScheme.primary, width: 2)
                          : BorderSide.none,
                    ),
                    child: ListTile(
                      leading: Icon(method.icon ?? Icons.payment, size: 30, color: colorScheme.secondary), // Use placeholder icon
                      title: Text(method.name, style: textTheme.titleMedium),
                      // Use a Radio button or Checkbox for selection indication
                      trailing: isSelected
                          ? Icon(Icons.check_circle, color: colorScheme.primary)
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedMethod = method;
                        });
                      },
                    ),
                  );
                },
              ),
            ),

            // Confirm Button
            const SizedBox(height: 20.0),
            SizedBox(
              width: double.infinity, // Make button full width
              child: ElevatedButton.icon(
                icon: const Icon(Icons.lock_outline_rounded),
                label: Text('Confirm Payment (${currencyFormat.format(widget.amountDue)})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                ),
                onPressed: _selectedMethod != null ? _processPayment : null, // Enable only if method selected
              ),
            ),
          ],
        ),
      ),
    );
  }
}
