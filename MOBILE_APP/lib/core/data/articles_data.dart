/// Article Data Model
class ArticleModel {
  final String title;
  final String source;
  final String url;
  final String topic;
  final String summary;
  final String audience; // "Beginner", "Intermediate", "Expert"
  final String coverImageUrl;

  const ArticleModel({
    required this.title,
    required this.source,
    required this.url,
    required this.topic,
    required this.summary,
    required this.audience,
    required this.coverImageUrl,
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
    title: "Tomato Leaf Disease Image Dataset",
    source: "Bureau of Plant Industry — FOI Philippines",
    url:
        "https://www.foi.gov.ph/agencies/bpi/tomato-leaf-disease-image-dataset/",
    topic: "Visual Identification & Philippines Context",
    summary:
        "References field images of tomato leaf diseases from Philippine-grown varieties, directly relevant to local disease identification and monitoring.",
    audience: "Intermediate",
    coverImageUrl: "assets/articles/default_tomato_cover.jpg",
  ),
  const ArticleModel(
    title: "Effect of exogenous application of salicylic acid on the severity of tomato leaf curl disease",
    source: "UPLB",
    url: "https://www.ukdr.uplb.edu.ph/journal-articles/5630/",
    topic: "Step-by-step treatment; prevention",
    summary: "Local university study on reducing tomato leaf curl disease severity using salicylic acid. Useful for treatment and plant-defense discussions.",
    audience: "Expert",
    coverImageUrl: "assets/articles/philippines_farming_cover.jpg",
  ),
  const ArticleModel(
    title: "Development of weather-based empirical forecasting models for tomato leaf curl disease",
    source: "UPLB",
    url: "https://www.ukdr.uplb.edu.ph/journal-articles/154/",
    topic: "How environmental factors affect tomato leaf health",
    summary: "Philippine field study linking temperature, humidity, rainfall, wind, and whiteflies to disease incidence in Mindanao.",
    audience: "Expert",
    coverImageUrl: "assets/articles/philippines_farming_cover.jpg",
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
    title: "Tomato Profitable Crop in Philippines, Cultivated Worldwide",
    source: "Visayas State University",
    url: "https://atr.vsu.edu.ph/article/download/175/163",
    topic: "Prevention tips and best farming practices",
    summary: "Discusses tomato production constraints in the Philippines, including major diseases with management context.",
    audience: "Beginner",
    coverImageUrl: "assets/articles/philippines_farming_cover.jpg",
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
    title: "Environment-friendly fungicide against tomato black leaf mold",
    source: "DOST-PCAARRD",
    url: "https://www.pcaarrd.dost.gov.ph/index.php/quick-information-dispatch-qid-articles/environment-friendly-fungicide-against-tomato-black-leaf-mold/",
    topic: "Step-by-step treatment",
    summary: "Philippine research update on a biofungicide tested against tomato black leaf mold in Nueva Vizcaya.",
    audience: "Intermediate",
    coverImageUrl: "assets/articles/default_tomato_cover.jpg",
  ),
];
