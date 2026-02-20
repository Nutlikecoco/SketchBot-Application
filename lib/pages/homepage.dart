import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'categorypage.dart';
import 'favorite.dart';
import 'profile.dart';
import 'save.dart';

class HomePage extends StatefulWidget {
  final List<String> favorites;
  final Function(String) onFavoriteToggle;

  const HomePage({
    Key? key,
    required this.favorites,
    required this.onFavoriteToggle,
  }) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int currentIndex = 0;
  late Set<String> favorites;
  Map<String, List<String>> categoryImages = {};

  // 🔹 Default assets
  final Map<String, List<String>> defaultAssets = {
    'Anime': [
      'assets/images/lufy.jpg',
      'assets/images/naruto.jpg',
      'assets/images/hoshina.jpg',
      'assets/images/chin.jpg',
      'assets/images/go.jpg',
      'assets/images/gojo.jpg',
      'assets/images/saitama.jpg',
      'assets/images/mob100.jpg',
    ],
    'Cartoon': [
      'assets/images/cartoon1.jpg',
      'assets/images/cartoon2.jpg',
      'assets/images/cartoon3.jpg',
      'assets/images/cartoon4.jpg',
    ],
    'Pet': [
      'assets/images/cat1.jpg',
      'assets/images/cat2.jpg',
      'assets/images/dog.jpg',
    ],
    'Capybara': [
      'assets/images/capybara_cake.jpg',
      'assets/images/capybara_mac.jpg',
      'assets/images/capybara_pudding.jpg',
    ],
    'Human': [
      'assets/images/h1.jpg',
      'assets/images/h2.jpg',
      'assets/images/h3.jpg',
    ],
  };

  @override
  void initState() {
    super.initState();
    favorites = widget.favorites.toSet();
    _loadUserImages();
  }

  void handleFavoriteToggle(String url) {
    setState(() {
      if (favorites.contains(url)) {
        favorites.remove(url);
      } else {
        favorites.add(url);
      }
    });
    widget.onFavoriteToggle(url);
  }

  final List<Map<String, dynamic>> categories = [
    {'title': 'My Self', 'image': 'assets/images/self.jpg'},
    {'title': 'Anime', 'image': 'assets/images/Anime1.jpg'},
    {'title': 'Cartoon', 'image': 'assets/images/anime.jpg'},
    {'title': 'Pet', 'image': 'assets/images/Cat.jpg'},
    {'title': 'Capybara', 'image': 'assets/images/Capybara.jpg'},
    {'title': 'Human', 'image': 'assets/images/h2.jpg'},
  ];

  // 🔹 โหลดภาพจาก Firestore
  Future<void> _loadUserImages() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.email) // ✅ ใช้ email แทน uid
        .collection('my_images')
        .get();

    if (!mounted) return;

    setState(() {
      try {
        categoryImages['My Self'] = snapshot.docs
            .map((doc) => (doc.data()['url'] as String?) ?? '')
            .where((url) => url.isNotEmpty)
            .toList();
      } catch (e) {
        debugPrint("❌ Error parsing user images: $e");
      }
    });
  }

  // 🔹 เพิ่มรูปจาก Gallery และอัปโหลดไป Firebase Storage
  Future<void> pickImageFromGallery() async {
    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);

    if (pickedFile == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final file = File(pickedFile.path);

    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg');
      final uploadTask = storageRef.putFile(file);
      await uploadTask.whenComplete(() => debugPrint("✅ Upload complete"));
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('my_images')
          .add({'url': downloadUrl});

      _loadUserImages();
    } catch (e) {
      debugPrint("❌ อัปโหลดรูปไม่สำเร็จ: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("อัปโหลดไม่สำเร็จ: $e")),
      );
    }
  }

  // 🔹 ส่วนแสดงหน้า Home + ช่องค้นหา
  Widget _buildMainHomeContent() {
    TextEditingController searchController = TextEditingController();
    String searchQuery = "";

    return StatefulBuilder(
      builder: (context, setInnerState) {
        final filteredCategories = categories.where((category) {
          final title = category['title'].toString().toLowerCase();
          return title.contains(searchQuery.toLowerCase());
        }).toList();

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔹 Banner
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF13208C), Color(0xFF4055C8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Choose the right image and let us draw it for you.\n\nเลือกภาพที่ใช่ของคุณ แล้วเริ่มวาดไปด้วยกัน",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.brush,
                      color: Colors.white.withOpacity(0.9),
                      size: 50,
                    ),
                  ],
                ),
              ),

              // 🔹 ปุ่ม Add Image + Search
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: pickImageFromGallery,
                      icon: const Icon(Icons.add_photo_alternate, size: 20),
                      label: const Text("Add Image"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF13208C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: "Search categories...",
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.grey[200],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) {
                          setInnerState(() {
                            searchQuery = value.trim();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
                child: Text(
                  "Categories",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),

              // 🔹 Categories GridView
              Padding(
                padding:
                    const EdgeInsets.only(left: 16, right: 16, bottom: 100),
                child: filteredCategories.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: Text(
                            "ไม่พบหมวดหมู่ที่ค้นหา 😢",
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      )
                    : GridView.builder(
                        itemCount: filteredCategories.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: 3 / 4,
                        ),
                        itemBuilder: (context, index) {
                          final category = filteredCategories[index];
                          final categoryName = category['title'].trim();

                          final List<String> images = [
                            ...(categoryName == "My Self"
                                ? (categoryImages['My Self'] ?? [])
                                : (defaultAssets[categoryName] ?? [])),
                          ];

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CategoryPage(
                                    category: categoryName,
                                    favorites: favorites,
                                    onFavoriteToggle: handleFavoriteToggle,
                                    images: images,
                                  ),
                                ),
                              );
                            },
                            child: Card(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 4,
                              clipBehavior: Clip.hardEdge,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: Image.asset(
                                      category['image'],
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Container(
                                    color:
                                        const Color.fromARGB(149, 38, 116, 212),
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      categoryName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.white,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Please log in first")),
      );
    }

    final uid = user.uid;

    final pages = [
      _buildMainHomeContent(),
      FavoritePage(
        favorites: favorites.toList(),
        onFavoriteToggle: handleFavoriteToggle,
      ),
      const SavePage(),
      const ProfilePage(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF13208C),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Text("Welcome");
            }
            final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
            final name = data['name'] ?? "Guest";
            final imageUrl = data['imageUrl'];

            return Row(
              children: [
                CircleAvatar(
                  key: ValueKey(imageUrl),
                  radius: 20,
                  backgroundImage: (imageUrl != null && imageUrl.isNotEmpty)
                      ? NetworkImage(imageUrl)
                      : null,
                  child: (imageUrl == null || imageUrl.isEmpty)
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Hello, $name!",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: IndexedStack(index: currentIndex, children: pages),
    );
  }
}
