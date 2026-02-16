const functions = require("firebase-functions");
const admin = require("firebase-admin");

// Initialize Firebase Admin SDK
admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

/**
 * Cloud Function: Triggered when a new alert is created in user_alerts collection
 * Sends FCM notification to the user's device
 */
exports.sendAlertNotificationOnCreate = functions.firestore
  .document("user_alerts/{alertId}")
  .onCreate(async (snap, context) => {
    const alert = snap.data();
    const userEmail = alert.userEmail;

    if (!userEmail) {
      console.log("⚠️ No userEmail in alert, skipping notification");
      return;
    }

    try {
      // Get user document to find FCM token
      const userSnapshot = await db
        .collection("users")
        .where("email", "==", userEmail)
        .limit(1)
        .get();

      if (userSnapshot.empty) {
        console.log(`⚠️ User not found for email: ${userEmail}`);
        return;
      }

      const userData = userSnapshot.docs[0].data();
      const fcmToken = userData.fcmToken;

      if (!fcmToken) {
        console.log(`⚠️ No FCM token for user: ${userEmail}`);
        return;
      }

      // Determine alert level (match GlobalAlertHandler thresholds)
      let title = "🔥 Fire Alert";
      let priority = "high";

      const severity = alert.severity || 0;
      const alertLevel = alert.alert || 0;

      if (severity >= 0.70 && alertLevel >= 0.80) {
        title = "🔴 EXTREME FIRE DANGER";
        priority = "high";
      } else if (severity >= 0.55 && alertLevel >= 0.75) {
        title = "🟠 IGNITION ANOMALY DETECTED";
        priority = "high";
      } else if (severity >= 0.40 && alertLevel >= 0.73) {
        title = "🟡 FIRE-LIKE ACTIVITY";
        priority = "normal";
      }

      const message = {
        token: fcmToken,
        notification: {
          title: title,
          body: `${alert.device || "Unknown"} | Severity: ${(severity * 100).toFixed(1)}%`,
        },
        data: {
          title: title,
          device: alert.device || "Unknown",
          severity: String(severity),
          alert: String(alertLevel),
          snapshotUrl: alert.snapshotUrl || "",
          type: alert.type || "FIRE_ALERT",
        },
        webpush: {
          priority: priority,
        },
        apns: {
          headers: {
            "apns-priority": priority === "high" ? "10" : "5",
          },
          aps: {
            badge: 1,
            sound: "default",
          },
        },
      };

      // Send notification
      const response = await messaging.send(message);
      console.log(
        `✅ Alert notification sent to ${userEmail} for ${alert.device}`,
      );
      console.log(`📱 Message ID: ${response}`);

      return response;
    } catch (error) {
      console.error(`❌ Error sending notification to ${userEmail}:`, error);
      throw error;
    }
  });

/**
 * Cloud Function: Update user's FCM token
 * Call this via Cloud Function when user logs in or token refreshes
 */
exports.updateFcmToken = functions.https.onCall(async (data, context) => {
  const { email, fcmToken } = data;

  if (!email || !fcmToken) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "email and fcmToken are required",
    );
  }

  try {
    // Find user by email
    const userSnapshot = await db
      .collection("users")
      .where("email", "==", email)
      .limit(1)
      .get();

    if (userSnapshot.empty) {
      throw new functions.https.HttpsError("not-found", "User not found");
    }

    const userDoc = userSnapshot.docs[0];
    await userDoc.ref.update({
      fcmToken: fcmToken,
      lastFcmUpdate: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`✅ FCM token updated for ${email}`);
    return { success: true, message: "FCM token updated" };
  } catch (error) {
    console.error("❌ Error updating FCM token:", error);
    throw new functions.https.HttpsError("internal", error.message);
  }
});
