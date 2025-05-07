// lib/populate_water_data_may.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

// --- Configuration ---
const int year = 2025;
const int month = 5; // May

const String userId = "202108278"; // Keep your user ID or change if needed
const String? deviceId = null; // Optional: Set a specific device ID string if needed

// --- Realistic Water Hourly Usage Patterns (Liters per hour) ---
// Adjusted for typical household activities, ensuring minimum 2.0 L.
const Map<String, List<double>> hourlyWaterPattern = {
  'night': [2.0, 5.0],       // 00:00 - 05:59 (Minimum base: toilet flush, leaks)
  'morning_peak': [20.0, 100.0],// 06:00 - 09:59 (Showers, toilet, sinks)
  'daytime': [5.0, 30.0],     // 10:00 - 17:59 (Toilet, washing, maybe laundry/dishes)
  'evening_peak': [15.0, 90.0], // 18:00 - 22:59 (Cooking, dishes, toilet, maybe baths)
  'late_night': [2.0, 15.0],    // 23:00 - 23:59 (Tapering down, final flushes)
};
// --- End Configuration ---


// --- Firebase Config (Ensure these match your project) ---
// *** Use the same correct 'web' options from your Firebase project ***
const FirebaseOptions scriptFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyDY2cSLQvwnjz3qF7hMCE_GHMWkEj25w14', // KEEP YOURS
  appId: '1:283494879532:web:c7d20dc224ff0ecc2a5c89',   // KEEP YOURS
  messagingSenderId: '283494879532', // KEEP YOURS
  projectId: 'application-spark-74299', // KEEP YOURS
  authDomain: 'application-spark-74299.firebaseapp.com', // KEEP YOURS
  storageBucket: 'application-spark-74299.firebasestorage.app', // KEEP YOURS
  measurementId: 'G-R3X6H3ZY19', // KEEP YOURS
);
// --- End Firebase Config ---


final random = Random();

// Helper to get water usage range based on hour
List<double> _getWaterUsageRange(int hour) {
  if (hour >= 0 && hour < 6) return hourlyWaterPattern['night']!;
  if (hour >= 6 && hour < 10) return hourlyWaterPattern['morning_peak']!;
  if (hour >= 10 && hour < 18) return hourlyWaterPattern['daytime']!;
  if (hour >= 18 && hour < 23) return hourlyWaterPattern['evening_peak']!;
  if (hour == 23) return hourlyWaterPattern['late_night']!;
  // Default fallback (ensures minimum 2.0)
  return [2.0, 5.0];
}

void main() async {
  try {
    print("Initializing Firebase with explicit options...");
    // Ensure only one initialization if running scripts concurrently might happen
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: scriptFirebaseOptions,
      ).timeout(const Duration(seconds: 30));
      print("Firebase Initialized successfully.");
    } else {
      print("Firebase already initialized.");
    }
  } catch (e, s) {
    print("----------------------------------------");
    print("❌ Error initializing Firebase: $e");
    print("Stack trace:\n$s");
    print("----------------------------------------");
    print("🚨 Potential Checks:");
    print("   1. Verify `scriptFirebaseOptions` values are correct for your WEB setup in Firebase.");
    print("   2. Ensure Firestore is ENABLED in your Firebase project console.");
    print("   3. Check your internet connection.");
    print("   4. Check API key restrictions in Google Cloud Console (if any).");
    print("   5. Ensure dependencies (firebase_core, cloud_firestore) are in pubspec.yaml and `dart pub get` was run.");
    exit(1); // Exit script if Firebase fails to initialize
  }

  final firestore = FirebaseFirestore.instance;
  final collection = firestore.collection('usage_data'); // Same collection

  // --- Define start and end times for the whole month of May ---
  final startTime = DateTime(year, month, 1, 0, 0, 0); // May 1st, 00:00:00
  // End time is the beginning of the *next* month (June 1st) to include all of May 31st
  final endTime = DateTime(year, month + 1, 1, 0, 0, 0); // June 1st, 00:00:00

  var currentTime = startTime; // Start iteration at the beginning of May

  print("Generating HOURLY WATER data for ALL OF MAY $year");
  print("Data Range: $startTime (inclusive) to $endTime (exclusive)");
  print("Target Firestore collection: '${collection.path}'");
  print("Using User ID: $userId");
  if (deviceId != null) {
    print("Using Device ID: $deviceId");
  }
  print("--- Using Realistic Water usage patterns (min 2.0 L) ---");


  int recordsGenerated = 0;
  int batchCounter = 0;
  const int batchSize = 400; // Firestore batch limit is 500
  WriteBatch batch = firestore.batch();
  Stopwatch stopwatch = Stopwatch()..start(); // Time the operation

  try {
    while (currentTime.isBefore(endTime)) {
      // Get the usage range for the current hour
      List<double> range = _getWaterUsageRange(currentTime.hour);
      double minUsage = range[0];
      double maxUsage = range[1];

      // Generate a random value within the defined range for the hour
      double value = minUsage + random.nextDouble() * (maxUsage - minUsage);
      // Ensure the generated value is never less than the absolute minimum (2.0)
      value = max(2.0, value);

      // Prepare data map - WATER specific
      final data = <String, dynamic>{
        'time': Timestamp.fromDate(currentTime),
        'type': 'water',       // **** CHANGED ****
        'unit': 'L',           // **** CHANGED **** (Liters)
        'value': double.parse(value.toStringAsFixed(1)), // Round to 1 decimal for Liters
        'userId': userId,
        if (deviceId != null) 'deviceId': deviceId,
      };

      // Add to batch
      final docRef = collection.doc(); // Let Firestore generate the ID
      batch.set(docRef, data);
      recordsGenerated++;

      // Commit batch if full
      if (recordsGenerated % batchSize == 0) {
        batchCounter++;
        print("Committing batch #$batchCounter ($batchSize records, total: $recordsGenerated)...");
        await batch.commit().timeout(const Duration(seconds: 60)); // Add timeout to commit
        print("✅ Batch #$batchCounter committed.");
        batch = firestore.batch(); // Start a new batch
      }

      // Increment time by 1 HOUR for the next record
      currentTime = currentTime.add(const Duration(hours: 1));
    }

    // Commit any remaining records in the last batch
    final remainingRecords = recordsGenerated % batchSize;
    if (remainingRecords != 0) {
      batchCounter++;
      print("Committing final batch #$batchCounter ($remainingRecords records, total: $recordsGenerated)...");
      await batch.commit().timeout(const Duration(seconds: 60)); // Add timeout to commit
      print("✅ Final batch #$batchCounter committed.");
    }

    stopwatch.stop();
    print("\n--- WATER data generation complete! ---");
    print("📊 Total records generated for May $year: $recordsGenerated");
    print("⏱️ Total time: ${stopwatch.elapsed.inSeconds} seconds");

  } catch (e, s) {
    print("----------------------------------------");
    print("❌ Error during WATER data generation or batch commit: $e");
    print("Stack trace:\n$s");
    print("----------------------------------------");
    print("🚨 Potential Checks:");
    print("   1. Check Firestore Security Rules in your Firebase project console.");
    print("   2. Ensure the Firestore database exists and the region is selected.");
    print("   3. Check your internet connection stability.");
    print("   4. Verify the `scriptFirebaseOptions` are still correct.");
    print("   5. Is the collection path 'usage_data' correct?");
    exit(1); // Exit script on error during operation
  }
}
