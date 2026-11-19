import 'dart:convert';
import 'dart:io';

import 'ps4_ftp_client.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ThemeCreatorApp());
}

class ThemeCreatorApp extends StatelessWidget {
  const ThemeCreatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF38A9FF);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PS4 Theme Creator',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: blue,
          brightness: Brightness.dark,
          surface: const Color(0xFF121923),
        ),
        scaffoldBackgroundColor: const Color(0xFF080B10),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF080B10),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const CreatorHome(),
    );
  }
}

class ThemeDraft {
  String name;
  String author;
  String? wallpaperPath;
  String? audioPath;

  ThemeDraft({
    this.name = 'My PS4 Theme',
    this.author = '',
    this.wallpaperPath,
    this.audioPath,
  });

  Map<String, dynamic> toJson() => {
        'format': 'ps4-theme-project',
        'schemaVersion': 1,
        'name': name,
        'author': author,
        'wallpaperPath': wallpaperPath,
        'audioPath': audioPath,
        'packageStatus': 'not-built',
      };

  factory ThemeDraft.fromJson(Map<String, dynamic> json) => ThemeDraft(
        name: json['name'] as String? ?? 'My PS4 Theme',
        author: json['author'] as String? ?? '',
        wallpaperPath: json['wallpaperPath'] as String?,
        audioPath: json['audioPath'] as String?,
      );
}

class CreatorHome extends StatefulWidget {
  const CreatorHome({super.key});

  @override
  State<CreatorHome> createState() => _CreatorHomeState();
}

class _CreatorHomeState extends State<CreatorHome> {
  int tab = 0;
  final draft = ThemeDraft();
  final nameController = TextEditingController(text: 'My PS4 Theme');
  final authorController = TextEditingController();
  bool loading = true;
  String status = 'Create a theme project to get started.';
  final ipController = TextEditingController();
  final portController = TextEditingController(text: '2121');
  final userController = TextEditingController(text: 'anonymous');
  final passwordController = TextEditingController();
  bool transferring = false;
  bool obscurePassword = true;
  double transferProgress = 0;
  String transferStatus = 'Enter your PS4 FTP address to connect.';

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  @override
  void dispose() {
    nameController.dispose();
    authorController.dispose();
    ipController.dispose();
    portController.dispose();
    userController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('theme_draft');
    ipController.text = prefs.getString('ps4_ip') ?? '';
    portController.text = prefs.getString('ps4_port') ?? '2121';
    userController.text = prefs.getString('ps4_user') ?? 'anonymous';
    if (raw != null) {
      try {
        final restored = ThemeDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        draft
          ..name = restored.name
          ..author = restored.author
          ..wallpaperPath = restored.wallpaperPath
          ..audioPath = restored.audioPath;
        nameController.text = draft.name;
        authorController.text = draft.author;
      } catch (_) {
        // Ignore an outdated or malformed local draft.
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _saveDraft() async {
    draft
      ..name = nameController.text.trim().isEmpty ? 'My PS4 Theme' : nameController.text.trim()
      ..author = authorController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_draft', jsonEncode(draft.toJson()));
    if (mounted) setState(() => status = 'Draft saved on this device.');
  }

  Future<void> _pickAsset({required bool audio}) async {
    final result = await FilePicker.platform.pickFiles(
      type: audio ? FileType.audio : FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      if (audio) {
        draft.audioPath = result.files.single.path;
      } else {
        draft.wallpaperPath = result.files.single.path;
      }
      status = audio ? 'Background audio selected.' : 'Wallpaper selected.';
    });
    await _saveDraft();
  }

  Future<void> _exportManifest() async {
    await _saveDraft();
    final data = const JsonEncoder.withIndent('  ').convert(draft.toJson());
    await Clipboard.setData(ClipboardData(text: data));
    if (mounted) {
      setState(() => status = 'Project manifest copied as JSON.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project manifest copied to clipboard')),
      );
    }
  }


  Future<void> _transferToPs4() async {
    final host = ipController.text.trim();
    final port = int.tryParse(portController.text.trim());
    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      _showMessage('Enter a valid PS4 IP address and FTP port.');
      return;
    }
    final files = <File>[];
    if (draft.wallpaperPath != null) files.add(File(draft.wallpaperPath!));
    if (draft.audioPath != null) files.add(File(draft.audioPath!));
    if (files.isEmpty) {
      _showMessage('Choose a wallpaper or audio file before transferring.');
      return;
    }
    setState(() {
      transferring = true;
      transferProgress = 0;
      transferStatus = 'Connecting to PS4…';
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ps4_ip', host);
    await prefs.setString('ps4_port', port.toString());
    await prefs.setString('ps4_user', userController.text.trim());
    final client = Ps4FtpClient(
      host, port,
      userController.text.trim().isEmpty ? 'anonymous' : userController.text.trim(),
      passwordController.text,
    );
    try {
      await client.connect();
      if (mounted) setState(() => transferStatus = 'Connected. Preparing destination folder…');
      await client.prepareFolder('/data/PS4ThemeCreator');
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        if (!await file.exists()) {
          throw FileSystemException('Selected asset is no longer available', file.path);
        }
        final rawName = file.uri.pathSegments.isEmpty ? 'asset_$i' : file.uri.pathSegments.last;
        final safeName = rawName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        if (mounted) {
          setState(() => transferStatus = 'Uploading ' + safeName + ' (' +
              (i + 1).toString() + '/' + files.length.toString() + ')…');
        }
        await client.uploadFile(file, safeName);
        if (mounted) setState(() => transferProgress = (i + 1) / (files.length + 1));
      }
      final manifest = File(Directory.systemTemp.path + '/ps4_theme_project.json');
      await manifest.writeAsString(const JsonEncoder.withIndent('  ').convert(draft.toJson()));
      await client.uploadFile(manifest, 'theme-project.json');
      await manifest.delete();
      if (mounted) {
        setState(() {
          transferProgress = 1;
          transferStatus = 'Transfer complete: /data/PS4ThemeCreator/';
        });
        _showMessage('Theme assets sent to PS4.');
      }
    } catch (error) {
      if (mounted) setState(() => transferStatus = 'Transfer failed: $error');
    } finally {
      await client.close();
      if (mounted) setState(() => transferring = false);
    }
  }

  Widget _assetTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF38A9FF)),
        title: Text(title),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.upload_file),
        onTap: onTap,
      ),
    );
  }

  Widget _createPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 176,
          decoration: BoxDecoration(
            color: const Color(0xFF121923),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF26384A)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (draft.wallpaperPath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.file(
                    File(draft.wallpaperPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined, size: 42),
                    ),
                  ),
                )
              else
                const Center(
                  child: Icon(Icons.wallpaper_outlined, size: 48, color: Colors.white38),
                ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xDD000000)],
                    ),
                  ),
                  child: Text(
                    nameController.text.isEmpty ? 'My PS4 Theme' : nameController.text,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Theme name', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: authorController,
          decoration: const InputDecoration(labelText: 'Author (optional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 14),
        _assetTile(
          icon: Icons.image_outlined,
          title: 'Wallpaper image',
          subtitle: draft.wallpaperPath?.split('/').last ?? 'Choose an image from this device',
          onTap: () => _pickAsset(audio: false),
        ),
        _assetTile(
          icon: Icons.music_note,
          title: 'Background audio',
          subtitle: draft.audioPath?.split('/').last ?? 'Choose an audio file (optional)',
          onTap: () => _pickAsset(audio: true),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saveDraft,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save theme draft'),
        ),
        OutlinedButton.icon(
          onPressed: _exportManifest,
          icon: const Icon(Icons.data_object),
          label: const Text('Copy project JSON'),
        ),
        const SizedBox(height: 8),
        Text(status, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60)),
      ],
    );
  }

  Widget _transferPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Icon(Icons.sync_alt, size: 56, color: Color(0xFF38A9FF)),
          const SizedBox(height: 12),
          const Text('Android → PS4 transfer', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Enable the FTP server in GoldHEN on your PS4. Keep your phone and console on the same Wi-Fi network.'),
          const SizedBox(height: 18),
          TextField(controller: ipController, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'PS4 IP address', hintText: '192.168.1.100', border: OutlineInputBorder(), prefixIcon: Icon(Icons.computer))),
          const SizedBox(height: 10),
          TextField(controller: portController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'FTP port', border: OutlineInputBorder(), prefixIcon: Icon(Icons.settings_ethernet))),
          const SizedBox(height: 10),
          TextField(controller: userController, decoration: const InputDecoration(labelText: 'FTP username', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: passwordController, obscureText: obscurePassword, decoration: InputDecoration(labelText: 'FTP password (if required)', border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: () => setState(() => obscurePassword = !obscurePassword), icon: Icon(obscurePassword ? Icons.visibility : Icons.visibility_off)))),
          const SizedBox(height: 14),
          const Card(child: ListTile(leading: Icon(Icons.folder_outlined, color: Color(0xFF38A9FF)), title: Text('Destination folder'), subtitle: Text('/data/PS4ThemeCreator/'))),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: transferring ? null : _transferToPs4,
            icon: transferring ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
            label: Text(transferring ? 'Transferring…' : 'Send selected theme files'),
          ),
          if (transferring || transferProgress > 0) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: transferProgress),
          ],
          const SizedBox(height: 12),
          Text(transferStatus, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          const Text('This sends selected source assets and project JSON. It does not install a theme or create a PS4 PKG.', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );

  Widget _libraryPage() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Icon(Icons.collections_bookmark_outlined, size: 52, color: Color(0xFF38A9FF)),
          const SizedBox(height: 14),
          const Text('Theme library', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(draft.name),
              subtitle: Text(draft.wallpaperPath == null ? 'Draft · no wallpaper yet' : 'Draft · wallpaper selected'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => setState(() => tab = 0),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final pages = [_createPage(), _transferPage(), _libraryPage()];
    return Scaffold(
      appBar: AppBar(
        title: const Text('PS4 Theme Creator', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Save draft',
            onPressed: _saveDraft,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.palette_outlined), label: 'Create'),
          NavigationDestination(icon: Icon(Icons.sync_alt), label: 'Transfer'),
          NavigationDestination(icon: Icon(Icons.library_books_outlined), label: 'Library'),
        ],
      ),
    );
  }
}
