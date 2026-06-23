import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apula/main.dart' show currentRouteName, hasPopupRoute, navigatorKey;
import 'package:apula/services/global_alert_handler.dart';
import 'package:apula/utils/app_palette.dart';

class GlobalManualAlertButton extends StatefulWidget {
  final bool inline;
  final bool compactCircle;
  final bool forceShowOnHome;
  final double compactSize;

  const GlobalManualAlertButton({
    super.key,
    this.inline = false,
    this.compactCircle = false,
    this.forceShowOnHome = false,
    this.compactSize = 142,
  });

  @override
  State<GlobalManualAlertButton> createState() => _GlobalManualAlertButtonState();
}

class _GlobalManualAlertButtonState extends State<GlobalManualAlertButton> {
  bool _sending = false;
  bool _isRetryingQueue = false;
  Timer? _retryTimer;

  static const Duration _manualAlertCooldown = Duration(seconds: 45);
  static const Duration _retryInterval = Duration(seconds: 30);
  static const String _queuePrefsKey = 'manual_alert_queue';
  static const String _cooldownPrefsKey = 'manual_alert_last_sent_ms';

  static const List<String> _reasons = [
    'Fire got out of hand',
    'Smoke inside house',
    'Gas leak smell',
    'Electrical fire risk',
    'Other emergency',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(_flushQueuedAlerts);
    _retryTimer = Timer.periodic(_retryInterval, (_) {
      _flushQueuedAlerts();
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        currentRouteName,
        hasPopupRoute,
        GlobalAlertHandler.modalOpenListenable,
      ]),
      builder: (context, _) {
        if (FirebaseAuth.instance.currentUser == null) {
          return const SizedBox.shrink();
        }

        final routeName = currentRouteName.value;
        final fallbackRouteName = ModalRoute.of(
              navigatorKey.currentContext ?? context,
            )
            ?.settings
            .name;
        final effectiveRouteName = routeName ?? fallbackRouteName;

        final hideForRoute = effectiveRouteName == '/' ||
            effectiveRouteName == '/login' ||
            effectiveRouteName == '/register' ||
            effectiveRouteName == '/verification' ||
            ((effectiveRouteName == null || effectiveRouteName == '/home') &&
                !widget.forceShowOnHome);
        final hideForPopup = hasPopupRoute.value;
        final hideForGlobalAlert = GlobalAlertHandler.hasActiveModal;

        if (hideForRoute || hideForPopup || hideForGlobalAlert) {
          return const SizedBox.shrink();
        }

        final bottomInset = MediaQuery.of(context).padding.bottom;
        final button = widget.compactCircle
            ? _buildCompactCircleButton(context)
            : _buildExtendedButton();

        if (widget.inline) {
          return button;
        }

        return Positioned(
          right: 16,
          bottom: 86 + bottomInset,
          child: button,
        );
      },
    );
  }

  Widget _buildExtendedButton() {
    return FloatingActionButton.extended(
      heroTag: widget.inline ? null : 'global_manual_alert_btn',
      backgroundColor: const Color(0xFFA30000),
      foregroundColor: Colors.white,
      onPressed: _sending ? null : _openManualAlertModal,
      icon: const Icon(Icons.warning_amber_rounded),
      label: const Text('Emergency Alert'),
    );
  }

  Widget _buildCompactCircleButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final outerSize = widget.compactSize;
    final ringSize = outerSize - 6;
    final centerSize = outerSize * 0.69;
    final iconWrapSize = outerSize * 0.24;
    final iconSize = outerSize * 0.14;
    final dotSize = outerSize * 0.042;
    final ringStroke = outerSize * 0.07;
    final ringBase = isDark ? Colors.white24 : const Color(0xFFE8D6D6);
    final ringGradient = SweepGradient(
      startAngle: -1.35,
      endAngle: 4.2,
      colors: const [
        Color(0xFFFFC0C0),
        Color(0xFFFF6A6A),
        Color(0xFFCC1F1F),
      ],
    );

    return SizedBox(
      width: outerSize,
      height: outerSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: ringSize,
            height: ringSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFCC1F1F).withOpacity(0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: CustomPaint(
              painter: _RingPainter(
                baseColor: ringBase,
                gradient: ringGradient,
                progress: 0.78,
                strokeWidth: ringStroke,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _sending ? null : _openManualAlertModal,
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: centerSize,
                height: centerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.32 : 0.14),
                      blurRadius: 13,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _sending
                    ? Padding(
                        padding: EdgeInsets.all(outerSize * 0.22),
                        child: const CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: iconWrapSize,
                            height: iconWrapSize,
                            decoration: const BoxDecoration(
                              color: Color(0xFFCC1F1F),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.white,
                              size: iconSize,
                            ),
                          ),
                          SizedBox(height: outerSize * 0.04),
                          Text(
                            'SOS',
                            style: const TextStyle(
                              color: Color(0xFFB11A1A),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              letterSpacing: 0.35,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          Positioned(
            left: outerSize * 0.18,
            bottom: outerSize * 0.2,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(isDark ? 0.5 : 0.85),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  BuildContext? _dialogContext() {
    return navigatorKey.currentState?.overlay?.context ??
        navigatorKey.currentContext;
  }

  Future<void> _openManualAlertModal() async {
    final rootContext = _dialogContext();
    if (rootContext == null) return;
    if (hasPopupRoute.value || GlobalAlertHandler.hasActiveModal) return;

    final remainingCooldown = await _remainingCooldown();
    if (remainingCooldown != null) {
      await showDialog<void>(
        context: rootContext,
        builder: (context) => AlertDialog(
          title: const Text('Please Wait'),
          content: Text(
            'Manual alert is on cooldown. Try again in ${remainingCooldown.inSeconds}s.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    String selectedReason = _reasons.first;
    String selectedLocationSource = 'house';
    String? currentLocationAddress;
    double? currentLatitude;
    double? currentLongitude;
    bool isFetchingCurrentLocation = false;
    final detailsController = TextEditingController();
    XFile? pickedImage;

    final shouldSend = await showDialog<bool>(
      context: rootContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final accent = const Color(0xFFA30000);

            return AlertDialog(
              title: const Text('Manual Emergency Alert'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select the reason for this emergency report:',
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedReason,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Reason',
                      ),
                      items: _reasons
                          .map(
                            (reason) => DropdownMenuItem<String>(
                              value: reason,
                              child: Text(reason),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          selectedReason = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Alert location source:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('House Address'),
                          selected: selectedLocationSource == 'house',
                          onSelected: (_) {
                            setModalState(() {
                              selectedLocationSource = 'house';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Current Location'),
                          selected: selectedLocationSource == 'current',
                          onSelected: (_) {
                            setModalState(() {
                              selectedLocationSource = 'current';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (selectedLocationSource == 'current')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedButton.icon(
                            icon: isFetchingCurrentLocation
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.my_location),
                            label: Text(
                              isFetchingCurrentLocation
                                  ? 'Getting location...'
                                  : 'Use Current Location',
                            ),
                            onPressed: isFetchingCurrentLocation
                                ? null
                                : () async {
                                    setModalState(() {
                                      isFetchingCurrentLocation = true;
                                    });

                                    final result = await _resolveCurrentLocation();

                                    if (!mounted) return;

                                    setModalState(() {
                                      isFetchingCurrentLocation = false;
                                      if (result != null) {
                                        currentLocationAddress = result['address'] as String;
                                        currentLatitude = result['lat'] as double;
                                        currentLongitude = result['lng'] as double;
                                      }
                                    });
                                  },
                          ),
                          const SizedBox(height: 6),
                          Text(
                            currentLocationAddress ??
                                'No current location selected yet.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: detailsController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Additional details (optional)',
                        hintText: 'Type what is happening right now...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Take Picture'),
                            onPressed: () async {
                              final picked = await ImagePicker().pickImage(
                                source: ImageSource.camera,
                                imageQuality: 75,
                                maxWidth: 1280,
                              );
                              if (picked == null) return;
                              setModalState(() {
                                pickedImage = picked;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    if (pickedImage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.photo_camera, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Photo attached: ${pickedImage!.name}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            setModalState(() {
                              pickedImage = null;
                            });
                          },
                          child: const Text('Remove picture'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : accent,
                  ),
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    FocusManager.instance.primaryFocus?.unfocus();
                    await Future.delayed(const Duration(milliseconds: 80));

                    if (selectedLocationSource == 'current' &&
                        (currentLocationAddress == null ||
                            currentLatitude == null ||
                            currentLongitude == null)) {
                      final fetched = await _resolveCurrentLocation();
                      if (fetched != null) {
                        currentLocationAddress = fetched['address'] as String;
                        currentLatitude = fetched['lat'] as double;
                        currentLongitude = fetched['lng'] as double;
                      }
                    }

                    if (selectedLocationSource == 'current' &&
                        (currentLocationAddress == null ||
                            currentLatitude == null ||
                            currentLongitude == null)) {
                      ScaffoldMessenger.of(rootContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Current location is required for this alert. Tap "Use Current Location" and wait for success before sending.',
                          ),
                        ),
                      );
                      return;
                    }

                    final confirm = await showDialog<bool>(
                      context: rootContext,
                      useRootNavigator: true,
                      builder: (confirmContext) => AlertDialog(
                        title: const Text('Confirm Send'),
                        content: const Text(
                          'Send this manual emergency alert to admin/dispatcher now?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(confirmContext, false),
                            child: const Text('No'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(confirmContext, true),
                            child: const Text('Yes, Send'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      Navigator.pop(dialogContext, true);
                    }
                  },
                  child: const Text('Send'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSend == true) {
      await _sendManualAlert(
        reason: selectedReason,
        details: detailsController.text.trim(),
        imagePath: pickedImage?.path,
        locationSource: selectedLocationSource,
        currentLocationAddress: currentLocationAddress,
        currentLatitude: currentLatitude,
        currentLongitude: currentLongitude,
      );
    }

    detailsController.dispose();
  }

  Future<void> _sendManualAlert({
    required String reason,
    required String details,
    required String? imagePath,
    required String locationSource,
    required String? currentLocationAddress,
    required double? currentLatitude,
    required double? currentLongitude,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final rootContext = _dialogContext();
    if (rootContext == null) return;

    final remainingCooldown = await _remainingCooldown();
    if (remainingCooldown != null) {
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(
          content: Text(
            'Manual alert cooldown: ${remainingCooldown.inSeconds}s remaining.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _sending = true;
    });

    final queueItem = {
      'reason': reason,
      'details': details,
      'imagePath': imagePath ?? '',
      'locationSource': locationSource,
      'currentLocationAddress': currentLocationAddress ?? '',
      'currentLatitude': currentLatitude,
      'currentLongitude': currentLongitude,
      'createdAt': DateTime.now().toIso8601String(),
    };

    try {
      await _sendQueueItem(queueItem, user);
      await _setCooldownNow();

      if (!mounted) return;
      await showDialog<void>(
        context: rootContext,
        builder: (context) => AlertDialog(
          title: const Text('Alert Sent'),
          content: const Text(
            'Alert successful. Emergency personnel alerted.',
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA30000),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      await _enqueueManualAlert(queueItem);

      if (!mounted) return;
      await showDialog<void>(
        context: rootContext,
        builder: (context) => AlertDialog(
          title: const Text('Queued For Retry'),
          content: Text(
            'Could not send now. Your manual alert was saved and will retry automatically.\n\nError: $e',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _sendQueueItem(
    Map<String, dynamic> queueItem,
    User user,
  ) async {
    final userQuery = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: user.email)
        .limit(1)
        .get();

    final userData =
        userQuery.docs.isNotEmpty ? userQuery.docs.first.data() : <String, dynamic>{};

    String imageBase64 = '';
    String snapshotEncodeError = '';
    final rawImagePath = (queueItem['imagePath'] ?? '').toString();
    if (rawImagePath.isNotEmpty) {
      final file = File(rawImagePath);
      if (await file.exists()) {
        try {
          final bytes = await file.readAsBytes();
          imageBase64 = base64Encode(bytes);
        } catch (e) {
          // Do not block emergency alert delivery if image encoding fails.
          snapshotEncodeError = e.toString();
          imageBase64 = '';
        }
      }
    }

    final reason = (queueItem['reason'] ?? 'Other emergency').toString();
    final details = (queueItem['details'] ?? '').toString();
    final locationSource = (queueItem['locationSource'] ?? 'house').toString();
    final currentLocationAddress =
      (queueItem['currentLocationAddress'] ?? '').toString();
    final currentLatitude = (queueItem['currentLatitude'] as num?)?.toDouble();
    final currentLongitude = (queueItem['currentLongitude'] as num?)?.toDouble();
    final useCurrentLocation =
      locationSource == 'current' &&
      currentLocationAddress.isNotEmpty &&
      currentLatitude != null &&
      currentLongitude != null;

    final alertLocation = useCurrentLocation
      ? currentLocationAddress
      : (userData['address'] ?? 'Unknown Location').toString();
    final alertLatitude = useCurrentLocation
      ? currentLatitude
      : (userData['latitude'] as num?)?.toDouble() ?? 0;
    final alertLongitude = useCurrentLocation
      ? currentLongitude
      : (userData['longitude'] as num?)?.toDouble() ?? 0;
    final messagePrefix = 'User used the alert manually.';
    final detailsLine = details.isEmpty ? '' : ' Details: $details';

    await FirebaseFirestore.instance.collection('alerts').add({
      'type': '🚨 MANUAL PANIC ALERT',
      'location': alertLocation,
      'description': '$messagePrefix Reason: $reason.$detailsLine',
      'manualAlert': true,
      'triggerMethod': 'manual_button',
      'source': 'manual',
      'sourceLabel': 'Manual User Trigger',
      'dominantSource': 'manual',
      'reportedReason': reason,
      'reportedDetails': details,
      'locationSource': useCurrentLocation ? 'current' : 'house',
      'queuedCreatedAt': queueItem['createdAt'],
      'snapshotBase64': imageBase64,
      'snapshotEncodeError': snapshotEncodeError,
      'status': 'Pending',
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
      'userId': user.uid,
      'userEmail': user.email,
      'userName': userData['name'] ?? 'Unknown',
      'userAddress': alertLocation,
      'userContact': userData['contact'] ?? 'N/A',
      'userLatitude': alertLatitude,
      'userLongitude': alertLongitude,
    });
  }

  Future<Map<String, dynamic>?> _resolveCurrentLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showRootSnackBar('Location services are turned off.');
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showRootSnackBar('Location permission is required to use current location.');
        return null;
      }

      // Fast path: use recent, accurate last known position when available.
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (_isRecentAndAccurate(lastKnown)) {
        final address = await _resolveAddressForPosition(lastKnown!);
        return {
          'address': address,
          'lat': lastKnown.latitude,
          'lng': lastKnown.longitude,
        };
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      final resolvedAddress = await _resolveAddressForPosition(position);

      return {
        'address': resolvedAddress,
        'lat': position.latitude,
        'lng': position.longitude,
      };
    } catch (e) {
      _showRootSnackBar('Could not get current location: $e');
      return null;
    }
  }

  bool _isRecentAndAccurate(Position? position) {
    if (position == null) return false;

    final timestamp = position.timestamp;
    final age = timestamp == null
        ? const Duration(days: 1)
        : DateTime.now().difference(timestamp);
    final isRecent = age <= const Duration(minutes: 3);
    final isAccurateEnough = position.accuracy <= 80;

    return isRecent && isAccurateEnough;
  }

  Future<String> _resolveAddressForPosition(Position position) async {
    String resolvedAddress =
        'Lat ${position.latitude.toStringAsFixed(6)}, Lng ${position.longitude.toStringAsFixed(6)}';

    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 2));

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final pieces = [
          p.name,
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
          p.postalCode,
        ]
            .where((part) => part != null && part!.trim().isNotEmpty)
            .cast<String>()
            .toList();
        if (pieces.isNotEmpty) {
          resolvedAddress = pieces.join(', ');
        }
      }
    } catch (_) {
      // Keep coordinate fallback if reverse geocoding fails or times out.
    }

    return resolvedAddress;
  }

  void _showRootSnackBar(String message) {
    final rootContext = _dialogContext();
    if (rootContext == null) return;
    ScaffoldMessenger.of(rootContext).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _enqueueManualAlert(Map<String, dynamic> queueItem) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_queuePrefsKey) ?? <String>[];
    existing.add(jsonEncode(queueItem));
    await prefs.setStringList(_queuePrefsKey, existing);
  }

  Future<void> _flushQueuedAlerts() async {
    if (_isRetryingQueue) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _isRetryingQueue = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawItems = prefs.getStringList(_queuePrefsKey) ?? <String>[];
      if (rawItems.isEmpty) return;

      final remaining = <String>[];
      for (final raw in rawItems) {
        try {
          final item = jsonDecode(raw);
          if (item is! Map<String, dynamic>) {
            continue;
          }
          await _sendQueueItem(item, user);
        } catch (_) {
          remaining.add(raw);
        }
      }

      await prefs.setStringList(_queuePrefsKey, remaining);
    } finally {
      _isRetryingQueue = false;
    }
  }

  Future<void> _setCooldownNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_cooldownPrefsKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<Duration?> _remainingCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSent = prefs.getInt(_cooldownPrefsKey);
    if (lastSent == null) return null;

    final elapsed = DateTime.now().millisecondsSinceEpoch - lastSent;
    final remainingMs = _manualAlertCooldown.inMilliseconds - elapsed;
    if (remainingMs <= 0) return null;
    return Duration(milliseconds: remainingMs);
  }
}

class _RingPainter extends CustomPainter {
  final Color baseColor;
  final Gradient gradient;
  final double progress;
  final double strokeWidth;

  _RingPainter({
    required this.baseColor,
    required this.gradient,
    required this.progress,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - strokeWidth) / 2;

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..color = baseColor;

    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth
      ..shader = gradient.createShader(rect);

    canvas.drawCircle(center, radius, basePaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.35,
      6.28 * progress,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gradient != gradient;
  }
}
