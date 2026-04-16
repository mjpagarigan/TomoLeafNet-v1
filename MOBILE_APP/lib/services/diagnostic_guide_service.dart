class DiagnosticGuide {
  const DiagnosticGuide({
    required this.organism,
    required this.cause,
    required this.description,
    required this.remedies,
  });

  final String organism;
  final String cause;
  final String description;
  final List<String> remedies;
}

class DiagnosticGuideService {
  const DiagnosticGuideService._();

  static DiagnosticGuide? getGuide(String label, {required bool isFilipino}) {
    final languageMap = isFilipino ? _filipinoGuides : _englishGuides;
    return languageMap[label];
  }

  static List<String> getEnglishRemedies(String label) {
    return _englishGuides[label]?.remedies ?? const [];
  }

  static const Map<String, DiagnosticGuide> _englishGuides = {
    'Early_Blight': DiagnosticGuide(
      organism: 'Alternaria solani or A. linariae',
      cause:
          'Soilborne spores spread by wind, rain splash, and infected debris; thrives in warm, moist conditions.',
      description:
          'Dark brown circular spots with concentric rings ("target-like") on older leaves, followed by yellowing and defoliation. Lesions may also appear on stems and fruit near the stem end.',
      remedies: [
        'Apply fungicides such as chlorothalonil or mancozeb.',
        'Practice crop rotation to reduce carryover in the soil.',
        'Stake or support plants to improve airflow around the canopy.',
        'Remove infected leaves and dispose of them away from the field.',
        'Avoid wet foliage and prolonged leaf moisture.',
      ],
    ),
    'Leaf_Miner': DiagnosticGuide(
      organism: 'Tuta absoluta (South American tomato moth)',
      cause:
          'Adult moths lay eggs, and the larvae burrow into leaves, stems, buds, and fruit.',
      description:
          'Larvae create visible tunnels or "mines" inside leaves, stems, buds, and fruit. Severe infestations can cause up to 100% yield loss.',
      remedies: [
        'Use pheromone traps to monitor and reduce adult moth populations.',
        'Apply biological control options such as parasitoids or Bacillus thuringiensis.',
        'Use recommended insecticides such as spinosad or abamectin when needed.',
        'Remove and destroy infested plant material promptly.',
      ],
    ),
    'Leaf_Mold': DiagnosticGuide(
      organism: 'Passalora fulva (formerly Cladosporium fulvum)',
      cause:
          'High humidity above 85% and poor ventilation, especially in greenhouses or tunnels.',
      description:
          'Yellow spots appear on upper leaf surfaces while olive-green mold develops on the undersides. This is common in greenhouses or high tunnels with very high humidity.',
      remedies: [
        'Improve ventilation around the plants.',
        'Reduce humidity and avoid conditions that keep leaves damp.',
        'Apply fungicides such as chlorothalonil or copper products.',
        'Remove infected leaves to reduce disease spread.',
        'Use resistant tomato cultivars when available.',
      ],
    ),
  };

  static const Map<String, DiagnosticGuide> _filipinoGuides = {
    'Early_Blight': DiagnosticGuide(
      organism: 'Alternaria solani o A. linariae',
      cause:
          'Mga spores mula sa lupa na kumakalat dahil sa hangin, talsik ng ulan, at infected na debris; mabilis dumami sa mainit at basang kondisyon.',
      description:
          'Dark brown at pabilog na spots na parang target o concentric rings sa mga mas matatandang dahon, na sinusundan ng paninilaw at pagkalagas ng dahon. Maaari ring magkaroon ng lesions sa tangkay at bunga malapit sa tangkay.',
      remedies: [
        'Mag-spray ng fungicide tulad ng chlorothalonil o mancozeb.',
        'Mag-crop rotation upang mabawasan ang natitirang impeksiyon sa lupa.',
        'Lagyan ng tukod o suporta ang halaman para mas gumanda ang daloy ng hangin.',
        'Tanggalin at itapon ang mga infected na dahon sa malayo sa taniman.',
        'Iwasang laging basa ang mga dahon.',
      ],
    ),
    'Leaf_Miner': DiagnosticGuide(
      organism: 'Tuta absoluta (South American tomato moth)',
      cause:
          'Mangingitlog ang adult moth at ang mga uod o larvae ay papasok sa mga dahon, tangkay, usbong, at bunga.',
      description:
          'Ang mga uod ay gumagawa ng mga tunnels o "mines" sa loob ng mga dahon, tangkay, usbong, at bunga. Kapag malala, puwedeng masira ang hanggang 100% ng ani.',
      remedies: [
        'Gumamit ng pheromone traps para bantayan at bawasan ang adult moths.',
        'Magpatupad ng biological control tulad ng parasitoids o Bacillus thuringiensis.',
        'Gumamit ng angkop na insecticide tulad ng spinosad o abamectin kung kinakailangan.',
        'Tanggalin at sirain agad ang mga inatakeng bahagi ng halaman.',
      ],
    ),
    'Leaf_Mold': DiagnosticGuide(
      organism: 'Passalora fulva (dating Cladosporium fulvum)',
      cause:
          'Mataas na humidity na lampas 85% at mahinang bentilasyon, lalo na sa greenhouses o tunnels.',
      description:
          'May mga dilaw na spots sa ibabaw ng dahon at may olive-green na amag sa ilalim nito. Karaniwan ito sa mga greenhouse o high tunnel na may napakataas na humidity.',
      remedies: [
        'Pagandahin ang bentilasyon sa paligid ng mga halaman.',
        'Pababain ang humidity at iwasang manatiling mamasa ang mga dahon.',
        'Mag-spray ng fungicide tulad ng chlorothalonil o copper-based products.',
        'Tanggalin ang mga infected na dahon upang mabawasan ang pagkalat.',
        'Gumamit ng resistant na barayti ng kamatis kung mayroon.',
      ],
    ),
  };
}
