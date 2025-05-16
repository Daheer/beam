import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/material.dart';
import '../services/config.dart';
import '../services/snackbar_service.dart';

class UploadService {
  static final Dio _dio = Dio();

  /// Uploads an image file to Bytescale and returns the CDN URL
  static Future<String?> uploadImage(
    String imagePath, {
    required BuildContext context,
    Function(bool isLoading)? onLoadingChanged,
  }) async {
    if (imagePath.isEmpty) return null;

    try {
      if (onLoadingChanged != null) onLoadingChanged(true);

      // Get file information
      final File imageFile = File(imagePath);
      final String fileName = imageFile.path.split('/').last;
      final String mimeType = 'image/${fileName.split('.').last}';

      // Read file as bytes
      final bytes = await imageFile.readAsBytes();

      // Upload to Bytescale API
      final response = await _dio.post(
        'https://api.bytescale.com/v2/accounts/${AppConfig.bytescaleAccountId}/uploads/binary',
        data: bytes,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${AppConfig.bytescaleApiKey}',
            'Content-Type': mimeType,
          },
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Extract the file URL from the response
        final String fileUrl = response.data['fileUrl'];
        return fileUrl;
      } else {
        throw Exception('Failed to upload image: ${response.statusCode}');
      }
    } catch (e) {
      // Only show error in context if provided
      if (context.mounted) {
        SnackbarService.showError(
          context,
          message: 'Error uploading image: $e',
        );
      }
      return null;
    } finally {
      if (onLoadingChanged != null) onLoadingChanged(false);
    }
  }
}
