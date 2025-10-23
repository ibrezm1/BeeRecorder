// screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  final Function(bool) onThemeChanged;

  const SettingsScreen({super.key, required this.onThemeChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('geminiApiKey') ?? '';
      _modelController.text = prefs.getString('geminiModel') ?? 'gemini-2.5-flash-lite';
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('geminiApiKey', _apiKeyController.text);
    await prefs.setString('geminiModel', _modelController.text);
    await prefs.setBool('isDarkMode', _isDarkMode);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _apiKeyController,
            decoration: const InputDecoration(
              labelText: 'Google API Key',
              hintText: 'Enter your Gemini API key',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _modelController,
            decoration: const InputDecoration(
              labelText: 'Gemini Model',
              hintText: 'gemini-2.5-flash-lite',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: _isDarkMode,
            onChanged: (value) {
              setState(() {
                _isDarkMode = value;
              });
              widget.onThemeChanged(value);
              _saveSettings();
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saveSettings,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            child: const Text('Save Settings'),
          ),
        ],
      ),
    );
  }
}
