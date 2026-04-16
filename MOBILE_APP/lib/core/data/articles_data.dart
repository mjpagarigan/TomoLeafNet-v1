/// Article Data Model
class ArticleModel {
  final String title;
  final String source;
  final String url;
  final String topic;
  final String summary;
  final String audience; // "Beginner", "Intermediate", "Expert"
  final String coverImageUrl;

  /// Video tutorials open a lightweight YouTube placeholder instead of
  /// a bundled offline player, which helps keep the APK smaller.
  final bool isVideo;

  const ArticleModel({
    required this.title,
    required this.source,
    required this.url,
    required this.topic,
    required this.summary,
    required this.audience,
    required this.coverImageUrl,
    this.isVideo = false,
  });
}

// To add a new article, append a new ArticleModel to the list below.
// Required fields: title, source, url, topic, summary, audience, coverImageUrl
// Run flutter pub get after adding new local asset images to pubspec.yaml

final List<ArticleModel> hardcodedArticles = [
  const ArticleModel(
    title: "Collecting Disease Samples in the Philippines",
    source: "AVRDC / WorldVeg",
    url: "https://avrdc.org/collecting-disease-samples-in-the-philippines/",
    topic: "Visual Identification & Philippines Context",
    summary:
        "Discusses tomato disease sampling in Philippine farms, covering fungal, bacterial, and viral diseases with local production area context from UPLB and regional partners.",
    audience: "Intermediate",
    coverImageUrl: "assets/articles/philippines_farming_cover.jpg",
  ),
  const ArticleModel(
    title: "Iba't Ibang Uri ng Sakit sa Kamatis",
    source: "YouTube",
    url: "https://youtu.be/Mq1_FH8kSR8?si=NzRlBIc_JkxC2H74",
    topic: "Visual Identification & Philippines Context",
    summary:
        "Isang panimulang gabay sa mga karaniwang sakit na maaaring maranasan sa pagtatanim ng kamatis — kasama ang mga palatandaan at paraan ng pag-iwas.",
    audience: "Intermediate",
    coverImageUrl: "assets/articles/default_tomato_cover.jpg",
    isVideo: true,
  ),
  const ArticleModel(
    title: "Tomato Farming Video Tutorial",
    source: "YouTube",
    url: "https://youtu.be/OldrAt_jIs4?si=Ip3YXPZoPv9ck5Li",
    topic: "Step-by-step treatment; prevention",
    summary:
        "Practical tomato-growing video guide from YouTube. Tap to watch the tutorial outside the app.",
    audience: "Intermediate",
    coverImageUrl: "assets/articles/philippines_farming_cover.jpg",
    isVideo: true,
  ),
  const ArticleModel(
    title: "Tomato Care Video Tutorial",
    source: "YouTube",
    url: "https://youtu.be/5AhbXxKHvrY?si=dwnDsZy9T8t2LauD",
    topic: "How environmental factors affect tomato leaf health",
    summary:
        "Another practical YouTube tutorial for tomato growers, opened as a lightweight video placeholder instead of an offline file.",
    audience: "Intermediate",
    coverImageUrl: "assets/articles/philippines_farming_cover.jpg",
    isVideo: true,
  ),
  const ArticleModel(
    title: "Inventory and incidence of plant diseases affecting vegetables in Visayas and Mindanao",
    source: "Visayas State University",
    url: "https://atr.vsu.edu.ph/article/view/167",
    topic: "Visual identification",
    summary: "Philippine survey documenting tomato diseases such as bacterial canker, target spot, Septoria leaf spot, and wilt.",
    audience: "Intermediate",
    coverImageUrl: "assets/articles/default_tomato_cover.jpg",
  ),
  const ArticleModel(
    title: "Dapat Mong Gawin sa Pagtanim ng Kamatis",
    source: "YouTube",
    url: "https://youtu.be/Ge5YAX1m-3g?si=J5oE48al2tIEsgba",
    topic: "Prevention tips and best farming practices",
    summary: "Mga pangunahing hakbang at tamang paraan sa pagtatanim ng kamatis para sa masaganang ani.",
    audience: "Beginner",
    coverImageUrl: "assets/articles/philippines_farming_cover.jpg",
    isVideo: true,
  ),
  const ArticleModel(
    title: "Pathogenic and genetic variability of Ralstonia solanacearum in the Philippines",
    source: "UPLB",
    url: "https://www.ukdr.uplb.edu.ph/journal-articles/36/",
    topic: "Causes and explanation; treatment",
    summary: "Local study on bacterial wilt pathogens affecting tomato and other crops in the Philippines.",
    audience: "Expert",
    coverImageUrl: "assets/articles/default_tomato_cover.jpg",
  ),
  const ArticleModel(
    title: "Development of tomato yellow leaf curl virus detection kit",
    source: "DOST-PCAARRD",
    url: "https://www.pcaarrd.dost.gov.ph/index.php/quick-information-dispatch-qid-articles/development-of-tomato-yellow-leaf-curl-virus-detection-kit/",
    topic: "Detection; prevention",
    summary: "Philippine government research update on TYLCV detection, highly relevant to local disease-response programs.",
    audience: "Intermediate",
    coverImageUrl: "assets/articles/philippines_farming_cover.jpg",
  ),
  const ArticleModel(
    title: "Mabisang Spray para Iwas Leaf Miner at Leaf Blight",
    source: "YouTube",
    url: "https://youtu.be/oEmY2aHUuoA?si=IF2w5dJaQXOA8W-q",
    topic: "Step-by-step treatment",
    summary: "Paano gumawa at gumamit ng epektibong spray laban sa leaf miner at leaf blight sa kamatis.",
    audience: "Intermediate",
    coverImageUrl: "assets/articles/default_tomato_cover.jpg",
    isVideo: true,
  ),
  const ArticleModel(
    title: "Paano Magtanim ng Kamatis sa Plastic Bottle",
    source: "YouTube",
    url: "https://youtu.be/Y31u7I4X4SU?si=5fvnzfsENbVe3nOZ",
    topic: "Prevention tips and best farming practices",
    summary: "Praktikal at tipid na paraan ng pagtatanim ng kamatis gamit ang recycled plastic bottles — perfect para sa maliliit na espasyo.",
    audience: "Beginner",
    coverImageUrl: "assets/articles/philippines_farming_cover.jpg",
    isVideo: true,
  ),
];
