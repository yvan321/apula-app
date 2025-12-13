// lib/screens/app/notification/notification_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  // DETAILS POPUP
  // ----------------------------------------------------------------------
  void _showDetails(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          data["device"] ?? "Fire Alert",
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
                await FirebaseFirestore.instance
                    .collection("user_alerts")
                    .doc(docId)
                    .update({"read": !data["read"]});

                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Delete Notification",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.red)),
              onTap: () async {
                await FirebaseFirestore.instance
                    .collection("user_alerts")
                    .doc(docId)
                    .delete();

                Navigator.pop(context);
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

    return GestureDetector(
      onTap: () => _showDetails(data),
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
                    data["device"] ?? "Fire Alert",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight:
                          unread ? FontWeight.bold : FontWeight.normal,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (data["timestamp"] ?? "").toString(),
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
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection("user_alerts")
                  .orderBy("timestamp", descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: red));
                }

                final docs = snap.data!.docs
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
