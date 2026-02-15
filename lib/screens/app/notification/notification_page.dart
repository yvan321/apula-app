// lib/screens/app/notification/notification_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class NotificationPage extends StatefulWidget {
  final List<String> availableDevices;

  const NotificationPage({
    super.key,
    required this.availableDevices,
  });

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  String _filter = "All";
  static const Color red = Color(0xFFA30000);

  // Format timestamp to readable string
  String _formatTimestamp(dynamic timestamp) {
    try {
      if (timestamp == null) return "Unknown time";
      
      DateTime dt;
      if (timestamp is Timestamp) {
        dt = timestamp.toDate();
      } else {
        return "Unknown time";
      }

      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) {
        return "Just now";
      } else if (diff.inMinutes < 60) {
        return "${diff.inMinutes}m ago";
      } else if (diff.inHours < 24) {
        return "${diff.inHours}h ago";
      } else if (diff.inDays < 7) {
        return "${diff.inDays}d ago";
      } else {
        return DateFormat("MMM d, h:mm a").format(dt);
      }
    } catch (e) {
      return "Unknown time";
    }
  }

  // Delete all alerts
  void _deleteAllAlerts() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Delete All Alerts?"),
        content: const Text(
          "This will permanently delete all alerts. This action cannot be undone.",
          style: TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              _performDeleteAll();
            },
            child: const Text("Delete All", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _performDeleteAll() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("User not authenticated"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      Query query = FirebaseFirestore.instance.collection("user_alerts");
      if (user.uid.isNotEmpty) {
        query = query.where('userId', isEqualTo: user.uid);
      } else if (user.email != null && user.email!.isNotEmpty) {
        query = query.where('userEmail', isEqualTo: user.email);
      }

      final querySnapshot = await query.get();

      if (querySnapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("No alerts to delete"),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("All alerts deleted successfully"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error deleting alerts: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ----------------------------------------------------------------------
  // FILTER HELPER
  // ----------------------------------------------------------------------
  bool _matchesFilter(Map<String, dynamic> doc) {
    final read = doc["read"] == true;

    if (_filter == "Unread") return !read;
    if (_filter == "Read") return read;
    return true; // All
  }

  // ----------------------------------------------------------------------
  // DETAILS POPUP (auto-mark as read)
  // ----------------------------------------------------------------------
  void _showDetails(String docId, Map<String, dynamic> data) async {
    // Mark as read when viewing
    if (!data["read"]) {
      try {
        await FirebaseFirestore.instance
            .collection("user_alerts")
            .doc(docId)
            .update({"read": true});
      } catch (e) {
        print("Error marking as read: $e");
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          data["deviceName"] ?? "Fire Alert",
          style: const TextStyle(color: red),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((data["snapshotUrl"] ?? "").toString().isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  data["snapshotUrl"],
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 10),
            Text("Severity: ${data["severity"] ?? 0}"),
            Text("Alert Score: ${data["alert"] ?? 0}"),
            const SizedBox(height: 10),
            const Text("Tap CLOSE to return."),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE", style: TextStyle(color: red)),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------------
  // BOTTOM OPTIONS MENU (mark read / unread / delete)
  // ----------------------------------------------------------------------
  void _showOptions(String docId, Map<String, dynamic> data) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(
                data["read"] ? Icons.mark_email_unread : Icons.mark_email_read,
                color: red,
              ),
              title: Text(
                data["read"] ? "Mark as Unread" : "Mark as Read",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: () async {
                try {
                  await FirebaseFirestore.instance
                      .collection("user_alerts")
                      .doc(docId)
                      .update({"read": !data["read"]});

                  Navigator.pop(context);
                } catch (e) {
                  Navigator.pop(context);
                  print("Error updating read status: $e");
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error: $e")),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Delete Notification",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red)),
              onTap: () async {
                try {
                  await FirebaseFirestore.instance
                      .collection("user_alerts")
                      .doc(docId)
                      .delete();

                  Navigator.pop(context);
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Alert deleted")),
                    );
                  }
                } catch (e) {
                  Navigator.pop(context);
                  print("Error deleting alert: $e");
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error deleting: $e")),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text("Cancel"),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------------
  // INDIVIDUAL TILE
  // ----------------------------------------------------------------------
  Widget _notifTile(String id, Map<String, dynamic> data) {
    final bool unread = data["read"] == false;

    return Dismissible(
      key: Key(id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) async {
        try {
          await FirebaseFirestore.instance
              .collection("user_alerts")
              .doc(id)
              .delete();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Alert deleted")),
            );
          }
        } catch (e) {
          print("Error deleting alert: $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Error: $e")),
            );
          }
        }
      },
      child: GestureDetector(
        onTap: () => _showDetails(id, data),
        onLongPress: () => _showOptions(id, data),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: unread ? red.withOpacity(0.10) : Colors.grey.shade900,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: unread ? red : Colors.grey.shade700),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.notifications, color: red, size: 28),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data["deviceName"] ?? "Fire Alert",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            unread ? FontWeight.bold : FontWeight.normal,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatTimestamp(data["timestamp"]),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),

              if (unread)
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                      color: red, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------------
  // UI
  // ----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("Alerts"),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: "Delete all alerts",
            onPressed: _deleteAllAlerts,
          ),
        ],
      ),

      body: Column(
        children: [
          // FILTER CHIPS
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              children: [
                _chip("All"),
                _chip("Unread"),
                _chip("Read"),
              ],
            ),
          ),

          // LIVE FIRESTORE STREAM
          Expanded(
            child: Builder(
              builder: (context) {
                final userEmail = FirebaseAuth.instance.currentUser?.email;
                
                if (userEmail == null) {
                  return const Center(
                    child: Text(
                      "Not logged in",
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection("user_alerts")
                      .orderBy("timestamp", descending: true)
                      .snapshots(),
                  builder: (context, snap) {
                    print("📊 StreamBuilder state: hasData=${snap.hasData}, hasError=${snap.hasError}, connectionState=${snap.connectionState}");
                    
                    if (snap.hasError) {
                      return Center(
                        child: Text(
                          "Error: ${snap.error}",
                          style: const TextStyle(color: Colors.red),
                        ),
                      );
                    }

                    if (!snap.hasData) {
                      return const Center(
                          child: CircularProgressIndicator(color: red));
                    }

                    // Filter by current user email in the app
                    final docs = snap.data!.docs
                        .where((d) {
                          final data = Map<String, dynamic>.from(d.data() as Map);
                          final docEmail = data['userEmail'] ?? data['email'] ?? '';
                          return docEmail == userEmail;
                        })
                        .where((d) => _matchesFilter(
                            Map<String, dynamic>.from(d.data() as Map)))
                        .toList();

                    if (docs.isEmpty) {
                      return const Center(
                        child: Text(
                          "No alerts found",
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final Map<String, dynamic> data =
                            Map<String, dynamic>.from(doc.data() as Map);
                        return _notifTile(doc.id, data);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------------
  // CHIP BUILDER
  // ----------------------------------------------------------------------
  Widget _chip(String label) {
    final bool selected = _filter == label;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = label),
      selectedColor: red,
      checkmarkColor: Colors.white,
      backgroundColor: Colors.grey.shade800,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.white70,
      ),
    );
  }
}
