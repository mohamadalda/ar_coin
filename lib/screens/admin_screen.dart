// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import '../models/hero_model.dart';
import '../utils/file_helper.dart';
import '../utils/firebase_service.dart';
import 'test_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  /// Daftar aset yang tersedia di dalam aplikasi, dibaca dari AssetManifest.
  /// Dipakai agar model 3D dan gambar rincian bisa DIPILIH, bukan menunggu
  /// penyelarasan dari assets yang baru jalan saat aplikasi dibuka ulang.
  List<String> _modelAssets = [];
  List<String> _infoImageAssets = [];
  List<String> _imageAssets = [];
  List<String> _audioAssets = [];

  @override
  void initState() {
    super.initState();
    _loadAssetLists();
  }

  Future<void> _loadAssetLists() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final keys = manifest.listAssets();
      if (!mounted) return;
      setState(() {
        _modelAssets = keys
            .where((k) => k.startsWith('assets/models/') && k.endsWith('.glb'))
            .toList()
          ..sort();
        _infoImageAssets = keys
            .where((k) =>
                k.startsWith('assets/images/') && k.contains('_info.'))
            .toList()
          ..sort();
        _imageAssets = keys
            .where((k) =>
                k.startsWith('assets/images/') && !k.contains('_info.'))
            .toList()
          ..sort();
        // Awalan 'assets/' SENGAJA dibuang di sini.
        //
        // Nilai audio disimpan tanpa awalan itu karena AudioPlayer memakai
        // AssetSource, yang menambahkannya sendiri — 'audio/Barong.mp3' akan
        // dibaca sebagai 'assets/audio/Barong.mp3'. Menyimpan jalur penuh
        // membuatnya dicari di 'assets/assets/audio/...' dan audionya diam
        // tanpa pesan apa pun. Model 3D dan gambar tidak begini: keduanya
        // memang disimpan dengan jalur penuh.
        _audioAssets = keys
            .where((k) => k.startsWith('assets/audio/'))
            .map((k) => k.substring('assets/'.length))
            .toList()
          ..sort();
      });
    } catch (e) {
      debugPrint('Gagal membaca daftar aset: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Pengaturan Hero'),
        backgroundColor: const Color(0xFF6A0DAD),
        actions: [
          // Status Firebase dibuat kasatmata. Jalan mundurnya ke penyimpanan
          // lokal sengaja senyap agar aplikasi tetap jalan, tapi tanpa penanda
          // ini tidak ada cara tahu data sedang tersimpan ke mana.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (FirebaseService.ready
                        ? Colors.greenAccent
                        : Colors.orangeAccent)
                    .withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                FirebaseService.ready ? 'Firebase' : 'Lokal',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: FirebaseService.ready
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Pengujian',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TestScreen()),
            ),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: mockHeroes.length,
        itemBuilder: (context, index) {
          final hero = mockHeroes[index];
          
          ImageProvider imageProvider;
          if (FileHelper.isLocalFile(hero.image)) {
            imageProvider = FileImage(File(FileHelper.resolve(hero.image)));
          } else {
            imageProvider = AssetImage(hero.image);
          }

          return Card(
            color: const Color(0xFF1E293B),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage: imageProvider,
                onBackgroundImageError: (_, __) {},
                child: const Icon(Icons.person, color: Colors.white24),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(hero.getName('id'),
                        style: const TextStyle(color: Colors.white),
                        overflow: TextOverflow.ellipsis),
                  ),
                  // Penanda model 3D. Sengaja hanya tampilan, bukan kolom yang
                  // bisa diedit: sumber model 3D adalah assets/heroes.json.
                  if (hero.model.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6A0DAD).withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('3D',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
              // Label ikut ditampilkan: dua hero boleh bernama sama, dan
              // label-lah satu-satunya pembedanya di daftar ini.
              subtitle: Text(
                hero.label.isEmpty
                    ? hero.getCoin('id')
                    : '${hero.getCoin('id')}  ·  ${hero.label}',
                style: const TextStyle(color: Colors.white70),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blueAccent),
                    onPressed: () => _showHeroForm(context, hero: hero, index: index),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () => _confirmDelete(context, index),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFD01B98),
        onPressed: () => _showHeroForm(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _confirmDelete(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Hapus Hero?', style: TextStyle(color: Colors.white)),
        content: const Text('Apakah Anda yakin ingin menghapus data hero ini?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final hero = mockHeroes[index];
              setState(() {
                mockHeroes.removeAt(index);
              });
              saveHeroes();
              await FileHelper.deleteLocalFile(hero.image);
              await FileHelper.deleteLocalFile(hero.audio);
              await FileHelper.deleteLocalFile(hero.model);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _showHeroForm(BuildContext context, {HeroModel? hero, int? index}) {
    final isEditing = hero != null;
    
    final nameIdCtrl = TextEditingController(text: hero?.name['id'] ?? '');
    final coinIdCtrl = TextEditingController(text: hero?.coin['id'] ?? '');
    final descIdCtrl = TextEditingController(text: hero?.description['id'] ?? '');
    final keywordsCtrl = TextEditingController(text: hero?.keywords.join(', ') ?? '');
    final labelCtrl = TextEditingController(text: hero?.label ?? '');

    String currentImage = hero?.image ?? '';
    String currentAudio = hero?.audio ?? '';
    String currentModel = hero?.model ?? '';
    String currentInfoImage = hero?.infoImage ?? '';
    String currentDisplayMode = hero?.displayMode ?? HeroModel.displayPanel;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEditing ? 'Edit Hero' : 'Tambah Hero',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(nameIdCtrl, 'Nama Pahlawan'),
                    _buildTextField(coinIdCtrl, 'Teks Koin'),
                    _buildTextField(descIdCtrl, 'Deskripsi Pahlawan', maxLines: 3),
                    _buildTextField(keywordsCtrl, 'Keywords (pisahkan dengan koma)'),
                    _buildTextField(labelCtrl, 'Label Model'),

                    // Pilihan tampilan saat hero terdeteksi. Hanya muncul bila
                    // hero punya model 3D — tanpa model, memilih '3D' cuma
                    // menghasilkan layar kosong.
                    _buildAssetPicker(
                      title: 'Model 3D',
                      value: currentModel,
                      options: _modelAssets,
                      onChanged: (v) =>
                          setModalState(() => currentModel = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    _buildAssetPicker(
                      title: 'Gambar rincian koin',
                      value: currentInfoImage,
                      options: _infoImageAssets,
                      onChanged: (v) =>
                          setModalState(() => currentInfoImage = v ?? ''),
                    ),
                    const SizedBox(height: 10),

                    // Selektor SELALU tampil, termasuk saat membuat hero baru.
                    // Dulu disembunyikan ketika model 3D belum ada — padahal
                    // hero baru memang belum punya: modelnya menempel kemudian
                    // dari assets begitu Label Model-nya cocok. Akibatnya
                    // pilihan ini tidak pernah bisa diatur saat membuat hero.
                    ...[
                      const Text('Tampilan saat terdeteksi',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildModeChip(
                            label: 'Keterangan saja',
                            icon: Icons.article_outlined,
                            selected:
                                currentDisplayMode == HeroModel.displayPanel,
                            onTap: () => setModalState(() =>
                                currentDisplayMode = HeroModel.displayPanel),
                          ),
                          const SizedBox(width: 8),
                          _buildModeChip(
                            label: '3D + keterangan',
                            icon: Icons.view_in_ar,
                            selected:
                                currentDisplayMode == HeroModel.displayBoth,
                            onTap: () => setModalState(() =>
                                currentDisplayMode = HeroModel.displayBoth),
                          ),
                        ],
                      ),
                      if (currentModel.isEmpty) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Model 3D belum menempel pada hero ini. Ia diambil '
                          'dari assets dan dicocokkan lewat Label Model, jadi '
                          'akan muncul setelah aplikasi dibuka ulang. Sampai '
                          'itu terjadi, tampilannya jatuh ke keterangan saja.',
                          style: TextStyle(
                              color: Colors.orangeAccent, fontSize: 11),
                        ),
                      ],
                    ],
                    const SizedBox(height: 10),
                    
                    // Media hero dipilih dari aset yang IKUT DI DALAM
                    // aplikasi, bukan diunggah dari perangkat.
                    //
                    // Tombol unggah dihapus karena menyesatkan: berkas yang
                    // diunggah hanya tersalin ke folder dokumen aplikasi di
                    // perangkat yang mengunggahnya, sementara yang tersimpan
                    // di Firestore cuma jalurnya. Di perangkat lain jalur itu
                    // menunjuk berkas yang tidak ada, pemutaran gagal diam-
                    // diam, dan hero tampak tidak bersuara tanpa sebab yang
                    // terlihat. Untuk menambah media baru, taruh berkasnya di
                    // assets/ lalu terbitkan versi baru aplikasinya.
                    _buildAssetPicker(
                      title: 'Gambar',
                      value: currentImage,
                      options: _imageAssets,
                      onChanged: (v) =>
                          setModalState(() => currentImage = v ?? ''),
                    ),
                    const SizedBox(height: 10),
                    _buildAssetPicker(
                      title: 'Audio',
                      value: currentAudio,
                      options: _audioAssets,
                      onChanged: (v) =>
                          setModalState(() => currentAudio = v ?? ''),
                    ),

                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        onPressed: () {
                          // Clean up if replaced original files (and they were local)
                          if (isEditing) {
                            if (currentImage != hero.image) {
                              FileHelper.deleteLocalFile(hero.image);
                            }
                            if (currentAudio != hero.audio) {
                              FileHelper.deleteLocalFile(hero.audio);
                            }
                          }

                          // Hanya simpan teks 'id' agar bahasa lain otomatis di-translate ulang
                          final newHero = HeroModel(
                            name: {'id': nameIdCtrl.text},
                            coin: {'id': coinIdCtrl.text},
                            image: currentImage,
                            audio: currentAudio,
                            model: currentModel,
                            infoImage: currentInfoImage,
                            displayMode: currentDisplayMode,
                            description: {'id': descIdCtrl.text},
                            keywords: keywordsCtrl.text.split(',').map((e) => e.trim().toUpperCase()).where((e) => e.isNotEmpty).toList(),
                            label: labelCtrl.text,
                          );

                          setState(() {
                            if (isEditing && index != null) {
                              mockHeroes[index] = newHero;
                            } else {
                              mockHeroes.add(newHero);
                            }
                          });
                          
                          saveHeroes();
                          Navigator.pop(ctx);
                        },
                        child: const Text('Simpan', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  /// Pemilih aset dari yang ter-bundle di aplikasi.
  ///
  /// Berupa daftar pilihan, bukan unggahan: berkas berat sengaja tetap di
  /// dalam aplikasi demi kecepatan muat dan agar tetap jalan tanpa jaringan.
  Widget _buildAssetPicker({
    required String title,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    // Nilai tersimpan yang tidak ada di daftar (mis. aset sudah dihapus)
    // tetap ditawarkan, supaya tidak hilang diam-diam saat form dibuka.
    final items = <String>{...options, if (value.isNotEmpty) value}.toList()
      ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value.isEmpty ? null : value,
              hint: const Text('(tidak ada)',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('(tidak ada)',
                      style: TextStyle(color: Colors.white38)),
                ),
                for (final a in items)
                  DropdownMenuItem<String>(
                    value: a,
                    child: Text(a.split('/').last,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF6A0DAD).withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFFD01B98) : Colors.white24,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected ? Colors.white : Colors.white54),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: selected ? Colors.white : Colors.white54)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFD01B98))),
        ),
      ),
    );
  }
}
