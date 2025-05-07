import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:multicast_dns/multicast_dns.dart';

class DeviceDiscovery {
  MDnsClient? _mdnsClient;
  StreamSubscription<Map<String, Object>>? _mdnsSubscription;
  StreamController<String> _controller =
  StreamController<String>.broadcast();
  final List<String> _networkDevices = [];
  bool _isDiscovering = false;
  String _scanStatus = 'Not Started';
  int _scanTimeoutSeconds = 15;
  String _targetIp = '172.20.10.5';

  DeviceDiscovery({String targetIp = '172.20.10.5'}) : _targetIp = targetIp;

  Stream<String> get deviceStream => _controller.stream;
  List<String> get networkDevices => _networkDevices;
  String get scanStatus => _scanStatus;

  Future<void> startDiscovery() async {
    if (_isDiscovering) return;
    _isDiscovering = true;
    _scanStatus = 'Scanning...';
    _networkDevices.clear();
    print("DeviceDiscovery: startDiscovery() called");
    _controller = StreamController<String>.broadcast();
    try {
      if (kIsWeb) {
        print("DeviceDiscovery: Using web discovery (HTTP Probe)");
        await _webDiscovery();
      } else {
        print("DeviceDiscovery: Using native discovery");
        await _nativeDiscovery();
      }
    } catch (e) {
      print("DeviceDiscovery: Discovery error: $e");
      _scanStatus = 'Scan Failed';
      _isDiscovering = false;
      _controller.addError(e);
    }
  }

  Future<void> _webDiscovery() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('http://$_targetIp'));
      final response = await request.close();
      if (response.statusCode == 200) {
        if (!_networkDevices.contains(_targetIp)) {
          _networkDevices.add(_targetIp);
          _controller.add(_targetIp);
        }
      }
    } catch (e) {
      print("Web discovery error: $e");
      _scanStatus = 'Scan Failed';
      _isDiscovering = false;
      _controller.addError(e);
      //rethrow;  Removed rethrow
    } finally{
      _isDiscovering = false;
    }
  }

  Future<void> _nativeDiscovery() async {
    _mdnsClient = MDnsClient();
    try {
      print("DeviceDiscovery: _nativeDiscovery() started");
      await _mdnsClient!.start();
      print("DeviceDiscovery: mDNS client started");

      _mdnsSubscription = _mdnsClient!
          .lookup(ResourceRecordQuery.serverPointer('_http._tcp.local.'),
          timeout: Duration(seconds: _scanTimeoutSeconds))
          .asyncExpand((ResourceRecord record) async* {
        if (record is PtrResourceRecord) {
          final srvQuery = ResourceRecordQuery.service(record.domainName!);
          final srvResponse = await _mdnsClient?.lookup(srvQuery)?.toList() ?? [];

          for (var srvRecord in srvResponse.whereType<SrvResourceRecord>()) {
            final ipQuery = ResourceRecordQuery.addressIPv4(srvRecord.target);
            final ipResponse =
                await _mdnsClient?.lookup(ipQuery)?.toList() ?? [];

            for (var ipRecord in
            ipResponse.whereType<IPAddressResourceRecord>()) {
              yield {
                'name': srvRecord.name,
                'ip': ipRecord.address.address,
                'port': srvRecord.port
              };
            }
          }
        }
      }).listen((data) {
        final deviceInfo = '${data['name']}|${data['ip']}|${data['port']}';
        if (!_networkDevices.contains(deviceInfo)) {
          _networkDevices.add(deviceInfo);
          _controller.add(deviceInfo);
        }
      }, onError: (error) {
        print("mDNS error: $error");
        _scanStatus = 'Scan Failed';
        _isDiscovering = false;
        _controller.addError(error);
      }, onDone: () {
        _isDiscovering = false;
        _scanStatus = 'Scan Complete';
        if (!_controller.isClosed) _controller.close();
      });
    } catch (e) {
      print("Native discovery error: $e");
      _scanStatus = 'Scan Failed';
      _isDiscovering = false;
      _controller.addError(e);
    } finally {
      _mdnsClient?.stop();
    }
  }

  Future<Map<int, bool>> scanPorts(String host) async {
    final ports = [80];
    final results = <int, bool>{};
    print("DeviceDiscovery: scanPorts() started for host: $host");
    try {
      if (kIsWeb) {
        print("DeviceDiscovery: Port scanning is not supported on web.");
        return {};
      } else {
        for (var port in ports) {
          try {
            final socket = await Socket.connect(host, port)
                .timeout(const Duration(seconds: 2));
            socket.destroy();
            results[port] = true;
            print("DeviceDiscovery: Port $port on $host is open (native)");
          } catch (_) {
            results[port] = false;
            print("DeviceDiscovery: Port $port on $host is closed (native)");
          }
        }
      }
    } catch (e) {
      print("DeviceDiscovery: Port scan error: $e");
      _scanStatus = 'Scan Failed';
    }
    return results;
  }

  void stopDiscovery() {
    print("DeviceDiscovery: stopDiscovery() called");
    _mdnsSubscription?.cancel();
    _mdnsClient?.stop();
    _mdnsClient = null;
    _isDiscovering = false;
    _scanStatus = 'Scan Complete';
    _controller.close();
    print("DeviceDiscovery: Discovery stopped");
  }
}

