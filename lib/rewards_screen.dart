import 'package:flutter/material.dart';
import 'dart:async'; // For simulating delay
import 'package:intl/intl.dart'; // Import for NumberFormat

// --- Data Model for Rewards ---
class Reward {
  final String id;
  final String title;
  final String description;
  final int pointsCost;
  final IconData icon; // Using IconData for simplicity, could be Image URL

  Reward({
    required this.id,
    required this.title,
    required this.description,
    required this.pointsCost,
    required this.icon,
  });
}

// --- Rewards Screen Widget ---
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  // --- State Variables ---
  int _userPoints = 0; // Start with 0, will be "loaded"
  List<Reward> _availableRewards = [];
  bool _isLoading = true;
  String? _errorMessage;

  // --- Simulate Data Fetching ---
  @override
  void initState() {
    super.initState();
    _fetchRewardsData();
  }

  Future<void> _fetchRewardsData() async {
    // Reset loading state if already loaded (for pull-to-refresh)
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));

    // In a real app, fetch user points and rewards list from Firestore/backend
    try {
      // --- Dummy Data ---
      const fetchedPoints = 1150; // Example points
      final fetchedRewards = [
        Reward(id: 'r1', title: '10% Off Next Bill', description: 'Apply a discount to your upcoming electricity bill.', pointsCost: 1000, icon: Icons.receipt_long_rounded),
        Reward(id: 'r2', title: 'Smart LED Bulb', description: 'Receive a free energy-efficient smart LED bulb.', pointsCost: 1500, icon: Icons.lightbulb_outline_rounded),
        Reward(id: 'r3', title: 'Smart Thermostat Discount', description: 'Get 5 BHD off a smart thermostat purchase.', pointsCost: 2500, icon: Icons.thermostat_rounded),
        Reward(id: 'r4', title: 'Plant a Tree', description: 'We\'ll plant a tree in your name to help the environment.', pointsCost: 500, icon: Icons.park_rounded),
        Reward(id: 'r5', title: '5% Off Next Bill', description: 'A smaller discount for fewer points.', pointsCost: 550, icon: Icons.receipt_rounded),

      ];
      // --- End Dummy Data ---

      if (mounted) {
        setState(() {
          _userPoints = fetchedPoints;
          _availableRewards = fetchedRewards;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      print("Error fetching rewards: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Could not load rewards. Please try again.";
        });
      }
    }
  }

  // --- Redemption Logic (Placeholder) ---
  void _redeemReward(Reward reward) {
    if (_userPoints >= reward.pointsCost) {
      // --- Confirmation Dialog ---
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
            title: Text('Confirm Redemption', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            content: Text('Redeem "${reward.title}" for ${reward.pointsCost} points?'),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(dialogContext).pop(); // Close the dialog
                },
              ),
              FilledButton.icon( // Use FilledButton for primary action
                icon: const Icon(Icons.redeem),
                label: const Text('Redeem'),
                onPressed: () {
                  Navigator.of(dialogContext).pop(); // Close the dialog
                  // --- Actual Redemption (Simulated) ---
                  if (mounted) {
                    setState(() {
                      _userPoints -= reward.pointsCost; // Deduct points
                    });
                    // Show success message
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('"${reward.title}" redeemed successfully!'),
                        backgroundColor: Colors.green[700],
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                      ),
                    );
                    // In a real app: Update points in Firestore/backend,
                    // potentially add redeemed reward to user's history, etc.
                  }
                },
              ),
            ],
          );
        },
      );
    } else {
      // --- Insufficient Points Message ---
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Not enough points to redeem this reward.'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        ),
      );
    }
  }


  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return Scaffold(
      // FIX: Add a standard AppBar for the fixed title
      appBar: AppBar(
        title: const Text('Rewards'),
        backgroundColor: colorScheme.surfaceContainerLowest, // Match background start
        elevation: 0, // No shadow for seamless look
      ),
      // Use a gradient background for visual appeal
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colorScheme.surfaceContainerLowest, colorScheme.surfaceContainerLow],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _fetchRewardsData, // Allow pull-to-refresh
          child: CustomScrollView( // Use CustomScrollView for flexible layout
            slivers: [
              // FIX: Remove title from SliverAppBar, make it transparent
              SliverAppBar(
                // title: const Text('Rewards'), // Title moved to Scaffold's AppBar
                backgroundColor: Colors.transparent, // Make AppBar transparent
                elevation: 0,
                // pinned: true, // No longer needed as header scrolls freely
                automaticallyImplyLeading: false, // Don't show back button here
                expandedHeight: 160.0, // Adjusted height for the points section
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildPointsHeader(context, theme, textTheme, colorScheme),
                ),
              ),
              // Show loading indicator or error message
              if (_isLoading)
                const SliverFillRemaining( // Use SliverFillRemaining to center content
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 40),
                          const SizedBox(height: 10),
                          Text(_errorMessage!, style: textTheme.titleMedium?.copyWith(color: colorScheme.error), textAlign: TextAlign.center),
                          const SizedBox(height: 10), ElevatedButton(onPressed: _fetchRewardsData, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_availableRewards.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Text("No rewards available right now.", style: textTheme.titleMedium),
                    ),
                  )
                // Build the rewards list
                else
                  _buildRewardsList(context, theme, textTheme, colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper Widgets ---

  // Header displaying user points
  Widget _buildPointsHeader(BuildContext context, ThemeData theme, TextTheme textTheme, ColorScheme colorScheme) {
    // Calculate alpha values from opacity
    int textAlpha = (255 * 0.8).round();

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primaryContainer, colorScheme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        // Keep rounded corners if desired, or remove for full width under fixed AppBar
        // borderRadius: const BorderRadius.only(
        //     bottomLeft: Radius.circular(30),
        //     bottomRight: Radius.circular(30)
        // )
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // FIX: Removed SizedBox(height: kToolbarHeight / 2) as it's not needed with fixed AppBar
          Text(
            "Your Points Balance",
            // FIX: Use withAlpha instead of withOpacity
            style: textTheme.titleMedium?.copyWith(color: colorScheme.onPrimary.withAlpha(textAlpha)),
          ),
          const SizedBox(height: 8),
          // AnimatedSwitcher can be added later for point changes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.star_rounded, color: Colors.yellow.shade600, size: 40),
              const SizedBox(width: 10),
              Text(
                // Use NumberFormat (requires intl package import)
                NumberFormat.compact().format(_userPoints),
                style: textTheme.displayMedium?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Keep saving energy to earn more!",
            // FIX: Use withAlpha instead of withOpacity
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onPrimary.withAlpha(textAlpha)),
          ),
        ],
      ),
    );
  }

  // Builds the list of reward cards
  Widget _buildRewardsList(BuildContext context, ThemeData theme, TextTheme textTheme, ColorScheme colorScheme) {
    // Calculate alpha values from opacity
    int disabledBgAlpha = (255 * 0.12).round();
    int disabledFgAlpha = (255 * 0.38).round();

    return SliverPadding(
      padding: const EdgeInsets.all(16.0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
              (context, index) {
            final reward = _availableRewards[index];
            final bool canRedeem = _userPoints >= reward.pointsCost;

            return Card(
              elevation: 3,
              margin: const EdgeInsets.only(bottom: 16.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
              color: colorScheme.surfaceContainer, // Use a card background color
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon
                    Icon(reward.icon, size: 40.0, color: colorScheme.primary),
                    const SizedBox(width: 16.0),
                    // Title, Description, Cost
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reward.title,
                            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                          ),
                          const SizedBox(height: 4.0),
                          Text(
                            reward.description,
                            style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12.0),
                          Row(
                            children: [
                              Icon(Icons.star_border_rounded, size: 18, color: Colors.amber.shade700),
                              const SizedBox(width: 4),
                              Text(
                                '${reward.pointsCost} Points',
                                style: textTheme.titleMedium?.copyWith(
                                    color: Colors.amber.shade800,
                                    fontWeight: FontWeight.bold
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16.0),
                    // Redeem Button
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center, // Center button vertically
                      children: [
                        const SizedBox(height: 4), // Align button better
                        ElevatedButton(
                          onPressed: canRedeem ? () => _redeemReward(reward) : null, // Disable if not enough points
                          style: ElevatedButton.styleFrom(
                            // FIX: Use withAlpha instead of withOpacity
                            backgroundColor: canRedeem ? colorScheme.primary : colorScheme.onSurface.withAlpha(disabledBgAlpha),
                            foregroundColor: canRedeem ? colorScheme.onPrimary : colorScheme.onSurface.withAlpha(disabledFgAlpha),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                          ),
                          child: const Text('Redeem'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: _availableRewards.length,
        ),
      ),
    );
  }
}
