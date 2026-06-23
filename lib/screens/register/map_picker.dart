import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapPickerScreen extends StatefulWidget {
  final String? initialAddress;

  const MapPickerScreen({super.key, this.initialAddress});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();

  LatLng selected = const LatLng(14.5995, 120.9842); // Default Manila
  String readableAddress = "Fetching address...";
  bool _isResolvingAddress = false;
  bool _isSearchingAddress = false;
  bool _isGettingCurrentLocation = false;

  @override
  void initState() {
    super.initState();

    if (widget.initialAddress != null && widget.initialAddress!.isNotEmpty) {
      _searchController.text = widget.initialAddress!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchAddress();
      });
    }

    _reverseGeocode(selected);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    if (mounted) {
      setState(() => _isGettingCurrentLocation = true);
    }

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showMessage("Location services are disabled.");
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage("Location permission is required.");
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;

      setState(() {
        selected = LatLng(position.latitude, position.longitude);
      });

      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(selected, 17),
      );
      await _reverseGeocode(selected);
    } catch (_) {
      _showMessage("Unable to fetch current location right now.");
    } finally {
      if (mounted) {
        setState(() => _isGettingCurrentLocation = false);
      }
    }
  }

  Future<void> _reverseGeocode(LatLng pos) async {
    if (mounted) {
      setState(() => _isResolvingAddress = true);
    }

    try {
      final places = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );

      if (!mounted) return;

      if (places.isNotEmpty) {
        final p = places.first;
        final parts = [
          p.name,
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
          p.postalCode,
          p.country,
        ]
            .where((part) => part != null && part!.trim().isNotEmpty)
            .cast<String>()
            .toList();
        setState(() {
          readableAddress = parts.isNotEmpty
              ? parts.join(', ')
              : "Lat ${pos.latitude.toStringAsFixed(6)}, Lng ${pos.longitude.toStringAsFixed(6)}";
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

    try {
      final locations = await locationFromAddress(query);

      if (!mounted) return;

      if (locations.isNotEmpty) {
        final hit = locations.first;
        setState(() {
          selected = LatLng(hit.latitude, hit.longitude);
        });
        await _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(selected, 17),
        );
        await _reverseGeocode(selected);
      } else {
        _showMessage("No results found. Try a more complete address.");
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pick Location"),
        backgroundColor: const Color(0xFFA30000),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: selected,
              zoom: 16,
            ),
            mapType: MapType.normal,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onCameraIdle: () {
              _reverseGeocode(selected);
            },
            onCameraMove: (position) {
              selected = position.target;
            },
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
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: "Search address or place...",
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
                  onPressed:
                      _isGettingCurrentLocation ? null : _useCurrentLocation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA30000),
                  ),
                  child: _isGettingCurrentLocation
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
