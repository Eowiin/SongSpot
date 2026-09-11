import 'package:flutter/material.dart';
import 'app_theme.dart';

/// The colour a category is shown in, wherever it appears: the home screen's
/// genre row and the category grid.
Color categoryColor(String? category) => switch (category) {
      'pop' => const Color(0xFFE91E8C),
      'hiphop' => const Color(0xFF9C27B0),
      'rock' => const Color(0xFFE53935),
      'electro' => const Color(0xFF00BCD4),
      'dance' => const Color(0xFFFF9800),
      'rnb' => const Color(0xFF795548),
      'kpop' => const Color(0xFFEC407A),
      'rap_fr' => const Color(0xFF3F51B5),
      'variete_fr' => const Color(0xFF009688),
      'latino' => const Color(0xFFFF5722),
      'disco' => const Color(0xFF4CAF50),
      'afrobeats' => const Color(0xFFFFC107),
      'jpop' => const Color(0xFFF48FB1),
      'bollywood' => const Color(0xFFFF7043),
      _ => AppTheme.primaryColor,
    };

/// The icon a category is shown with. See [categoryColor].
IconData categoryIcon(String? category) => switch (category) {
      'pop' => Icons.star_rounded,
      'hiphop' => Icons.mic_rounded,
      'rock' => Icons.electric_bolt_rounded,
      'electro' => Icons.headphones_rounded,
      'dance' => Icons.nightlife_rounded,
      'rnb' => Icons.favorite_rounded,
      'kpop' => Icons.auto_awesome_rounded,
      'rap_fr' => Icons.record_voice_over_rounded,
      'variete_fr' => Icons.music_note_rounded,
      'latino' => Icons.local_fire_department_rounded,
      'disco' => Icons.blur_circular_rounded,
      'afrobeats' => Icons.celebration_rounded,
      'jpop' => Icons.spa_rounded,
      'bollywood' => Icons.movie_rounded,
      _ => Icons.library_music_rounded,
    };
