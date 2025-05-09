import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'device_discovery.dart';
import 'device.dart';
import 'device_control_screen.dart';
import 'usage_analysis_screen.dart';
import 'bill_management_screen.dart';
import 'rewards_screen.dart';
import 'auth_service.dart';
import 'welcome_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  final String userEmail;

  const HomeScreen({
    Key? key,
    required this.userId,
    required this.userEmail,
  }) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  late AuthService auth;

  // Ensure _screens are initialized correctly
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    auth = Provider.of<AuthService>(context, listen: false);
    // Initialize _screens here where context is available if needed by HomeContentScreen's provider
    _screens = [
      HomeContentScreen(key: UniqueKey()), // Added UniqueKey for potential state issues
      const UsageAnalysisScreen(),
      const BillManagementScreen(),
      const RewardsScreen(),
    ];
  }

  void _onItemTapped(int index) {
    if (index < _screens.length) { // Ensure index is within bounds
      setState(() {
        _selectedIndex = index;
      });
    } else {
      print("Error: _onItemTapped called with out-of-bounds index: $index");
    }
  }

  @override
  Widget build(BuildContext context) {
    print("HomeScreen: build() called with selectedIndex: $_selectedIndex");
    return Scaffold(
      appBar: _selectedIndex == 0
          ? AppBar(
        title: Text("${auth.userName ?? 'User'}'s Home"),
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
        BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Analytics'),
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
                  MaterialPageRoute(builder: (context) => const WelcomeScreen()),
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
  const HomeContentScreen({Key? key}) : super(key: key);

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

  late AuthService auth;
  final CollectionReference _devicesCollection =
  FirebaseFirestore.instance.collection('devices');

  final _deviceNameController = TextEditingController();
  final _roomNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    auth = Provider.of<AuthService>(context, listen: false);
    _loadInitialData();
    print("HomeContentScreen: initState completed.");
  }

  Future<void> _loadInitialData() async {
    print("HomeContentScreen: Loading initial data...");
    if (mounted) { // Added mounted check
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

  Future<void> _fetchUserDevices() async {
    try {
      final userId = auth.userId;
      if (userId == null) {
        print("HomeContentScreen: User ID is null, cannot fetch devices.");
        if (mounted) {
          setState(() {
            _devices = [];
            _scanErrorMessage = "User not logged in. Cannot fetch saved devices.";
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
          SnackBar(content: Text("Failed to load saved devices: ${e.toString()}")),
        );
      }
    }
  }

  Future<void> _saveDevices() async {
    try {
      final userId = auth.userId;
      if (userId == null) {
        print("HomeContentScreen: User ID is null, cannot save devices.");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("User not logged in. Cannot save devices.")),
          );
        }
        return;
      }

      print("Saving ${_devices.length} devices for user ID: $userId");

      final existingDevicesSnapshot = await _devicesCollection
          .where('userId', isEqualTo: userId)
          .get();
      final existingDeviceIds = existingDevicesSnapshot.docs.map((doc) => doc.id).toSet();
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
    if (mounted) { // Added mounted check
      setState(() {
        _isScanning = true;
        _showScanningIndicator = true;
        _scanStatus = 'Scanning...';
        _scanErrorMessage = null;
        print("HomeContentScreen: UI state set to scanning. Current devices: ${_devices.length}");
      });
    } else { // If not mounted, don't proceed with discovery
      print("HomeContentScreen: _startDeviceDiscovery called but widget is not mounted. Aborting scan.");
      return;
    }


    _deviceStreamSubscription?.cancel();
    _deviceDiscovery.startDiscovery();

    _deviceStreamSubscription = _deviceDiscovery.deviceStream.listen(
          (discoveredDevice) {
        print("HomeContentScreen: Discovered device via stream: ${discoveredDevice.name} (IP: ${discoveredDevice.ip})");
        if (mounted) {
          setState(() {
            final exists = _devices.any((d) =>
            (discoveredDevice.ip != null && d.ip == discoveredDevice.ip) ||
                (discoveredDevice.ip == null && d.name == discoveredDevice.name));

            if (!exists) {
              _devices = List.from(_devices)..add(discoveredDevice);
              print("HomeContentScreen: Added discovered device to list. New length: ${_devices.length}");
            } else {
              print("HomeContentScreen: Skipping duplicate discovered device from stream: ${discoveredDevice.name}");
            }
          });
        }
      },
      onError: (error) {
        print("HomeContentScreen: Device discovery stream error: $error");
        if (mounted) {
          setState(() {
            _isScanning = false;
            _showScanningIndicator = false;
            _scanStatus = 'Scan Failed';
            _scanErrorMessage = "Discovery Error: ${error.toString()}";
            print("HomeContentScreen: Scan failed state updated. Devices: ${_devices.length}");
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Discovery Error: ${error.toString()}")),
          );
        }
      },
      onDone: () {
        print("HomeContentScreen: Device discovery stream finished (onDone).");
        if (mounted) {
          setState(() {
            _isScanning = false;
            _showScanningIndicator = false;
            if (_scanErrorMessage == null) {
              _scanStatus = 'Scan Complete';
            } else {
              _scanStatus = 'Scan Finished with Errors';
            }
            print("HomeContentScreen: Scan complete state updated. Devices: ${_devices.length}");
          });
          final completionMessage = _scanErrorMessage == null ? "Device scan complete." : "Device scan finished. Check messages for details.";
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
                    const SnackBar(content: Text("Device name and room cannot be empty.")),
                  );
                  return;
                }

                Navigator.pop(context);

                if (mounted) {
                  setState(() {
                    _devices = List.from(_devices)..add(newDevice);
                    print("HomeContentScreen: Manually added device. New list length: ${_devices.length}");
                  });
                }
                await _saveDevices();

                _deviceNameController.clear();
                _roomNameController.clear();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Device '${newDevice.name}' added.")),
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
                    const SnackBar(content: Text("Device name and room cannot be empty.")),
                  );
                  return;
                }

                Navigator.pop(context);

                Device? deviceToUpdate;
                int deviceIndex = -1;

                if (mounted) {
                  setState(() {
                    deviceIndex = _devices.indexWhere((d) => d.id == device.id || (d.id == null && d.name == device.name && d.ip == device.ip));
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
                      print("HomeContentScreen: Edited device. Current list length: ${_devices.length}");
                    } else {
                      print("HomeContentScreen: Error: Could not find device to edit.");
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
                    SnackBar(content: Text("Device '${device.name}' updated.")),
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
                    return !(d.name == device.name && d.room == device.room && d.ip == device.ip);
                  }).toList();
                  deviceRemoved = _devices.length < initialLength;
                  if(deviceRemoved) {
                    print("HomeContentScreen: Deleted device. New list length: ${_devices.length}");
                  } else {
                    print("HomeContentScreen: Device not found for deletion in local list.");
                  }
                });
              }

              if (deviceRemoved && device.id != null) {
                await _saveDevices();
              } else if (deviceRemoved && device.id == null) {
                print("HomeContentScreen: Device removed locally (was not in Firestore).");
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


  @override
  Widget build(BuildContext context) {
    print("HomeContentScreen: build() called. Devices: ${_devices.length}, Scanning: $_isScanning, Indicator: $_showScanningIndicator, Status: $_scanStatus");
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcomeHeader(auth.userName ?? 'User'),
          const SizedBox(height: 20),
          _buildBillCard(),
          const SizedBox(height: 20),
          _buildControlButtons(),
          const SizedBox(height: 25),
          _buildNetworkSection(),
          const SizedBox(height: 25),
          _buildSecuritySection(),
          const SizedBox(height: 25),
          _buildDevicesGrid(),
        ],
      ),
    );
  }

  Widget _buildWelcomeHeader(String userName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Welcome back, $userName!",
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Here's your home overview",
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildBillCard() {
    return Card(
      color: Colors.greenAccent.shade100,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Current Bill", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              "17.03 BHD",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: 0.34,
              backgroundColor: Colors.grey[200],
              color: Colors.blue,
            ),
            const SizedBox(height: 8),
            Text(
              "Estimated progress this billing cycle",
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
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
            Icons.security,
            "Run Security",
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

  Widget _buildControlButton(IconData icon, String label, VoidCallback onPressed, {bool isButtonEnabled = true}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, size: 32),
          onPressed: isButtonEnabled ? onPressed : null,
          color: isButtonEnabled ? Colors.blue.shade800 : Colors.grey,
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: isButtonEnabled ? Colors.black : Colors.grey)),
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
              // Corrected the typo here from _isScanning_ to _isScanning
              key: ValueKey('networkStatusRow_${_isScanning}_$_showScanningIndicator'),
              children: [
                if (_showScanningIndicator)
                  const SizedBox(
                      width: 24, height: 24, child: CircularProgressIndicator())
                else if (_scanErrorMessage != null)
                  const Icon(Icons.error_outline_rounded, color: Colors.red, size: 24)
                else
                  Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 24),
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
      "Router - Secure",
      "Smart TV - Port 8080 open",
      "AC Unit - No vulnerabilities",
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
                result.contains("Port 8080 open") ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                color: result.contains("Port 8080 open") ? Colors.orange : Colors.green,
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
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20.0),
            child: Text("No smart devices found or added yet. Try scanning."),
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
                  Text(device.room, style: TextStyle(color: Colors.grey[600]),
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
        return const Icon(Icons.device_unknown, size: 32, color: Colors.blueGrey);
      }
    } else {
      return const Icon(Icons.device_unknown, size: 32, color: Colors.blueGrey);
    }
  }

  void _toggleDevice(Device device, bool value) async {
    if (!mounted) return;
    setState(() => device.status = value);
    await _saveDevices();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("${device.name} turned ${value ? 'on' : 'off'}.")),
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
              if (device.openPorts != null && device.openPorts!.isNotEmpty) ...[
                const Text('Open Ports:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(device.openPorts!.join(', ')),
              ] else ...[
                const Text('No open ports detected or available for this device.'),
              ],
              const SizedBox(height: 16),
              const Text("Device Controls (Placeholder):", style: TextStyle(fontWeight: FontWeight.bold)),
              const DeviceControlScreen(),
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
    print("HomeContentScreen: dispose() called. Stopping discovery and cleaning up.");
    _deviceStreamSubscription?.cancel();
    _deviceDiscovery.dispose();
    _deviceNameController.dispose();
    _roomNameController.dispose();
    super.dispose();
  }
}
