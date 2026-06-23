const admin = require("firebase-admin");
const fs = require("fs/promises");
const path = require("path");

function usage() {
  console.log(
    "Usage: node export-firestore.js <serviceAccountKey.json> <output.json>",
  );
}

function normalizeValue(value) {
  if (value === null || value === undefined) {
    return value;
  }

  if (Array.isArray(value)) {
    return value.map(normalizeValue);
  }

  if (Buffer.isBuffer(value)) {
    return {
      __type: "buffer",
      base64: value.toString("base64"),
    };
  }

  if (typeof value === "object") {
    const constructorName = value.constructor ? value.constructor.name : "";

    if (
      constructorName === "Timestamp" ||
      (typeof value.toDate === "function" &&
        typeof value.seconds === "number" &&
        typeof value.nanoseconds === "number")
    ) {
      return {
        __type: "timestamp",
        seconds: value.seconds,
        nanoseconds: value.nanoseconds,
      };
    }

    if (
      constructorName === "GeoPoint" ||
      (typeof value.latitude === "number" && typeof value.longitude === "number")
    ) {
      return {
        __type: "geopoint",
        latitude: value.latitude,
        longitude: value.longitude,
      };
    }

    if (constructorName === "DocumentReference" && typeof value.path === "string") {
      return {
        __type: "documentReference",
        path: value.path,
      };
    }

    if (constructorName === "FieldValue") {
      return {
        __type: "fieldValue",
      };
    }

    const output = {};
    for (const [key, nestedValue] of Object.entries(value)) {
      output[key] = normalizeValue(nestedValue);
    }
    return output;
  }

  return value;
}

async function exportDocument(documentSnapshot) {
  const data = documentSnapshot.data() || {};
  const subcollections = await documentSnapshot.ref.listCollections();

  const exportedSubcollections = {};
  for (const subcollection of subcollections) {
    const querySnapshot = await subcollection.get();
    exportedSubcollections[subcollection.id] = await Promise.all(
      querySnapshot.docs.map(exportDocument),
    );
  }

  return {
    id: documentSnapshot.id,
    path: documentSnapshot.ref.path,
    data: normalizeValue(data),
    subcollections: exportedSubcollections,
  };
}

async function main() {
  const [, , serviceAccountPath, outputPath] = process.argv;

  if (!serviceAccountPath || !outputPath) {
    usage();
    process.exitCode = 1;
    return;
  }

  const resolvedServiceAccountPath = path.resolve(serviceAccountPath);
  const resolvedOutputPath = path.resolve(outputPath);
  const serviceAccount = JSON.parse(
    await fs.readFile(resolvedServiceAccountPath, "utf8"),
  );

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }

  const db = admin.firestore();
  const collections = await db.listCollections();
  const backup = {
    exportedAt: new Date().toISOString(),
    projectId: serviceAccount.project_id || null,
    collections: {},
  };

  for (const collection of collections) {
    const querySnapshot = await collection.get();
    backup.collections[collection.id] = await Promise.all(
      querySnapshot.docs.map(exportDocument),
    );
  }

  await fs.writeFile(resolvedOutputPath, JSON.stringify(backup, null, 2));
  console.log(`Exported Firestore data to ${resolvedOutputPath}`);
}

main().catch((error) => {
  console.error("Firestore export failed:");
  console.error(error);
  process.exitCode = 1;
});