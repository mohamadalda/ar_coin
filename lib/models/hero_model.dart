class HeroModel {
  final Map<String, String> name;
  final Map<String, String> coin;
  final String image;
  final String audio; // Path ke file audio asset
  final Map<String, String> description;
  final List<String> keywords;
  final String label;

  HeroModel({
    required this.name,
    required this.coin,
    required this.image,
    required this.description,
    this.audio = '',
    this.keywords = const [],
    this.label = '',
  });

  // Helper untuk mengambil teks berdasarkan bahasa
  String getName(String lang) => name[lang] ?? name['id'] ?? '';
  String getCoin(String lang) => coin[lang] ?? coin['id'] ?? '';
  String getDescription(String lang) => description[lang] ?? description['id'] ?? '';
}

final List<HeroModel> mockHeroes = [
  HeroModel(
    name: {'id': 'Mr. I Gusti Ketut Pudja', 'en': 'Mr. I Gusti Ketut Pudja'},
    coin: {'id': 'Koin Rp 1.000 (2016)', 'en': 'Rp 1,000 Coin (2016)'},
    image: 'assets/images/pudja.jpg',
    audio: 'audio/pudja.mp3',
    description: {
      'id': 'Pahlawan Nasional dari Bali yang ikut serta dalam perumusan naskah proklamasi.',
      'en': 'National Hero from Bali who participated in the formulation of the proclamation text.'
    },
    keywords: ['1000', 'PUDJA', 'IGUSTI'],
    label: 'koin_1000',
  ),
  HeroModel(
    name: {'id': 'Letjen TNI T.B. Simatupang', 'en': 'Lt. Gen. T.B. Simatupang'},
    coin: {'id': 'Koin Rp 500 (2016)', 'en': 'Rp 500 Coin (2016)'},
    image: 'assets/images/simatupang.png',
    audio: 'audio/simatupang.mp3',
    description: {
      'id': 'Tokoh militer Indonesia yang pernah menjabat sebagai Kepala Staf Angkatan Perang.',
      'en': 'Indonesian military figure who served as the Chief of Staff of the Armed Forces.'
    },
    keywords: ['500', 'SIMATUPANG'],
    label: 'koin_500',
  ),
  HeroModel(
    name: {'id': 'Dr. Tjipto Mangoenkoesoemo', 'en': 'Dr. Tjipto Mangoenkoesoemo'},
    coin: {'id': 'Koin Rp 200 (2016)', 'en': 'Rp 200 Coin (2016)'},
    image: 'assets/images/tjipto.webp',
    audio: 'audio/tjipto.mp3',
    description: {
      'id': 'Salah satu dari "Tiga Serangkai" yang mendirikan Indische Partij.',
      'en': 'One of the "Three Sovereigns" who founded the Indische Partij.'
    },
    keywords: ['200', 'TJIPTO', 'MANGOENKOESOEMO'],
    label: 'koin_200',
  ),
  HeroModel(
    name: {'id': 'Prof. Dr. Ir. Herman Johannes', 'en': 'Prof. Dr. Herman Johannes'},
    coin: {'id': 'Koin Rp 100 (2016)', 'en': 'Rp 100 Coin (2016)'},
    image: 'assets/images/johannes.jpg',
    audio: 'audio/johannes.mp3',
    description: {
      'id': 'Seorang cendekiawan, ilmuwan, dan pahlawan nasional yang menjabat Menteri PU.',
      'en': 'A scholar, scientist, and national hero who served as Minister of Public Works.'
    },
    keywords: ['100', 'HERMAN', 'JOHANNES'],
    label: 'koin_100',
  ),
  HeroModel(
    name: {'id': 'Semar', 'en': 'Semar'},
    coin: {'id': 'Koin Perak Semar (Seri Wayang)', 'en': 'Silver Semar Coin (Puppet Series)'},
    image: 'assets/images/semar.jpg',
    audio: 'audio/semar.mp3',
    description: {
      'id': 'Tokoh punakawan utama yang dianggap penjelmaan dewa pembimbing kebenaran.',
      'en': 'Main Punakawan character considered the incarnation of a god guiding truth.'
    },
    keywords: ['TEMAN', 'PUNAKAWAN', 'SERIES'],
    label: 'semar',
  ),
];
