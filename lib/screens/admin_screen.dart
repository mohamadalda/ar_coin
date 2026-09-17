import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/hero_model.dart';
import '../utils/file_helper.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Pengaturan Hero'),
        backgroundColor: const Color(0xFF6A0DAD),
      ),
      body: ListView.builder(
        itemCount: mockHeroes.length,
        itemBuilder: (context, index) {
          final hero = mockHeroes[index];
          
          ImageProvider imageProvider;
          if (FileHelper.isLocalFile(hero.image)) {
            imageProvider = FileImage(File(hero.image));
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
              title: Text(hero.getName('id'), style: const TextStyle(color: Colors.white)),
              subtitle: Text(hero.getCoin('id'), style: const TextStyle(color: Colors.white70)),
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
                    const SizedBox(height: 10),
                    
                    // Upload Image
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            currentImage.isEmpty ? 'Pilih Gambar...' : currentImage.split('/').last.split('\\').last,
                            style: const TextStyle(color: Colors.white70),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final result = await FilePicker.pickFile(type: FileType.image);
                            if (result?.path != null) {
                              final path = await FileHelper.saveFileLocally(File(result!.path!), 'img');
                              if (path != null) {
                                // Delete old local file if replaced
                                if (currentImage.isNotEmpty && currentImage != (hero?.image ?? '')) {
                                  FileHelper.deleteLocalFile(currentImage);
                                }
                                setModalState(() {
                                  currentImage = path;
                                });
                              }
                            }
                          },
                          icon: const Icon(Icons.image),
                          label: const Text('Upload'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6A0DAD)),
                        ),
                        if (currentImage.isNotEmpty)
                          IconButton(
                            tooltip: 'Hapus gambar',
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent),
                            onPressed: () {
                              // File yang baru diunggah dan belum disimpan langsung
                              // dibuang di sini. File milik hero lama tidak disentuh —
                              // pembersihannya sudah ditangani saat tombol Simpan.
                              if (currentImage != (hero?.image ?? '')) {
                                FileHelper.deleteLocalFile(currentImage);
                              }
                              setModalState(() => currentImage = '');
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Upload Audio
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            currentAudio.isEmpty ? 'Pilih Audio...' : currentAudio.split('/').last.split('\\').last,
                            style: const TextStyle(color: Colors.white70),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final result = await FilePicker.pickFile(type: FileType.audio);
                            if (result?.path != null) {
                              final path = await FileHelper.saveFileLocally(File(result!.path!), 'aud');
                              if (path != null) {
                                // Delete old local file if replaced
                                if (currentAudio.isNotEmpty && currentAudio != (hero?.audio ?? '')) {
                                  FileHelper.deleteLocalFile(currentAudio);
                                }
                                setModalState(() {
                                  currentAudio = path;
                                });
                              }
                            }
                          },
                          icon: const Icon(Icons.audiotrack),
                          label: const Text('Upload'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD01B98)),
                        ),
                        if (currentAudio.isNotEmpty)
                          IconButton(
                            tooltip: 'Hapus audio',
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.redAccent),
                            onPressed: () {
                              // File yang baru diunggah dan belum disimpan langsung
                              // dibuang di sini. File milik hero lama tidak disentuh —
                              // pembersihannya sudah ditangani saat tombol Simpan.
                              if (currentAudio != (hero?.audio ?? '')) {
                                FileHelper.deleteLocalFile(currentAudio);
                              }
                              setModalState(() => currentAudio = '');
                            },
                          ),
                      ],
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
                          if (isEditing && hero != null) {
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
