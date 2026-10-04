import 'package:flutter/material.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help and Support')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          Text(
            'HMU Technical Support',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 8),
          Text(
            'Contact our support team for help with your account or orders.',
          ),
          SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.phone_outlined),
            title: Text('+266 50898333'),
            subtitle: Text('Technical support'),
          ),
          Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.phone_outlined),
            title: Text('+266 6307 1313'),
            subtitle: Text('Technical support'),
          ),
        ],
      ),
    );
  }
}
