import 'package:apula/screens/app/settings/account_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:apula/widgets/custom_bottom_nav.dart';
import 'package:provider/provider.dart';
import 'package:apula/providers/theme_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SettingsPage extends StatefulWidget {
  final List<String> availableDevices;

  const SettingsPage({super.key, required this.availableDevices});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedIndex = 3;
  String? _userName;
  String? _userEmail;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        setState(() {
          _userName = "Guest User";
          _userEmail = "Not logged in";
          _isLoading = false;
        });
        return;
      }

      final userEmail = currentUser.email;
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: userEmail)
          .limit(1)
          .get();

      if (userSnapshot.docs.isNotEmpty) {
        final userData = userSnapshot.docs.first.data();
        setState(() {
          _userName = userData['name'] ?? "Unknown";
          _userEmail = userData['email'] ?? "No email";
          _isLoading = false;
        });
      } else {
        setState(() {
          _userName = "Unknown User";
          _userEmail = userEmail;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("❌ Error fetching user data: $e");
      setState(() {
        _userName = "Error loading user";
        _userEmail = "";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    const redColor = Color(0xFFA30000);

    final gradientColors = isDarkMode
        ? [Colors.black, redColor]
        : [redColor, Colors.black];
    final titleColor = Colors.white;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : Colors.white,
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔙 Back Button
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 10),
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(shape: BoxShape.circle),
                    child: Icon(
                      Icons.chevron_left,
                      size: 30,
                      color: titleColor,
                    ),
                  ),
                ),
              ),

              // 🏷️ Title
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 5),
                child: Text(
                  "Settings",
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 50),

              // ⚪ Rounded Container
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.grey[900] : Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(25),
                          topRight: Radius.circular(25),
                        ),
                        border: const Border(
                          top: BorderSide(color: redColor, width: 3),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          vertical: 70,
                          horizontal: 20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 🧍 User Info
                            _isLoading
                                ? const CircularProgressIndicator(
                                    color: redColor,
                                  )
                                : Column(
                                    children: [
                                      Text(
                                        _userName ?? "Unknown User",
                                        style: const TextStyle(
                                          color: redColor,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _userEmail ?? "",
                                        style: TextStyle(
                                          color: isDarkMode
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                            const SizedBox(height: 35),

                            // ⚙️ Settings List
                            _buildThemeModeTile(context),
                            _buildSettingsTile(
                              isDarkMode,
                              Icons.notifications_none_outlined,
                              "Notifications",
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/notifsettings_page',
                              ),
                            ),
                            _buildSettingsTile(
                              isDarkMode,
                              Icons.account_circle_outlined,
                              "Account Settings",
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/account_settings',
                              ),
                            ),
                            _buildSettingsTile(
                              isDarkMode,
                              Icons.info_outline,
                              "About",
                              onTap: () =>
                                  Navigator.pushNamed(context, '/about'),
                            ),
                            _buildSettingsTile(
                              isDarkMode,
                              Icons.logout,
                              "Log Out",
                              onTap: () {
                                FirebaseAuth.instance.signOut();
                                Navigator.pushNamedAndRemoveUntil(
                                  context,
                                  '/login',
                                  (route) => false,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 👤 Profile Picture
                    Positioned(
                      top: -55,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            const CircleAvatar(
                              radius: 55,
                              backgroundImage: AssetImage(
                                'assets/examples/profile_pic.jpg',
                              ),
                              backgroundColor: Colors.transparent,
                            ),
                            Positioned(
                              bottom: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isDarkMode
                                      ? Colors.grey[850]
                                      : Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 3,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  size: 18,
                                  color: redColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // 🔻 Bottom Nav
      bottomNavigationBar: CustomBottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
        availableDevices: widget.availableDevices,
      ),
    );
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/live');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/notifications');
        break;
      case 3:
        break;
    }
  }

  Widget _buildSettingsTile(
    bool isDarkMode,
    IconData icon,
    String title, {
    VoidCallback? onTap,
  }) {
    const redColor = Color(0xFFA30000);
    final tileColor = isDarkMode ? Colors.grey[850] : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final iconColor = isDarkMode ? Colors.white : redColor;
    final borderColor = isDarkMode
        ? Colors.grey[700]!
        : const Color(0xFFE0E0E0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDarkMode
                ? Colors.black.withOpacity(0.4)
                : Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: borderColor),
      ),
      child: ListTile(
        leading: Icon(icon, color: iconColor, size: 26),
        title: Text(
          title,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: isDarkMode ? Colors.white70 : Colors.grey,
        ),
        onTap: onTap ?? () {},
      ),
    );
  }

  Widget _buildThemeModeTile(BuildContext context) {
    const redColor = Color(0xFFA30000);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    final tileColor = isDarkMode ? Colors.grey[850] : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final iconColor = isDarkMode ? Colors.white : redColor;
    final borderColor = isDarkMode
        ? Colors.grey[700]!
        : const Color(0xFFE0E0E0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: isDarkMode
                ? Colors.black.withOpacity(0.4)
                : Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(
          isDarkMode ? Icons.dark_mode : Icons.light_mode,
          color: iconColor,
          size: 26,
        ),
        title: Text(
          isDarkMode ? "Dark Mode" : "Light Mode",
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Switch(
          value: isDarkMode,
          activeColor: redColor,
          onChanged: (value) {
            themeProvider.toggleTheme(value);
          },
        ),
      ),
    );
  }
}
