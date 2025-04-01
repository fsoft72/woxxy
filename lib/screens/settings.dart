import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import '../models/user.dart';
import '../models/file_transfer_manager.dart';
import '../funcs/debug.dart'; // Import zprint for debugging

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
  bool _enableMd5Checksum = true; // Initialize state variable

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user.username);
    _selectedImagePath = widget.user.profileImage;
    _selectedDirectory = widget.user.defaultDownloadDirectory;
    _enableMd5Checksum = widget.user.enableMd5Checksum; // Initialize from user object
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'svg'],
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
      // Attempt to update the download path in the manager first
      bool success = await FileTransferManager.instance.updateDownloadPath(selectedDirectory);

      if (success) {
        setState(() {
          _selectedDirectory = selectedDirectory;
        });
        _updateUser();
      } else {
        // Optionally show an error message if the path update failed
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to set download directory. Check permissions.')),
          );
        }
        zprint("❌ Failed to update download directory in FileTransferManager");
      }
    }
  }

  void _updateUser() {
    final updatedUser = widget.user.copyWith(
      username: _usernameController.text,
      profileImage: _selectedImagePath,
      defaultDownloadDirectory: _selectedDirectory,
      enableMd5Checksum: _enableMd5Checksum, // Include the checksum setting
    );
    widget.onUserUpdated(updatedUser);
  }

  Widget _buildProfileImage() {
    // Default placeholder
    Widget imageWidget = const CircleAvatar(
      radius: 50,
      child: Icon(Icons.person, size: 50),
    );

    if (_selectedImagePath != null && _selectedImagePath!.isNotEmpty) {
      final file = File(_selectedImagePath!);
      if (file.existsSync()) {
        // Check if file actually exists
        if (_selectedImagePath!.toLowerCase().endsWith('.svg')) {
          imageWidget = CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey[200], // Add a background for SVG transparency
            child: ClipOval(
              child: SvgPicture.file(
                // Use SvgPicture.file for local files
                file,
                fit: BoxFit.cover, // Ensure SVG covers the circle
                width: 100,
                height: 100,
                placeholderBuilder: (context) => const CircularProgressIndicator(),
              ),
            ),
          );
        } else {
          imageWidget = CircleAvatar(
            radius: 50,
            backgroundImage: FileImage(file),
            onBackgroundImageError: (exception, stackTrace) {
              zprint("❌ Error loading profile image: $exception");
              // Optionally revert to placeholder if image fails to load
              // setState(() { _selectedImagePath = null; });
            },
          );
        }
      } else {
        zprint("⚠️ Profile image file does not exist: $_selectedImagePath");
        // Keep the default placeholder if file doesn't exist
      }
    }

    return imageWidget;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        // Make content scrollable
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Profile Image Section (Centered)
              Column(
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
              const SizedBox(height: 24),

              // Username Field
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                onChanged: (_) => _updateUser(),
              ),
              const SizedBox(height: 24),

              // Download Directory Section
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Download Directory:',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          _selectedDirectory?.isNotEmpty ?? false
                              ? _selectedDirectory!
                              : 'Default (Documents/WoxxyDownloads)', // Show effective default
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    onPressed: _pickDirectory,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Icon(Icons.folder_open, size: 18), SizedBox(width: 8), Text('Select')],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24), // Add space before the checkbox

              // MD5 Checksum Checkbox
              CheckboxListTile(
                title: const Text("Enable MD5 Checksum Verification"),
                subtitle: const Text("Verify file integrity after transfer (slightly slower)"),
                value: _enableMd5Checksum,
                onChanged: (bool? value) {
                  if (value != null) {
                    setState(() {
                      _enableMd5Checksum = value;
                    });
                    _updateUser(); // Save the change immediately
                  }
                },
                controlAffinity: ListTileControlAffinity.leading, // Checkbox on the left
                contentPadding: EdgeInsets.zero, // Remove default padding if desired
              ),
            ],
          ),
        ),
      ),
    );
  }
}
