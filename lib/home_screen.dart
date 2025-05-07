
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'device_discovery.dart'; // Import the device_discovery.dart file
import 'device.dart';
import 'device_control_screen.dart';
import 'usage_analysis_screen.dart';
import 'bill_management_screen.dart';
import 'rewards_screen.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final List<Widget> _widgetOptions = [
    const HomeScreenContent(),
    const UsageAnalysisScreen(),
    const BillManagementScreen(),
    const RewardsScreen(),
  ];
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: _widgetOptions[_selectedIndex]),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'My Home'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Analytics'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Bill'),
          BottomNavigationBarItem(icon: Icon(Icons.star), label: 'Rewards'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue.shade800,
        unselectedItemColor: Colors.grey.shade600,
        onTap: _onItemTapped,
        backgroundColor: Colors.transparent,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        showUnselectedLabels: false,
      ),
    );
  }
}

class HomeScreenContent extends StatefulWidget {
  const HomeScreenContent({super.key});
  @override
  State<HomeScreenContent> createState() => _HomeScreenContentState();
}

class _HomeScreenContentState extends State<HomeScreenContent> {
  final List<Device> _devices = [
    Device(name: "Smart TV", room: "Haidar room", status: false, icon: 'tv.svg'),
    Device(
        name: "Air Purifier", room: "Kitchen", status: true, icon: 'air-purifier.svg'),
    Device(
        name: "Air Conditioner", room: "Hussain\'s Room", status: false,
        icon: 'air-conditioner.svg'),
    Device(name: "Main Router", room: "Huawei Router 5G", status: true,
        icon: 'router.svg'),
    Device(
        name: "Smart Light", room: "Hall - 4 lights", status: false,
        icon: 'light-bulb.svg'),
    Device(name: "Socket", room: "Kitchen", status: false, icon: 'plug.svg'),
  ];
  final DeviceDiscovery _deviceDiscovery = DeviceDiscovery();
  List<String> _discoveredDevices = [];
  List<String> _networkDevices = [];
  String _discoveryStatus = 'Not Started';
  List<String> _securityResults = [];
  Map<String, Map<int, bool>> _portResults = {};
  bool _isScanning = false;
  StreamSubscription<String>? _deviceStreamSubscription;

  @override
  void initState() {
    super.initState();
    print("HomeScreenContent: initState()");
    _startDeviceDiscovery();
  }

  @override
  void dispose() {
    print("HomeScreenContent: dispose()");
    _deviceDiscovery.stopDiscovery();
    _deviceStreamSubscription?.cancel();
    super.dispose();
  }

  void _startDeviceDiscovery() {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
      _discoveryStatus = 'Scanning...';
      _discoveredDevices.clear();
      _securityResults.clear();
      _networkDevices.clear();
      _portResults.clear();
    });

    _deviceDiscovery.startDiscovery();
    _deviceStreamSubscription = _deviceDiscovery.deviceStream.listen(
          (deviceInfo) {
        print("HomeScreenContent: Device Discovered: $deviceInfo");
        //final parts = deviceInfo.split('|'); // Removed this line
        //if (parts.length == 3) {
        //  final name = parts[0];
        //  final ip = parts[1];
        //  final port = parts[2];
        //  final deviceString = '$name|$ip|$port';
        if (mounted && !_discoveredDevices.contains(deviceInfo)) {
          // Changed from deviceString to deviceInfo
          setState(() {
            _discoveredDevices.add(deviceInfo);
            print(
                "HomeScreenContent: Device added to _discoveredDevices (setState): $_discoveredDevices");
            if (_discoveredDevices.isNotEmpty) {
              _discoveryStatus = 'Devices Found';
            }
          });
        }
        //} else {
        //  print(
        //      "HomeScreenContent: Discovered device string was not in the expected format: $deviceInfo");
        //}
      },
      onError: (error) {
        print("HomeScreenContent: Error during discovery: $error");
        if (mounted) {
          setState(() {
            _discoveryStatus = 'Scan Failed';
            _isScanning = false;
          });
        }
      },
      onDone: () {
        print("HomeScreenContent: Discovery stream completed.");
        if (mounted && _isScanning) {
          setState(() {
            _isScanning = false;
            _discoveryStatus = 'Scan Complete';
          });
        }
      },
    );

    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _isScanning) {
        setState(() {
          _isScanning = false;
          _discoveryStatus = 'Scan Complete (Timeout)';
        });
        _deviceDiscovery.stopDiscovery();
      }
    });
  }

  Future<void> _performSecurityChecks() async {
    print("HomeScreenContent: _performSecurityChecks() started");
    final allDevices = [..._discoveredDevices, ..._networkDevices];
    if (allDevices.isEmpty) {
      setState(() => _securityResults.add("No devices found to check."));
      print("HomeScreenContent: No devices found to check");
      return;
    }
    for (var device in allDevices) {
      //final ip = device is PtrResourceRecord ? device.domainName?.split('.').first ?? 'unknown' : device.toString();
      final parts = device.split('|');
      final ip = parts.length > 1 ? parts[1] : 'Unknown';
      print("HomeScreenContent: Checking security for device: $ip, $device");
      await _performPortScan(ip, device);
    }
  }

  Future<void> _performPortScan(String host, String deviceName) async {
    final results = await _deviceDiscovery.scanPorts(host);
    print("HomeScreenContent: Port scan results for $host: $results");
    if (mounted) {
      setState(() {
        _portResults[host] = results;
        final openPorts = results.entries.where((e) => e.value);
        if (openPorts.isNotEmpty) {
          _securityResults.add(
              "🔓 $deviceName - Open ports: ${openPorts.map((e) => e.key).join(
                ', ',
              )} open");
        } else {
          _securityResults.add("🔒 $deviceName - No open ports found");
        }
      });
    }
  }

  Widget _buildControlButton(
      String icon, String label, VoidCallback onPressed) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[100],
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: SvgPicture.asset(
            "assets/icons/$icon",
            width: 28,
            height: 28,
            colorFilter: const ColorFilter.mode(Colors.green, BlendMode.srcIn),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderSection(constraints),
              const SizedBox(height: 20),
              _buildBillCard(),
              const SizedBox(height: 20),
              _buildControlButtonsRow(),
              const SizedBox(height: 25),
              _buildNetworkSection(),
              const SizedBox(height: 25),
              _buildSecurityResults(),
              const SizedBox(height: 25),
              _buildDevicesGrid(constraints),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection(BoxConstraints constraints) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("Mohammed\'s Home",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: constraints.maxWidth * 0.055,
            )),
        IconButton(
          icon: const Icon(Icons.person, size: 28),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildBillCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green[200]!, const Color(0xFFE8F5E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Current Bill",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              )),
          Text("17.03 BHD",
              style: TextStyle(
                color: Colors.green[900],
                fontWeight: FontWeight.w900,
                fontSize: 16,
              )),
        ],
      ),
    );
  }

  Widget _buildControlButtonsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildControlButton("control.svg", "Control & Secure", () {
          _startDeviceDiscovery();
          setState(() => _securityResults.clear());
        }),
        _buildControlButton("add.svg", "Add Devices", () {}),
        _buildControlButton("solar.svg", "Solar Panel", () {}),
      ],
    );
  }

  Widget _buildNetworkSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Network Devices",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            )),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _isScanning
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : const Icon(Icons.wifi_find, size: 20),
                  const SizedBox(width: 8),
                  Text(_discoveryStatus),
                ],
              ),
              const SizedBox(height: 12),
              Text("Discovered Devices Count: ${_discoveredDevices.length}"),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildDeviceList() {
    print(
        "HomeScreenContent: _buildDeviceList() called with _discoveredDevices: $_discoveredDevices");
    List<Widget> deviceList = [];
    for (var device in _discoveredDevices) {
      //final deviceName = _formatDeviceName(
      //    device.domainName ?? 'Unknown Device'); //error is here
      final parts = device.split('|');
      final deviceName = parts[0];
      final deviceIp = parts.length > 1 ? parts[1] : 'Unknown IP';
      print("HomeScreenContent: Building list tile for device: $deviceName, $deviceIp");
      deviceList.add(
        ListTile(
          key: ValueKey(device),
          title: Text(deviceName),
          subtitle: Text('IP: $deviceIp'),
          leading: const Icon(Icons.device_hub),
        ),
      );
    }
    return deviceList;
  }

  Widget _buildSecurityResults() {
    print("HomeScreenContent: _buildSecurityResults() called");
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Security Results",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            )),
        const SizedBox(height: 12),
        Column(
          children: _securityResults.map((r) {
            print("HomeScreenContent: Security result: $r");
            return ListTile(
              key: ValueKey(r),
              title: Text(r),
              leading: const Icon(Icons.security, size: 20),
              dense: true,
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        if (_discoveredDevices.isNotEmpty || _networkDevices.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Discovered Devices:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Column(
                children: _buildDeviceList(),
              )
            ],
          )
      ],
    );
  }

  Widget _buildDevicesGrid(BoxConstraints constraints) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("My IoT Devices",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            )),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.1,
          ),
          itemCount: _devices.length,
          itemBuilder: (context, index) =>
              _buildDeviceCard(_devices[index]),
        ),
      ],
    );
  }

  String _formatDeviceName(String domain) {
    String formattedName = domain
        .replaceAll('._http._tcp.local.', '')
        .replaceAll('.local', '')
        .replaceAll('_', ' ');
    print(
        "HomeScreenContent: Formatted device name: $domain to $formattedName");
    return formattedName;
  }

  Widget _buildDeviceCard(Device device) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDeviceIcon(device.icon, 32, 32),
                Switch(
                  value: device.status,
                  onChanged: (v) => setState(() => device.status = v),
                  activeColor: Colors.green,
                  materialTapTargetSize:
                  MaterialTapTargetSize.shrinkWrap,
                )
              ],
            ),
            const SizedBox(height: 8),
            Text(device.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(device.room,
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            const Spacer(),
            Align(
              alignment: Alignment.bottomRight,
              child: IconButton(
                icon: const Icon(Icons.settings, size: 20),
                onPressed: () => _showDeviceControlPopup(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceIcon(String iconName, double width, double height) {
    return iconName.endsWith('.svg')
        ? SvgPicture.asset(
      "assets/icons/$iconName",
      width: width,
      height: height,
      colorFilter:
      const ColorFilter.mode(Colors.green, BlendMode.srcIn),
    )
        : Image.asset("assets/icons/$iconName", width: width, height: height);
  }

  void _showDeviceControlPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const AlertDialog(
        content: DeviceControlScreen(),
      ),
    );
  }
}

