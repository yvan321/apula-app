import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class MapPickerScreen extends StatefulWidget {
  final String? initialAddress;   // <-- FIXED

  const MapPickerScreen({super.key, this.initialAddress});   // <-- FIXED


  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  LatLng selected = LatLng(14.5995, 120.9842); // Default Manila
  String readableAddress = "Fetching address...";

  @override
  void initState() {
    super.initState();

    // If user typed an address before opening map
    if (widget.initialAddress != null && widget.initialAddress!.isNotEmpty) {
      _searchController.text = widget.initialAddress!;
      _searchAddress(); // auto search
    }

    _reverseGeocode(selected);
  }

  // 📌 Convert LatLng → Readable address
  Future<void> _reverseGeocode(LatLng pos) async {
    final url = Uri.parse(
        "https://nominatim.openstreetmap.org/reverse?lat=${pos.latitude}&lon=${pos.longitude}&format=json");

    final response = await http.get(url, headers: {
      "User-Agent": "ApulaApp/1.0"
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      setState(() {
        readableAddress = data["display_name"] ?? "Unknown location";
      });
    }
  }

  // 🔍 Search address in Bacoor/Cavite
  Future<void> _searchAddress() async {
    String query = _searchController.text.trim();
    if (query.isEmpty) return;

    final enhancedQuery = "$query, Bacoor, Cavite, Philippines";

    final url = Uri.parse(
        "https://nominatim.openstreetmap.org/search?q=$enhancedQuery&format=json&limit=1");

    final response = await http.get(url, headers: {
      "User-Agent": "ApulaApp/1.0"
    });

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data.isNotEmpty) {
        final lat = double.parse(data[0]["lat"]);
        final lon = double.parse(data[0]["lon"]);

        setState(() {
          selected = LatLng(lat, lon);
        });

        _mapController.move(selected, 17);
        _reverseGeocode(selected);
      } else {
        _showMessage("No results found. Try adding street or barangay.");
      }
    } else {
      _showMessage("Search failed. Check your internet.");
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pick Location"),
        backgroundColor: const Color(0xFFA30000),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              center: selected,
              zoom: 16,
              onPositionChanged: (pos, gesture) {
                if (gesture == true && pos.center != null) {
                  selected = pos.center!;
                  _reverseGeocode(selected);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: const ['a', 'b', 'c'],
              ),
            ],
          ),

          const Center(
            child: Icon(Icons.location_pin, size: 50, color: Colors.red),
          ),

          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Search address...",
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onSubmitted: (_) => _searchAddress(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _searchAddress,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA30000),
                  ),
                  child: const Icon(Icons.search, color: Colors.white),
                ),
              ],
            ),
          ),

          Positioned(
            bottom: 80,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                readableAddress,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),

          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA30000),
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.pop(context, {
                  "address": readableAddress,
                  "lat": selected.latitude,
                  "lng": selected.longitude,
                });
              },
              child: const Text(
                "Confirm Address",
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
