// screens/home_screen.dart
import 'package:flutter/material.dart';
import 'recording_screen.dart';
import 'recordings_list_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final Function(bool) onThemeChanged;

  const HomeScreen({super.key, required this.onThemeChanged});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const RecordingScreen(),
      const RecordingsListScreen(),
      SettingsScreen(onThemeChanged: widget.onThemeChanged),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.mic),
            label: 'Record',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music),
            label: 'Recordings',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}