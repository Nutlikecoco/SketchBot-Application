import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 🔹 import หน้าที่คุณมี
import 'favorite.dart';
import 'homepage.dart';
import 'save.dart';
import 'profile.dart';

class HomeScaffold extends StatefulWidget {
  const HomeScaffold({super.key});

  @override
  State<HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<HomeScaffold> {
  int currentIndex = 0;
  List<String> favorites = [];

  File? profileImage;
  String profileName = "Hello!";

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      favorites = prefs.getStringList('favorites') ?? [];
    });
  }

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites', favorites);
  }

  void toggleFavorite(String url) {
    setState(() {
      if (favorites.contains(url)) {
        favorites.remove(url);
      } else {
        favorites.add(url);
      }
    });
    _saveFavorites();
  }

  void updateProfile(File? newImage, String newName) {
    setState(() {
      profileImage = newImage;
      profileName = newName;
    });
  }

  // 🔹 หน้าที่จะสลับตาม bottom navigation
  List<Widget> get pages => [
        HomePage(
          favorites: favorites,
          onFavoriteToggle: toggleFavorite,
        ),
        FavoritePage(
          favorites: favorites,
          onFavoriteToggle: toggleFavorite,
        ),
        const SavePage(),
        const ProfilePage(),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed, // ✅ ใช้กับ 4 tabs
        currentIndex: currentIndex,
        selectedItemColor: Colors.indigo,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Favorite'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: 'Save'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}