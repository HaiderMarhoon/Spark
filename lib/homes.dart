import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart';
import 'otp_screen.dart'; // Adjust as needed

class HomesPage extends StatelessWidget {
  const HomesPage({Key? key}) : super(key: key);

  get home => null;

  void _setSelectedHome(BuildContext context, String homeId) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.setSelectedHome(homeId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Home selected successfully!')),
    );
    // You can navigate to the main app here
    //  Navigator.pushNamed(context, '/otp');
    final user = Provider.of<AuthService>(context, listen: false).user;
    if (user != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => OTPScreen(
            userEmail: user.email ?? 'N/A',
            userId: user.uid,
          ),
        ),
      );
    } else {
      // Handle the case where user is null (e.g., show an error or navigate back to login)
      print("Error: User is null after selecting home.");
      Navigator.pop(context); // Or show error dialog
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final userId = authService.userId;

    if (userId == null) {
      return const Center(child: Text('User not logged in.'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Select Home')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('homes')
            .where('userId', isEqualTo: userId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No homes found. Please register one.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/homes_rig');
                    },
                    child: const Text('Register Home'),
                  ),
                ],
              ),
            );
          }

          final homes = snapshot.data!.docs;

          return ListView.builder(
            itemCount: homes.length,
            itemBuilder: (context, index) {
              final home = homes[index];
              final homeData = home.data() as Map<String, dynamic>?;

              if (homeData == null) {
                return const ListTile(title: Text('Invalid home data'));
              }

              return ListTile(
                title: Text(homeData['name'] ?? 'Unnamed Home'),
                subtitle: Text(
                  'Home: ${homeData['home']}, Road: ${homeData['road']}, Block: ${homeData['block']}, City: ${homeData['city']}',
                ),
                trailing: ElevatedButton(
                  onPressed: () => _setSelectedHome(context, home.id),
                  child: const Text('Select'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}