class HeroModel {
  final String name;
  final String coin;
  final String image;
  final String description;

  HeroModel({
    required this.name,
    required this.coin,
    required this.image,
    required this.description,
  });

  factory HeroModel.fromMap(Map<String, dynamic> map) {
    return HeroModel(
      name: map['name'] ?? '',
      coin: map['coin'] ?? '',
      image: map['image'] ?? '',
      description: map['description'] ?? '',
    );
  }
}

final List<HeroModel> mockHeroes = [
  HeroModel(
    name: 'Mr. I Gusti Ketut Pudja',
    coin: 'Koin Rp 1.000 (2016)',
    image: 'https://upload.wikimedia.org/wikipedia/commons/thumb/1/1a/I_Gusti_Ketut_Pudja.jpg/400px-I_Gusti_Ketut_Pudja.jpg',
    description: 'Pahlawan Nasional dari Bali yang ikut serta dalam perumusan naskah proklamasi dan menjadi Gubernur Sunda Kecil pertama.',
  ),
  HeroModel(
    name: 'Letjen TNI T.B. Simatupang',
    coin: 'Koin Rp 500 (2016)',
    image: 'https://upload.wikimedia.org/wikipedia/commons/thumb/c/ca/T.B._Simatupang_1950s.jpg/400px-T.B._Simatupang_1950s.jpg',
    description: 'Tahi Bonar Simatupang adalah tokoh militer Indonesia yang pernah menjabat sebagai Kepala Staf Angkatan Perang Republik Indonesia (KSAP) setelah Jenderal Sudirman wafat.',
  ),
  HeroModel(
    name: 'Dr. Tjipto Mangoenkoesoemo',
    coin: 'Koin Rp 200 (2016)',
    image: 'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d3/Tjipto_Mangoenkoesoemo.jpg/400px-Tjipto_Mangoenkoesoemo.jpg',
    description: 'Salah satu dari "Tiga Serangkai" yang mendirikan Indische Partij dan aktif berjuang melawan penjajahan Belanda.',
  ),
  HeroModel(
    name: 'Prof. Dr. Ir. Herman Johannes',
    coin: 'Koin Rp 100 (2016)',
    image: 'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Herman_Johannes.jpg/400px-Herman_Johannes.jpg',
    description: 'Seorang cendekiawan, ilmuwan, dan pahlawan nasional Indonesia yang pernah menjabat sebagai Menteri Pekerjaan Umum.',
  ),
];
