import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'auth_service.dart'; // Adjust the path as needed

class HomeRegistrationPage extends StatefulWidget {
  const HomeRegistrationPage({Key? key}) : super(key: key);

  @override
  State<HomeRegistrationPage> createState() => _HomeRegistrationPageState();
}

class _HomeRegistrationPageState extends State<HomeRegistrationPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _homeController = TextEditingController();
  final _roadController = TextEditingController();
  final _blockController = TextEditingController();
  final _cityController = TextEditingController();

  bool _isLoading = false;

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.userId;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    await authService.addHomeForUser(
      userId: userId,
      name: _nameController.text.trim(),
      home: _homeController.text.trim(),
      road: _roadController.text.trim(),
      block: _blockController.text.trim(),
      city: _cityController.text.trim(),
    );

    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Home registered successfully!')),
    );

    Navigator.pushReplacementNamed(context, '/homes'); // Go back to the previous screen
  }

  @override
  void dispose() {
    _nameController.dispose();
    _homeController.dispose();
    _roadController.dispose();
    _blockController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register Home')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Home Name'),
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _homeController,
                decoration: const InputDecoration(labelText: 'Home Number'),
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _roadController,
                decoration: const InputDecoration(labelText: 'Road'),
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _blockController,
                decoration: const InputDecoration(labelText: 'Block'),
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _cityController,
                decoration: const InputDecoration(labelText: 'City'),
                validator: (value) => value!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                onPressed: _submit,
                child: const Text('Register Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
