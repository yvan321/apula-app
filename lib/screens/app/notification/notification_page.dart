import 'package:flutter/material.dart';
import 'package:apula/widgets/custom_bottom_nav.dart';

class NotificationPage extends StatefulWidget {
  final List<String> availableDevices;

  const NotificationPage({super.key, required this.availableDevices});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  int _selectedIndex = 2;
  String _filter = "All";

  final List<Map<String, dynamic>> _notifications = [
    {
      "title": "Fire detected in CCTV 1",
      "time": "2 minutes ago",
      "read": false,
      "details":
          "A possible fire was detected in CCTV 1 (Building A). Please verify immediately and ensure safety protocols are followed.",
      "image": "assets/examples/fire_example.jpg",
    },
    {
      "title": "Smoke detected in CCTV 2",
      "time": "10 minutes ago",
      "read": true,
      "details":
          "Smoke was detected near CCTV 2 (Laboratory Area). This could indicate a nearby fire or system malfunction.",
      "image": "assets/examples/fire_example.jpg",
    },
    {
      "title": "High temperature in CCTV 3",
      "time": "30 minutes ago",
      "read": false,
      "details":
          "The temperature around CCTV 3 has exceeded normal limits. This may indicate overheating or an environmental hazard.",
      "image": "assets/examples/fire_example.jpg",
    },
  ];

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
        break;
      case 3:
        Navigator.pushReplacementNamed(context, '/settings');
        break;
    }
  }

  List<Map<String, dynamic>> get _filteredNotifications {
    if (_filter == "Read") {
      return _notifications.where((n) => n["read"] == true).toList();
    } else if (_filter == "Unread") {
      return _notifications.where((n) => n["read"] == false).toList();
    }
    return _notifications;
  }

  IconData _getNotificationIcon(String title) {
    if (title.toLowerCase().contains("fire")) {
      return Icons.local_fire_department_rounded;
    } else if (title.toLowerCase().contains("smoke")) {
      return Icons.smoking_rooms_rounded;
    } else if (title.toLowerCase().contains("temperature")) {
      return Icons.thermostat_rounded;
    } else {
      return Icons.notifications_active_rounded;
    }
  }

  // 🔥 Details dialog with image and Take Action button
  void _showNotificationDetails(Map<String, dynamic> notif) {
    const Color redColor = Color(0xFFA30000);

    setState(() {
      notif["read"] = true;
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(_getNotificationIcon(notif["title"]), color: redColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                notif["title"],
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: redColor),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🖼️ Image below header
              if (notif["image"] != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    notif["image"],
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              // 🔍 Details text
              Text(
                notif["details"] ?? "No additional details available.",
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 18, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    notif["time"],
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          // 🚨 Take Action button
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/live');
            },
            child: const Text(
              "Take Action",
              style: TextStyle(
                color: redColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Close",
              style: TextStyle(color: redColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showOptions(Map<String, dynamic> notif) {
    const Color redColor = Color(0xFFA30000);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(
                notif["read"]
                    ? Icons.mark_email_unread_rounded
                    : Icons.mark_email_read_rounded,
                color: redColor,
              ),
              title: Text(
                notif["read"] ? "Mark as Unread" : "Mark as Read",
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                setState(() {
                  notif["read"] = !notif["read"];
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: const Text(
                "Delete Notification",
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                setState(() {
                  _notifications.remove(notif);
                });
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text("Cancel"),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    const Color redColor = Color(0xFFA30000);

    return Scaffold(
      body: SafeArea(
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
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),

            // 📋 Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(
                "Notifications",
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // 🧭 Filter Chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 8,
                children: [
                  _buildFilterChip("All"),
                  _buildFilterChip("Unread"),
                  _buildFilterChip("Read"),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 🔔 Notification list
            Expanded(
              child: _filteredNotifications.isEmpty
                  ? _buildNoNotifications()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _filteredNotifications.length,
                      itemBuilder: (context, index) {
                        final notif = _filteredNotifications[index];
                        final bool isUnread = notif["read"] == false;

                        final bgColor = isUnread
                            ? redColor.withOpacity(0.1)
                            : (isDark
                                ? const Color(0xFF1C1C1E)
                                : Colors.grey.shade50);
                        final borderColor =
                            isUnread ? redColor : Colors.grey.shade300;
                        final titleColor = isUnread
                            ? redColor
                            : (isDark ? Colors.white : Colors.black87);
                        final subtitleColor =
                            isDark ? Colors.white60 : Colors.grey.shade700;

                        return GestureDetector(
                          onTap: () => _showNotificationDetails(notif),
                          onLongPress: () => _showOptions(notif),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: bgColor,
                              borderRadius: BorderRadius.circular(18),
                              border:
                                  Border.all(color: borderColor, width: 1.4),
                              boxShadow: [
                                if (!isDark)
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Dynamic icon
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _getNotificationIcon(notif["title"]),
                                    color: redColor,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Texts
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        notif["title"],
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: titleColor,
                                          fontWeight: isUnread
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        notif["time"],
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: subtitleColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                if (isUnread)
                                  Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: redColor,
                                      shape: BoxShape.circle,
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
      ),

      // 🔻 Bottom Nav
      bottomNavigationBar: CustomBottomNavBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
        availableDevices: widget.availableDevices,
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    return FilterChip(
      label: Text(label),
      selected: _filter == label,
      onSelected: (_) => setState(() => _filter = label),
      selectedColor: const Color(0xFFA30000),
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: _filter == label ? Colors.white : Colors.grey.shade800,
        fontWeight:
            _filter == label ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: Colors.grey.withOpacity(0.1),
    );
  }

  Widget _buildNoNotifications() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_rounded, size: 80, color: Colors.grey),
          SizedBox(height: 12),
          Text(
            "No notifications found",
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
