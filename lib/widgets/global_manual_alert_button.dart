import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apula/main.dart' show currentRouteName, hasPopupRoute, navigatorKey;
import 'package:apula/services/global_alert_handler.dart';

class GlobalManualAlertButton extends StatefulWidget {
  const GlobalManualAlertButton({super.key});

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
        final hideForRoute = routeName == '/' ||
            routeName == '/login' ||
            routeName == '/register' ||
            routeName == '/verification';
        final hideForPopup = hasPopupRoute.value;
        final hideForGlobalAlert = GlobalAlertHandler.hasActiveModal;

        if (hideForRoute || hideForPopup || hideForGlobalAlert) {
          return const SizedBox.shrink();
        }

        final bottomInset = MediaQuery.of(context).padding.bottom;

        return Positioned(
          right: 16,
          bottom: 86 + bottomInset,
          child: FloatingActionButton.extended(
            heroTag: 'global_manual_alert_btn',
            backgroundColor: const Color(0xFFA30000),
            foregroundColor: Colors.white,
            onPressed: _sending ? null : _openManualAlertModal,
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('Emergency Alert'),
          ),
        );
      },
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
      );
    }

    detailsController.dispose();
  }

  Future<void> _sendManualAlert({
    required String reason,
    required String details,
    required String? imagePath,
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
    final messagePrefix = 'User used the alert manually.';
    final detailsLine = details.isEmpty ? '' : ' Details: $details';

    await FirebaseFirestore.instance.collection('alerts').add({
      'type': '🚨 MANUAL PANIC ALERT',
      'location': userData['address'] ?? 'Unknown Location',
      'description': '$messagePrefix Reason: $reason.$detailsLine',
      'manualAlert': true,
      'triggerMethod': 'manual_button',
      'source': 'manual',
      'sourceLabel': 'Manual User Trigger',
      'dominantSource': 'manual',
      'reportedReason': reason,
      'reportedDetails': details,
      'queuedCreatedAt': queueItem['createdAt'],
      'snapshotBase64': imageBase64,
      'snapshotEncodeError': snapshotEncodeError,
      'status': 'Pending',
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
      'userId': user.uid,
      'userEmail': user.email,
      'userName': userData['name'] ?? 'Unknown',
      'userAddress': userData['address'] ?? 'N/A',
      'userContact': userData['contact'] ?? 'N/A',
      'userLatitude': userData['latitude'] ?? 0,
      'userLongitude': userData['longitude'] ?? 0,
    });
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
