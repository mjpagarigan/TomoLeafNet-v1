import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark Theme Background
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Header ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        "Manila", // Mock Location
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, color: Colors.white),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        "25°C - 29°C",
                        style: GoogleFonts.poppins(color: Colors.grey),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.cloud, color: Colors.white),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 20),

              // --- Search Bar ---
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.green, width: 1.5),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.grey),
                    const SizedBox(width: 10),
                    Text(
                      "Search plants",
                      style: GoogleFonts.poppins(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // --- Action Cards ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildActionCard(
                      icon: Icons.camera_alt,
                      label: "Identify",
                      color: const Color(0xFF2C2C2C)),
                  _buildActionCard(
                      icon: Icons.medical_services,
                      label: "Diagnose",
                      color: const Color(0xFF2C2C2C),
                      highlight: true), // Gold icon
                  _buildActionCard(
                      icon: Icons.local_florist,
                      label: "My Garden",
                      color: const Color(0xFF2C2C2C)),
                ],
              ),
              const SizedBox(height: 30),

              // --- Trending Section ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: "Trending in ",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: "Manila",
                          style: GoogleFonts.poppins(
                            color: Colors.green, // Highlight color
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.more_horiz, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 15),

              // --- Trending List (Horizontal) ---
              SizedBox(
                height: 180,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildTrendingCard("China rose", "assets/china_rose.jpg"), // Placeholder
                    const SizedBox(width: 15),
                    _buildTrendingCard("Japanese camellia", "assets/camellia.jpg"), // Placeholder
                    const SizedBox(width: 15),
                    _buildTrendingCard("Tomato", "assets/tomato_leaf.jpg"), // Placeholder
                  ],
                ),
              ),

               const SizedBox(height: 30),

               // --- Plant Index ---
               Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                   RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: "Plant Index in ",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: "Manila",
                          style: GoogleFonts.poppins(
                            color: Colors.green, // Highlight color
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.more_horiz, color: Colors.grey),
                ],
              ),
               const SizedBox(height: 15),
              // --- Index Cards ---
              Row(
                children: [
                   _buildIndexCard("Native\nPlants", const Color(0xFFE8E0C5)),
                   const SizedBox(width: 10,),
                   _buildIndexCard("Toxic\nPlants", const Color(0xFFE8E0C5)),
                ],
              )

            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(
      {required IconData icon,
      required String label,
      required Color color,
      bool highlight = false}) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: highlight ? Colors.amber : Colors.green, // Highlight Diagnose
            size: 32,
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.grey[300],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendingCard(String title, String imagePath) {
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.grey, // Placeholder for image
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(15), topRight: Radius.circular(15)),
              ),
               // child: Image.asset(imagePath, fit: BoxFit.cover), // Uncomment when assets exist
               child: const Center(child: Icon(Icons.image, color: Colors.white24, size: 40)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              title,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

   Widget _buildIndexCard(String title, Color color) {
    return Container(
      width: 100,
      height: 100,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Center(
        child: Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.brown[900],
                fontWeight: FontWeight.bold,
                fontSize: 14
              ),
            ),
      )
    );
  }
}
