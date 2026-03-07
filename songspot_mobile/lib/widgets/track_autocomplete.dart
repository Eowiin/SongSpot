import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/track.dart';
import '../services/api_service.dart';

class TrackAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final Function(Track) onTrackSelected;
  final String? labelText;
  final String hintText;

  const TrackAutocomplete({
    super.key,
    required this.controller,
    required this.onTrackSelected,
    this.labelText,
    this.hintText = 'Enter song title',
  });

  @override
  State<TrackAutocomplete> createState() => _TrackAutocompleteState();
}

class _TrackAutocompleteState extends State<TrackAutocomplete> {
  final ApiService _apiService = ApiService();
  final ScrollController _suggestionsScrollController = ScrollController();
  final GlobalKey _suggestionsPanelKey = GlobalKey();
  List<Track> _suggestions = [];
  bool _isLoading = false;
  Timer? _debounce;

  static const double _suggestionsMaxHeight = 200;

  Future<void> _searchTracks(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final results = await _apiService.searchTracks(query, limit: 25);
      setState(() {
        _suggestions = results
            .map((json) => Track.fromJson(json as Map<String, dynamic>))
            .toList();
        _isLoading = false;
      });
      _scrollSuggestionsIntoView();
    } catch (e) {
      setState(() {
        _suggestions = [];
        _isLoading = false;
      });
    }
  }

  void _scrollSuggestionsIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _suggestions.isEmpty) return;
      final suggestionsContext = _suggestionsPanelKey.currentContext;
      if (suggestionsContext == null) return;
      Scrollable.ensureVisible(
        suggestionsContext,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 1,
      );
    });
  }

  void _selectTrack(Track track) {
    setState(() {
      widget.controller.text = '${track.title} - ${track.artist}';
      _suggestions = [];
    });
    widget.onTrackSelected(track);
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _searchTracks(value);
    });
  }

  @override
  void dispose() {
    _suggestionsScrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.labelText != null) ...[
          Text(widget.labelText!, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: widget.controller,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(
              Icons.music_note,
              color: AppTheme.textSecondary,
            ),
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppTheme.primaryColor,
                        ),
                      ),
                    ),
                  )
                : null,
            filled: true,
            fillColor: AppTheme.surfaceColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadius),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadius),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadius),
              borderSide: const BorderSide(
                color: AppTheme.primaryColor,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
          ),
          onChanged: _onQueryChanged,
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            key: _suggestionsPanelKey,
            constraints: const BoxConstraints(maxHeight: _suggestionsMaxHeight),
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(AppTheme.borderRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Scrollbar(
              controller: _suggestionsScrollController,
              thumbVisibility: true,
              thickness: 4,
              radius: const Radius.circular(8),
              child: ListView.builder(
                controller: _suggestionsScrollController,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final track = _suggestions[index];
                  return ListTile(
                    leading: const Icon(
                      Icons.music_note,
                      color: AppTheme.primaryColor,
                    ),
                    title: Text(
                      track.title,
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                    subtitle: Text(
                      track.artist,
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    onTap: () => _selectTrack(track),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}
