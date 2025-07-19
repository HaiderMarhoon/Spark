import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart'; // Needed for @required


Future<void> populateElectricityDataForMonth({
  required FirebaseFirestore firestore,
  required int year,
  required int month,
  required String userId,
  required String deviceId,
  int readingsPerHour = 1, // Generate one reading per hour by default
  Function(String)? onProgress,
  Function(String)? onError,
}) async {
  final Random random = Random();
  final CollectionReference usageCollection = firestore.collection('usage_data');
  final int daysInMonth = DateTime(year, month + 1, 0).day;

  if (readingsPerHour < 1) readingsPerHour = 1;
  final int minutesIncrement = 60 ~/ readingsPerHour;

  print('Starting data population for $year-$month...');
  onProgress?.call('Starting data population for $year-$month...');

  try {
    // Use batch writes for better performance
    WriteBatch batch = firestore.batch();
    int batchCounter = 0;
    const int batchLimit = 400; // Firestore batch limit is 500, stay safe

    for (int day = 1; day <= daysInMonth; day++) {
      final DateTime currentDay = DateTime(year, month, day);
      final bool isWeekend = currentDay.weekday == DateTime.saturday ||
          currentDay.weekday == DateTime.sunday;

      // --- Daily Pattern ---
      // Base daily usage slightly lower on weekdays
      double baseHourlyRate = isWeekend ? 0.3 : 0.2; // kWh per hour base
      // Add some random daily variation
      baseHourlyRate += random.nextDouble() * 0.1 - 0.05; // +/- 0.05 kWh/hr

      for (int hour = 0; hour < 24; hour++) {
        for (int readingIndex = 0; readingIndex < readingsPerHour; readingIndex++) {
          final int minute = readingIndex * minutesIncrement;
          final DateTime timestamp = DateTime(year, month, day, hour, minute);

          double currentReading = baseHourlyRate / readingsPerHour; // Base for this interval

          // --- Time-of-Day Peak (e.g., evening) ---
          if (hour >= 18 && hour < 22) { // 6 PM to 10 PM peak
            currentReading += (isWeekend ? 0.6 : 0.4) / readingsPerHour; // Higher peak on weekends
          }
          // --- Morning small peak ---
          else if (hour >= 7 && hour < 9) { // 7 AM to 9 AM
            currentReading += 0.15 / readingsPerHour;
          }

          // --- Add Random Noise ---
          currentReading += random.nextDouble() * 0.1 / readingsPerHour - 0.05 / readingsPerHour; // +/- noise

          // Ensure usage is not negative
          currentReading = max(0.01, currentReading); // Minimum small usage

          // --- Create Data Map ---
          final Map<String, dynamic> data = {
            'deviceId': deviceId,
            'time': Timestamp.fromDate(timestamp), // Use Firestore Timestamp
            'type': 'electricity',
            'unit': 'kWh',
            'userId': userId,
            'value': double.parse(currentReading.toStringAsFixed(3)), // Round to 3 decimal places
          };

          // Add to batch
          batch.set(usageCollection.doc(), data); // Auto-generate document ID
          batchCounter++;

          // Commit batch if limit reached
          if (batchCounter >= batchLimit) {
            print('Committing batch ($batchCounter documents)...');
            await batch.commit();
            print('Batch committed.');
            // Start a new batch
            batch = firestore.batch();
            batchCounter = 0;
            // Small delay to avoid hitting rate limits aggressively
            await Future.delayed(const Duration(milliseconds: 200));
          }
        } // End readings per hour loop
      } // End hour loop

      print('Processed Day $day/$daysInMonth');
      onProgress?.call('Processed Day $day/$daysInMonth');

    } // End day loop

    // Commit any remaining documents in the last batch
    if (batchCounter > 0) {
      print('Committing final batch ($batchCounter documents)...');
      await batch.commit();
      print('Final batch committed.');
    }

    print('--- Population Complete for $year-$month ---');
    onProgress?.call('Population Complete for $year-$month');

  } catch (e, s) {
    print('--- ERROR during data population ---');
    print('Error: $e');
    print('Stack Trace: $s');
    print('------------------------------------');
    onError?.call('Error during population: $e');
  }
}
