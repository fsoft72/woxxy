// ignore_for_file: constant_identifier_names

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import '../models/user.dart';
import '../models/file_transfer_manager.dart';
import '../services/profile_image_store.dart';

/// Pause after the last keystroke before the new username is saved and announced.
const Duration USERNAME_SAVE_DELAY = Duration(milliseconds: 600);

class SettingsScreen extends StatefulWidget {
  final User user;
  final Function(User) onUserUpdated;
  final FileTransferManager fileTransferManager;
  final ProfileImageStore? profileImageStore;

  const SettingsScreen({
    super.key,
    required this.user,
    required this.onUserUpdated,
    required this.fileTransferManager,
    this.profileImageStore,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _usernameController;
  String? _selectedImagePath;
  String? _selectedDirectory;
  Timer? _usernameDebounce;
  String? _usernameError;
  late final ProfileImageStore _profileImageStore = widget.profileImageStore ?? ProfileImageStore();

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user.username);
    _selectedImagePath = widget.user.profileImage;
    _selectedDirectory = widget.user.defaultDownloadDirectory;
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      // SVG is not offered: peers decode avatars as raster images and would reject it
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
      ],
    );

    final pickedPath = result?.files.single.path;
    if (pickedPath == null) return;

    final storedPath = await _profileImageStore.import(pickedPath);
    if (!mounted) return;
    setState(() {
      _selectedImagePath = storedPath;
    });
    _updateUser();
  }

  Future<void> _pickDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      // Update FileTransferManager download path
      await widget.fileTransferManager.updateDownloadPath(selectedDirectory);

      setState(() {
        _selectedDirectory = selectedDirectory;
      });
      _updateUser();
    }
  }

  /// Called on every keystroke: validates immediately but saves only after a short pause.
  void _onUsernameChanged(String _) {
    _usernameDebounce?.cancel();
    final empty = _usernameController.text.trim().isEmpty;
    setState(() => _usernameError = empty ? 'Username cannot be empty' : null);
    if (empty) return;
    _usernameDebounce = Timer(USERNAME_SAVE_DELAY, _commitUsername);
  }

  void _commitUsername() {
    _usernameDebounce?.cancel();
    if (_usernameController.text.trim().isEmpty) return;
    _updateUser();
  }

  void _updateUser() {
    // An empty username would be announced as an anonymous peer, keep the last valid one
    final username = _usernameController.text.trim().isEmpty ? widget.user.username : _usernameController.text.trim();
    final updatedUser = widget.user.copyWith(
      username: username,
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
          child: SvgPicture.file(File(_selectedImagePath!)),
        ),
      );
    }

    return CircleAvatar(
      radius: 50,
      backgroundImage: FileImage(File(_selectedImagePath!)),
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
              decoration: InputDecoration(
                labelText: 'Username',
                border: const OutlineInputBorder(),
                errorText: _usernameError,
              ),
              onChanged: _onUsernameChanged,
              onSubmitted: (_) => _commitUsername(),
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
