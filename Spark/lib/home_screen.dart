import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // For date formatting and number formatting
import 'dart:math'; // For min function

import 'device_discovery.dart';
import 'device.dart';
import 'device_control_screen.dart';
import 'usage_analysis_screen.dart';
import 'bill_management_screen.dart'; // Still imported for navigation
import 'rewards_screen.dart';
import 'auth_service.dart';
import 'welcome_screen.dart'; // Ensure WelcomeScreen is imported
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  final String userEmail;

  const HomeScreen({
    super.key,
    required this.userId,
    required this.userEmail,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  late AuthService auth;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    auth = Provider.of<AuthService>(context, listen: false);
    _screens = [
      HomeContentScreen(key: UniqueKey(), authService: auth), // Pass authService
      const UsageAnalysisScreen(),
      const BillManagementScreen(),
      const RewardsScreen(),
    ];
  }

  void _onItemTapped(int index) {
    if (index < _screens.length) {
      setState(() {
        _selectedIndex = index;
      });
    } else {
      print("Error: _onItemTapped called with out-of-bounds index: $index");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectedIndex == 0
          ? AppBar(
        title: Text("${auth.userName ?? 'User'}'s Home"),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () => _showUserProfile(context, auth),
          ),
        ],
      )
          : null,
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  BottomNavigationBar _buildBottomNavBar() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      selectedItemColor: Colors.blue.shade800,
      unselectedItemColor: Colors.grey.shade600,
      onTap: _onItemTapped,
      backgroundColor: Colors.transparent,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
      showUnselectedLabels: false,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(
            icon: Icon(Icons.analytics), label: 'Analytics'),
        BottomNavigationBarItem(icon: Icon(Icons.receipt), label: 'Bills'),
        BottomNavigationBarItem(icon: Icon(Icons.star), label: 'Rewards'),
      ],
    );
  }

  void _showUserProfile(BuildContext context, AuthService auth) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(auth.userName ?? 'User Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Email: ${auth.userEmail ?? 'N/A'}"),
            const SizedBox(height: 8),
            Text("Name: ${auth.userName ?? 'N/A'}"),
            const SizedBox(height: 8),
            Text("ID: ${auth.userId ?? 'N/A'}"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
          if (auth.isLoggedIn)
            TextButton(
              onPressed: () async {
                await auth.signOut();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const WelcomeScreen()),
                      (Route<dynamic> route) => false,
                );
              },
              child: const Text("Logout"),
            ),
        ],
      ),
    );
  }
}

class HomeContentScreen extends StatefulWidget {
  final AuthService authService; // Receive AuthService
  const HomeContentScreen({Key? key, required this.authService})
      : super(key: key);

  @override
  State<HomeContentScreen> createState() => _HomeContentScreenState();
}

class _HomeContentScreenState extends State<HomeContentScreen> {
  final DeviceDiscovery _deviceDiscovery = DeviceDiscovery();
  StreamSubscription<Device>? _deviceStreamSubscription;

  List<Device> _devices = [];
  bool _isScanning = false;
  String _scanStatus = 'Not Started';
  String? _scanErrorMessage;
  bool _showScanningIndicator = false;

  final CollectionReference _devicesCollection =
  FirebaseFirestore.instance.collection('devices');

  final _deviceNameController = TextEditingController();
  final _roomNameController = TextEditingController();

  // --- State Variables for Bill Estimation ---
  double? _estimatedMonthlyBill;
  double? _currentAccumulatedBillMonth;
  int? _daysPassedInMonth;
  int? _totalDaysInMonth;
  bool _isLoadingBillEstimate = true;
  String? _billErrorEstimateMessage;
  DateTime? _billCalculationTime; // To store the exact calculation time

  // --- Tariff Configuration (Copied from BillManagementScreen for now) ---
  final double _electricityTier1Rate = 0.003; // BHD per kWh
  final double _electricityTier2Rate = 0.009; // BHD per kWh
  final double _electricityTier3Rate = 0.016; // BHD per kWh
  final double _electricityTier1Limit = 3000.0; // kWh (monthly assumed)
  final double _electricityTier2Limit = 5000.0; // kWh (monthly assumed)
  final double _waterRatePerLiter =
  0.0008; // Example: 0.8 fils per Liter (0.0008 BHD/L)
  // --- End Tariff Configuration ---

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _fetchAndEstimateMonthlyBill();
    print("HomeContentScreen: initState completed.");
  }

  Future<void> _loadInitialData() async {
    print("HomeContentScreen: Loading initial data...");
    if (mounted) {
      setState(() {
        _isScanning = false;
        _showScanningIndicator = false;
        _scanStatus = 'Not Started';
        _scanErrorMessage = null;
      });
    }
    await _fetchUserDevices();
    print("HomeContentScreen: Initial data loaded.");
  }

  // --- Bill Estimation Logic ---
  Future<void> _fetchAndEstimateMonthlyBill() async {
    if (!mounted) return;
    setState(() {
      _isLoadingBillEstimate = true;
      _billErrorEstimateMessage = null;
    });

    try {
      final now = DateTime.now(); // Capture current time for calculations
      _billCalculationTime = now; // Store the exact time of calculation

      final currentMonth = now.month;
      final currentYear = now.year;

      _daysPassedInMonth = now.day;
      _totalDaysInMonth = DateTime(currentYear, currentMonth + 1, 0).day;

      // Start of the current calendar month
      final DateTime cycleStartDate = DateTime(currentYear, currentMonth, 1);
      // End of today (for fetching up to current moment)
      // MODIFIED: Use 'now' directly to fetch up to the current time
      final DateTime cycleEndDate = now;

      // Fetch electricity usage
      final electricitySnapshot = await FirebaseFirestore.instance
          .collection("usage_data")
          .where("type", isEqualTo: "electricity")
          .where("time",
          isGreaterThanOrEqualTo: Timestamp.fromDate(cycleStartDate))
          .where("time",
          isLessThanOrEqualTo:
          Timestamp.fromDate(cycleEndDate)) // Fetch up to current time
      // .where('userId', isEqualTo: widget.authService.userId) // UNCOMMENT IF NEEDED
          .get();

      double totalElectricityUsageMonth = 0.0;
      for (var doc in electricitySnapshot.docs) {
        final data = doc.data();
        final value = (data["value"] as num?)?.toDouble();
        if (value != null && value >= 0) {
          totalElectricityUsageMonth += value;
        }
      }

      // Fetch water usage
      final waterSnapshot = await FirebaseFirestore.instance
          .collection("usage_data")
          .where("type", isEqualTo: "water")
          .where("time",
          isGreaterThanOrEqualTo: Timestamp.fromDate(cycleStartDate))
          .where("time",
          isLessThanOrEqualTo:
          Timestamp.fromDate(cycleEndDate)) // Fetch up to current time
      // .where('userId', isEqualTo: widget.authService.userId) // UNCOMMENT IF NEEDED
          .get();

      double totalWaterUsageMonth = 0.0;
      for (var doc in waterSnapshot.docs) {
        final data = doc.data();
        final value = (data["value"] as num?)?.toDouble();
        if (value != null && value >= 0) {
          totalWaterUsageMonth += value;
        }
      }

      double currentElectricityCost =
      _calculateElectricityCost(totalElectricityUsageMonth);
      double currentWaterCost = _calculateWaterCost(totalWaterUsageMonth);
      _currentAccumulatedBillMonth = currentElectricityCost + currentWaterCost;

      // Estimate for the whole month based on current accumulation and time passed
      if (_daysPassedInMonth! > 0 &&
          _totalDaysInMonth! > 0 &&
          _currentAccumulatedBillMonth! > 0) {
        // Calculate fraction of the day passed for more precise proration
        double fractionOfDayPassed = now.hour / 24.0 +
            now.minute / (24.0 * 60.0) +
            now.second / (24.0 * 60.0 * 60.0);
        double daysPassedWithFraction =
            (_daysPassedInMonth! - 1) + fractionOfDayPassed;

        if (daysPassedWithFraction > 0) {
          _estimatedMonthlyBill = (_currentAccumulatedBillMonth! /
              daysPassedWithFraction) *
              _totalDaysInMonth!;
        } else {
          _estimatedMonthlyBill =
          0.0; // Avoid division by zero if it's the very start of the month
        }
      } else {
        _estimatedMonthlyBill =
            _currentAccumulatedBillMonth; // If no days passed or no accumulation, estimate is current
      }

      if (mounted) {
        setState(() {
          _isLoadingBillEstimate = false;
        });
      }
    } catch (e, s) {
      print("----------------------------------------");
      print("❌ Error fetching/estimating bill data for home screen: $e");
      print("Stack trace:\n$s");
      print("----------------------------------------");
      if (mounted) {
        setState(() {
          _isLoadingBillEstimate = false;
          _billErrorEstimateMessage = "Could not load bill estimate.";
          _estimatedMonthlyBill = null;
          _currentAccumulatedBillMonth = null;
        });
      }
    }
  }

  double _calculateElectricityCost(double totalMonthlyUsage) {
    if (totalMonthlyUsage <= 0) return 0.0;
    double cost = 0.0;
    double remainingUsage = totalMonthlyUsage;

    double tier1Usage = min(remainingUsage, _electricityTier1Limit);
    cost += tier1Usage * _electricityTier1Rate;
    remainingUsage -= tier1Usage;

    if (remainingUsage > 0) {
      double tier2Usage =
      min(remainingUsage, _electricityTier2Limit - _electricityTier1Limit);
      cost += tier2Usage * _electricityTier2Rate;
      remainingUsage -= tier2Usage;
    }
    if (remainingUsage > 0) {
      cost += remainingUsage * _electricityTier3Rate;
    }
    return cost;
  }

  double _calculateWaterCost(double totalMonthlyUsage) {
    if (totalMonthlyUsage <= 0) return 0.0;
    return totalMonthlyUsage * _waterRatePerLiter;
  }
  // --- End Bill Estimation Logic ---

  Future<void> _fetchUserDevices() async {
    try {
      final userId = widget.authService.userId;
      if (userId == null) {
        print("HomeContentScreen: User ID is null, cannot fetch devices.");
        if (mounted) {
          setState(() {
            _devices = [];
            _scanErrorMessage = "Theres no saved devices.";
          });
        }
        return;
      }

      print("Fetching devices for user ID: $userId");
      final snapshot =
      await _devicesCollection.where('userId', isEqualTo: userId).get();

      final fetchedDevices = snapshot.docs.map((doc) {
        return Device.fromJson(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();

      print("Loaded ${fetchedDevices.length} devices from Firestore.");
      if (mounted) {
        setState(() {
          _devices = fetchedDevices;
          _scanErrorMessage = null;
        });
      }
    } catch (e, s) {
      print("----------------------------------------");
      print("Error fetching devices from Firestore: $e");
      print("Stack trace:\n$s");
      print("----------------------------------------");
      if (mounted) {
        setState(() {
          _scanErrorMessage = "Failed to load saved devices: ${e.toString()}";
          _devices = [];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Failed to load saved devices: ${e.toString()}")),
        );
      }
    }
  }

  Future<void> _saveDevices() async {
    try {
      final userId = widget.authService.userId;
      if (userId == null) {
        print("HomeContentScreen: User ID is null, cannot save devices.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("User not logged in. Cannot save devices.")),
          );
        }
        return;
      }

      print("Saving ${_devices.length} devices for user ID: $userId");

      final existingDevicesSnapshot =
      await _devicesCollection.where('userId', isEqualTo: userId).get();
      final existingDeviceIds =
      existingDevicesSnapshot.docs.map((doc) => doc.id).toSet();
      WriteBatch batch = FirebaseFirestore.instance.batch();

      for (final device in _devices) {
        final deviceDataWithUser = {...device.toJson(), 'userId': userId};
        if (device.id != null && existingDeviceIds.contains(device.id)) {
          print("Updating device: ${device.id}");
          batch.update(_devicesCollection.doc(device.id!), deviceDataWithUser);
          existingDeviceIds.remove(device.id);
        } else {
          print("Adding new device: ${device.name}");
          final newDocRef = _devicesCollection.doc();
          batch.set(newDocRef, deviceDataWithUser);
          device.id = newDocRef.id;
        }
      }

      for (final idToDelete in existingDeviceIds) {
        print("Deleting device: $idToDelete");
        batch.delete(_devicesCollection.doc(idToDelete));
      }

      await batch.commit();
      print("Devices saved successfully.");
    } catch (e, s) {
      print("----------------------------------------");
      print("Error saving devices to Firestore: $e");
      print("Stack trace:\n$s");
      print("----------------------------------------");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save devices: ${e.toString()}")),
        );
      }
    }
  }

  void _startDeviceDiscovery() {
    if (_isScanning) {
      print("HomeContentScreen: Scan already in progress.");
      return;
    }

    print("HomeContentScreen: Starting device discovery process...");
    if (mounted) {
      setState(() {
        _isScanning = true;
        _showScanningIndicator = true;
        _scanStatus = 'Scanning...';
        _scanErrorMessage = null;
      });
    } else {
      print(
          "HomeContentScreen: _startDeviceDiscovery called but widget is not mounted. Aborting scan.");
      return;
    }

    _deviceStreamSubscription?.cancel();
    _deviceDiscovery.startDiscovery();

    _deviceStreamSubscription = _deviceDiscovery.deviceStream.listen(
          (discoveredDevice) {
        if (mounted) {
          setState(() {
            final exists = _devices.any((d) =>
            (discoveredDevice.ip != null &&
                d.ip == discoveredDevice.ip) ||
                (discoveredDevice.ip == null &&
                    d.name == discoveredDevice.name));
            if (!exists) {
              _devices = List.from(_devices)..add(discoveredDevice);
            }
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _isScanning = false;
            _showScanningIndicator = false;
            _scanStatus = 'Scan Failed';
            _scanErrorMessage = "Discovery Error: ${error.toString()}";
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Discovery Error: ${error.toString()}")),
          );
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isScanning = false;
            _showScanningIndicator = false;
            if (_scanErrorMessage == null) {
              _scanStatus = 'Scan Complete';
            } else {
              _scanStatus = 'Scan Finished with Errors';
            }
          });
          final completionMessage = _scanErrorMessage == null
              ? "Device scan complete."
              : "Device scan finished. Check messages for details.";
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(completionMessage)),
          );
        }
      },
    );
  }

  Future<void> _performSecurityScan() async {
    if (!mounted) return;
    setState(() {
      _scanStatus = "Running security scan...";
      _scanErrorMessage = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Running security scan (simulated)...")),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      _scanStatus = "Security scan complete.";
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Security scan complete (simulated).")),
    );
  }

  void _showAddDeviceDialog() {
    _deviceNameController.clear();
    _roomNameController.clear();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add New Device"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _deviceNameController,
              decoration: const InputDecoration(labelText: "Device Name"),
            ),
            TextField(
              controller: _roomNameController,
              decoration: const InputDecoration(labelText: "Room"),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final newDevice = Device(
                  name: _deviceNameController.text.trim(),
                  room: _roomNameController.text.trim(),
                  status: false,
                  icon: 'assets/icons/device_unknown.svg',
                  id: null,
                  openPorts: null,
                  ip: null,
                );

                if (newDevice.name.isEmpty || newDevice.room.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                        Text("Device name and room cannot be empty.")),
                  );
                  return;
                }
                Navigator.pop(context);
                if (mounted) {
                  setState(() {
                    _devices = List.from(_devices)..add(newDevice);
                  });
                }
                await _saveDevices();
                _deviceNameController.clear();
                _roomNameController.clear();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text("Device '${newDevice.name}' added.")),
                  );
                }
              },
              child: const Text("Add Device"),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeviceOptions(Device device) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Device'),
              onTap: () {
                Navigator.pop(context);
                _showEditDeviceDialog(device);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete Device'),
              onTap: () {
                Navigator.pop(context);
                _deleteDevice(device);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('View Details'),
              onTap: () {
                Navigator.pop(context);
                _showDeviceSettings(device);
              },
            ),
          ],
        );
      },
    );
  }

  void _showEditDeviceDialog(Device device) {
    _deviceNameController.text = device.name;
    _roomNameController.text = device.room;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Device"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _deviceNameController,
              decoration: const InputDecoration(labelText: "Device Name"),
            ),
            TextField(
              controller: _roomNameController,
              decoration: const InputDecoration(labelText: "Room"),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final updatedName = _deviceNameController.text.trim();
                final updatedRoom = _roomNameController.text.trim();

                if (updatedName.isEmpty || updatedRoom.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                        Text("Device name and room cannot be empty.")),
                  );
                  return;
                }
                Navigator.pop(context);
                Device? deviceToUpdate;
                int deviceIndex = -1;

                if (mounted) {
                  setState(() {
                    deviceIndex = _devices.indexWhere((d) =>
                    d.id == device.id ||
                        (d.id == null &&
                            d.name == device.name &&
                            d.ip == device.ip));
                    if (deviceIndex != -1) {
                      deviceToUpdate = _devices[deviceIndex];
                      final updatedDevice = Device(
                        id: deviceToUpdate!.id,
                        name: updatedName,
                        room: updatedRoom,
                        status: deviceToUpdate!.status,
                        icon: deviceToUpdate!.icon,
                        openPorts: deviceToUpdate!.openPorts,
                        ip: deviceToUpdate!.ip,
                      );
                      _devices = List.from(_devices);
                      _devices[deviceIndex] = updatedDevice;
                    }
                  });
                }
                if (deviceIndex != -1) {
                  await _saveDevices();
                }
                _deviceNameController.clear();
                _roomNameController.clear();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text("Device '${device.name}' updated.")),
                  );
                }
              },
              child: const Text("Update Device"),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteDevice(Device device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Device"),
        content: Text("Are you sure you want to delete \"${device.name}\"?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              bool deviceRemoved = false;
              if (mounted) {
                setState(() {
                  int initialLength = _devices.length;
                  _devices = _devices.where((d) {
                    if (device.id != null) return d.id != device.id;
                    return !(d.name == device.name &&
                        d.room == device.room &&
                        d.ip == device.ip);
                  }).toList();
                  deviceRemoved = _devices.length < initialLength;
                });
              }
              if (deviceRemoved && device.id != null) {
                await _saveDevices();
              } else if (deviceRemoved && device.id == null) {
                // Device was only local
              }
              if (mounted && deviceRemoved) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Device '${device.name}' deleted.")),
                );
              }
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  // Method to handle logout
  Future<void> _handleLogout() async {
    // Access AuthService (passed via widget.authService)
    final auth = widget.authService;
    await auth.signOut();

    // Navigate to WelcomeScreen and remove all previous routes
    if (mounted) { // Check if the widget is still in the tree
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const WelcomeScreen()),
            (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await _fetchUserDevices();
        await _fetchAndEstimateMonthlyBill();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeHeader(widget.authService.userName ?? 'User'),
            const SizedBox(height: 20),
            _buildBillEstimateCard(),
            const SizedBox(height: 20),
            _buildControlButtons(),
            const SizedBox(height: 25),
            _buildNetworkSection(),
            const SizedBox(height: 25),
            _buildSecuritySection(),
            const SizedBox(height: 25),
            _buildDevicesGrid(),
            const SizedBox(height: 30), // Add some spacing before the logout button
            // Log out Button
            Center( // Center the button
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text("Log Out"),
                onPressed: _handleLogout, // Call the logout handler
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent, // Example styling
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 20), // Add some spacing at the very end
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader(String userName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Welcome back, $userName!",
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          "Here's your home overview",
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildBillEstimateCard() {
    final currencyFormat =
    NumberFormat.currency(locale: 'en_BH', symbol: 'BHD', decimalDigits: 3);
    final timeFormat = DateFormat.jm(); // For formatting time e.g. 9:30 AM

    if (_isLoadingBillEstimate) {
      return Card(
        color: Colors.greenAccent.shade100,
        elevation: 2,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_billErrorEstimateMessage != null) {
      return Card(
        color: Colors.red.shade100,
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade700, size: 30),
              const SizedBox(height: 8),
              Text(
                _billErrorEstimateMessage!,
                style: TextStyle(
                    color: Colors.red.shade700, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                  onPressed: _fetchAndEstimateMonthlyBill,
                  child: const Text("Retry"))
            ],
          ),
        ),
      );
    }

    double progress = 0.0;
    if (_daysPassedInMonth != null &&
        _totalDaysInMonth != null &&
        _totalDaysInMonth! > 0) {
      // More precise progress based on time of day
      double fractionOfDayPassed = 0.0;
      if (_billCalculationTime != null) {
        fractionOfDayPassed = _billCalculationTime!.hour / 24.0 +
            _billCalculationTime!.minute / (24.0 * 60.0);
      }
      progress =
          ((_daysPassedInMonth! - 1) + fractionOfDayPassed) / _totalDaysInMonth!;
      progress = progress.clamp(0.0, 1.0); // Ensure progress is between 0 and 1
    }

    String estimatedBillText = _estimatedMonthlyBill != null
        ? currencyFormat.format(_estimatedMonthlyBill)
        : "N/A";
    String currentAccumulationText = _currentAccumulatedBillMonth != null
        ? currencyFormat.format(_currentAccumulatedBillMonth)
        : "N/A";
    String calculationTimeText = _billCalculationTime != null
        ? " (as of ${timeFormat.format(_billCalculationTime!)})"
        : "";

    return Card(
      color: Colors.greenAccent.shade100,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Estimated Monthly Bill",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              estimatedBillText,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[300],
              color: Colors.blue.shade600,
              minHeight: 6,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  // Use Expanded to prevent overflow if text is long
                  child: Text(
                    "Accumulated: $currentAccumulationText$calculationTimeText",
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    overflow: TextOverflow.ellipsis, // Add ellipsis for long text
                  ),
                ),
                Text(
                  "${_daysPassedInMonth ?? '-'}/${_totalDaysInMonth ?? '-'} days",
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
            if (_daysPassedInMonth != null &&
                _totalDaysInMonth != null &&
                _billCalculationTime != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  // Calculate remaining days more accurately
                  "${(_totalDaysInMonth! - (_daysPassedInMonth! - 1) - (_billCalculationTime!.hour / 24.0)).toStringAsFixed(0)} days remaining this month.",
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButtons() {
    return Container(
      color: Colors.greenAccent.shade100,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildControlButton(
            Icons.search,
            "Scan Devices",
            _startDeviceDiscovery,
            isButtonEnabled: !_isScanning,
          ),
          _buildControlButton(
            Icons.solar_power_outlined,
            "Solar Energy",
            _performSecurityScan,
            isButtonEnabled: !_isScanning,
          ),
          _buildControlButton(
            Icons.add,
            "Add Device",
            _showAddDeviceDialog,
            isButtonEnabled: !_isScanning,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(IconData icon, String label, VoidCallback onPressed,
      {bool isButtonEnabled = true}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, size: 32),
          onPressed: isButtonEnabled ? onPressed : null,
          color: isButtonEnabled ? Colors.blue.shade800 : Colors.grey,
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                color: isButtonEnabled ? Colors.black : Colors.grey)),
      ],
    );
  }

  Widget _buildNetworkSection() {
    final displayedDeviceCount = _devices.length;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Network Status",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            Row(
              key: ValueKey(
                  'networkStatusRow_${_isScanning}_$_showScanningIndicator'),
              children: [
                if (_showScanningIndicator)
                  const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator())
                else if (_scanErrorMessage != null)
                  const Icon(Icons.error_outline_rounded,
                      color: Colors.red, size: 24)
                else
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Colors.green, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _showScanningIndicator
                        ? "Scanning... ($displayedDeviceCount found so far)"
                        : (_scanErrorMessage != null
                        ? _scanErrorMessage!
                        : "$_scanStatus ($displayedDeviceCount device${displayedDeviceCount == 1 ? '' : 's'})"),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecuritySection() {
    final List<String> securityResults = [
      "Huwawei Batelco Router - Secure",
      "Smart TV - Port 8080 open",
      "Ali's Smart AC - Secure",
    ];
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Security Report",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            if (securityResults.isEmpty)
              const Text("Run a security scan to see the report."),
            ...securityResults.map((result) => ListTile(
              leading: Icon(
                result.contains("Port 8080 open")
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline_rounded,
                color: result.contains("Port 8080 open")
                    ? Colors.orange
                    : Colors.green,
              ),
              title: Text(result),
              dense: true,
              contentPadding: EdgeInsets.zero,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Your Smart Devices",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 12),
        if (!_isScanning && _devices.isEmpty)
          const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child:
                Text("No smart devices found or added yet. Try scanning."),
              )),
        if (_devices.isNotEmpty || _isScanning)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1,
            ),
            itemCount: _devices.length,
            itemBuilder: (context, index) {
              return _buildDeviceCard(_devices[index]);
            },
          ),
      ],
    );
  }

  Widget _buildDeviceCard(Device device) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () => _showDeviceOptions(device),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDeviceIcon(device.icon),
                  Switch(
                    value: device.status,
                    onChanged: (value) => _toggleDevice(device, value),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                  Text(device.room,
                      style: TextStyle(color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
              Align(
                alignment: Alignment.bottomRight,
                child: IconButton(
                  icon: const Icon(Icons.settings, size: 20),
                  onPressed: () => _showDeviceSettings(device),
                  tooltip: "Device Settings",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceIcon(String iconName) {
    if (iconName.endsWith('.svg') && iconName.startsWith('assets/icons/')) {
      try {
        return SvgPicture.asset(
          iconName,
          width: 32,
          height: 32,
          colorFilter:
          const ColorFilter.mode(Colors.blue, BlendMode.srcIn),
        );
      } catch (e) {
        print("Error loading SVG icon '$iconName': $e");
        return const Icon(Icons.device_unknown,
            size: 32, color: Colors.blueGrey);
      }
    } else {
      return const Icon(Icons.device_unknown,
          size: 32, color: Colors.blueGrey);
    }
  }

  void _toggleDevice(Device device, bool value) async {
    if (!mounted) return;
    setState(() => device.status = value);
    await _saveDevices();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text("${device.name} turned ${value ? 'on' : 'off'}.")),
    );
  }

  void _showDeviceSettings(Device device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Details for ${device.name}"),
        content: SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              Text('Name: ${device.name}'),
              const SizedBox(height: 8),
              Text('Room: ${device.room}'),
              const SizedBox(height: 8),
              Text('Status: ${device.status ? 'On' : 'Off'}'),
              const SizedBox(height: 8),
              if (device.ip != null && device.ip!.isNotEmpty) ...[
                Text('IP Address: ${device.ip}'),
                const SizedBox(height: 8),
              ],
              if (device.openPorts != null &&
                  device.openPorts!.isNotEmpty) ...[
                const Text('Open Ports:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(device.openPorts!.join(', ')),
              ] else ...[
                const Text(
                    'No open ports detected or available for this device.'),
              ],
              const SizedBox(height: 16),
              const Text("Device Controls (Placeholder):",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const DeviceControlScreen(), // Assuming this is a simple placeholder
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    print(
        "HomeContentScreen: dispose() called. Stopping discovery and cleaning up.");
    _deviceStreamSubscription?.cancel();
    _deviceDiscovery.dispose();
    _deviceNameController.dispose();
    _roomNameController.dispose();
    super.dispose();
  }
}
