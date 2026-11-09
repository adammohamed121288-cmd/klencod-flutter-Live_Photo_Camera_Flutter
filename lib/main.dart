import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

const Color accent = Color(0xFF19A0FF);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LivePhotoApp());
}

class LivePhotoApp extends StatelessWidget {
  const LivePhotoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Live Photo Camera',
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(primary: accent, surface: Color(0xFF151515)),
    ),
    home: const CameraHome(),
  );
}

class LiveItem {
  final String videoPath;
  final String imagePath;
  final DateTime createdAt;
  LiveItem({required this.videoPath, required this.imagePath, required this.createdAt});
}

class CameraHome extends StatefulWidget {
  const CameraHome({super.key});
  @override
  State<CameraHome> createState() => _CameraHomeState();
}

class _CameraHomeState extends State<CameraHome> with WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  bool _initializing = true;
  bool _recording = false;
  bool _liveEnabled = true;
  bool _flashOn = false;
  int _cameraIndex = 0;
  String? _error;
  List<LiveItem> _items = [];
  Timer? _captureTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _loadItems();
  }

  Future<Directory> _liveDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/LivePhotos');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _loadItems() async {
    try {
      final dir = await _liveDirectory();
      final files = dir.listSync().whereType<File>().toList();
      final videos = files.where((f) => f.path.endsWith('.mp4')).toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final loaded = <LiveItem>[];
      for (final video in videos) {
        final jpg = video.path.replaceFirst('.mp4', '.jpg');
        if (File(jpg).existsSync()) {
          loaded.add(LiveItem(videoPath: video.path, imagePath: jpg, createdAt: video.lastModifiedSync()));
        }
      }
      if (mounted) setState(() => _items = loaded);
    } catch (_) {}
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw Exception('لم يتم العثور على كاميرا');
      await _setCamera(_cameraIndex);
    } catch (e) {
      if (mounted) setState(() { _error = 'تعذر تشغيل الكاميرا. تأكد من السماح بإذن الكاميرا.'; _initializing = false; });
    }
  }

  Future<void> _setCamera(int index) async {
    final old = _camera;
    _camera = null;
    if (old != null) await old.dispose();
    final controller = CameraController(_cameras[index], ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    _camera = controller;
    await controller.initialize();
    await controller.setFlashMode(FlashMode.off);
    if (mounted) setState(() { _initializing = false; _error = null; });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      camera.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _takeLivePhoto() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _recording || camera.value.isRecordingVideo) return;
    if (!_liveEnabled) {
      try {
        final shot = await camera.takePicture();
        final dir = await _liveDirectory();
        final target = '${dir.path}/Photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(shot.path).copy(target);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم التقاط الصورة')));
      } catch (e) { _showError(e); }
      return;
    }
    setState(() => _recording = true);
    try {
      await camera.startVideoRecording();
      _captureTimer?.cancel();
      _captureTimer = Timer(const Duration(seconds: 3), () async {
        try {
          final clip = await camera.stopVideoRecording();
          final dir = await _liveDirectory();
          final stamp = DateTime.now().millisecondsSinceEpoch;
          final videoPath = '${dir.path}/Live_$stamp.mp4';
          await File(clip.path).copy(videoPath);
          final thumbnailPath = await VideoThumbnail.thumbnailFile(
            video: videoPath, thumbnailPath: dir.path, imageFormat: ImageFormat.JPEG,
            maxWidth: 1100, quality: 92, timeMs: 900,
          );
          if (thumbnailPath == null) throw Exception('تعذر إنشاء صورة المعاينة');
          final finalImage = '${videoPath.replaceFirst('.mp4', '.jpg')}';
          await File(thumbnailPath).copy(finalImage);
          final item = LiveItem(videoPath: videoPath, imagePath: finalImage, createdAt: DateTime.now());
          if (mounted) {
            setState(() { _recording = false; _items.insert(0, item); });
            _openViewer(item);
          }
        } catch (e) {
          if (mounted) setState(() => _recording = false);
          _showError(e);
        }
      });
    } catch (e) {
      setState(() => _recording = false);
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
  }

  Future<void> _toggleFlash() async {
    final c = _camera;
    if (c == null) return;
    _flashOn = !_flashOn;
    await c.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    if (mounted) setState(() {});
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _recording) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    setState(() => _initializing = true);
    try { await _setCamera(_cameraIndex); } catch (e) { _showError(e); }
  }

  void _openViewer(LiveItem item) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LiveViewer(item: item, onDelete: () {
    setState(() => _items.remove(item));
  })));

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _captureTimer?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12), child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(onPressed: _toggleFlash, icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off, color: _flashOn ? Colors.yellow : Colors.white, size: 27)),
            GestureDetector(onTap: () => setState(() => _liveEnabled = !_liveEnabled), child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: _liveEnabled ? const Color(0xFFFFD928) : Colors.white24, borderRadius: BorderRadius.circular(22)),
              child: Row(children: [Icon(Icons.circle, size: 11, color: _liveEnabled ? Colors.black : Colors.white), const SizedBox(width: 7), Text(_liveEnabled ? 'LIVE' : 'LIVE OFF', style: TextStyle(color: _liveEnabled ? Colors.black : Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1))]),
            )),
            IconButton(onPressed: _switchCamera, icon: const Icon(Icons.cameraswitch_outlined, size: 27)),
          ],
        )),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(24), child: Stack(fit: StackFit.expand, children: [
          if (camera != null && camera.value.isInitialized) CameraPreview(camera)
          else Container(color: const Color(0xFF161616), child: Center(child: _initializing ? const CircularProgressIndicator(color: accent) : Text(_error ?? 'الكاميرا غير متاحة', textAlign: TextAlign.center))),
          if (_recording) Positioned(top: 18, left: 0, right: 0, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.fiber_manual_record, size: 10), SizedBox(width: 7), Text('جارٍ تسجيل اللحظة...')])))),
          Positioned(left: 16, right: 16, bottom: 18, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const _ZoomChip(label: '0.5'), const _ZoomChip(label: '1x', selected: true), const _ZoomChip(label: '2x'), const _ZoomChip(label: '3x'),
          ])),
        ]))),
        const SizedBox(height: 16),
        const Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [Text('SLO-MO', style: TextStyle(color: Colors.white54, fontSize: 11)), Text('VIDEO', style: TextStyle(color: Colors.white54, fontSize: 11)), Text('PHOTO', style: TextStyle(color: Color(0xFFFFD928), fontWeight: FontWeight.bold, fontSize: 12)), Text('PORTRAIT', style: TextStyle(color: Colors.white54, fontSize: 11)), Text('PANO', style: TextStyle(color: Colors.white54, fontSize: 11))]),
        const SizedBox(height: 15),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          GestureDetector(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GalleryPage(items: _items, onOpen: _openViewer))), child: _items.isEmpty ? const SizedBox(width: 48) : ClipRRect(borderRadius: BorderRadius.circular(9), child: Image.file(File(_items.first.imagePath), width: 48, height: 48, fit: BoxFit.cover))),
          GestureDetector(onTap: _takeLivePhoto, child: Container(width: 76, height: 76, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 5)), child: Center(child: Container(width: 60, height: 60, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))))),
          IconButton(onPressed: _switchCamera, icon: const Icon(Icons.flip_camera_ios_outlined, size: 30)),
        ])),
        const SizedBox(height: 8),
      ])),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  final String label; final bool selected;
  const _ZoomChip({required this.label, this.selected = false});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8), decoration: BoxDecoration(color: selected ? const Color(0xFFFFD928) : Colors.black54, shape: BoxShape.circle), child: Text(label, style: TextStyle(color: selected ? Colors.black : Colors.white, fontWeight: FontWeight.bold)));
}

class GalleryPage extends StatelessWidget {
  final List<LiveItem> items; final ValueChanged<LiveItem> onOpen;
  const GalleryPage({super.key, required this.items, required this.onOpen});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Live Photos'), backgroundColor: Colors.black), body: items.isEmpty ? const Center(child: Text('لا توجد صور لايف بعد')) : GridView.builder(padding: const EdgeInsets.all(8), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 5, mainAxisSpacing: 5), itemCount: items.length, itemBuilder: (_, i) => GestureDetector(onTap: () => onOpen(items[i]), child: Stack(fit: StackFit.expand, children: [Image.file(File(items[i].imagePath), fit: BoxFit.cover), Positioned(left: 6, bottom: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)), child: const Row(children: [Icon(Icons.motion_photos_on, size: 13), SizedBox(width: 3), Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))])))]))));
}

class LiveViewer extends StatefulWidget {
  final LiveItem item; final VoidCallback onDelete;
  const LiveViewer({super.key, required this.item, required this.onDelete});
  @override
  State<LiveViewer> createState() => _LiveViewerState();
}

class _LiveViewerState extends State<LiveViewer> {
  VideoPlayerController? _player;
  bool _loop = false;
  bool _bounce = false;
  bool _playing = false;
  @override
  void initState() { super.initState(); _init(); }
  Future<void> _init() async {
    final p = VideoPlayerController.file(File(widget.item.videoPath));
    _player = p;
    await p.initialize();
    p.setLooping(true);
    if (mounted) setState(() {});
  }
  Future<void> _play() async {
    final p = _player; if (p == null || !p.value.isInitialized) return;
    if (_playing) { await p.pause(); } else { await p.seekTo(Duration.zero); await p.play(); }
    if (mounted) setState(() => _playing = !_playing);
  }
  @override
  void dispose() { _player?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final p = _player;
    return Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, title: const Text('Today'), actions: [IconButton(onPressed: () async { try { await Gal.putImage(widget.item.imagePath); await Gal.putVideo(widget.item.videoPath); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ في المعرض'))); } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e'))); } }, icon: const Icon(Icons.download, color: accent)), IconButton(onPressed: () async { await Share.shareXFiles([XFile(widget.item.videoPath), XFile(widget.item.imagePath)], text: 'Live Photo'); }, icon: const Icon(Icons.share, color: accent)), PopupMenuButton<String>(onSelected: (v) async { if (v == 'delete') { await File(widget.item.videoPath).delete(); await File(widget.item.imagePath).delete(); widget.onDelete(); if (context.mounted) Navigator.pop(context); } }, itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('حذف'))])]),
      body: Column(children: [Expanded(child: Center(child: GestureDetector(onTap: _play, child: Stack(alignment: Alignment.center, children: [
        if (p != null && p.value.isInitialized) AspectRatio(aspectRatio: p.value.aspectRatio, child: VideoPlayer(p)) else Image.file(File(widget.item.imagePath), fit: BoxFit.contain),
        if (!_playing) Container(width: 66, height: 66, decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(40)), child: const Icon(Icons.play_arrow, size: 44)),
        Positioned(top: 14, left: 14, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)), child: const Row(children: [Icon(Icons.motion_photos_on, size: 17), SizedBox(width: 6), Text('LIVE')]))),
      ])))),
      Padding(padding: const EdgeInsets.fromLTRB(18, 12, 18, 28), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _EffectButton(icon: Icons.play_circle_outline, label: 'Live', selected: !_loop && !_bounce, onTap: () => setState(() { _loop = false; _bounce = false; })),
        _EffectButton(icon: Icons.all_inclusive, label: 'Loop', selected: _loop, onTap: () { setState(() { _loop = true; _bounce = false; }); _player?.setLooping(true); _play(); }),
        _EffectButton(icon: Icons.swap_horiz, label: 'Bounce', selected: _bounce, onTap: () { setState(() { _bounce = true; _loop = false; }); _play(); }),
      ]))]),
    );
  }
}

class _EffectButton extends StatelessWidget {
  final IconData icon; final String label; final bool selected; final VoidCallback onTap;
  const _EffectButton({required this.icon, required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: selected ? accent : Colors.white70, size: 28), const SizedBox(height: 5), Text(label, style: TextStyle(color: selected ? accent : Colors.white70))]));
}