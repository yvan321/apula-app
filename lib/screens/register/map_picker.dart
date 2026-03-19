import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class MapPickerScreen extends StatefulWidget {
  final String? initialAddress;

  const MapPickerScreen({super.key, this.initialAddress});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  LatLng selected = LatLng(14.5995, 120.9842); // Default Manila
  String readableAddress = "Fetching address...";
  bool _isResolvingAddress = false;
  bool _isSearchingAddress = false;
  bool _isLocating = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();

    if (widget.initialAddress != null && widget.initialAddress!.isNotEmpty) {
      _searchController.text = widget.initialAddress!;
      _searchAddress();
    }

    _reverseGeocode(selected);
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    if (mounted) {
      setState(() => _isResolvingAddress = true);
    }

    final url = Uri.parse(
        "https://nominatim.openstreetmap.org/reverse?lat=${pos.latitude}&lon=${pos.longitude}&format=json");

    try {
      final response = await http.get(url, headers: {
        "User-Agent": "ApulaApp/1.0"
      });

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          readableAddress = (data["display_name"] ?? "Unknown location").toString();
        });
      } else {
        setState(() {
          readableAddress = "Unable to resolve address right now";
        });
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        readableAddress = "Unable to resolve address right now";
      });
    } finally {
      if (mounted) {
        setState(() => _isResolvingAddress = false);
      }
    }
  }

  Future<void> _searchAddress() async {
    String query = _searchController.text.trim();
    if (query.isEmpty) return;

    if (mounted) {
      setState(() => _isSearchingAddress = true);
    }

    final url = Uri.parse(
        "https://nominatim.openstreetmap.org/search?q=${Uri.encodeQueryComponent(query)}&format=json&limit=1");

    try {
      final response = await http.get(url, headers: {
        "User-Agent": "ApulaApp/1.0"
      });

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data is List && data.isNotEmpty) {
          final lat = double.parse(data[0]["lat"].toString());
          final lon = double.parse(data[0]["lon"].toString());

          setState(() {
            selected = LatLng(lat, lon);
          });

          _mapController.move(selected, 17);
          await _reverseGeocode(selected);
        } else {
          _showMessage("No results found. Try a more complete address.");
        }
      } else {
        _showMessage("Search is temporarily unavailable. Please try again.");
      }
    } catch (_) {
      _showMessage("Search failed right now. Please try again.");
    } finally {
      if (mounted) {
        setState(() => _isSearchingAddress = false);
      }
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _detectMyLocation() async {
    if (mounted) setState(() => _isLocating = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage("Location services are disabled. Please enable GPS.");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showMessage("Location permission denied.");
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showMessage("Location permission permanently denied. Enable it in Settings.");
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;

      final loc = LatLng(position.latitude, position.longitude);
      setState(() => selected = loc);
      _mapController.move(loc, 17);
      await _reverseGeocode(loc);
    } catch (e) {
      if (mounted) _showMessage("Could not detect location. Try again.");
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _debouncedReverseGeocode(LatLng pos) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      _reverseGeocode(pos);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
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
              initialCenter: selected,        // UPDATED
              initialZoom: 16,                // UPDATED
              onPositionChanged: (MapCamera camera, bool hasGesture) {
                if (hasGesture) {
                  selected = camera.center;
                  _debouncedReverseGeocode(selected);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.apula.location',
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
                  onPressed: _isSearchingAddress ? null : _searchAddress,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA30000),
                  ),
                  child: _isSearchingAddress
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.search, color: Colors.white),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLocating ? null : _detectMyLocation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  ),
                  child: _isLocating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.my_location, color: Colors.white),
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
                _isResolvingAddress ? "Resolving address..." : readableAddress,
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
                final address = readableAddress.trim();
                if (_isResolvingAddress ||
                    address.isEmpty ||
                    address == "Fetching address..." ||
                    address == "Unable to resolve address right now") {
                  _showMessage("Please wait for a valid address before confirming.");
                  return;
                }

                Navigator.pop(context, {
                  "address": address,
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
