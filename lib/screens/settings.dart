import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/user.dart';

class SettingsScreen extends StatefulWidget {
  final User user;
  final Function(User) onUserUpdated;

  const SettingsScreen({
    super.key,
    required this.user,
    required this.onUserUpdated,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _usernameController;
  String? _selectedImagePath;
  String? _selectedDirectory;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user.username);
    _selectedImagePath = widget.user.profileImage;
    _selectedDirectory = widget.user.defaultDownloadDirectory;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'svg'
      ],
    );

    if (result != null) {
      setState(() {
        _selectedImagePath = result.files.single.path;
      });
      _updateUser();
    }
  }

  Future<void> _pickDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      setState(() {
        _selectedDirectory = selectedDirectory;
      });
      _updateUser();
    }
  }

  void _updateUser() {
    final updatedUser = widget.user.copyWith(
      username: _usernameController.text,
      profileImage: _selectedImagePath,
      defaultDownloadDirectory: _selectedDirectory,
    );
    widget.onUserUpdated(updatedUser);
  }

  Widget _buildProfileImage() {
    if (_selectedImagePath == null) {
      return const CircleAvatar(
        radius: 50,
        child: Icon(Icons.person, size: 50),
      );
    }

    if (_selectedImagePath!.toLowerCase().endsWith('.svg')) {
      return CircleAvatar(
        radius: 50,
        child: ClipOval(
          child: SvgPicture.asset(_selectedImagePath!),
        ),
      );
    }

    return CircleAvatar(
      radius: 50,
      backgroundImage: AssetImage(_selectedImagePath!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: _buildProfileImage(),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _pickImage,
                    child: const Text('Change Profile Picture'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _updateUser(),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Download Directory:\n${_selectedDirectory ?? 'Not selected'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _pickDirectory,
                  child: const Text('Select Directory'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
