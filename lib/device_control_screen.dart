
import 'package:flutter/material.dart';

class DeviceControlScreen extends StatelessWidget {
  const DeviceControlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Text("Device Control Interface",
          style: TextStyle(fontSize: 20)),
    );
  }
}
