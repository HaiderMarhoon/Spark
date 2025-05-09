import 'dart:async';
import 'dart:io';
import 'dart:convert'; // Import for JSON decoding
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:multicast_dns/multicast_dns.dart';
import 'device.dart';

class DeviceDiscovery {
  MDnsClient? _mdnsClient;
  StreamSubscription<ResourceRecord>? _mdnsSubscription;

  late StreamController<Device> _controller;
  bool _isControllerClosedByPrimaryLogic = false; // Renamed for clarity
  bool _pythonProcessExitedCleanly = false; // New flag

  Stream<Device> get deviceStream => _controller.stream;

  final List<Device> _discoveredDevicesInternal = [];
  final int _scanTimeoutSeconds = 15; // For mDNS

  Process? _pythonProcess;
  StreamSubscription<String>? _pythonOutputSubscription;
  StreamSubscription<String>? _pythonErrorSubscription;

  final String _pythonScriptPath = 'lib/python_discovery_script.py';

  DeviceDiscovery();

  Future<void> startDiscovery() async {
    print("DeviceDiscovery: startDiscovery() called");

    _controller = StreamController<Device>.broadcast();
    _isControllerClosedByPrimaryLogic = false;
    _pythonProcessExitedCleanly = false; // Reset for new scan
    _discoveredDevicesInternal.clear();

    await _cleanupPreviousDiscovery();

    if (kIsWeb) {
      print("DeviceDiscovery: Web discovery is not supported.");
      if (!_controller.isClosed) {
        _controller.addError("Discovery is not supported on Web.");
        _controller.close();
        _isControllerClosedByPrimaryLogic = true;
      }
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.windows) {
      print("DeviceDiscovery: Using Python IPC for Windows discovery");
      await _startPythonDiscovery();
    } else {
      print("DeviceDiscovery: Using native discovery for other platforms (mDNS)");
      await _nativeDiscovery();
    }
  }

  Future<void> _cleanupPreviousDiscovery() async {
    print("DeviceDiscovery: Cleaning up previous discovery resources...");
    await _mdnsSubscription?.cancel();
    _mdnsClient?.stop();
    _mdnsClient = null;
    _mdnsSubscription = null;

    if (_pythonProcess != null) {
      print("DeviceDiscovery: Killing existing Python process PID: ${_pythonProcess?.pid}");
      _pythonProcess!.kill(ProcessSignal.sigkill);
      try {
        await _pythonProcess!.exitCode.timeout(const Duration(seconds: 2));
        print("DeviceDiscovery: Existing Python process confirmed exit or timed out.");
      } catch (e) {
        print("DeviceDiscovery: Error/timeout waiting for old Python process to exit during cleanup: $e");
      }
      _pythonProcess = null;
    }

    await _pythonOutputSubscription?.cancel();
    _pythonOutputSubscription = null;
    await _pythonErrorSubscription?.cancel();
    _pythonErrorSubscription = null;
    print("DeviceDiscovery: Cleanup of previous resources complete.");
  }

  Future<void> _startPythonDiscovery() async {
    try {
      final scriptFile = File(_pythonScriptPath);
      print("DeviceDiscovery: Checking for Python script at: ${scriptFile.absolute.path}");

      if (!await scriptFile.exists()) {
        final errorMsg = "Python script not found at: ${scriptFile.absolute.path}";
        print("DeviceDiscovery: ERROR - $errorMsg");
        if (!_controller.isClosed) {
          _controller.addError(errorMsg);
          _controller.close();
          _isControllerClosedByPrimaryLogic = true;
        }
        return;
      }

      _pythonProcess = await Process.start('python', [_pythonScriptPath]);
      print("DeviceDiscovery: Python process started with PID: ${_pythonProcess?.pid}.");

      _pythonOutputSubscription = _pythonProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
          print("DeviceDiscovery: Received raw line from Python stdout: '$line'");
          if (_controller.isClosed) {
            print("DeviceDiscovery: stdout listener: Controller is ALREADY closed. Ignoring line: $line");
            return;
          }

          if (line.trim().isEmpty) {
            print("DeviceDiscovery: Skipping empty line.");
            return;
          }

          if (line == "DISCOVERY_COMPLETE") {
            print("DeviceDiscovery: Python script signaled completion (DISCOVERY_COMPLETE).");
            if (!_controller.isClosed) {
              print("DeviceDiscovery: Closing controller due to DISCOVERY_COMPLETE.");
              _controller.close();
              _isControllerClosedByPrimaryLogic = true;
            }
          } else {
            try {
              final dynamic deviceData = jsonDecode(line);
              if (deviceData is Map<String, dynamic>) {
                final newDevice = Device.fromPythonJson(deviceData);
                final exists = _discoveredDevicesInternal.any((d) =>
                (newDevice.ip != null && d.ip == newDevice.ip) ||
                    (newDevice.ip == null && d.name == newDevice.name));

                if (!exists) {
                  _discoveredDevicesInternal.add(newDevice);
                  if (!_controller.isClosed) {
                    _controller.add(newDevice);
                  }
                  print("DeviceDiscovery: Added discovered device to stream: ${newDevice.name} (IP: ${newDevice.ip})");
                } else {
                  print("DeviceDiscovery: Skipping duplicate discovered device: ${newDevice.name} (IP: ${newDevice.ip})");
                }
              } else {
                print("DeviceDiscovery: Skipping non-JSON Map line: '$line'");
              }
            } catch (e) {
              print("DeviceDiscovery: FAILED to parse JSON line from Python: '$line'. Error: $e");
              if (!_controller.isClosed) {
                _controller.addError("Failed to parse device data: '$line'. Error: $e");
              }
            }
          }
        },
        onError: (error) {
          print("DeviceDiscovery: ERROR from Python process stdout stream: $error");
          if (!_controller.isClosed) {
            _controller.addError("Python process stdout stream error: $error");
            _controller.close();
            _isControllerClosedByPrimaryLogic = true;
          }
        },
        onDone: () {
          print("DeviceDiscovery: Python process stdout stream finished (onDone). All stdout data processed.");
          if (!_isControllerClosedByPrimaryLogic && !_controller.isClosed) {
            print("DeviceDiscovery: stdout onDone: Controller was not closed by DISCOVERY_COMPLETE. Checking Python exit status before closing.");
            // At this point, all stdout is processed. If Python exited cleanly, this is normal completion.
            // If Python exited with an error, that error should have been caught by exitCode handler.
            // If _pythonProcessExitedCleanly is true, it means script finished and exited 0.
            if (_pythonProcessExitedCleanly) {
              print("DeviceDiscovery: stdout onDone: Python process exited cleanly. Closing controller as normal completion.");
            } else {
              print("DeviceDiscovery: stdout onDone: Python process did NOT exit cleanly or status unknown, but stdout ended. Closing controller.");
              // Optionally add a generic error if no specific error was added by exitCode handler
              if(!_controller.isClosed) { // Check again, as exitCode might have run
                // _controller.addError("Stdout stream ended; Python process status unclear or errored.");
              }
            }
            _controller.close();
            _isControllerClosedByPrimaryLogic = true;
          } else {
            print("DeviceDiscovery: stdout onDone: Controller already closed by primary logic (e.g., DISCOVERY_COMPLETE).");
          }
        },
      );

      _pythonErrorSubscription = _pythonProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        print("Python Stderr: $line");
      });

      _pythonProcess!.exitCode.then((exitCode) {
        print("DeviceDiscovery: Python process EXITED with code $exitCode.");
        if (exitCode == 0) {
          _pythonProcessExitedCleanly = true;
          print("DeviceDiscovery: Python process exited cleanly (code 0). Closure should be handled by stdout.onDone or DISCOVERY_COMPLETE.");
          // If stdout.onDone hasn't fired yet but process exited 0, and DISCOVERY_COMPLETE was missed,
          // stdout.onDone will handle the closure.
        } else { // Python script exited with an error
          _pythonProcessExitedCleanly = false;
          print("DeviceDiscovery: Python process exited with ERROR code $exitCode.");
          if (!_controller.isClosed) { // If not already closed by stdout error or DISCOVERY_COMPLETE (unlikely for error exit)
            print("DeviceDiscovery: Closing controller due to Python error exit (code $exitCode).");
            _controller.addError("Python script exited with error code: $exitCode. Discovery may be incomplete.");
            _controller.close();
            _isControllerClosedByPrimaryLogic = true;
          } else {
            print("DeviceDiscovery: Python process exited with ERROR code $exitCode, but controller was already closed.");
          }
        }
        // Final check: If after all this, the stdout stream is done AND the process has exited,
        // but the controller is still open (highly unlikely now), close it.
        // This is a deep safety net.
        // This check is tricky because stdout.onDone might not have fired yet.
        // Relying on stdout.onDone as the finalizer for clean exits is better.
      }).catchError((e) {
        print("DeviceDiscovery: CRITICAL ERROR waiting for Python process exit code: $e");
        _pythonProcessExitedCleanly = false;
        if (!_controller.isClosed) {
          _controller.addError("Critical error observing Python process exit: $e");
          _controller.close();
          _isControllerClosedByPrimaryLogic = true;
        }
      });

    } catch (e, s) {
      print("DeviceDiscovery: FATAL error starting Python process: $e\nStack: $s");
      if (!_controller.isClosed) {
        _controller.addError("Fatal error starting Python process: $e");
        _controller.close();
        _isControllerClosedByPrimaryLogic = true;
      }
    }
  }

  Future<void> _nativeDiscovery() async {
    print("DeviceDiscovery: _nativeDiscovery() for mDNS started.");
    _mdnsClient = MDnsClient();
    try {
      await _mdnsClient!.start();
      print("DeviceDiscovery: mDNS client started. Looking up services...");

      _mdnsSubscription = _mdnsClient!.lookup(ResourceRecordQuery.serverPointer('_http._tcp.local.'),
          timeout: Duration(seconds: _scanTimeoutSeconds))
          .listen((ResourceRecord record) {
        print("mDNS ResourceRecord received: $record");
        // ... (mDNS processing logic) ...
      }, onError: (error) {
        print("DeviceDiscovery: mDNS lookup error: $error");
        if (!_controller.isClosed) {
          _controller.addError("mDNS scan error: $error");
          _controller.close();
          _isControllerClosedByPrimaryLogic = true;
        }
      }, onDone: () {
        print("DeviceDiscovery: mDNS lookup complete (onDone).");
        if (!_controller.isClosed) {
          _controller.close();
          _isControllerClosedByPrimaryLogic = true;
        }
      });

      await Future.delayed(Duration(seconds: _scanTimeoutSeconds + 2));
      if (!_isControllerClosedByPrimaryLogic && !_controller.isClosed) {
        print("DeviceDiscovery: mDNS overall scan timed out. Closing controller.");
        _controller.addError("mDNS scan timed out.");
        _controller.close();
        _isControllerClosedByPrimaryLogic = true;
      }

    } catch (e) {
      print("DeviceDiscovery: Failed to start or run mDNS client: $e");
      if (!_controller.isClosed) {
        _controller.addError("Failed to start mDNS client: $e");
        _controller.close();
        _isControllerClosedByPrimaryLogic = true;
      }
    } finally {
      _mdnsClient?.stop();
      print("DeviceDiscovery: mDNS client stopped in finally block.");
    }
  }

  Future<void> stopDiscovery() async {
    print("DeviceDiscovery: stopDiscovery() called by user/dispose.");
    await _mdnsSubscription?.cancel();
    _mdnsClient?.stop();
    _mdnsClient = null;
    _mdnsSubscription = null;

    if (_pythonProcess != null) {
      print("DeviceDiscovery: Attempting to kill Python process ${_pythonProcess?.pid} from stopDiscovery.");
      _pythonProcess!.kill(ProcessSignal.sigkill);
      try {
        await _pythonProcess!.exitCode.timeout(const Duration(seconds: 1));
        print("DeviceDiscovery: Python process kill acknowledged or timed out in stopDiscovery.");
      } catch (e) {
        print("DeviceDiscovery: Error/timeout waiting for process kill confirmation in stopDiscovery: $e");
      }
      _pythonProcess = null;
    }
    await _pythonOutputSubscription?.cancel();
    _pythonOutputSubscription = null;
    await _pythonErrorSubscription?.cancel();
    _pythonErrorSubscription = null;

    if (!_controller.isClosed) {
      if (!_isControllerClosedByPrimaryLogic) { // Check if it was closed by the intended logic
        print("DeviceDiscovery: Closing controller from stopDiscovery as it wasn't closed by primary logic.");
        _controller.close(); // Force close if necessary
      } else {
        print("DeviceDiscovery: stopDiscovery: Controller was already closed by primary logic.");
      }
    } else {
      print("DeviceDiscovery: stopDiscovery: Controller was already closed.");
    }
    print("DeviceDiscovery: Discovery stop process complete.");
  }

  void dispose() {
    print("DeviceDiscovery: dispose() called. Initiating stopDiscovery.");
    stopDiscovery();
  }
}
