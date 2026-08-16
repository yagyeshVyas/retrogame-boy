import 'package:flutter/material.dart';
import 'ui/discovery_screen.dart';

const Color kBg = Color(0xFF0D0D12);   // near-black
const Color kPurple = Color(0xFFA13BFF); // electric purple (face buttons)
const Color kCyan = Color(0xFF22D3EE);   // cyan (d-pad)
const Color kGreen = Color(0xFF3BFFB8);
const Color kAmber = Color(0xFFFFC23B);
const Color kInk = Color(0xFFEDEDF2);
const Color kMuted = Color(0xFF8A8A9E);

void main() {
  runApp(const RetroLanApp());
}

class RetroLanApp extends StatelessWidget {
  const RetroLanApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RetroLAN Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kPurple, surface: kBg),
        fontFamily: 'sans-serif', // rounded geometric system font
        useMaterial3: true,
        fontFamilyFallback: const ['Roboto'],
      ),
      home: const DiscoveryScreen(),
    );
  }
}
