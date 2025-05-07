import 'package:flutter/material.dart';
import 'auth_service.dart';

class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const List<String> settings = [
      "Change Password",
      "Notifications",
      "Theme"
    ];
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Center(
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
                child: const Text("John Doe"),
              ),
            ),
            const SizedBox(height: 16.0),
            Center(
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 20,
                  color: Theme.of(context).primaryColor,
                ),
                child: const Text("johndoe@email.com"),
              ),
            ),
            const SizedBox(height: 32.0),
            Center(
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
                child: const Text("Conservation Goals"),
              ),
            ),
            const SizedBox(height: 16.0),
            Center(
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 20,
                  color: Theme.of(context).primaryColor,
                ),
                child: const Text("Reduce water usage by 10%"),
              ),
            ),
            const SizedBox(height: 32.0),
            Center(
              child: DefaultTextStyle(
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
                child: const Text("Settings"),
              ),
            ),
            const SizedBox(height: 16.0),
            Expanded(
              child: Center(
                child: ListView(
                  children: settings.map((setting) {
                    return ListTile(
                      title: Text(
                        setting,
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontSize: 18,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.blue,
                        size: 30,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}